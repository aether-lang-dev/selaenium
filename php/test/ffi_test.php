<?php

// No-browser FFI test: proves the PHP ext-ffi binding loads
// libselenium_core.so and marshals correctly, exercising the pure engine
// helpers and the transport error path. Run with ext-ffi enabled:
//   php -d extension=ffi -d ffi.enable=1 test/ffi_test.php

declare(strict_types=1);

require __DIR__ . '/../src/Native.php';
require __DIR__ . '/../src/WebDriver.php';

use SeleniumCore\By;
use SeleniumCore\WebDriver;
use SeleniumCore\WebDriverException;

$fails = 0;
function check(bool $cond, string $label): void
{
    global $fails;
    if ($cond) {
        echo "  ok: $label\n";
    } else {
        echo "FAIL: $label\n";
        $fails++;
    }
}

check(WebDriver::route('get') === 'POST /session/:sessionId/url', 'route get');
check(WebDriver::route('nope') === '', 'route unknown');
check(WebDriver::errorCode('no such element') === 17, 'errorCode no such element');
check(WebDriver::errorCode('') === 0, 'errorCode success');
check(WebDriver::locator(By::CSS, 'div.foo') === '{"using":"css selector","value":"div.foo"}', 'locator css');
check(\str_contains(WebDriver::locator(By::ID, 'main'), '*[id='), 'locator id rewrite');

$threw = false;
try {
    WebDriver::chrome('http://127.0.0.1:1');
} catch (WebDriverException $e) {
    $threw = $e->code_ === -1;
}
check($threw, 'transport failure -> code -1');

if ($fails === 0) {
    echo "PASS: PHP FFI tests green\n";
    exit(0);
}
echo "FAILED: $fails PHP FFI test(s)\n";
exit(1);
