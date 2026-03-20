import Foundation

@objc protocol NextDNSHelperProtocol {
	func runCommand(
		_ command: String,
		withReply reply: @escaping (Int32, String, String) -> Void
	)
}

enum NextDNSHelperCommand: String {
	case start
	case stop
}

enum NextDNSHelperConstants {
	static let serviceName = "com.doumiao.nd-toggle.helper"
	static let daemonPlistName = "com.doumiao.nd-toggle.helper.plist"
	static let executableName = "nd-toggle-helper"
}
