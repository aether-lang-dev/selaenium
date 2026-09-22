<?php

/**
 * Selenium WebDriver for PHP, over the shared pure-Aether engine.
 *
 * Carries NO protocol logic: the W3C command map, routing, By normalization,
 * error decode and HTTP round-trip all live in the Aether engine, reached
 * through Native (ext-ffi). This is pure marshalling: PHP arrays <-> JSON.
 */

declare(strict_types=1);

namespace SeleniumCore;

// No composer autoloader (thin hand-written binding): pull in the fetcher so
// WebDriver::ENGINE_VERSION / fetchEngine() resolve.
require_once __DIR__ . '/EngineFetcher.php';

use FFI;

final class By
{
    public const ID = 'id';
    public const NAME = 'name';
    public const CSS = 'css selector';
    public const CLASS_NAME = 'className';
    public const TAG_NAME = 'tag name';
    public const LINK_TEXT = 'link text';
    public const PARTIAL_LINK_TEXT = 'partial link text';
    public const XPATH = 'xpath';

    // --- desktop / native strategies (WinAppDriver, Appium) ---------------
    // Against a native driver the engine does NOT rewrite ID/NAME/CLASS_NAME to
    // CSS: they are the driver's own UIA AutomationId / Name / ClassName, and a
    // native driver has no CSS engine. So the constants above keep working on
    // desktop; these add the strategies that only exist there. Values match
    // Appium's AppiumBy.
    public const ACCESSIBILITY_ID = 'accessibility id';
    public const ANDROID_UIAUTOMATOR = 'androidUIAutomator';
    public const ANDROID_VIEWTAG = 'androidViewTag';
    public const ANDROID_DATAMATCHER = 'androidDataMatcher';
    public const ANDROID_VIEWMATCHER = 'androidViewMatcher';
    public const IOS_PREDICATE = 'iOSPredicateString';
    public const IOS_CLASS_CHAIN = 'iOSClassChain';
    public const IMAGE = 'image';
    public const CUSTOM = 'custom';
}

class WebDriverException extends \RuntimeException
{
    public int $code_;
    public function __construct(string $message, int $code)
    {
        parent::__construct($message);
        $this->code_ = $code;
    }
}

final class NoSuchElementException extends WebDriverException {}
final class StaleElementReferenceException extends WebDriverException {}
final class TimeoutException extends WebDriverException {}
final class InvalidSelectorException extends WebDriverException {}
final class NoSuchShadowRootException extends WebDriverException {}
final class DetachedShadowRootException extends WebDriverException {}

const W3C_ELEMENT_KEY = 'element-6066-11e4-a52e-4f735466cecf';
const W3C_SHADOW_KEY = 'shadow-6066-11e4-a52e-4f735466cecf';

final class WebElement
{
    public function __construct(private WebDriver $driver, public string $id) {}

    public function click(): void { $this->exec('clickElement'); }
    public function clear(): void { $this->exec('clearElement'); }
    public function sendKeys(string $text): void
    {
        $this->exec('sendKeysToElement', ['text' => $text, 'value' => \preg_split('//u', $text, -1, PREG_SPLIT_NO_EMPTY)]);
    }
    public function text(): string { return (string) $this->exec('getElementText'); }
    public function tagName(): string { return (string) $this->exec('getElementTagName'); }
    public function getProperty(string $name): mixed { return $this->exec('getElementProperty', ['name' => $name]); }
    public function rect(): array { return (array) $this->exec('getElementRect'); }

    /**
     * This element's shadow root as a search context (getShadowRoot). Reads the
     * shadow-6066 key (distinct from the element key). Throws
     * NoSuchShadowRootException (code 19) if the element hosts no open shadow root.
     */
    public function getShadowRoot(): ShadowRoot
    {
        $r = $this->exec('getShadowRoot');
        if (!\is_array($r) || !isset($r[W3C_SHADOW_KEY])) {
            throw new NoSuchShadowRootException('no such shadow root', 19);
        }
        return new ShadowRoot($this->driver, $r[W3C_SHADOW_KEY]);
    }

    private function exec(string $command, array $params = []): mixed
    {
        $params['id'] = $this->id;
        return $this->driver->execute($command, $params);
    }
}

/**
 * A shadow root as a search context (mainstream ShadowRoot). Only findElement /
 * findElements are supported, scoped inside the shadow tree — through the
 * findElementFromShadowRoot / findElementsFromShadowRoot commands with the
 * shadow id passed as the `id` param, reading the element-6066 key from results.
 */
final class ShadowRoot
{
    public function __construct(private WebDriver $driver, public string $id) {}

    public function findElement(string $by, string $value): WebElement
    {
        $params = $this->driver->decodeBy($by, $value);
        $params['id'] = $this->id;
        $r = $this->driver->execute('findElementFromShadowRoot', $params);
        return new WebElement($this->driver, $r[W3C_ELEMENT_KEY]);
    }

    /** @return WebElement[] */
    public function findElements(string $by, string $value): array
    {
        $params = $this->driver->decodeBy($by, $value);
        $params['id'] = $this->id;
        $r = $this->driver->execute('findElementsFromShadowRoot', $params);
        return \array_map(fn($e) => new WebElement($this->driver, $e[W3C_ELEMENT_KEY]), $r);
    }
}

final class WebDriver
{
    /** @var \FFI\CData|null */
    private $handle;
    private FFI $ffi;

    private function __construct(string $commandExecutor, array $capabilities)
    {
        $this->ffi = Native::ffi();
        $this->handle = $this->ffi->aether_sel_embed_open($commandExecutor);
        if ($this->handle === null || FFI::isNull($this->handle)) {
            throw new WebDriverException('failed to open session handle', -1);
        }
        $this->execute('newSession', ['capabilities' => ['alwaysMatch' => $capabilities]]);
    }

    /**
     * Resolve the driver binary for $browser ("chrome"/"firefox"/"edge"/...),
     * downloading and caching it if need be. '' when the engine cannot provide
     * one. The resolution rules live in the engine, not here.
     */
    public static function resolveDriver(string $browser = 'chrome', string $hint = ''): string
    {
        $ffi = Native::ffi();
        return Native::takeString($ffi, $ffi->aether_sel_embed_resolve_driver($browser, $hint));
    }

    /**
     * Resolve + launch a driver for $browser on a free port and wait for it to
     * answer. null when none could be started — the cue to skip a live test.
     * Lets a test drive a real browser with no driver on PATH and no Grid.
     */
    public static function ensureDriver(string $browser = 'chrome', string $hint = '', int $timeoutMs = 15000): ?DriverProcess
    {
        $ffi = Native::ffi();
        $h = $ffi->aether_sel_embed_ensure_driver($browser, $hint, $timeoutMs);
        return FFI::isNull($h) ? null : new DriverProcess($ffi, $h);
    }

    /** Launch an explicit driver binary on a free port. null if it never came up. */
    public static function launchDriver(string $driverPath, int $timeoutMs = 15000): ?DriverProcess
    {
        $ffi = Native::ffi();
        $h = $ffi->aether_sel_embed_launch_driver($driverPath, $timeoutMs);
        return FFI::isNull($h) ? null : new DriverProcess($ffi, $h);
    }

    public static function chrome(string $commandExecutor, array $options = []): self
    {
        return new self($commandExecutor, \array_merge(['browserName' => 'chrome'], $options));
    }

    public static function headlessChrome(string $commandExecutor): self
    {
        return self::chrome($commandExecutor, [
            'goog:chromeOptions' => ['args' => ['--headless=new', '--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage']],
        ]);
    }

    public static function firefox(string $commandExecutor, array $options = []): self
    {
        return new self($commandExecutor, \array_merge(['browserName' => 'firefox'], $options));
    }

    public static function headlessFirefox(string $commandExecutor): self
    {
        return self::firefox($commandExecutor, [
            'moz:firefoxOptions' => ['args' => ['-headless']],
        ]);
    }

    /** W3C browserName is "MicrosoftEdge". */
    public static function edge(string $commandExecutor, array $options = []): self
    {
        return new self($commandExecutor, \array_merge(['browserName' => 'MicrosoftEdge'], $options));
    }

    public static function headlessEdge(string $commandExecutor): self
    {
        return self::edge($commandExecutor, [
            'ms:edgeOptions' => ['args' => ['--headless=new', '--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage']],
        ]);
    }

    /** safaridriver, macOS only. Safari has no headless mode. */
    public static function safari(string $commandExecutor, array $options = []): self
    {
        return new self($commandExecutor, \array_merge(['browserName' => 'safari'], $options));
    }

    public static function configureNativeLib(string $path): void { Native::configure($path); }

    /**
     * The engine gh-release tag this binding downloads its prebuilt
     * libselenium_core from (see EngineFetcher; distinct from the binding's own
     * version).
     */
    public const ENGINE_VERSION = EngineFetcher::ENGINE_VERSION;

    /**
     * Download + cache the prebuilt engine for this platform from the project's
     * GitHub releases, so no Aether toolchain is needed. Explicit + one-time —
     * what `composer fetch-engine` calls. Returns the cached library path.
     * $tag pins a different engine release; $force re-downloads.
     */
    public static function fetchEngine(string $tag = EngineFetcher::ENGINE_VERSION, bool $force = false): string
    {
        return EngineFetcher::fetch($tag, $force);
    }

    /** The FFI seam: one command by name with a params array. */
    public function execute(string $command, array $params = []): mixed
    {
        $paramsJson = \json_encode((object) $params, JSON_UNESCAPED_SLASHES);
        $rc = $this->ffi->aether_sel_embed_execute($this->handle, $command, $paramsJson);
        if ($rc !== 0) {
            $code = $this->ffi->aether_sel_embed_last_error_code($this->handle);
            $message = Native::takeString($this->ffi, $this->ffi->aether_sel_embed_last_error($this->handle));
            if ($rc === -1 && $code === 0) {
                throw new WebDriverException($message !== '' ? $message : 'transport failure', -1);
            }
            throw self::classify($code, $message);
        }
        $raw = Native::takeString($this->ffi, $this->ffi->aether_sel_embed_last_value($this->handle));
        if ($raw === '') {
            return null;
        }
        return \json_decode($raw, true);
    }

    private static function classify(int $code, string $message): WebDriverException
    {
        return match ($code) {
            17 => new NoSuchElementException($message, $code),
            23 => new StaleElementReferenceException($message, $code),
            21, 24 => new TimeoutException($message, $code),
            11 => new InvalidSelectorException($message, $code),
            19 => new NoSuchShadowRootException($message, $code),
            2 => new DetachedShadowRootException($message, $code),
            default => new WebDriverException($message, $code),
        };
    }

    /**
     * The {"using","value"} locator array for a (by, value) pair, normalized by
     * the ENGINE for THIS session: browser rules (id/name/class name -> CSS)
     * against a browser, and Appium's native strategies against a desktop
     * driver (WinAppDriver / Appium), where those same strategies must reach
     * the wire intact because a native driver has no CSS engine.
     */
    public function decodeBy(string $by, string $value): array
    {
        $raw = Native::takeString(
            $this->ffi,
            $this->ffi->aether_sel_embed_by_locator_for($this->handle, $by, $value)
        );
        return \json_decode($raw, true);
    }

    /** True when this session was detected as (or set to) a desktop/native driver. */
    public function isNative(): bool
    {
        return $this->ffi->aether_sel_embed_is_native($this->handle) === 1;
    }

    /** Force desktop (true) or browser (false) By-normalization. */
    public function setNative(bool $on): void
    {
        $this->ffi->aether_sel_embed_set_native($this->handle, $on ? 1 : 0);
    }

    // navigation
    public function get(string $url): void { $this->execute('get', ['url' => $url]); }
    public function title(): string { return (string) $this->execute('getTitle'); }
    public function currentUrl(): string { return (string) $this->execute('getCurrentUrl'); }
    public function back(): void { $this->execute('goBack'); }
    public function forward(): void { $this->execute('goForward'); }
    public function refresh(): void { $this->execute('refresh'); }

    // elements
    public function findElement(string $by, string $value): WebElement
    {
        $r = $this->execute('findElement', $this->decodeBy($by, $value));
        return new WebElement($this, $r[W3C_ELEMENT_KEY]);
    }
    /** @return WebElement[] */
    public function findElements(string $by, string $value): array
    {
        $r = $this->execute('findElements', $this->decodeBy($by, $value));
        return \array_map(fn($e) => new WebElement($this, $e[W3C_ELEMENT_KEY]), $r);
    }

    // script
    public function executeScript(string $script, array $args = []): mixed
    {
        return $this->execute('executeScript', ['script' => $script, 'args' => $args]);
    }

    // windows
    public function windowHandles(): array { return (array) $this->execute('getWindowHandles'); }
    public function currentWindowHandle(): string { return (string) $this->execute('getCurrentWindowHandle'); }
    public function setWindowRect(array $rect): mixed { return $this->execute('setWindowRect', $rect); }
    public function getWindowRect(): array { return (array) $this->execute('getWindowRect'); }

    // cookies
    public function addCookie(array $cookie): void { $this->execute('addCookie', ['cookie' => $cookie]); }
    public function getCookies(): mixed { return $this->execute('getCookies'); }
    public function getCookie(string $name): mixed { return $this->execute('getCookie', ['name' => $name]); }
    public function deleteCookie(string $name): void { $this->execute('deleteCookie', ['name' => $name]); }
    public function deleteAllCookies(): void { $this->execute('deleteAllCookies'); }

    // actions
    public function performActions(array $actions): void { $this->execute('actions', ['actions' => $actions]); }
    public function clearActions(): void { $this->execute('clearActions'); }

    // screenshots
    public function screenshotBase64(): string { return (string) $this->execute('screenshot'); }

    // lifecycle
    public function sessionId(): string { return Native::takeString($this->ffi, $this->ffi->aether_sel_embed_session_id($this->handle)); }
    public function quit(): void
    {
        try {
            $this->execute('quit');
        } finally {
            $this->closeHandle();
        }
    }
    private function closeHandle(): void
    {
        if ($this->handle !== null && !FFI::isNull($this->handle)) {
            $this->ffi->aether_sel_embed_close($this->handle);
            $this->handle = null;
        }
    }

    // pure engine helpers
    public static function route(string $command): string
    {
        $ffi = Native::ffi();
        return Native::takeString($ffi, $ffi->aether_sel_embed_route($command));
    }
    public static function errorCode(string $w3cError): int
    {
        return Native::ffi()->aether_sel_embed_error_code($w3cError);
    }
    public static function locator(string $by, string $value): string
    {
        $ffi = Native::ffi();
        return Native::takeString($ffi, $ffi->aether_sel_embed_by_locator($by, $value));
    }
}

/**
 * A driver process (chromedriver/geckodriver/...) launched by the engine.
 *
 * Lifecycle: ensureDriver -> url() -> WebDriver::chrome(url) -> ... -> quit() ->
 * stop(). The engine's stop_driver heap-frees the handle and is safe ONCE, so
 * stop() clears it first and is itself idempotent — the same contract every
 * other binding's DriverProcess honours.
 */
final class DriverProcess
{
    private ?FFI\CData $handle;

    public function __construct(private FFI $ffi, FFI\CData $handle)
    {
        $this->handle = $handle;
    }

    /** The "http://127.0.0.1:<port>" to pass to a WebDriver factory. '' once stopped. */
    public function url(): string
    {
        return $this->handle === null
            ? ''
            : Native::takeString($this->ffi, $this->ffi->aether_sel_embed_driver_url($this->handle));
    }

    /** The driver's pid (diagnostics). 0 once stopped. */
    public function pid(): int
    {
        return $this->handle === null ? 0 : $this->ffi->aether_sel_embed_driver_pid($this->handle);
    }

    /** Kill + reap the driver process. Idempotent. */
    public function stop(): void
    {
        if ($this->handle === null) {
            return;
        }
        $h = $this->handle;
        $this->handle = null;
        $this->ffi->aether_sel_embed_stop_driver($h);
    }

    public function __destruct()
    {
        $this->stop();
    }
}
