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
        char* aether_sel_embed_route(const char* name);
        char* aether_sel_embed_build_request(const char* name, const char* session_id, const char* params_json);
        int   aether_sel_embed_error_code(const char* w3c_error);
        void  aether_sel_embed_free_string(char* s);
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
            'selenium_core: could not load libselenium_core.so (tried: '
            . \implode(', ', $tried) . '). Last error: '
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
        yield 'libselenium_core.so';
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
