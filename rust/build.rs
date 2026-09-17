// Link the shared Aether Selenium engine (.so) at BUILD time. The library and
// its search dir are found in this order:
//   1. SELENIUM_CORE_LIB — an explicit path to the .so (dev/CI), whose parent
//      dir becomes the link search path;
//   2. the crate's own bundled native/ dir (a published crate ships the .so
//      there and rpaths to it);
//   3. the shared fetch cache a `scripts/fetch-engine.sh` (or any binding's
//      fetch task) populates: $XDG_CACHE_HOME/selaenium/<tag>/ — so a dev with
//      no Aether toolchain runs that once, then `cargo build` just works;
//   4. ../selenium_core/native — the monorepo layout (this crate next to core/).
// An rpath to the resolved dir lets the built binary/tests find the .so at run
// time without LD_LIBRARY_PATH.
use std::path::{Path, PathBuf};

// The libselenium_core gh-release tag whose fetch-cache this crate searches.
// Single source of truth: the repo-root SELENIUM_CORE_VERSION file (no trailing
// newline), read here at build time so the tag lives in ONE place across every
// binding — no per-binding literal to drift.
const SELENIUM_CORE_VERSION: &str = include_str!("../SELENIUM_CORE_VERSION");

fn main() {
    let dir = resolve_dir();
    println!("cargo:rustc-link-search=native={}", dir.display());
    println!("cargo:rustc-link-lib=dylib=selenium_core");
    // rpath so THIS crate's own tests/binaries locate the .so at run time.
    println!("cargo:rustc-link-arg=-Wl,-rpath,{}", dir.display());
    // Publish the native dir to downstream crates (available to their build.rs
    // as DEP_SELENIUM_CORE_NATIVE_DIR, since Cargo.toml sets `links`). A consumer
    // binary's own build.rs re-emits the rpath from it — `rustc-link-arg` does
    // NOT propagate across the dependency edge, so the consumer must do this.
    println!("cargo:native_dir={}", dir.display());
    // Re-run if the pin changes.
    println!("cargo:rerun-if-env-changed=SELENIUM_CORE_LIB");
    println!("cargo:rerun-if-changed=../SELENIUM_CORE_VERSION");
}

fn resolve_dir() -> PathBuf {
    if let Ok(p) = std::env::var("SELENIUM_CORE_LIB") {
        let path = PathBuf::from(&p);
        if path.exists() {
            if let Some(parent) = path.parent() {
                return parent.to_path_buf();
            }
        }
    }
    let manifest = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap());
    let bundled = manifest.join("native");
    if bundled.join("libselenium_core.so").exists() {
        return bundled;
    }
    // The shared fetch cache (scripts/fetch-engine.sh): $XDG_CACHE_HOME (or the
    // OS default) /selaenium/<tag>/libselenium_core.so.
    if let Some(cache) = fetch_cache_dir() {
        if cache.join("libselenium_core.so").exists() {
            return cache;
        }
    }
    let mono = manifest.join("..").join("selenium_core").join("native");
    if mono.join("libselenium_core.so").exists() {
        return mono;
    }
    // Fall back to the bundled dir even if empty; the link step will error
    // clearly if the .so is truly absent.
    if Path::new(&bundled).exists() {
        bundled
    } else {
        mono
    }
}

// $XDG_CACHE_HOME/selaenium/<tag>/ (or the OS default), matching
// scripts/fetch-engine.sh and the runtime bindings' cache convention.
fn fetch_cache_dir() -> Option<PathBuf> {
    let base = if let Ok(x) = std::env::var("XDG_CACHE_HOME") {
        if x.is_empty() { return home_cache(); }
        PathBuf::from(x)
    } else {
        return home_cache();
    };
    Some(base.join("selaenium").join(SELENIUM_CORE_VERSION))
}

fn home_cache() -> Option<PathBuf> {
    let home = std::env::var("HOME").ok()?;
    // macOS uses ~/Library/Caches; Linux/other use ~/.cache. cfg picks at build.
    let sub = if cfg!(target_os = "macos") { "Library/Caches" } else { ".cache" };
    Some(PathBuf::from(home).join(sub).join("selaenium").join(SELENIUM_CORE_VERSION))
}
