<?php

// No-browser FFI test: proves the PHP ext-ffi binding loads
// libselenium_core.so and marshals correctly, exercising the pure engine
// helpers and the transport error path. Needs only the .so (SELENIUM_CORE_LIB /
// bundled native/); ext-ffi is enabled via `-d ffi.enable=1` (aeb's php.ini()).

declare(strict_types=1);

use PHPUnit\Framework\TestCase;
use SeleniumCore\By;
use SeleniumCore\WebDriver;
use SeleniumCore\WebDriverException;

final class FfiTest extends TestCase
{
    public function testRoute(): void
    {
        $this->assertSame('POST /session/:sessionId/url', WebDriver::route('get'));
        $this->assertSame('', WebDriver::route('nope'));
    }

    public function testErrorCode(): void
    {
        $this->assertSame(17, WebDriver::errorCode('no such element'));
        $this->assertSame(0, WebDriver::errorCode(''));
    }

    public function testLocatorCss(): void
    {
        $this->assertSame(
            '{"using":"css selector","value":"div.foo"}',
            WebDriver::locator(By::CSS, 'div.foo'),
        );
    }

    public function testLocatorIdRewrite(): void
    {
        $this->assertStringContainsString('*[id=', WebDriver::locator(By::ID, 'main'));
    }

    public function testTransportFailureCode(): void
    {
        $threw = false;
        try {
            WebDriver::chrome('http://127.0.0.1:1');
        } catch (WebDriverException $e) {
            $threw = $e->code_ === -1;
        }
        $this->assertTrue($threw, 'transport failure should surface code -1');
    }

    // ---- browser session factories (no browser) ----

    public function testBrowserFactoriesDeclared(): void
    {
        // firefox/edge/safari (+ headless variants) mirror chrome: each is a
        // static factory setting the right browserName then negotiating
        // newSession. Pin the surface — the factories exist.
        $this->assertTrue(\method_exists(WebDriver::class, 'firefox'));
        $this->assertTrue(\method_exists(WebDriver::class, 'headlessFirefox'));
        $this->assertTrue(\method_exists(WebDriver::class, 'edge'));
        $this->assertTrue(\method_exists(WebDriver::class, 'headlessEdge'));
        $this->assertTrue(\method_exists(WebDriver::class, 'safari'));
    }

    public function testFirefoxFactoryReachesTransport(): void
    {
        // firefox() runs newSession against the endpoint; a dead endpoint must
        // surface code -1 — proves the factory is wired (no driver required).
        $threw = false;
        try {
            WebDriver::firefox('http://127.0.0.1:1');
        } catch (WebDriverException $e) {
            $threw = $e->code_ === -1;
        }
        $this->assertTrue($threw, 'firefox transport failure should surface code -1');
    }

    // ---- shadow DOM: route + error-code + surface facts (no browser) ----

    public function testShadowRoutes(): void
    {
        $this->assertSame('GET /session/:sessionId/element/:id/shadow', WebDriver::route('getShadowRoot'));
        $this->assertSame('POST /session/:sessionId/shadow/:id/element', WebDriver::route('findElementFromShadowRoot'));
        $this->assertSame('POST /session/:sessionId/shadow/:id/elements', WebDriver::route('findElementsFromShadowRoot'));
    }

    public function testShadowErrorCodes(): void
    {
        $this->assertSame(19, WebDriver::errorCode('no such shadow root'));
        $this->assertSame(2, WebDriver::errorCode('detached shadow root'));
    }

    public function testShadowRootSurface(): void
    {
        // ShadowRoot is a search context with findElement / findElements, and the
        // shadow key is distinct from the element key (do not conflate).
        $this->assertNotSame(\SeleniumCore\W3C_SHADOW_KEY, \SeleniumCore\W3C_ELEMENT_KEY);
        $this->assertTrue(\method_exists(\SeleniumCore\ShadowRoot::class, 'findElement'));
        $this->assertTrue(\method_exists(\SeleniumCore\ShadowRoot::class, 'findElements'));
        $this->assertTrue(\method_exists(\SeleniumCore\WebElement::class, 'getShadowRoot'));
    }
}
