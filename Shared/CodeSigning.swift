import Foundation
import Security

enum CodeSigning {
    /// Team ID of the running process's signature, used so the app and the helper only trust each other.
    static func ownTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Requirement string pinning a peer to an identifier signed by our team.
    static func requirement(identifier: String) -> String {
        if let team = ownTeamIdentifier() {
            return "identifier \"\(identifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
        }
        return "identifier \"\(identifier)\""
    }
}
