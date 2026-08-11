// swift-tools-version: 5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.
// 5.5 specifically: SupportedPlatform.IOSVersion.v15 below was introduced in
// PackageDescription 5.5, and under 5.4 it fails the manifest with "'v15' is
// unavailable" before any target compiles.

import PackageDescription

let package = Package(
     name: "Rayn Packages",
     platforms: [
        // Minimum platform version
         .iOS(.v15)
     ],
     products: [
         .library(
             name: "RaynCore",
             targets: ["RaynCore"]),
     ],
     dependencies: [
         // No dependencies
     ],
     targets: [
        .binaryTarget(
            name: "RaynCore",
            path: "../Frameworks/RaynCore.xcframework"
        )
     ]
 )
