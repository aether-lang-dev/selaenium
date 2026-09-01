/// selenium_core — Selenium WebDriver for Dart, re-glued to the shared pure-
/// Aether WebDriver core. A thin dart:ffi binding: the entire W3C protocol lives
/// once in the in-repo Aether engine (core/selenium_core.ae) and is shared by
/// every language binding via libselenium_core.so. This package is the Dart
/// face — it carries no protocol logic.
///
/// ```dart
/// import 'package:selenium_core/selenium_core.dart';
/// final d = WebDriver.headlessChrome('http://127.0.0.1:9515');
/// d.get('https://example.com');
/// print(d.title);
/// d.findElement(By.css, 'a').click();
/// d.quit();
/// ```
library;

export 'src/webdriver.dart'
    show
        By,
        WebDriver,
        WebElement,
        BiDi,
        BidiEvent,
        WebDriverError,
        NoSuchElementError,
        StaleElementReferenceError,
        TimeoutError,
        DriverProcess,
        LocalChrome,
        resolveDriver,
        launchDriver,
        ensureDriver,
        route,
        errorCode,
        locator;
