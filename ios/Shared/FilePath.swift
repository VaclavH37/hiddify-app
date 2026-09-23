//
//  FilePath.swift
//  RaynTunnel
//

import Foundation

public enum FilePath {
    public static let packageName = {
        Bundle.main.infoDictionary?["BASE_BUNDLE_IDENTIFIER"] as? String ?? "unknown"
    }()
}

public extension FilePath {
    /// The app group the app and the packet-tunnel extension share: the
    /// container that holds the working directory, and the keychain access group
    /// ConfigKey and GrpcSecret store under.
    ///
    /// Read from the `RaynAppGroup` Info.plist key when a target sets one, which
    /// the macOS targets do. macOS names its groups with the team prefix
    /// (`<TEAMID>.group.com.raynlabs.app`), because that form needs no portal
    /// registration and is what macOS 12 to 14 expect; iOS uses the
    /// `group.`-prefixed identifier. iOS sets no key and falls back to exactly
    /// the value this has always been.
    static let groupName: String = {
        if let configured = Bundle.main.infoDictionary?["RaynAppGroup"] as? String, !configured.isEmpty {
            return configured
        }
        return "group.\(packageName)"
    }()

    /// Crashes with the group's name rather than a bare force-unwrap: a missing
    /// container is a signing misconfiguration, not a runtime condition, and the
    /// crash log should say which entitlement to look at. On iOS a nil here means
    /// the target lacks `com.apple.security.application-groups` for this group.
    /// On macOS the system hands back a path even for a group the target is not
    /// entitled to, so a misconfigured Mac build fails later, at the first write,
    /// rather than here.
    static let sharedDirectory: URL = {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupName) else {
            fatalError("no container for app group \(groupName): the target lacks the com.apple.security.application-groups entitlement for it")
        }
        return url
    }()

    private static let libraryDirectory = sharedDirectory
        .appendingPathComponent("Library", isDirectory: true)

    /// Genuinely disposable: this is what `get_paths` reports as `temp`.
    static let cacheDirectory = libraryDirectory
        .appendingPathComponent("Caches", isDirectory: true)

    /// Holds `configs/<id>.enc`, the extracted `rulesets/*.srs` and the core's
    /// own state, and it is also the directory the core chdir's into
    /// (`v2/hcore/grpc_server.go:72`), so every `Type: Local` rule-set path
    /// resolves against it.
    ///
    /// Application Support, not Caches: iOS reclaims Caches under storage
    /// pressure, at any time, without telling the app. Losing this tree costs a
    /// subscription re-fetch and a rule-set re-extract, and until the app is
    /// next opened an on-demand tunnel start has nothing to start from — the
    /// extension would fail with "no stored configuration". Application Support
    /// is not purged.
    ///
    /// No migration from the old Caches location: iOS has never shipped, so
    /// there is no install with data at the old path. Writing a migration for a
    /// population of zero would only add a code path nothing ever exercises.
    static let workingDirectory = libraryDirectory
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("Working", isDirectory: true)
}

public extension URL {
    var fileName: String {
        var path = relativePath
        if let index = path.lastIndex(of: "/") {
            path = String(path[path.index(index, offsetBy: 1)...])
        }
        return path
    }
}
