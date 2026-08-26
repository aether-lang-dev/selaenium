// A consumer of selenium-core needs the engine .so on its own rpath, because
// Cargo does not propagate the dependency's `rustc-link-arg` (rpath) to this
// binary. The selenium-core crate sets `links = "selenium_core"` and its
// build.rs publishes `cargo:native_dir=...`, which Cargo exposes here as
// DEP_SELENIUM_CORE_NATIVE_DIR. We re-emit the link search + rpath from it.
fn main() {
    if let Ok(dir) = std::env::var("DEP_SELENIUM_CORE_NATIVE_DIR") {
        println!("cargo:rustc-link-search=native={dir}");
        println!("cargo:rustc-link-arg=-Wl,-rpath,{dir}");
    }
}
