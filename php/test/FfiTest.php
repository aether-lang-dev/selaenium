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
}
