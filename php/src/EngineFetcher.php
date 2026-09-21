<?php

/**
 * Fetches the prebuilt pure-Aether engine (libselenium_core) from the project's
 * GitHub releases and caches it, so a PHP dev never needs the Aether toolchain:
 * `composer install` ships no engine, then ONE explicit command
 *
 *   composer fetch-engine        # or: php bin/fetch-engine
 *
 * downloads the right .so/.dylib/.dll for this OS+arch, verifies its published
 * .sha256, and drops it in the per-user cache where Native's loader already
 * looks. Explicit, one-time, opt-in — nothing downloads behind the dev's back
 * at autoload or install time.
 *
 * PHP stdlib only (file_get_contents over an https stream context + hash()),
 * matching the binding's zero-new-dependency contract.
 */

declare(strict_types=1);

namespace SeleniumCore;

use RuntimeException;

final class EngineFetcher
{
    /**
     * The engine release this binding targets. It tracks the gh-release TAG of
     * the shared engine (NOT the binding's own version) — that is the tag whose
     * assets this fetcher downloads. Bump it when the binding is re-glued to a
     * newer engine.
     */
    public const ENGINE_VERSION = 'v0.9.0';

    public const REPO = 'aether-lang-dev/selaenium';

    /**
     * GET https://github.com/<repo>/releases/download/<tag>/<asset> — the
     * public, unauthenticated asset URL `gh release create` publishes to.
     */
    public const RELEASE_BASE = 'https://github.com/' . self::REPO . '/releases/download';

    /**
     * Download (unless already cached + verified) the engine for this platform
     * and return the absolute path to the cached library. Idempotent: a present,
     * checksum-matching cached copy is returned without a network call. $tag
     * overrides ENGINE_VERSION (e.g. to pin an older engine); $force re-fetches.
     */
    public static function fetch(string $tag = self::ENGINE_VERSION, bool $force = false): string
    {
        $dest = self::cachedPath($tag);
        $want = self::expectedSha($tag);
        if (!$force && \is_file($dest) && self::checksumOk($dest, $want)) {
            return $dest;
        }

        $dir = \dirname($dest);
        if (!\is_dir($dir) && !@\mkdir($dir, 0o755, true) && !\is_dir($dir)) {
            throw new RuntimeException("selenium_core: could not create cache dir {$dir}");
        }

        $asset = self::assetName($tag);
        $url = self::RELEASE_BASE . "/{$tag}/{$asset}";
        $body = self::download($url);

        $got = \hash('sha256', $body);
        if ($want !== null && $got !== $want) {
            throw new RuntimeException(
                "selenium_core: checksum mismatch for {$asset}: expected {$want}, got {$got}"
            );
        }

        // Write atomically so a half-written file is never left where the loader
        // would try to dlopen it.
        $tmp = $dest . '.' . \getmypid() . '.part';
        if (@\file_put_contents($tmp, $body) === false) {
            throw new RuntimeException("selenium_core: could not write {$tmp}");
        }
        if (!@\rename($tmp, $dest)) {
            @\unlink($tmp);
            throw new RuntimeException("selenium_core: could not move engine into place at {$dest}");
        }
        return $dest;
    }

    /**
     * The absolute path the fetched engine is cached at (whether or not it
     * exists yet) — this is exactly the path Native::candidates() adds, so a
     * fetched engine is found on the next load with no further config.
     */
    public static function cachedPath(string $tag = self::ENGINE_VERSION): string
    {
        return self::cacheDir() . \DIRECTORY_SEPARATOR . $tag . \DIRECTORY_SEPARATOR . self::libraryFilename();
    }

    /**
     * $XDG_CACHE_HOME/selaenium (or the OS default): ~/.cache/selaenium on
     * Linux, ~/Library/Caches/selaenium on macOS, %LOCALAPPDATA%\selaenium on
     * Windows. Kept separate from the package so it survives reinstalls.
     */
    public static function cacheDir(): string
    {
        $xdg = \getenv('XDG_CACHE_HOME');
        if ($xdg !== false && $xdg !== '') {
            $base = $xdg;
        } elseif (\PHP_OS_FAMILY === 'Windows') {
            $local = \getenv('LOCALAPPDATA');
            $base = ($local !== false && $local !== '')
                ? $local
                : self::home() . \DIRECTORY_SEPARATOR . 'AppData' . \DIRECTORY_SEPARATOR . 'Local';
        } elseif (\PHP_OS_FAMILY === 'Darwin') {
            $base = self::home() . \DIRECTORY_SEPARATOR . 'Library' . \DIRECTORY_SEPARATOR . 'Caches';
        } else {
            $base = self::home() . \DIRECTORY_SEPARATOR . '.cache';
        }
        return $base . \DIRECTORY_SEPARATOR . 'selaenium';
    }

    /**
     * The gh-release asset for this platform, e.g.
     * libselenium_core-v0.8.0-linux-x86_64.so.
     */
    public static function assetName(string $tag = self::ENGINE_VERSION): string
    {
        return "libselenium_core-{$tag}-" . self::osTag() . '-' . self::archTag() . '.' . self::ext();
    }

    /**
     * The local filename the loader looks for (bare libselenium_core.<ext>, no
     * tag/platform — the cache dir already keys by tag).
     */
    public static function libraryFilename(): string
    {
        return match (\PHP_OS_FAMILY) {
            'Windows' => 'selenium_core.dll',
            'Darwin' => 'libselenium_core.dylib',
            default => 'libselenium_core.so',
        };
    }

    // --- platform mapping (matches release/build.sh's artifact names) ---

    public static function osTag(): string
    {
        return match (\PHP_OS_FAMILY) {
            'Windows' => 'windows',
            'Darwin' => 'macos',
            'Linux' => 'linux',
            default => throw new RuntimeException(
                'selenium_core: unsupported OS for a prebuilt engine: ' . \PHP_OS_FAMILY
            ),
        };
    }

    public static function archTag(): string
    {
        $m = \strtolower(\trim((string) \php_uname('m')));
        return match (true) {
            \in_array($m, ['x86_64', 'x64', 'amd64'], true) => 'x86_64',
            \in_array($m, ['arm64', 'aarch64'], true) => 'arm64',
            default => throw new RuntimeException(
                "selenium_core: unsupported CPU for a prebuilt engine: {$m}"
            ),
        };
    }

    public static function ext(): string
    {
        return match (\PHP_OS_FAMILY) {
            'Windows' => 'dll',
            'Darwin' => 'dylib',
            default => 'so',
        };
    }

    // --- helpers ---

    /**
     * Fetch the published <asset>.sha256 sidecar (a "<hex>  <name>" line) and
     * return the hex. Returns null if the sidecar can't be fetched — the caller
     * then downloads without a checksum gate rather than failing hard, but a
     * present sidecar is always enforced.
     */
    public static function expectedSha(string $tag = self::ENGINE_VERSION): ?string
    {
        try {
            $line = self::download(self::RELEASE_BASE . "/{$tag}/" . self::assetName($tag) . '.sha256');
        } catch (RuntimeException) {
            return null;
        }
        $first = \preg_split('/\s+/', \trim($line))[0] ?? '';
        return $first === '' ? null : $first;
    }

    private static function checksumOk(string $path, ?string $want): bool
    {
        if ($want === null) {
            return false;
        }
        return \hash_file('sha256', $path) === $want;
    }

    private static function home(): string
    {
        $home = \getenv('HOME');
        if ($home !== false && $home !== '') {
            return $home;
        }
        $up = \getenv('USERPROFILE');
        return ($up !== false && $up !== '') ? $up : \sys_get_temp_dir();
    }

    /**
     * GET a URL, following GitHub's redirect to the asset CDN. Binary-safe.
     * Uses only the PHP stdlib (an https stream context with follow_location).
     */
    private static function download(string $url): string
    {
        $ctx = \stream_context_create([
            'http' => [
                'method' => 'GET',
                'follow_location' => 1,
                'max_redirects' => 6,
                'timeout' => 120,
                'header' => 'User-Agent: selaenium-php/' . self::ENGINE_VERSION . "\r\n",
                'ignore_errors' => true,
            ],
            'ssl' => [
                'verify_peer' => true,
                'verify_peer_name' => true,
            ],
        ]);
        $body = @\file_get_contents($url, false, $ctx);
        if ($body === false) {
            $err = \error_get_last();
            throw new RuntimeException(
                "selenium_core: GET {$url} failed" . ($err ? ': ' . $err['message'] : '')
            );
        }
        // $http_response_header is populated by the http stream wrapper.
        $status = self::statusFromHeaders($http_response_header ?? []);
        if ($status !== null && ($status < 200 || $status >= 300)) {
            throw new RuntimeException("selenium_core: GET {$url} -> HTTP {$status}");
        }
        return $body;
    }

    /** @param list<string> $headers */
    private static function statusFromHeaders(array $headers): ?int
    {
        // After redirects the wrapper leaves each response's status line in
        // order; the last "HTTP/..." line is the final response.
        $code = null;
        foreach ($headers as $h) {
            if (\preg_match('#^HTTP/\S+\s+(\d{3})#', $h, $m) === 1) {
                $code = (int) $m[1];
            }
        }
        return $code;
    }
}
