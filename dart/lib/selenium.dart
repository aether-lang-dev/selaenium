/// selenium — Selenium WebDriver for Dart, re-glued to the shared pure-Aether
/// WebDriver core. A thin dart:ffi binding: the entire W3C protocol lives once
/// in the in-repo Aether engine (core/selenium_core.ae) and is shared by every
/// language binding via libselenium_core.so. This package is the Dart face — it
/// carries no protocol logic.
///
/// ```dart
/// import 'package:selenium/selenium.dart';
/// final d = WebDriver.headlessChrome('http://127.0.0.1:9515');
/// d.get('https://example.com');
/// print(d.title);
/// d.findElement(By.cssSelector('a')).click();
/// d.quit();
/// ```
library;

// WebDriverError is re-exported below as a deprecated alias for source
// compatibility; exporting it is intentional, not a use to be flagged.
// ignore_for_file: deprecated_member_use_from_same_package
export 'src/webdriver.dart'
    show
        By,
        WebDriver,
        WebElement,
        BiDi,
        BidiEvent,
        WebDriverException,
        WebDriverError,
        NoSuchElementException,
        StaleElementReferenceException,
        TimeoutException,
        DriverProcess,
        LocalChrome,
        resolveDriver,
        launchDriver,
        ensureDriver,
        route,
        errorCode,
        locator;
