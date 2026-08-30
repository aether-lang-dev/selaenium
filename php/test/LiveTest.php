<?php

// Live end-to-end + surface test (PHP): a real headless Chrome session driven
// through the pure-Aether engine via ext-ffi. chromedriver + a content server
// (php's built-in server) are spawned here; FFI calls are synchronous, so the
// content server runs in its own process. markTestSkipped when chromedriver is
// absent, so the suite is green on a box without a browser.

declare(strict_types=1);

use PHPUnit\Framework\TestCase;
use SeleniumCore\By;
use SeleniumCore\WebDriver;
use SeleniumCore\NoSuchElementException;

final class LiveTest extends TestCase
{
    private static function which(string $cmd): ?string
    {
        foreach (\explode(':', \getenv('PATH') ?: '') as $dir) {
            $p = $dir . '/' . $cmd;
            if (\is_file($p) && \is_executable($p)) {
                return $p;
            }
        }
        return null;
    }

    private static function freePort(): int
    {
        $s = \stream_socket_server('tcp://127.0.0.1:0', $errno, $errstr);
        $name = \stream_socket_get_name($s, false);
        \fclose($s);
        return (int) \substr($name, \strrpos($name, ':') + 1);
    }

    private static function waitUp(int $port, int $timeoutMs): bool
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

    public function testLiveChromeSurface(): void
    {
        $driverBin = self::which('chromedriver');
        if ($driverBin === null) {
            $this->markTestSkipped('chromedriver not on PATH');
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
        $webPort = self::freePort();
        $web = \proc_open(
            [\PHP_BINARY, '-S', "127.0.0.1:$webPort", $router],
            [['pipe', 'r'], ['file', '/dev/null', 'w'], ['file', '/dev/null', 'w']],
            $webPipes
        );
        $base = "http://127.0.0.1:$webPort";

        $cdPort = self::freePort();
        $cd = \proc_open(
            [$driverBin, "--port=$cdPort"],
            [['pipe', 'r'], ['file', '/dev/null', 'w'], ['file', '/dev/null', 'w']],
            $cdPipes
        );

        try {
            if (!self::waitUp($cdPort, 10000) || !self::waitUp($webPort, 5000)) {
                $this->markTestSkipped('chromedriver/server did not come up');
            }

            $d = WebDriver::headlessChrome("http://127.0.0.1:$cdPort");
            try {
                $this->assertGreaterThan(0, \strlen($d->sessionId()), 'session started');

                $d->get("$base/one");
                $this->assertSame('Page One', $d->title(), 'title');
                $this->assertSame('One', $d->findElement(By::ID, 'hdr')->text(), 'hdr text');
                $this->assertSame('a', \strtolower($d->findElement(By::CSS, '#go')->tagName()), 'tag name');

                // navigation
                $d->findElement(By::ID, 'go')->click();
                $this->assertSame('Page Two', $d->title(), 'after click');
                $d->back();
                $this->assertSame('Page One', $d->title(), 'after back');
                $d->forward();
                $this->assertSame('Page Two', $d->title(), 'after forward');
                $d->back();

                // cookies
                $d->deleteAllCookies();
                $d->addCookie(['name' => 'flavor', 'value' => 'mint']);
                $this->assertSame('mint', $d->getCookie('flavor')['value'], 'cookie value');
                $d->deleteCookie('flavor');

                // windows
                $this->assertGreaterThanOrEqual(1, \count($d->windowHandles()), 'window handles');
                $d->setWindowRect(['width' => 900, 'height' => 650]);
                $this->assertSame(900, (int) $d->getWindowRect()['width'], 'window width');

                // script
                $this->assertSame(42, (int) $d->executeScript('return 6*7;'), 'script scalar');
                $this->assertSame(42, (int) $d->executeScript('return arguments[0]+arguments[1];', [40, 2]), 'script args');

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
                $this->assertSame('clicked', $d->findElement(By::ID, 'hdr')->text(), 'actions click fired');
                $d->clearActions();

                // screenshot
                $png = \base64_decode($d->screenshotBase64());
                $this->assertTrue(\strlen($png) > 8 && \substr($png, 1, 3) === 'PNG', 'screenshot is PNG');

                // negative path
                $nse = false;
                try {
                    $d->findElement(By::ID, 'does-not-exist');
                } catch (NoSuchElementException $e) {
                    $nse = true;
                }
                $this->assertTrue($nse, 'no such element error');
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
    }
}
