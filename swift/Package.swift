// swift-tools-version:5.9
// Swift binding for the shared Aether Selenium engine. CSeleniumCore exposes the
// engine's flat C ABI (aether_sel_embed_*) via a module map; Selenium is the
// idiomatic Swift surface over it. The engine .so is found at link/run time via
// SELENIUM_CORE_LIB and the -L/-rpath below (the .tests.ae stages native/).
import Foundation
import PackageDescription

// The link paths below MUST be absolute and computed here, at
// manifest-evaluation time. A relative "-L native" resolves against whatever
// directory the LINKER runs in — which, the moment this package is consumed as
// a dependency, is the CONSUMER's directory, not ours. That builds fine in
// place and fails with `cannot find -lselenium_core` for every downstream user,
// while swift/.tests.ae stays green throughout; only a consumer-install proof
// (swift/.example.ae) catches it. #filePath is this manifest, so every copy of
// the package — in-tree, staged, or installed — computes its own location.
// (The same trap, and the same fix, in the sibling servirtium-vcr repo.)
let nativeDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("native")
    .path

let package = Package(
    name: "Selenium",
    products: [
        .library(name: "Selenium", targets: ["Selenium"])
    ],
    targets: [
        // The C ABI as a Swift-importable module (header + module map only).
        // This target keeps the CSeleniumCore name — it is the C-module seam
        // mapping to the engine's flat C ABI, not the user-facing surface.
        .target(name: "CSeleniumCore"),
        // The idiomatic Swift surface. Links the engine .so from native/.
        .target(
            name: "Selenium",
            dependencies: ["CSeleniumCore"],
            linkerSettings: [
                .unsafeFlags([
                    "-L", nativeDir,
                    "-lselenium_core",
                    "-Xlinker", "-rpath", "-Xlinker", nativeDir,
                ])
            ]
        ),
        .testTarget(name: "SeleniumTests", dependencies: ["Selenium"]),
    ]
)
