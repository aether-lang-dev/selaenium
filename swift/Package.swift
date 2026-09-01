// swift-tools-version:5.9
// Swift binding for the shared Aether Selenium engine. CSeleniumCore exposes the
// engine's flat C ABI (aether_sel_embed_*) via a module map; Selenium is the
// idiomatic Swift surface over it. The engine .so is found at link/run time via
// SELENIUM_CORE_LIB and the -L/-rpath below (the .tests.ae stages native/).
import PackageDescription

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
                    "-L", "native",
                    "-lselenium_core",
                    "-Xlinker", "-rpath", "-Xlinker", "native",
                ])
            ]
        ),
        .testTarget(name: "SeleniumTests", dependencies: ["Selenium"]),
    ]
)
