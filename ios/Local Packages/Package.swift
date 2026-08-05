// swift-tools-version: 5.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

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
