# chromedriver version-resolution algorithm — extracted reference spec

Extracted from the classic Selenium Manager Rust source (`classic-selenium`
branch, `rust/src/{chrome,lib,files,metadata,downloads,config}.rs`) for the
pure-Aether port. This is the B1 (chrome vertical slice) implementation
reference. NOTE: `rules.rs` is NOT the version-match logic (it's an unrelated
LLM-rules writer) — the resolution lives in `chrome.rs` + `lib.rs`.

## Constants (quote exactly)

    CFT_URL                  = "https://googlechromelabs.github.io/chrome-for-testing/"
    GOOD_VERSIONS_ENDPOINT   = "known-good-versions-with-downloads.json"      (big versions[] list)
    LATEST_VERSIONS_ENDPOINT = "last-known-good-versions-with-downloads.json" (small channels file)
    DRIVER_URL (pre-CfT)     = "https://chromedriver.storage.googleapis.com/"
    LATEST_RELEASE           = "LATEST_RELEASE"
    MIN_CHROME_VERSION_CFT       = 113   (browser-download floor)
    MIN_CHROMEDRIVER_VERSION_CFT = 115   (CfT-vs-legacy driver cutoff)
    CHROME_NAME="chrome"  CHROMEDRIVER_NAME="chromedriver"
    CACHE_FOLDER=".cache/selenium"  METADATA_FILE="se-metadata.json"
    TTL_SEC=3600  CACHE_TTL_DAYS=30
    CHROMIUM_SNAP_LINK="/snap/bin/chromium"
    CHROMIUM_SNAP_BINARY="/snap/chromium/current/usr/lib/chromium-browser/chrome"

Counter-intuitive: LATEST_VERSIONS_ENDPOINT (last-known-good-*) = the small
Stable/Beta/Dev/Canary channels file; GOOD_VERSIONS_ENDPOINT (known-good-*) =
the big ascending versions[] list.

## 1. Browser detection
(a) Linux fixed-location scan (default channel only): dirs
  /usr/local/sbin,/usr/local/bin,/usr/sbin,/usr/bin,/sbin,/bin,/opt/google/chrome,/opt/chromium.org/chromium
  names chrome,google-chrome,chromium,chromium-browser (NAME-major search).
(b) Channel path map: LINUX stable=/usr/bin/google-chrome, beta=-beta, dev=-unstable.
  MACOS /Applications/Google Chrome[ Beta/Dev/Canary].app/Contents/MacOS/...
  WINDOWS Google\Chrome[ Beta/Dev/SxS]\Application\chrome.exe under %PROGRAMFILES%*.
(c) PATH fallback via `which` over [chrome,google-chrome,chromium,chromium-browser];
  snap: if path==CHROMIUM_SNAP_LINK substitute CHROMIUM_SNAP_BINARY.
Version cmd: Win → PE ProductVersion (GetFileVersionInfoW) else REG QUERY
  HKCU\...\BLBeacon /v version; mac/linux → `<path> --version`.
Parse (files.rs parse_version): split on spaces; per token strip [^\d.]; match
  `(?:(\d+)\.)?(?:(\d+)\.)?(?:(\d+)\.\d+)`; first match wins; strip trailing dot;
  "error" (any case) in output → "Wrong browser/driver version". major=split('.')[0].

## 2. Driver-version resolution (request_driver_version, chrome.rs)
Step 0: metadata TTL cache — get_driver_version_from_metadata(drivers,"chromedriver",
  major_browser_version); exact (name,major) match, expired rows pruned on load → return.
Step 0.5: offline guard on miss → err "Unable to discover proper chromedriver version in offline mode".
Step 1 branch (exact order):
  1. stable OR major empty OR unstable → request_latest_driver_version_from_online()  [Path A]
  2. else major_int < 115 → legacy request_driver_version_from_latest(LATEST_RELEASE_<major>) [Path B]
  3. else → request_good_driver_version_from_online()  [Path C]
Step 2: cache write if ttl>0 && major!="" && driver_version!="".

Path A (latest stable): GET CFT_URL+last-known-good-versions-with-downloads.json →
  .channels.Stable; chromedriver=stable.downloads.chromedriver (Option).
  If None → fall back to legacy GET DRIVER_URL+LATEST_RELEASE (plain text), driver_url unset.
  Else filter chromedriver where platform==label (case-insens), driver_url=first().url,
  return stable.version.
Path B (Chrome <=114): GET DRIVER_URL+"LATEST_RELEASE_"+major (plain text) → parse_version.
Path C (CfT known-good, 115+): version_for_filtering = full driver version if specific,
  else major of (driver_version||browser_version). GET CFT_URL+known-good-versions-with-downloads.json
  → .versions[] filter where version.starts_with(version_for_filtering); if empty → hard err
  "chromedriver <v> not available ... (minimum version: 115)"; else take .last() (ascending!),
  in its .downloads.chromedriver filter platform==label, driver_url=first().url, return .version.

get_driver_url(): if major>=115 && driver_url None → run Path C to populate. If driver_url Some
  → return it. Else legacy URL: {DRIVER_URL}{driver_version}/chromedriver_{label}.zip where
  label: Win=win32; macArm64= major<106?mac64_m1:mac_arm64; macX64=mac64; Linux arm64=HARD ERROR;
  else linux64.

## 3. JSON shapes
last-known-good-*: { channels: { Stable:{ version, downloads:{ chrome:[{platform,url}],
  chromedriver:[{platform,url}]? } }, Beta, Dev, Canary } }
known-good-*: { versions:[ { version, downloads:{ chrome:[...], chromedriver:[...]? } } ] } (ascending)
PlatformUrl={platform,url}; platform match eq_ignore_ascii_case.

## 4. Platform label (get_platform_label) — CfT filter AND cache subdir
  Win x32→win32, Win x64→win64, mac arm64→mac-arm64, mac x64→mac-x64, else linux64.
  X32=[x86,i386,x32,i686] X64=[x86_64,amd64,x64,ia64] ARM64=[arm64,aarch64,arm].
  (Legacy driver-url labels DIFFER: mac64/mac64_m1/mac_arm64/win32/linux64.)

## 5. Cache + metadata
Root: <home>/.cache/selenium (SE_CACHE_PATH/config override).
Driver dir: <cache>/<driver>/<label>/<version>/<driver><ext>  (ext=.exe on Win).
Browser dir: <cache>/<browser>/<label>/<version>/ (+ mac .app/Contents/MacOS/...).
se-metadata.json at <cache>/se-metadata.json:
  { browsers:[{browser_name,major_browser_version,browser_version,browser_ttl}],
    drivers:[{major_browser_version,driver_name,driver_version,driver_ttl}],
    stats:[...], cached_assets:[{asset_name,asset_version,last_used}] }
TTL = absolute unix expiry (now+ttl at write); pruned on read where ttl<=now;
  corrupt file → empty metadata (not fatal). Lookup exact (driver_name,major), first match.

## 6. Download + unpack
Lock at driver cache dir; if lock absent && path exists → already downloaded.
get_driver_url → archive; download to selenium-manager tmp; filename=last URL segment.
uncompress: format by MAGIC BYTES (infer), not extension; chromedriver always .zip → unzip.
Zip quirk: 115+ zips wrap in a top folder, 114- don't → strip first path component when >1;
  single_file=Some("chromedriver"+ext). chmod 0o755 on the single extracted binary (Unix).
Final binary → compose_driver_path_in_cache path.

## 7. Offline / fallback / scars
- --offline blocks discovery (unless TTL cache has it); "Unable to download chromedriver in offline mode".
- Cache-first everywhere; driver binary in cache → skip download + refresh cached_assets.last_used.
- Driver-in-PATH short-circuit: chromedriver on PATH && no browser version specified && discovery
  fails → swallow error (only if fallback_driver_from_cache) + compat warning if majors differ.
- fallback_driver_from_cache=false when user-caused mismatch (bad --browser-path, missing browser,
  failed browser download) → errors propagate instead of silent PATH/cache use.
- find_best_driver_from_cache: prefer cached driver whose version-dir starts with browser major
  (take last), else latest driver of any version.
- CfT stable chromedriver==None → legacy LATEST_RELEASE fallback. CfT known-good empty → hard err
  (no silent previous-stable). Metadata write skipped when ttl==0/empty major/empty version.

## Scars checklist (design out)
1. Endpoint names swapped-feeling (see Constants).
2. 115 = CfT/legacy cutoff; 113 = browser floor.
3. stable/unstable/empty → latest-stable channel path (reads .channels.Stable).
4. known-good filtered list ASCENDING → take .last(); prefix-match on FULL major only.
5. legacy vs CfT platform labels differ; mac arm64 legacy split at driver major 106.
6. Linux arm64 = hard error for Chrome.
7. zip top-folder flatten (115+ folder, 114- none); force 0o755 on single binary.
8. TTL absolute expiry, pruned on read; corrupt metadata → empty, not fatal.
