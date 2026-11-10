// swift-tools-version:5.9
//
// HourglassCore — platform-independent heart of the Hourglass app.
//
// Contains everything that does NOT need UIKit / Metal / CoreMotion:
//   • falling-sand cellular automaton + hourglass SDF + time-synchronised flow governor
//   • timer engine (dates are the source of truth), sequences, flip detector
//   • library models with schema migrations, sand themes
//
// It builds on macOS, iOS, visionOS *and Linux*, so the critical logic can be unit-tested
// in CI (or `docker run swift:5.10 swift test`) without a simulator.

import PackageDescription

let package = Package(
    name: "HourglassCore",
    platforms: [.iOS(.v15), .macOS(.v12), .visionOS(.v1)],
    products: [
        .library(name: "HourglassCore", targets: ["HourglassCore"]),
    ],
    targets: [
        .target(name: "HourglassCore"),
        .testTarget(
            name: "HourglassCoreTests",
            dependencies: ["HourglassCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
