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
    static let groupName = "group.\(packageName)"

    private static let defaultSharedDirectory: URL! = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: FilePath.groupName)

    static let sharedDirectory = defaultSharedDirectory!

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
