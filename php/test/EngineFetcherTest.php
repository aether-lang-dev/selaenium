<?php

// Unit test for the engine fetcher — the `composer fetch-engine` machinery that
// lets a PHP dev get the prebuilt pure-Aether engine from GitHub releases with
// no Aether toolchain. The pure logic (asset naming, cache path, platform
// mapping, the version pin) needs no network. One live download test is gated
// on SELENIUM_FETCH_LIVE=1 so the default suite stays offline/deterministic.

declare(strict_types=1);

use PHPUnit\Framework\TestCase;
use SeleniumCore\EngineFetcher;
use SeleniumCore\Native;
use SeleniumCore\WebDriver;

final class EngineFetcherTest extends TestCase
{
    public function testEngineVersionIsAReleaseTag(): void
    {
        $this->assertMatchesRegularExpression(
            '/^v\d+\.\d+\.\d+$/',
            EngineFetcher::ENGINE_VERSION,
            'ENGINE_VERSION is a vX.Y.Z gh-release tag'
        );
        $this->assertSame(
            EngineFetcher::ENGINE_VERSION,
            WebDriver::ENGINE_VERSION,
            're-exported on the WebDriver class'
        );
    }

    public function testAssetNameMatchesTheReleaseArtifactScheme(): void
    {
        // libselenium_core-<tag>-<os>-<arch>.<ext> — exactly what release/build.sh emits.
        $this->assertMatchesRegularExpression(
            '/^libselenium_core-v\d+\.\d+\.\d+-(linux|macos|windows)-(x86_64|arm64)\.(so|dylib|dll)$/',
            EngineFetcher::assetName()
        );
    }

    public function testCachedPathIsUnderTheCacheDirKeyedByTag(): void
    {
        $path = EngineFetcher::cachedPath();
        $this->assertStringStartsWith(EngineFetcher::cacheDir(), $path, 'cached under the cache dir');
        $this->assertStringContainsString(
            EngineFetcher::ENGINE_VERSION,
            $path,
            'keyed by the engine tag (survives reinstalls)'
        );
        $this->assertSame(
            EngineFetcher::libraryFilename(),
            \basename($path),
            'bare library filename the loader looks for'
        );
    }

    public function testCachedPathIsKeyedByTagArgument(): void
    {
        $this->assertStringContainsString('v9.9.9', EngineFetcher::cachedPath('v9.9.9'));
        $this->assertStringNotContainsString('v9.9.9', EngineFetcher::cachedPath());
    }

    public function testPlatformMappingIsTotalForThisHost(): void
    {
        // osTag/archTag/ext must not throw on the host running the suite.
        $this->assertContains(EngineFetcher::osTag(), ['linux', 'macos', 'windows']);
        $this->assertContains(EngineFetcher::archTag(), ['x86_64', 'arm64']);
        $this->assertContains(EngineFetcher::ext(), ['so', 'dylib', 'dll']);
    }

    public function testLoaderLooksInTheFetchCache(): void
    {
        // Native's candidate list must include exactly where the fetcher caches,
        // so a fetched engine loads with no further config.
        $reflect = new \ReflectionMethod(Native::class, 'candidates');
        $reflect->setAccessible(true);
        $cands = \iterator_to_array($reflect->invoke(null), false);
        $this->assertContains(EngineFetcher::cachedPath(), $cands);
    }

    public function testLiveFetchDownloadsAndVerifies(): void
    {
        if (\getenv('SELENIUM_FETCH_LIVE') !== '1') {
            $this->markTestSkipped('set SELENIUM_FETCH_LIVE=1 to hit the network');
        }
        $dir = \sys_get_temp_dir() . \DIRECTORY_SEPARATOR . 'selaenium-fetch-test-' . \getmypid();
        $prev = \getenv('XDG_CACHE_HOME');
        \putenv("XDG_CACHE_HOME={$dir}");
        try {
            $path = WebDriver::fetchEngine(EngineFetcher::ENGINE_VERSION, true);
            $this->assertFileExists($path, 'engine downloaded to the cache');
            $this->assertGreaterThan(0, \filesize($path), 'non-empty');
            $want = EngineFetcher::expectedSha();
            if ($want !== null) {
                $this->assertSame($want, \hash_file('sha256', $path), 'matches the published .sha256');
            }
        } finally {
            if ($prev === false) {
                \putenv('XDG_CACHE_HOME');
            } else {
                \putenv("XDG_CACHE_HOME={$prev}");
            }
        }
    }
}
