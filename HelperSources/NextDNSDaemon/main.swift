import Foundation

private struct HelperCommandResult {
	let exitCode: Int32
	let stdout: String
	let stderr: String
}

private final class NextDNSHelperService: NSObject, NSXPCListenerDelegate,
	NextDNSHelperProtocol
{
	private let xpcListener = NSXPCListener(
		machServiceName: NextDNSHelperConstants.serviceName
	)

	func run() {
		xpcListener.delegate = self
		xpcListener.resume()
		RunLoop.current.run()
	}

	func listener(
		_ listener: NSXPCListener,
		shouldAcceptNewConnection newConnection: NSXPCConnection
	) -> Bool {
		newConnection.exportedInterface = NSXPCInterface(
			with: NextDNSHelperProtocol.self
		)
		newConnection.exportedObject = self
		newConnection.resume()
		return true
	}

	func runCommand(
		_ command: String,
		withReply reply: @escaping (Int32, String, String) -> Void
	) {
		guard let requestedCommand = NextDNSHelperCommand(rawValue: command) else {
			reply(-1, "", "Unsupported command")
			return
		}

		let result = Self.execute(requestedCommand)
		reply(result.exitCode, result.stdout, result.stderr)
	}

	private static func execute(_ command: NextDNSHelperCommand)
		-> HelperCommandResult
	{
		guard let binaryURL = resolveBinary() else {
			return HelperCommandResult(
				exitCode: -1,
				stdout: "",
				stderr: "nextdns binary not found"
			)
		}

		return runProcess(at: binaryURL, arguments: [command.rawValue])
	}

	private static func resolveBinary() -> URL? {
		let candidates = [
			"/opt/homebrew/bin/nextdns",
			"/usr/local/bin/nextdns",
			"/usr/bin/nextdns",
		]

		for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
			return URL(fileURLWithPath: candidate)
		}

		let whichResult = runProcess(
			at: URL(fileURLWithPath: "/usr/bin/which"),
			arguments: ["nextdns"]
		)
		guard whichResult.exitCode == 0 else {
			return nil
		}

		let resolvedPath = whichResult.stdout
			.components(separatedBy: .newlines)
			.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?
			.trimmingCharacters(in: .whitespacesAndNewlines)

		guard let resolvedPath else {
			return nil
		}

		return URL(fileURLWithPath: resolvedPath)
	}

	private static func runProcess(at executableURL: URL, arguments: [String])
		-> HelperCommandResult
	{
		let process = Process()
		let stdoutPipe = Pipe()
		let stderrPipe = Pipe()

		process.executableURL = executableURL
		process.arguments = arguments
		process.standardOutput = stdoutPipe
		process.standardError = stderrPipe

		do {
			try process.run()
			process.waitUntilExit()

			let stdout = String(
				decoding: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
				as: UTF8.self
			)
			let stderr = String(
				decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
				as: UTF8.self
			)

			return HelperCommandResult(
				exitCode: process.terminationStatus,
				stdout: stdout,
				stderr: stderr
			)
		} catch {
			return HelperCommandResult(
				exitCode: -1,
				stdout: "",
				stderr: error.localizedDescription
			)
		}
	}
}

private let service = NextDNSHelperService()
service.run()
