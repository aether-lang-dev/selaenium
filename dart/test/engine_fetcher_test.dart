// Unit test for the engine fetcher — the `dart run selenium:fetch_engine`
// machinery that lets a Dart dev get the prebuilt pure-Aether engine from
// GitHub releases with no Aether toolchain. The pure logic (asset naming, cache
// path, platform mapping, the version pin, SHA-256) needs no network. One live
// download test is gated on SELENIUM_FETCH_LIVE=1 so the default suite stays
// offline/deterministic. Mirrors ruby/spec/engine_fetcher_test.rb.
import 'dart:convert';
import 'dart:io';

import 'package:selenium/selenium.dart';
import 'package:selenium/src/native.dart';
import 'package:test/test.dart';

void main() {
  test('engineVersion is a release tag, re-exported at the top level', () {
    expect(EngineFetcher.engineVersion, matches(RegExp(r'^v\d+\.\d+\.\d+$')),
        reason: 'engineVersion is a vX.Y.Z gh-release tag');
    expect(EngineFetcher.engineVersion, 'v0.9.0');
  });

  test('assetName matches the release artifact scheme', () {
    // libselenium_core-<tag>-<os>-<arch>.<ext> — exactly what release/build.sh emits.
    expect(
      EngineFetcher.assetName(),
      matches(RegExp(
          r'^libselenium_core-v\d+\.\d+\.\d+-(linux|macos|windows)-(x86_64|arm64)\.(so|dylib|dll)$')),
    );
  });

  test('cachedPath is under the cache dir, keyed by tag', () {
    final path = EngineFetcher.cachedPath();
    expect(path, startsWith(EngineFetcher.cacheDir()),
        reason: 'cached under the cache dir');
    expect(path, contains(EngineFetcher.engineVersion),
        reason: 'keyed by the engine tag (survives package upgrades)');
    expect(path.split(Platform.pathSeparator).last,
        EngineFetcher.libraryFilename(),
        reason: 'bare library filename the loader looks for');
  });

  test('cachedPath keys by an overriding tag', () {
    final path = EngineFetcher.cachedPath('v9.9.9');
    expect(path, contains('v9.9.9'));
    expect(path, isNot(contains(EngineFetcher.engineVersion)));
  });

  test('platform mapping is total for this host', () {
    expect(['linux', 'macos', 'windows'], contains(EngineFetcher.osTag()));
    expect(['x86_64', 'arm64'], contains(EngineFetcher.archTag()));
    expect(['so', 'dylib', 'dll'], contains(EngineFetcher.ext()));
  });

  test('loader candidate list includes the fetch cache path', () {
    // Native's candidate list must include exactly where the fetcher caches, so
    // a fetched engine loads with no further config.
    expect(Native.candidatesForTest(), contains(EngineFetcher.cachedPath()));
  });

  test('sha256 matches known vectors', () {
    // FIPS 180-4 sample + empty string, proving the self-contained digest.
    expect(EngineFetcher.sha256Hex(utf8.encode('')),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    expect(EngineFetcher.sha256Hex(utf8.encode('abc')),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    expect(
        EngineFetcher.sha256Hex(utf8.encode(
            'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq')),
        '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1');
  });

  test('live fetch downloads and verifies', () async {
    if (Platform.environment['SELENIUM_FETCH_LIVE'] != '1') {
      markTestSkipped('set SELENIUM_FETCH_LIVE=1 to hit the network');
      return;
    }
    final dir =
        Directory.systemTemp.createTempSync('selaenium_fetch_test_');
    try {
      // The fetcher reads XDG_CACHE_HOME from Platform.environment; run a child
      // process with it pointed at the tmp dir so the real cache is untouched.
      final result = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'bin/fetch_engine.dart', '--force'],
        environment: {'XDG_CACHE_HOME': dir.path},
        workingDirectory: Directory.current.path,
      );
      expect(result.exitCode, 0,
          reason: 'fetch_engine exited nonzero:\n${result.stderr}');

      final expected =
          '${dir.path}${Platform.pathSeparator}selaenium${Platform.pathSeparator}${EngineFetcher.engineVersion}${Platform.pathSeparator}${EngineFetcher.libraryFilename()}';
      final f = File(expected);
      expect(f.existsSync(), isTrue,
          reason: 'engine downloaded to the cache at $expected');
      expect(f.lengthSync(), greaterThan(0), reason: 'non-empty');

      final want = await EngineFetcher.expectedSha();
      if (want != null) {
        expect(EngineFetcher.sha256Hex(f.readAsBytesSync()), want,
            reason: 'matches the published .sha256');
      }
    } finally {
      dir.deleteSync(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
