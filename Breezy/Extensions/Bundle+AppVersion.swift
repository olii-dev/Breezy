import Foundation

extension Bundle {
    var shortVersionString: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var buildVersionString: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var appVersionDisplayString: String {
        if shortVersionString == buildVersionString {
            return "Version \(shortVersionString)"
        }

        return "Version \(shortVersionString) (Build \(buildVersionString))"
    }
}