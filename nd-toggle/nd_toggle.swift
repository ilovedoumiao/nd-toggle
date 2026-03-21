import Observation
import ServiceManagement
import SwiftUI

@main
struct nd_toggle: App {
	@State private var model = model_ndns()
	@State private var isHoveringQuit = false
	
	var body: some Scene {
		MenuBarExtra {
			VStack(alignment: .leading, spacing: 7) {
				HStack {
					Label(model.profile_display, systemImage: "person.crop.circle")
						.opacity(model.isRunningToggleOn ? 1 : 0.5)
					Spacer(minLength: 16)
					Toggle(
						isOn: Binding(
							get: { model.isRunningToggleOn },
							set: { model.setRunning($0) }
						)
					) {
						EmptyView()
					}
					.toggleStyle(.switch)
					.controlSize(.small)
					.disabled(!model.tog_status)
				}
				
				VStack(alignment: .leading, spacing: 2) {
					Text(model.txt_status)
						.font(.system(size: 12))
						.opacity(0.5)
					Text(model.txt_dns)
						.font(.system(size: 12))
						.opacity(0.5)
					Text(model.txt_ver)
						.font(.system(size: 12))
						.opacity(0.5)
				}
				
				Divider()
				
				HStack {
					Text("Launch at login")
					Spacer(minLength: 16)
					Toggle(
						isOn: Binding(
							get: { model.launchAtLoginEnabled },
							set: { model.setLaunchAtLogin($0) }
						)
					) {
						EmptyView()
					}
					.toggleStyle(.switch)
					.controlSize(.small)
					.disabled(model.launchAtLoginBusy)
				}
				
				Divider()

				Text("ND Toggler v1.1")
					.font(.system(size: 12))
					.opacity(0.5)
					.padding(.bottom, -3)
				
				Button {
					NSApplication.shared.terminate(nil)
				} label: {
					HStack {
						Text("Quit")
						Spacer(minLength: 16)
						Text("⌘Q")
							.opacity(0.5)
					}
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(.vertical, 4)
					.contentShape(Rectangle())
					.background {
						RoundedRectangle(cornerRadius: 5)
							.fill(Color.accentColor.opacity(isHoveringQuit ? 0.7 : 0))
							.padding(.horizontal, -6)
					}
				}
				.buttonStyle(.plain)
				.onHover { hovering in
					isHoveringQuit = hovering
				}
				.keyboardShortcut("q", modifiers: .command)
			}
			.padding(.horizontal, 12)
			.padding(.top, 12)
			.padding(.bottom, 6)
			.frame(width: 240, alignment: .leading)
			.onAppear {
				model.refreshOnMenuOpen()
			}
		} label: {
			Image(model.ico_asset)
				.renderingMode(.template)
				.resizable()
				.scaledToFit()
				.frame(width: 18, height: 18, alignment: .center)
		}
		.menuBarExtraStyle(.window)
	}
}

@MainActor
@Observable
final class model_ndns {
	private enum Constants {
		static let profile_maxchar = 15
		static let profile_default = "NextDNS"
		static let notFoundText = "NextDNS not found"
		static let unknownVersion = "Unknown"
	}
	
	private enum BinaryResolution {
		case found(URL)
		case notFound
		case error
	}
	
	private enum Menustatus {
		case running
		case stopped
		case error
		case notFound
	}
	
	private var status: Menustatus = .stopped
	private(set) var profile_name = Constants.profile_default
	private(set) var version = Constants.unknownVersion
	private(set) var dns_address = "Unknown DNS"
	private(set) var isBusy = false
	private(set) var launchAtLoginEnabled = false
	private(set) var launchAtLoginBusy = false
	private var err_cmd: String?
	private(set) var helper_message: String?
	
	private var url_ndns: URL?
	private let helperClient = PrivilegedHelperClient()
	
	init() {
		Task {
			prepareHelper()
			await refresh()
			await refreshLaunchAtLoginState()
		}
	}
	
	var ico_asset: String {
		if err_cmd != nil {
			return "exclamationmark.shield"
		}
		
		switch status {
		case .running:
			return "checkmark.shield.fill"
		case .stopped:
			return "shield"
		case .error, .notFound:
			return "exclamationmark.shield"
		}
	}
	
	var txt_status: String {
		switch status {
		case .running:
			return "NextDNS daemon: Running"
		case .stopped, .error:
			return "NextDNS daemon: Stopped"
		case .notFound:
			return Constants.notFoundText
		}
	}
	
	var profile_display: String {
		trim_profile
	}
	
	var isRunningToggleOn: Bool {
		status == .running
	}
	
	var txt_ver: String {
		version.replacingOccurrences(of: "nextdns", with: "nextdns-cli")
	}

	var txt_dns: String {
		dns_address
	}
	
	var tog_status: Bool {
		status != .notFound && !isBusy
	}
	
	private var trim_profile: String {
		let trimmed = profile_name.trimmingCharacters(
			in: .whitespacesAndNewlines
		)
		let fallback = trimmed.isEmpty ? Constants.profile_default : trimmed
		
		guard fallback.count > Constants.profile_maxchar else {
			return fallback
		}
		
		let index = fallback.index(
			fallback.startIndex,
			offsetBy: Constants.profile_maxchar
		)
		return String(fallback[..<index]) + "..."
	}
	
	func setRunning(_ shouldRun: Bool) {
		guard tog_status else { return }
		guard shouldRun != (status == .running) else { return }
		
		Task {
			let command: NextDNSHelperCommand = shouldRun ? .start : .stop
			let expectedstatus: Menustatus =
			command == .start ? .running : .stopped
			let succeeded = await run_cmd(command)
			if succeeded {
				err_cmd = nil
				helper_message = nil
				status = expectedstatus
				if shouldRun {
					dns_address = "Fetching updated DNS..."
				}
				await wait_status(expectedstatus, preserveDNSPlaceholder: shouldRun)
				await wait_dns_change(expectLoopback: shouldRun)
				return
			}
			await refresh()
		}
	}
	
	func setLaunchAtLogin(_ enabled: Bool) {
		Task {
			await setLaunchAtLoginAsync(enabled)
		}
	}

	func refreshOnMenuOpen() {
		Task {
			await refresh()
			try? await Task.sleep(nanoseconds: 500_000_000)
			await refresh()
		}
	}
	
	func refresh(updateDNS: Bool = true) async {
		let resolution = await where_ndns()
		
		switch resolution {
		case .found(let url):
			url_ndns = url
		case .notFound:
			url_ndns = nil
			status = .notFound
			profile_name = Constants.profile_default
			version = Constants.unknownVersion
			dns_address = "Unknown DNS"
			return
		case .error:
			url_ndns = nil
			status = .error
			profile_name = Constants.profile_default
			version = Constants.unknownVersion
			dns_address = "Unknown DNS"
			return
		}
		
		guard let url_ndns else { return }
		
		async let runningstatus = status_now()
		async let profileResult = run_proc(
			at: url_ndns,
			arguments: ["config", "list"]
		)
		async let what_ver = run_proc(at: url_ndns, arguments: ["version"])
		async let dns_now = fetch_dns_address()
		
		let daemonstatus = await runningstatus
		let profile = await profileResult
		let what_verValue = await what_ver
		let current_dns = await dns_now
		
		err_cmd = nil
		profile_name = get_profile(profile.stdout) ?? Constants.profile_default
		version =
		fetch_actualinfo(in: what_verValue.stdout)
		?? Constants.unknownVersion
		if updateDNS {
			dns_address = current_dns
		}
		
		status = daemonstatus
	}
	
	private func wait_status(_ expectedstatus: Menustatus, preserveDNSPlaceholder: Bool = false) async {
		for _ in 0..<10 {
			let currentstatus = await status_now()
			if currentstatus == expectedstatus {
				await refresh(updateDNS: !preserveDNSPlaceholder)
				return
			}
			
			if currentstatus == .error {
				status = .error
				await refresh(updateDNS: !preserveDNSPlaceholder)
				return
			}
			
			try? await Task.sleep(nanoseconds: 500_000_000)
		}
		
		await refresh(updateDNS: !preserveDNSPlaceholder)
	}

	private func wait_dns_change(expectLoopback: Bool) async {
		for _ in 0..<24 {
			let currentDNS = await fetch_dns_address()

			let hasLoopback = currentDNS.contains("(Loopback)")

			if expectLoopback {
				if hasLoopback == expectLoopback {
					dns_address = currentDNS
					await refresh()
					return
				}
			} else {
				dns_address = currentDNS
				if hasLoopback == expectLoopback {
					await refresh()
					return
				}
			}

			try? await Task.sleep(nanoseconds: 500_000_000)
		}

		await refresh()
	}
	
	private func refreshLaunchAtLoginState() async {
		if #available(macOS 13.0, *) {
			switch SMAppService.mainApp.status {
			case .enabled:
				launchAtLoginEnabled = true
			case .notRegistered, .requiresApproval, .notFound:
				launchAtLoginEnabled = false
			@unknown default:
				launchAtLoginEnabled = false
			}
		} else {
			launchAtLoginEnabled = false
		}
	}
	
	private func setLaunchAtLoginAsync(_ enabled: Bool) async {
		guard #available(macOS 13.0, *) else { return }
		guard !launchAtLoginBusy else { return }
		
		launchAtLoginBusy = true
		defer { launchAtLoginBusy = false }
		
		do {
			if enabled {
				try SMAppService.mainApp.register()
			} else {
				try await SMAppService.mainApp.unregister()
			}
			
			launchAtLoginEnabled = enabled
		} catch {
			await refreshLaunchAtLoginState()
		}
	}
	
	private func status_now() async -> Menustatus {
		let result = await run_proc(
			at: URL(fileURLWithPath: "/usr/bin/pgrep"),
			arguments: ["-fl", "nextdns"]
		)
		
		if result.exitCode == 1 {
			return .stopped
		}
		
		guard result.exitCode == 0 else {
			return .error
		}
		
		let lines = result.stdout
			.components(separatedBy: .newlines)
			.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
			.filter { !$0.isEmpty }
		
		let has_daemon = lines.contains { $0.contains("nextdns run") }
		return has_daemon ? .running : .stopped
	}
	
	func openHelperSettings() {
		helperClient.openSystemSettings()
	}
	
	private func prepareHelper() {
		switch helperClient.prepare() {
		case .ready:
			helper_message = nil
		case .needsApproval:
			helper_message =
			"Approve the background helper in System Settings > Login Items"
		case .unavailable(let message):
			helper_message = message
		}
	}
	
	private func run_cmd(_ command: NextDNSHelperCommand) async -> Bool {
		isBusy = true
		defer { isBusy = false }
		
		let result = await helperClient.run(command)
		if result.exitCode != 0 {
			helper_message =
			fetch_actualinfo(in: result.stderr)
			?? fetch_actualinfo(in: result.stdout)
			err_cmd =
			fetch_actualinfo(in: result.stderr)
			?? fetch_actualinfo(in: result.stdout)
			if case .needsApproval = helperClient.prepare() {
				helper_message =
				"Approve the background helper in System Settings > Login Items"
			}
		} else {
			helper_message = nil
		}
		return result.exitCode == 0
	}
	
	private func where_ndns() async -> BinaryResolution {
		let path_to_ndns = [
			"/opt/homebrew/bin/nextdns",
			"/usr/local/bin/nextdns",
			"/usr/bin/nextdns",
		]
		
		for path in path_to_ndns {
			let url = URL(fileURLWithPath: path)
			let probe = await run_proc(at: url, arguments: ["version"])
			
			if probe.exitCode == 0 {
				return .found(url)
			}
			
			let stderr = probe.stderr.lowercased()
			if stderr.contains("operation not permitted")
				|| stderr.contains("permission denied")
			{
				return .error
			}
		}
		
		let path_which = await run_proc(
			at: URL(fileURLWithPath: "/usr/bin/which"),
			arguments: ["nextdns"]
		)
		guard path_which.exitCode == 0,
			  let path = fetch_actualinfo(in: path_which.stdout)
		else {
			return .notFound
		}
		
		let url_ndns = URL(fileURLWithPath: path)
		let probe = await run_proc(at: url_ndns, arguments: ["version"])
		
		if probe.exitCode == 0 {
			return .found(url_ndns)
		}
		
		let stderr = probe.stderr.lowercased()
		if stderr.contains("operation not permitted")
			|| stderr.contains("permission denied")
		{
			return .error
		}
		
		return .notFound
	}
	
	private func fetch_actualinfo(in text: String) -> String? {
		text
			.components(separatedBy: .newlines)
			.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
			.first(where: { !$0.isEmpty })
	}
	
	private func get_profile(_ text: String) -> String? {
		for rawLine in text.components(separatedBy: .newlines) {
			let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
			if line.hasPrefix("profile ") {
				let value = String(line.dropFirst("profile ".count))
					.trimmingCharacters(in: .whitespacesAndNewlines)
				return value.isEmpty ? nil : value
			}
		}
		
		return nil
	}

	private func fetch_dns_address() async -> String {
		let result = await run_proc(
			at: URL(fileURLWithPath: "/usr/sbin/scutil"),
			arguments: ["--dns"]
		)

		guard result.exitCode == 0 else {
			return "Unknown DNS"
		}

		let lines = result.stdout.components(separatedBy: .newlines)

		for rawLine in lines {
			let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
			guard line.hasPrefix("nameserver[") else { continue }

			guard let address = line.split(separator: ":", maxSplits: 1).last?
				.trimmingCharacters(in: .whitespacesAndNewlines),
				!address.isEmpty
			else {
				continue
			}

			guard is_ipv4_address(address) else { continue }
			return format_dns_address(address)
		}

		return "Unknown DNS"
	}

	private func format_dns_address(_ address: String) -> String {
		let lowercased = address.lowercased()

		if lowercased == "127.0.0.1" || lowercased == "::1" || lowercased == "localhost" {
			return "\(address) (Loopback)"
		}

		return address
	}

	private func is_ipv4_address(_ address: String) -> Bool {
		let parts = address.split(separator: ".")
		guard parts.count == 4 else { return false }

		return parts.allSatisfy { part in
			guard let value = Int(part), String(value) == part else { return false }
			return (0...255).contains(value)
		}
	}
	
	private func run_proc(at executableURL: URL, arguments: [String]) async
	-> cmd_result
	{
		await withCheckedContinuation { continuation in
			DispatchQueue.global(qos: .userInitiated).async {
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
						decoding: stdoutPipe.fileHandleForReading
							.readDataToEndOfFile(),
						as: UTF8.self
					)
					let stderr = String(
						decoding: stderrPipe.fileHandleForReading
							.readDataToEndOfFile(),
						as: UTF8.self
					)
					
					continuation.resume(
						returning: cmd_result(
							exitCode: process.terminationStatus,
							stdout: stdout,
							stderr: stderr
						)
					)
				} catch {
					continuation.resume(
						returning: cmd_result(
							exitCode: -1,
							stdout: "",
							stderr: error.localizedDescription
						)
					)
				}
			}
		}
	}
}

private struct cmd_result {
	let exitCode: Int32
	let stdout: String
	let stderr: String
}
