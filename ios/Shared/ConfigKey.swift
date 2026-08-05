//
//  ConfigKey.swift
//  Shared between Runner and RaynTunnel.
//

import Foundation
import Security
import os.log

/// Owns the 32-byte per-install key that seals `configs/<id>.enc`.
///
/// Stored in the keychain under the app group, so the packet-tunnel extension —
/// a separate process that the system can launch with the app not running — can
/// read the same item. On iOS an App Group identifier is a valid keychain access
/// group; it is also listed explicitly in `keychain-access-groups` in both
/// targets' entitlements so the intent is visible rather than implied.
///
/// Accessibility is `AfterFirstUnlockThisDeviceOnly`, and that is not
/// negotiable: the default (`WhenUnlocked`) makes the item unreadable to an
/// on-demand tunnel start before the first unlock after a reboot, and the
/// tunnel then fails with nothing to show the user. `ThisDeviceOnly` also keeps
/// the key out of iCloud Keychain and device backups — losing it on a restore
/// is the correct outcome, because the config is re-derivable from the
/// subscription.
///
/// Creation happens only in `getOrCreate`, reached from the app over the
/// platform channel. The extension calls `peek`, which never creates: a
/// background start must not race the app into generating a second key and
/// orphan every config already on disk.
public enum ConfigKey {
    private static let log = Logger(subsystem: "com.raynlabs.app", category: "ConfigKey")

    private static let service = "io.raynlabs.configkey"
    private static let account = "rayn_config_key"
    private static let keyLength = 32

    private static var accessGroup: String { FilePath.groupName }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
        ]
    }

    /// Returns the key, or nil if it has not been created yet. Never creates.
    public static func peek() -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            if status != errSecItemNotFound {
                log.warning("config key lookup failed with status \(status)")
            }
            return nil
        }
        guard data.count == keyLength else {
            log.error("config key is \(data.count) bytes, expected \(keyLength)")
            return nil
        }
        return data
    }

    /// Returns the key, generating and storing one on first call. App only.
    public static func getOrCreate() -> Data? {
        if let existing = peek() { return existing }

        var key = Data(count: keyLength)
        let generated = key.withUnsafeMutableBytes { buffer -> OSStatus in
            guard let base = buffer.baseAddress else { return errSecAllocate }
            return SecRandomCopyBytes(kSecRandomDefault, keyLength, base)
        }
        guard generated == errSecSuccess else {
            log.error("could not generate a config key")
            return nil
        }

        var insert = baseQuery
        insert[kSecValueData as String] = key
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            log.error("could not store the config key (status \(status))")
            return nil
        }
        log.info("generated a new per-install config key")
        return key
    }
}
