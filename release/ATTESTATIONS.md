# Attestations — cross-built engine artifacts run on real target hardware

Each record: a SHA256-identified artifact that was cross-built on one host and
verified on its actual target OS. A verifier re-hashes the artifact they hold,
matches `sha256`, and trusts the recorded result for those exact bytes. Format
per release/README.md.

---

```
sha256=8beb6ce5082b72b275faf0518a3275945bf11427aa81d7b24f49ee7d8b1b42df
artifact=libselenium_core-v0.1.0-116-g76c5a5c-macos-amd64.dylib
target=macos-amd64  host=Intel iMac (macOS 15.7, x86_64)  date=2026-09-01
built-on=ChromeOS/Linux dev box via 'ae build --target=x86_64-macos' (zig cc) — NO native build on the Mac
coverage=ffi+live-local-chrome
result=PASS
suite=C dlopen harness: dlopen + 48 exports (nm -gU) + newSession/get/getTitle/findElement(By.id)/quit against headless Chrome-for-Testing 138 via chromedriver 138
notes=chromedriver 138.0.7204.183 mac-x64; driver-resolver is now cross-platform (macOS os/arch detection, .app-bundle Chrome discovery, and version parse all VERIFIED correct on this cross-built dylib via a diag probe) — but full live self-provision is blocked on THIS artifact because std.http.client returns an empty body on https in an OpenSSL-less cross-build (aether-lang-dev/aether#1849), so the CfT metadata fetch yields nothing and Chrome/chromedriver were placed manually; offline/already-cached resolution is unaffected; no HTTPS-Grid tested (same #1849 cause); the .dylib crossed over as a finished Mach-O — only the trivial test harness was compiled on the Mac
```
