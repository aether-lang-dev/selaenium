// Link the shared Aether Selenium engine (.so) at BUILD time. The library and
// its search dir are found in this order:
//   1. SELENIUM_CORE_LIB — an explicit path to the .so (dev/CI), whose parent
//      dir becomes the link search path;
//   2. the crate's own bundled native/ dir (a published crate ships the .so
//      there and rpaths to it);
//   3. ../selenium_core/native — the monorepo layout (this crate next to core/).
// An rpath to the resolved dir lets the built binary/tests find the .so at run
// time without LD_LIBRARY_PATH.
use std::path::{Path, PathBuf};

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
    let mono = manifest.join("..").join("core").join("native");
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
