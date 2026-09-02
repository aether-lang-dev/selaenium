# Attestations — cross-built engine artifacts run on real target hardware

Each record: a SHA256-identified artifact that was cross-built on one host and
verified on its actual target OS. A verifier re-hashes the artifact they hold,
matches `sha256`, and trusts the recorded result for those exact bytes. Format
per release/README.md.

---

```
sha256=55ceb2a75bbcfe3e18a08119a0ee2cc1db23e82c647349d9efc56802447a1c2f
artifact=libselenium_core macos-amd64 dylib (ae 0.622.0, drivermgr xplat + tls13_client import)
target=macos-amd64  host=macvm (macOS, x86_64)  date=2026-09-02
built-on=ChromeOS/Linux dev box via 'ae build --target=x86_64-macos' (zig cc) — NO native build on the Mac
coverage=ffi+live-self-provision
result=PASS
suite=C dlopen harness: with an EMPTY cache, resolve_driver("chrome") fetched CfT metadata over https (pure-Aether TLS 1.3, no OpenSSL), downloaded + unpacked chromedriver 138.0.7204.183 mac-x64 into the cache (real Mach-O x86_64, --version OK); 2nd call = cache hit; ensure_driver("chrome") spawned a live chromedriver (port 49175) and stopped it
notes=THE aether#1849 https-on-cross-build gap is RESOLVED in ae 0.622.0. Fix required in the engine: `import std.cryptography.tls13_client` in drivermgr/resolve.ae (overrides the weak TLS stubs at link time); build unchanged otherwise (--with=net,os,fs already grants fs for the trust store). Full self-provision (detect->https metadata->download->unpack->cache->spawn) now works from a cross-built dylib with no native rebuild and no manually-placed driver. Supersedes the 2026-09-01 record below (which pre-dates the fix and needed manual driver placement).
```

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
