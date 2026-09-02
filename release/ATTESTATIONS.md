# Attestations — cross-built engine artifacts run on real target hardware

Each record: a SHA256-identified artifact that was cross-built on one host and
verified on its actual target OS. A verifier re-hashes the artifact they hold,
matches `sha256`, and trusts the recorded result for those exact bytes. Format
per release/README.md.

---

```
artifact-set=B2 Firefox+Edge resolution (ae 0.622.0)
  linux64  host.so  sha256=5eda8bc584392a22a61388e58f5a9d014f9434a15651fdc134506711c4dc9ecd
  macos-x64 dylib   sha256=daf15edb592b04730720397ec007f806f450075cc719f5b739f39171f655ab74
  win64    dll      sha256=a17687a12468706c4cfb7104370788c53e3037eff72ea3e6055790707113994a
built-on=ChromeOS/Linux dev box (dylib+dll via ae build --target=, zig cc) — NO native build on mac/win
date=2026-09-02  coverage=ffi+live-self-provision
result=PASS (Firefox all 3 OSes; Edge Linux+macOS full, Windows resolve+download only)
suite=empty-cache resolve_driver + ensure_driver for firefox and edge:
  FIREFOX: geckodriver 0.37.1 resolved via SeleniumHQ geckodriver-support.json (firefox 140 on
    Linux) or the releases/latest fallback (no browser on mac/win); downloaded (tar.gz on
    Linux/macOS -> mac64/linux64, zip on Windows -> win64), launched live + stopped. Linux port
    ~40953, macOS ~49181, Windows ~62130. Real runnable binaries (geckodriver --version OK).
  EDGE: msedgedriver resolved via msedgedriver.microsoft.com LATEST_STABLE (UTF-16LE body decoded)
    -> LATEST_RELEASE_<major>_<OS>; downloaded (zip), unpacked. Linux 152.0.4191.53 launched live
    (port 44943); macOS mac64 launched live (port 49193); Windows win64 downloaded + the .exe runs
    + binds 127.0.0.1 standalone, but the ENGINE's launch()/os.spawn_proc of msedgedriver HANGS on
    Windows (geckodriver/chromedriver launch fine) — a driver.ae launch-layer/spawn issue, NOT a
    resolution issue (filed aether asks/win-spawn-msedgedriver-launch-hang.md).
notes=B2 of docs/Selenium-Manager-Port.md. New drivermgr modules gecko.ae + edgedriver.ae; ports
  firefox.rs/edge.rs. Two general fixes landed with it: _download now follows redirects (GitHub
  releases 302s to objects.githubusercontent.com — chromedriver only worked before because
  googleapis served 200 direct), and .tar.gz unpack via `tar -xzf`. Edge Windows launch is the one
  open item; everything up to and including the resolved+downloaded+runnable driver is proven on
  all three OSes.
```

```
sha256=f4799aa3518085d7a1dea54873ff1bcd620075373d1dd216761391e9604cb5b2
artifact=libselenium_core win64 dll (ae 0.622.0, drivermgr xplat + tls13_client import + binary-download/cache-path fixes)
target=win64  host=winbaz (Windows 10, x86_64, MSYS2/git-bash)  date=2026-09-02
built-on=ChromeOS/Linux dev box via 'ae build --target=x86_64-windows' (zig cc) — NO native build on Windows
coverage=ffi+live-self-provision
result=PASS
suite=C LoadLibrary/GetProcAddress harness (compiled on-target with a standalone zig cc): with an EMPTY cache and no system Chrome, resolve_driver("chrome") fetched CfT metadata over https (pure-Aether TLS 1.3 via bcrypt.dll, no OpenSSL), resolved latest stable 152.0.7977.75 win64, downloaded + unpacked chromedriver.exe via PowerShell Expand-Archive into C:/Users/paul/.cache/selenium/... (23,805,952 bytes, --version OK); 2nd call = 0.98s cache hit; ensure_driver("chrome") spawned a live ChromeDriver 152 (port 52082) and stopped it
notes=Required on-target: SSL_CERT_FILE -> the MSYS ca-bundle.crt (the pure-TLS trust store); a C compiler for the harness (used a standalone ziglang.org zig 0.13.0 as `zig cc` — winbaz had none). The dll imports only WS2_32.dll + bcrypt.dll (system) — self-contained, no OpenSSL. Surfaced + fixed two bugs this build (see commit 4af8ddd): binary download corruption (file.write text-encoded the zip) and the Windows cache root using MSYS /c/... HOME that PowerShell rejects.
```

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
