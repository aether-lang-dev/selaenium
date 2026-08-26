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

const W3C_ELEMENT_KEY = 'element-6066-11e4-a52e-4f735466cecf';

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

    private function exec(string $command, array $params = []): mixed
    {
        $params['id'] = $this->id;
        return $this->driver->execute($command, $params);
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

    public static function configureNativeLib(string $path): void { Native::configure($path); }

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
            default => new WebDriverException($message, $code),
        };
    }

    private function decodeBy(string $by, string $value): array
    {
        $raw = Native::takeString($this->ffi, $this->ffi->aether_sel_embed_by_locator($by, $value));
        return \json_decode($raw, true);
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
