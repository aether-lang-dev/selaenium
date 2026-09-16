/// Fetches the prebuilt pure-Aether engine (`libselenium_core`) from the
/// project's GitHub releases and caches it, so a Dart dev never needs the Aether
/// toolchain: `dart pub get` ships no engine, then ONE explicit command
///
/// ```
/// dart run selenium:fetch_engine        # or EngineFetcher.fetch()
/// ```
///
/// downloads the right `.so`/`.dylib`/`.dll` for this OS+arch, verifies its
/// published `.sha256`, and drops it in the per-user cache where [Native]'s
/// loader already looks. Explicit, one-time, opt-in — no download happens behind
/// the dev's back at import or `pub get` time.
///
/// Stdlib only (`dart:io` for HTTP + a self-contained SHA-256 below), matching
/// the package's zero-runtime-dependency contract (mirrors Ruby's EngineFetcher,
/// which is net/http + digest only).
library;

import 'dart:async';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:typed_data';

/// Raised when the engine cannot be downloaded or fails its checksum gate.
class FetchException implements Exception {
  final String message;
  FetchException(this.message);
  @override
  String toString() => 'FetchException: $message';
}

/// Downloads + caches the shared engine from GitHub releases. All members are
/// static; the type is a namespace, mirroring Ruby's `module EngineFetcher`.
class EngineFetcher {
  EngineFetcher._();

  /// The engine release this package targets. It tracks the gh-release TAG of
  /// the shared engine (NOT the package's own version) — that is the tag whose
  /// assets this fetcher downloads. Bump it when the package is re-glued to a
  /// newer engine.
  static const String engineVersion = 'v0.8.0';

  static const String repo = 'aether-lang-dev/selaenium';

  /// `GET https://github.com/<repo>/releases/download/<tag>/<asset>` — the
  /// public, unauthenticated asset URL `gh release create` publishes to.
  static const String releaseBase =
      'https://github.com/$repo/releases/download';

  /// Download (unless already cached + verified) the engine for this platform
  /// and return the absolute path to the cached library. Idempotent: a present,
  /// checksum-matching cached copy is returned without a network call. [tag]
  /// overrides [engineVersion] (e.g. to pin an older engine); [force] re-fetches.
  static Future<String> fetch({
    String tag = engineVersion,
    bool force = false,
  }) async {
    final dest = cachedPath(tag);
    final want = await _expectedSha(tag);
    if (!force && File(dest).existsSync() && _checksumOk(dest, want)) {
      return dest;
    }

    Directory(File(dest).parent.path).createSync(recursive: true);
    final asset = assetName(tag);
    final url = '$releaseBase/$tag/$asset';
    final body = await _download(url);

    if (want != null) {
      final got = _sha256Hex(body);
      if (got != want) {
        throw FetchException(
            'checksum mismatch for $asset: expected $want, got $got');
      }
    }

    // Write atomically so a half-written file is never left where the loader
    // would try to open it.
    final tmp = '$dest.$pid.part';
    File(tmp).writeAsBytesSync(body, flush: true);
    File(tmp).renameSync(dest);
    return dest;
  }

  /// The absolute path the fetched engine is cached at (whether or not it exists
  /// yet) — this is exactly the path [Native]'s loader adds, so a fetched engine
  /// is found on the next load with no further config.
  static String cachedPath([String tag = engineVersion]) =>
      '${cacheDir()}${Platform.pathSeparator}$tag${Platform.pathSeparator}${libraryFilename()}';

  /// `$XDG_CACHE_HOME/selaenium` (or the OS default): `~/.cache/selaenium` on
  /// Linux, `~/Library/Caches/selaenium` on macOS,
  /// `%LOCALAPPDATA%\selaenium` on Windows. Kept separate from the package so it
  /// survives package upgrades/reinstalls.
  static String cacheDir() {
    final env = Platform.environment;
    final sep = Platform.pathSeparator;
    String base;
    final xdg = env['XDG_CACHE_HOME'];
    if (xdg != null && xdg.isNotEmpty) {
      base = xdg;
    } else if (Platform.isWindows) {
      base = env['LOCALAPPDATA'] ??
          '${_home()}${sep}AppData${sep}Local';
    } else if (Platform.isMacOS) {
      base = '${_home()}${sep}Library${sep}Caches';
    } else {
      base = '${_home()}$sep.cache';
    }
    return '$base${sep}selaenium';
  }

  /// The gh-release asset for this platform, e.g.
  /// `libselenium_core-v0.8.0-linux-x86_64.so`.
  static String assetName([String tag = engineVersion]) =>
      'libselenium_core-$tag-${osTag()}-${archTag()}.${ext()}';

  /// The local filename the loader looks for (bare `libselenium_core.<ext>`, no
  /// tag/platform — the cache dir already keys by tag). Matches [Native]'s own
  /// filename logic.
  static String libraryFilename() {
    if (Platform.isWindows) return 'selenium_core.dll';
    if (Platform.isMacOS) return 'libselenium_core.dylib';
    return 'libselenium_core.so';
  }

  // --- platform mapping (matches release/build.sh's artifact names) ---

  static String osTag() {
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    throw FetchException(
        'unsupported OS for a prebuilt engine: ${Platform.operatingSystem}');
  }

  static String archTag() {
    // Abi.current() renders as `<os>_<arch>`, e.g. linux_x64 / macos_arm64.
    final abi = Abi.current().toString();
    final arch = abi.contains('_') ? abi.split('_').last : abi;
    switch (arch) {
      case 'x64':
      case 'x86_64':
      case 'amd64':
        return 'x86_64';
      case 'arm64':
      case 'aarch64':
        return 'arm64';
      default:
        throw FetchException(
            'unsupported CPU for a prebuilt engine: $abi');
    }
  }

  static String ext() {
    if (Platform.isWindows) return 'dll';
    if (Platform.isMacOS) return 'dylib';
    return 'so';
  }

  // --- helpers ---

  static String _home() {
    final env = Platform.environment;
    return env['HOME'] ?? env['USERPROFILE'] ?? Directory.current.path;
  }

  /// Fetch the published `<asset>.sha256` sidecar (a "<hex>  <name>" line) and
  /// return the hex. Returns null if the sidecar can't be fetched — the caller
  /// then downloads without a checksum gate rather than failing hard, but a
  /// present sidecar is always enforced.
  static Future<String?> _expectedSha([String tag = engineVersion]) async {
    try {
      final line = await _download('$releaseBase/$tag/${assetName(tag)}.sha256');
      final text = String.fromCharCodes(line).trim();
      final first = text.split(RegExp(r'\s+')).first;
      return first.isEmpty ? null : first;
    } on FetchException {
      return null;
    }
  }

  /// Public accessor for the expected checksum, used by tests + `fetch`.
  static Future<String?> expectedSha([String tag = engineVersion]) =>
      _expectedSha(tag);

  static bool _checksumOk(String path, String? want) {
    if (want == null) return false;
    return _sha256Hex(File(path).readAsBytesSync()) == want;
  }

  /// GET a URL, following GitHub's redirect to the asset CDN. Binary-safe.
  static Future<Uint8List> _download(String url, {int limit = 5}) async {
    if (limit <= 0) {
      throw FetchException('too many redirects fetching $url');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      // Follow redirects ourselves so the User-Agent is re-sent and errors are
      // legible (GitHub 302s to a CDN host).
      ..userAgent = 'selaenium-dart';
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.followRedirects = false;
      req.headers.set(HttpHeaders.userAgentHeader, 'selaenium-dart');
      final res = await req.close();

      final code = res.statusCode;
      if (code >= 200 && code < 300) {
        final builder = BytesBuilder(copy: false);
        await for (final chunk in res) {
          builder.add(chunk);
        }
        return builder.takeBytes();
      }
      if (code >= 300 && code < 400) {
        final loc = res.headers.value(HttpHeaders.locationHeader);
        await res.drain<void>();
        if (loc == null || loc.isEmpty) {
          throw FetchException('GET $url -> $code with no Location header');
        }
        final next = Uri.parse(url).resolve(loc).toString();
        return _download(next, limit: limit - 1);
      }
      await res.drain<void>();
      throw FetchException('GET $url -> $code ${res.reasonPhrase}');
    } on SocketException catch (e) {
      throw FetchException('GET $url failed: $e');
    } on HttpException catch (e) {
      throw FetchException('GET $url failed: $e');
    } finally {
      client.close(force: true);
    }
  }

  // --- SHA-256 (FIPS 180-4), self-contained to keep zero runtime deps ---
  // A tiny, allocation-light implementation so the package stays dependency-free
  // like Ruby's Digest-based fetcher (package:crypto is only a transitive test
  // dependency here, not something lib/ code may rely on).

  static const List<int> _k = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, //
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  static int _rotr(int x, int n) =>
      ((x >>> n) | (x << (32 - n))) & 0xffffffff;

  /// Lowercase hex SHA-256 of [data].
  static String _sha256Hex(List<int> data) {
    var h0 = 0x6a09e667,
        h1 = 0xbb67ae85,
        h2 = 0x3c6ef372,
        h3 = 0xa54ff53a,
        h4 = 0x510e527f,
        h5 = 0x9b05688c,
        h6 = 0x1f83d9ab,
        h7 = 0x5be0cd19;

    final len = data.length;
    // Padding: 0x80, then zeros, then 64-bit big-endian bit length.
    final bitLen = len * 8;
    final withOne = len + 1;
    final padded = ((withOne + 8 + 63) ~/ 64) * 64;
    final msg = Uint8List(padded);
    msg.setRange(0, len, data);
    msg[len] = 0x80;
    // 64-bit length; Dart ints are 64-bit, bitLen fits for our sizes.
    for (var i = 0; i < 8; i++) {
      msg[padded - 1 - i] = (bitLen >>> (8 * i)) & 0xff;
    }

    final w = Int32List(64);
    for (var chunk = 0; chunk < padded; chunk += 64) {
      for (var i = 0; i < 16; i++) {
        final j = chunk + i * 4;
        w[i] = (msg[j] << 24) |
            (msg[j + 1] << 16) |
            (msg[j + 2] << 8) |
            msg[j + 3];
      }
      for (var i = 16; i < 64; i++) {
        final wi15 = w[i - 15] & 0xffffffff;
        final wi2 = w[i - 2] & 0xffffffff;
        final s0 = _rotr(wi15, 7) ^ _rotr(wi15, 18) ^ (wi15 >>> 3);
        final s1 = _rotr(wi2, 17) ^ _rotr(wi2, 19) ^ (wi2 >>> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
      }

      var a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, hh = h7;
      for (var i = 0; i < 64; i++) {
        final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
        final ch = (e & f) ^ (~e & g);
        final t1 = (hh + s1 + ch + _k[i] + (w[i] & 0xffffffff)) & 0xffffffff;
        final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final t2 = (s0 + maj) & 0xffffffff;
        hh = g;
        g = f;
        f = e;
        e = (d + t1) & 0xffffffff;
        d = c;
        c = b;
        b = a;
        a = (t1 + t2) & 0xffffffff;
      }

      h0 = (h0 + a) & 0xffffffff;
      h1 = (h1 + b) & 0xffffffff;
      h2 = (h2 + c) & 0xffffffff;
      h3 = (h3 + d) & 0xffffffff;
      h4 = (h4 + e) & 0xffffffff;
      h5 = (h5 + f) & 0xffffffff;
      h6 = (h6 + g) & 0xffffffff;
      h7 = (h7 + hh) & 0xffffffff;
    }

    final out = StringBuffer();
    for (final h in [h0, h1, h2, h3, h4, h5, h6, h7]) {
      out.write(h.toRadixString(16).padLeft(8, '0'));
    }
    return out.toString();
  }

  /// Exposed for tests: lowercase hex SHA-256 of [data].
  static String sha256Hex(List<int> data) => _sha256Hex(data);
}
