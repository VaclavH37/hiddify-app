//
//  GrpcSecret.swift
//  Shared between Runner and RaynTunnel.
//

import Foundation
import Security
import os.log

/// Owns the per-install credential that authenticates callers of the local gRPC
/// cores.
///
/// Both cores listen on loopback, and loopback is not isolated between apps on
/// iOS — any other process can connect. That is not theoretical here: with
/// Hiddify installed alongside, our client attached to *its* core and handed it a
/// decrypted subscription. TLS with a pinned certificate stops us talking to the
/// wrong server; this secret stops the wrong client talking to us. The core
/// requires it on every RPC (`requireSecret`, v2/hcore/grpc_server.go) and fails
/// closed when it is unset.
///
/// Deliberately modelled on `ConfigKey`, for the same reason and with the same
/// constraints:
///
///   * Keychain under the App Group, because the packet-tunnel extension is a
///     separate process that the system can launch with the app not running, and
///     it needs the same value. `com.apple.security.application-groups` is what
///     authorises this — see the long note in Runner.entitlements about why
///     `keychain-access-groups` must NOT be added.
///   * `AfterFirstUnlockThisDeviceOnly`. The default (`WhenUnlocked`) makes the
///     item unreadable to an on-demand start before the first unlock after a
///     reboot, and the tunnel then fails with nothing to show the user.
///   * PERSISTED, not per-launch. An on-demand start has no app process to hand
///     it a fresh value, so a per-launch secret would leave the background core
///     either unauthenticated or unreachable.
///
/// `getOrCreate` is app-only, reached over the platform channel. The extension
/// calls `peek`, which never creates: a background start must not race the app
/// into generating a second secret, which would leave the two cores disagreeing
/// and every RPC failing Unauthenticated.
public enum GrpcSecret {
    private static let log = Logger(subsystem: "com.raynlabs.app", category: "GrpcSecret")

    private static let service = "io.raynlabs.grpcsecret"
    private static let account = "rayn_grpc_secret"
    /// 32 bytes of entropy, hex-encoded to 64 characters. Hex rather than raw
    /// bytes because this crosses the gomobile boundary as a Go string and
    /// travels as an HTTP/2 header value, neither of which is binary-safe.
    private static let byteLength = 32

    private static var accessGroup: String { FilePath.groupName }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
        ]
    }

    /// Returns the secret, or nil if it has not been created yet. Never creates.
    public static func peek() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            if status != errSecItemNotFound {
                log.warning("grpc secret lookup failed with status \(status)")
            }
            return nil
        }
        guard let secret = String(data: data, encoding: .utf8), !secret.isEmpty else {
            log.error("grpc secret is not valid UTF-8")
            return nil
        }
        return secret
    }

    /// Returns the secret, generating and storing one on first call. App only.
    public static func getOrCreate() -> String? {
        if let existing = peek() { return existing }

        var bytes = Data(count: byteLength)
        let generated = bytes.withUnsafeMutableBytes { buffer -> OSStatus in
            guard let base = buffer.baseAddress else { return errSecAllocate }
            return SecRandomCopyBytes(kSecRandomDefault, byteLength, base)
        }
        guard generated == errSecSuccess else {
            log.error("could not generate a grpc secret")
            return nil
        }
        let secret = bytes.map { String(format: "%02x", $0) }.joined()

        var insert = baseQuery
        insert[kSecValueData as String] = Data(secret.utf8)
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            log.error("could not store the grpc secret (status \(status))")
            return nil
        }
        log.info("generated a new per-install grpc secret")
        return secret
    }
}
