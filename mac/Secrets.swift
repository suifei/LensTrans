import Foundation
import Security

// Keychain stub — Windows uses DPAPI. Never log the key.

enum MacSecrets {
    static func saveCloudKey(_: String) throws {
        throw NSError(domain: "LensTrans", code: 2, userInfo: [NSLocalizedDescriptionKey: "Keychain stub"])
    }

    static func loadCloudKey() -> String { "" }

    static func autostartEnabled() -> Bool { false }

    static func setAutostart(_: Bool) {
        // TODO: SMAppService / LaunchAgent. Bidirectional with Settings checkbox.
    }
}
