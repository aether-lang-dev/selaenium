<?php

// Live end-to-end + surface test (PHP): a real headless Chrome session driven
// through the pure-Aether engine via ext-ffi. chromedriver + a content server
// (php's built-in server) are spawned here; FFI calls are synchronous, so the
// content server runs in its own process. Skips if chromedriver is absent.
// Run: php -d extension=ffi -d ffi.enable=1 test/live_test.php

declare(strict_types=1);

require __DIR__ . '/../src/Native.php';
require __DIR__ . '/../src/WebDriver.php';

use SeleniumCore\By;
use SeleniumCore\WebDriver;
use SeleniumCore\NoSuchElementException;

function which(string $cmd): ?string
{
    foreach (\explode(':', \getenv('PATH') ?: '') as $dir) {
        $p = $dir . '/' . $cmd;
        if (\is_file($p) && \is_executable($p)) {
            return $p;
        }
    }
    return null;
}

function freePort(): int
{
    $s = \stream_socket_server('tcp://127.0.0.1:0', $errno, $errstr);
    $name = \stream_socket_get_name($s, false);
    \fclose($s);
    return (int) \substr($name, \strrpos($name, ':') + 1);
}

function waitUp(int $port, int $timeoutMs): bool
{
    $deadline = \microtime(true) + $timeoutMs / 1000.0;
    while (\microtime(true) < $deadline) {
        $c = @\fsockopen('127.0.0.1', $port, $e, $s, 0.5);
        if ($c) {
            \fclose($c);
            return true;
        }
        \usleep(100000);
    }
    return false;
}

$fails = 0;
function check($got, $want, string $label): void
{
    global $fails;
    if ($got === $want) {
        echo "  ok: $label\n";
    } else {
        echo "FAIL: $label (got " . \var_export($got, true) . ")\n";
        $fails++;
    }
}

$driverBin = which('chromedriver');
if ($driverBin === null) {
    echo "SKIPPED: chromedriver not on PATH\n";
    exit(0);
}

// Content server: php built-in server over a router that serves two pages.
$router = \sys_get_temp_dir() . '/sel_php_router_' . \getmypid() . '.php';
\file_put_contents($router, <<<'PHP'
<?php
$two = '<!doctype html><title>Page Two</title><h1 id="hdr">Two</h1>';
$one = '<!doctype html><title>Page One</title><h1 id="hdr">One</h1>'
     . '<a id="go" href="/two">to two</a>'
     . '<button id="btn" onclick="document.getElementById(\'hdr\').textContent=\'clicked\'">b</button>';
header('Content-Type: text/html; charset=utf-8');
echo str_starts_with($_SERVER['REQUEST_URI'], '/two') ? $two : $one;
PHP);
$webPort = freePort();
$web = \proc_open(
    [\PHP_BINARY, '-S', "127.0.0.1:$webPort", $router],
    [['pipe', 'r'], ['file', '/dev/null', 'w'], ['file', '/dev/null', 'w']],
    $webPipes
);
$base = "http://127.0.0.1:$webPort";

$cdPort = freePort();
$cd = \proc_open(
    [$driverBin, "--port=$cdPort"],
    [['pipe', 'r'], ['file', '/dev/null', 'w'], ['file', '/dev/null', 'w']],
    $cdPipes
);

try {
    if (!waitUp($cdPort, 10000) || !waitUp($webPort, 5000)) {
        echo "SKIPPED: chromedriver/server did not come up\n";
        exit(0);
    }

    $d = WebDriver::headlessChrome("http://127.0.0.1:$cdPort");
    try {
        check(\strlen($d->sessionId()) > 0, true, 'session started');

        $d->get("$base/one");
        check($d->title(), 'Page One', 'title');
        check($d->findElement(By::ID, 'hdr')->text(), 'One', 'hdr text');
        check(\strtolower($d->findElement(By::CSS, '#go')->tagName()), 'a', 'tag name');

        // navigation
        $d->findElement(By::ID, 'go')->click();
        check($d->title(), 'Page Two', 'after click');
        $d->back();
        check($d->title(), 'Page One', 'after back');
        $d->forward();
        check($d->title(), 'Page Two', 'after forward');
        $d->back();

        // cookies
        $d->deleteAllCookies();
        $d->addCookie(['name' => 'flavor', 'value' => 'mint']);
        check($d->getCookie('flavor')['value'], 'mint', 'cookie value');
        $d->deleteCookie('flavor');

        // windows
        check(\count($d->windowHandles()) >= 1, true, 'window handles');
        $d->setWindowRect(['width' => 900, 'height' => 650]);
        check((int) $d->getWindowRect()['width'], 900, 'window width');

        // script
        check((int) $d->executeScript('return 6*7;'), 42, 'script scalar');
        check((int) $d->executeScript('return arguments[0]+arguments[1];', [40, 2]), 42, 'script args');

        // W3C actions
        $r = $d->findElement(By::ID, 'btn')->rect();
        $cx = (int) ($r['x'] + $r['width'] / 2);
        $cy = (int) ($r['y'] + $r['height'] / 2);
        $d->performActions([[
            'type' => 'pointer', 'id' => 'mouse',
            'parameters' => ['pointerType' => 'mouse'],
            'actions' => [
                ['type' => 'pointerMove', 'duration' => 0, 'x' => $cx, 'y' => $cy],
                ['type' => 'pointerDown', 'button' => 0],
                ['type' => 'pointerUp', 'button' => 0],
            ],
        ]]);
        check($d->findElement(By::ID, 'hdr')->text(), 'clicked', 'actions click fired');
        $d->clearActions();

        // screenshot
        $png = \base64_decode($d->screenshotBase64());
        check(\strlen($png) > 8 && \substr($png, 1, 3) === 'PNG', true, 'screenshot is PNG');

        // negative path
        $nse = false;
        try {
            $d->findElement(By::ID, 'does-not-exist');
        } catch (NoSuchElementException $e) {
            $nse = true;
        }
        check($nse, true, 'no such element error');
    } finally {
        $d->quit();
    }
} finally {
    if (\is_resource($cd)) {
        \proc_terminate($cd);
    }
    if (\is_resource($web)) {
        \proc_terminate($web);
    }
    @\unlink($router);
}

if ($fails === 0) {
    echo "PASS: PHP live surface test green\n";
    exit(0);
}
echo "FAILED: $fails PHP live test(s)\n";
exit(1);
