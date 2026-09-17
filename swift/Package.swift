// swift-tools-version:5.9
// Swift binding for the shared Aether Selenium engine. CSeleniumCore exposes the
// engine's flat C ABI (aether_sel_embed_*) via a module map; Selenium is the
// idiomatic Swift surface over it. The engine .so is found at link/run time via
// SELENIUM_CORE_LIB and the -L/-rpath below (the .tests.ae stages native/).
import Foundation
import PackageDescription

// The engine gh-release tag whose fetch-cache this package searches (matches
// scripts/fetch-engine.sh's default TAG and the SELENIUM_CORE_VERSION file).
let seleniumCoreVersion = "v0.8.0"

// The link paths below MUST be absolute and computed here, at
// manifest-evaluation time. A relative "-L native" resolves against whatever
// directory the LINKER runs in — which, the moment this package is consumed as
// a dependency, is the CONSUMER's directory, not ours. That builds fine in
// place and fails with `cannot find -lselenium_core` for every downstream user,
// while swift/.tests.ae stays green throughout; only a consumer-install proof
// (swift/.example.ae) catches it. #filePath is this manifest, so every copy of
// the package — in-tree, staged, or installed — computes its own location.
// (The same trap, and the same fix, in the sibling servirtium-vcr repo.)
let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

// The engine .so directory is resolved at manifest-evaluation time, searched in
// the same order as the link-time reference (rust/build.rs):
//   1. SELENIUM_CORE_LIB — an explicit path to the .so; its parent dir is used;
//   2. the package's own bundled native/ (a published package ships the .so there);
//   3. the shared fetch cache scripts/fetch-engine.sh populates —
//      $XDG_CACHE_HOME/selaenium/<tag>/ (or ~/.cache | ~/Library/Caches /…) — so a
//      dev with no Aether toolchain runs that once and then `swift build` just works;
//   4. ../selenium_core/native — the monorepo layout (this package next to core/).
// Every existing candidate becomes a -L/-rpath entry so the linker takes the first
// that holds libselenium_core and the built product locates it at run time; if none
// exists yet, bundled native/ is emitted so the link error names a stable path.
let env = ProcessInfo.processInfo.environment
#if os(macOS)
let libName = "libselenium_core.dylib"
let cacheHome = env["XDG_CACHE_HOME"].flatMap { $0.isEmpty ? nil : $0 }
    ?? (NSHomeDirectory() + "/Library/Caches")
#else
let libName = "libselenium_core.so"
let cacheHome = env["XDG_CACHE_HOME"].flatMap { $0.isEmpty ? nil : $0 }
    ?? (NSHomeDirectory() + "/.cache")
#endif

var candidateDirs: [String] = []
if let explicit = env["SELENIUM_CORE_LIB"], !explicit.isEmpty {
    candidateDirs.append(URL(fileURLWithPath: explicit).deletingLastPathComponent().path)
}
candidateDirs.append(packageDir.appendingPathComponent("native").path)
candidateDirs.append(cacheHome + "/selaenium/" + seleniumCoreVersion)
candidateDirs.append(packageDir.deletingLastPathComponent()
    .appendingPathComponent("selenium_core").appendingPathComponent("native").path)

// Keep only dirs that actually hold the engine, preserving priority order. If
// none do (fresh checkout, engine not fetched yet), fall back to bundled native/
// so the link step fails with a clear, stable path rather than no -L at all.
let fm = FileManager.default
var linkDirs = candidateDirs.filter { fm.fileExists(atPath: $0 + "/" + libName) }
if linkDirs.isEmpty { linkDirs = [packageDir.appendingPathComponent("native").path] }

// -L + -rpath for each resolved dir; -lselenium_core once.
var engineLinkerFlags: [String] = []
for dir in linkDirs { engineLinkerFlags += ["-L", dir] }
engineLinkerFlags += ["-lselenium_core"]
for dir in linkDirs { engineLinkerFlags += ["-Xlinker", "-rpath", "-Xlinker", dir] }

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
                .unsafeFlags(engineLinkerFlags)
            ]
        ),
        .testTarget(name: "SeleniumTests", dependencies: ["Selenium"]),
    ]
)
