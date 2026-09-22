<?php

/**
 * The 1:1 FFI symbol table for the Selenium core C ABI (core/embed.ae, the
 * aether_sel_embed_* exports of core/selenium_core.ae). This file is the ONLY
 * place in the PHP binding that knows about the C ABI; WebDriver.php is
 * idiomatic PHP over it. No protocol logic lives here — the engine is shared by
 * every language binding.
 *
 * PHP's ext-ffi provides FFI::cdef; every char* the ABI returns is caller-owned
 * and must be freed via aether_sel_embed_free_string. takeString() copies with
 * FFI::string() then frees — the only place a returned pointer is touched.
 *
 * Run with ext-ffi enabled: `php -d extension=ffi -d ffi.enable=1`.
 */

declare(strict_types=1);

namespace SeleniumCore;

use FFI;
use RuntimeException;

final class Native
{
    private const CDEF = <<<'C'
        void* aether_sel_embed_open(const char* base_url);
        void  aether_sel_embed_close(void* h);
        int   aether_sel_embed_execute(void* h, const char* name, const char* params_json);
        char* aether_sel_embed_last_value(void* h);
        int   aether_sel_embed_last_status(void* h);
        int   aether_sel_embed_last_error_code(void* h);
        char* aether_sel_embed_last_error(void* h);
        char* aether_sel_embed_session_id(void* h);
        char* aether_sel_embed_by_locator(const char* strategy, const char* value);
        /* Session-aware By normalization: browser rules against a browser,
           Appium's native strategies against a desktop driver (WinAppDriver /
           Appium). The engine decides from the session; we pass the handle. */
        char* aether_sel_embed_by_locator_for(void* h, const char* strategy, const char* value);
        int aether_sel_embed_is_native(void* h);
        void aether_sel_embed_set_native(void* h, int on);
        char* aether_sel_embed_route(const char* name);
        char* aether_sel_embed_build_request(const char* name, const char* session_id, const char* params_json);
        int   aether_sel_embed_error_code(const char* w3c_error);
        void  aether_sel_embed_free_string(char* s);
        char* aether_sel_embed_resolve_driver(const char* browser, const char* hint);
        void* aether_sel_embed_launch_driver(const char* driver_path, int timeout_ms);
        void* aether_sel_embed_ensure_driver(const char* browser, const char* hint, int timeout_ms);
        char* aether_sel_embed_driver_url(void* dh);
        int   aether_sel_embed_driver_pid(void* dh);
        void  aether_sel_embed_stop_driver(void* dh);
        C;

    private static ?FFI $ffi = null;
    private static ?string $explicitPath = null;

    /** Pin an explicit .so path (wins over env/bundled). */
    public static function configure(?string $path): void
    {
        if ($path !== null && $path !== '' && self::$ffi === null) {
            self::$explicitPath = $path;
        }
    }

    /** Load the engine, caching it process-wide when no explicit path is given. */
    public static function ffi(): FFI
    {
        if (self::$ffi !== null) {
            return self::$ffi;
        }
        if (!\extension_loaded('ffi')) {
            throw new RuntimeException(
                'selenium_core: ext-ffi is not loaded. Run php with '
                . '-d extension=ffi -d ffi.enable=1, or enable it in php.ini.'
            );
        }
        $last = null;
        $tried = [];
        foreach (self::candidates() as $candidate) {
            $tried[] = $candidate;
            try {
                self::$ffi = FFI::cdef(self::CDEF, $candidate);
                return self::$ffi;
            } catch (\Throwable $e) {
                $last = $e;
            }
        }
        throw new RuntimeException(
            'selenium_core: could not load the native Selenium engine '
            . '(libselenium_core). No prebuilt engine was found — fetch it once with:'
            . "\n    composer fetch-engine"
            . "\n  (or:  php bin/fetch-engine)"
            . "\nThis downloads the engine for your platform from the project's "
            . 'GitHub releases and caches it; no Aether toolchain needed. Tried: '
            . \implode(', ', $tried) . '. Last error: '
            . ($last ? $last->getMessage() : 'none')
        );
    }

    /** @return iterable<string> */
    private static function candidates(): iterable
    {
        if (self::$explicitPath !== null && self::$explicitPath !== '') {
            yield self::$explicitPath;
        }
        $env = \getenv('SELENIUM_CORE_LIB');
        if ($env !== false && $env !== '') {
            yield $env;
        }
        $dir = __DIR__;
        yield $dir . '/../native/libselenium_core.so';
        yield $dir . '/../../selenium_core/native/libselenium_core.so';
        // The per-user cache a `composer fetch-engine` download lands in
        // (EngineFetcher::cachedPath). Lets a fetched engine load with no config.
        $cached = self::engineFetcherCachedPath();
        if ($cached !== null) {
            yield $cached;
        }
        yield 'libselenium_core.so';
    }

    /**
     * The path EngineFetcher caches a downloaded engine at, or null if the
     * fetcher isn't available (it's required lazily so Native has no hard dep
     * on it — the binding has no composer autoloader).
     */
    private static function engineFetcherCachedPath(): ?string
    {
        try {
            if (!\class_exists(EngineFetcher::class, false)) {
                $f = __DIR__ . '/EngineFetcher.php';
                if (!\is_file($f)) {
                    return null;
                }
                require_once $f;
            }
            return EngineFetcher::cachedPath();
        } catch (\Throwable) {
            return null;
        }
    }

    /**
     * Copy an ABI-returned char* into a PHP string, then free the original.
     * "" for NULL.
     *
     * @param \FFI\CData $ptr
     */
    public static function takeString(FFI $ffi, $ptr): string
    {
        if ($ptr === null || FFI::isNull($ptr)) {
            return '';
        }
        $s = FFI::string($ptr);
        $ffi->aether_sel_embed_free_string($ptr);
        return $s;
    }
}
