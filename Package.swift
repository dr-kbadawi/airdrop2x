// swift-tools-version:5.9
// AirDrop2X — make AirDrop deliver files straight into a folder of your choosing.
// Copyright (C) 2026 Dr. Karim Badawi, Techtag GmbH
//
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any later
// version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
// PARTICULAR PURPOSE. See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with
// this program. If not, see <https://www.gnu.org/licenses/>.

import PackageDescription

let package = Package(
    name: "airdrop2x",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "AirDrop2xApp", targets: ["AirDrop2xApp"]),
        .executable(name: "airdrop2x", targets: ["airdrop2x"]),
    ],
    targets: [
        .target(name: "AirDrop2xCore", path: "Sources/AirDrop2xCore"),
        .executableTarget(name: "AirDrop2xApp", dependencies: ["AirDrop2xCore"], path: "Sources/AirDrop2xApp"),
        .executableTarget(name: "airdrop2x", dependencies: ["AirDrop2xCore"], path: "Sources/airdrop2x"),
        .testTarget(name: "AirDrop2xCoreTests", dependencies: ["AirDrop2xCore"], path: "Tests/AirDrop2xCoreTests"),
        .testTarget(name: "AirDrop2xAppTests", dependencies: ["AirDrop2xApp", "AirDrop2xCore"], path: "Tests/AirDrop2xAppTests"),
        .testTarget(name: "airdrop2xCLITests", dependencies: ["airdrop2x"], path: "Tests/airdrop2xCLITests"),
    ],
    swiftLanguageVersions: [.v5]
)
