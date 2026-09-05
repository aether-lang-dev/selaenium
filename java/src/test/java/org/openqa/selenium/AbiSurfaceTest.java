package org.openqa.selenium;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertInstanceOf;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.openqa.selenium.chrome.ChromeOptions;
import org.openqa.selenium.interactions.Actions;
import org.openqa.selenium.support.ui.ExpectedConditions;
import org.openqa.selenium.support.ui.Select;
import org.openqa.selenium.support.ui.WebDriverWait;

/**
 * No-browser, no-engine ABI-parity tests (Java): prove the binding presents the
 * mainstream Selenium-Java surface (type names, method signatures, and the exact
 * W3C commands the facades issue) WITHOUT the {@code libselenium_core.so}.
 *
 * <p>The facades (Navigation / TargetLocator / Options / Window / Alert / Actions
 * / Select) route every command through {@link RemoteWebDriver#execute(String, Map)}
 * / {@link WebDriver#findElement(By)} / {@code executeScript}, so a small recording
 * {@link RecordingDriver} stands in for a live session and lets us assert the exact
 * {@code (command, params)} pairs. Placed in {@code org.openqa.selenium} so it can
 * reach the package-private element seam.
 */
class AbiSurfaceTest {

    /** Records every execute() call; returns canned values keyed by command. */
    static final class RecordingDriver extends RemoteWebDriver {
        final List<Map.Entry<String, Map<String, Object>>> calls = new ArrayList<>();
        final Map<String, Object> returns;

        RecordingDriver() {
            this(Map.of());
        }

        RecordingDriver(Map<String, Object> returns) {
            super();
            this.returns = returns;
        }

        @Override
        public Object execute(String command, Map<String, Object> params) {
            calls.add(Map.entry(command, params == null ? Map.of() : params));
            return returns.get(command);
        }

        // Bypass the engine's By decode for the no-.so tests.
        @Override
        public WebElement findElement(By by) {
            calls.add(Map.entry("findElement", Map.of("using", by.strategy(), "value", by.value())));
            Object canned = returns.get("findElement");
            return canned instanceof WebElement w ? w : new RemoteWebElement(this, "el-found");
        }

        @Override
        @SuppressWarnings("unchecked")
        public List<WebElement> findElements(By by) {
            calls.add(Map.entry("findElements", Map.of("using", by.strategy(), "value", by.value())));
            Object canned = returns.get("findElements");
            return canned instanceof List ? (List<WebElement>) canned : List.of();
        }

        boolean sent(String command) {
            return calls.stream().anyMatch(c -> c.getKey().equals(command));
        }

        Map<String, Object> paramsOf(String command) {
            return calls.stream().filter(c -> c.getKey().equals(command))
                    .map(Map.Entry::getValue).findFirst().orElse(null);
        }

        String lastCommand() {
            return calls.get(calls.size() - 1).getKey();
        }
    }

    // ---- navigate() facade ----

    @Test
    void navigateFacadeIssuesHistoryCommands() {
        RecordingDriver d = new RecordingDriver();
        d.navigate().to("https://example.com");
        d.navigate().back();
        d.navigate().forward();
        d.navigate().refresh();

        assertEquals(Map.of("url", "https://example.com"), d.paramsOf("get"));
        assertTrue(d.sent("goBack"));
        assertTrue(d.sent("goForward"));
        assertTrue(d.sent("refresh"));
    }

    // ---- switchTo() facade ----

    @Test
    void switchToWindowParentDefault() {
        RecordingDriver d = new RecordingDriver();
        d.switchTo().window("w-2");
        d.switchTo().parentFrame();
        d.switchTo().defaultContent();

        assertEquals(Map.of("handle", "w-2"), d.paramsOf("switchToWindow"));
        assertTrue(d.sent("switchToFrameParent"));
        // defaultContent sends {"id": null}
        Map<String, Object> frame = d.paramsOf("switchToFrame");
        assertTrue(frame.containsKey("id") && frame.get("id") == null);
    }

    @Test
    void switchToFrameByIndexAndElement() {
        RecordingDriver d = new RecordingDriver();
        d.switchTo().frame(1);
        assertEquals(1, d.paramsOf("switchToFrame").get("id"));

        RecordingDriver d2 = new RecordingDriver();
        WebElement el = new RemoteWebElement(d2, "frame-99");
        d2.switchTo().frame(el);
        Object id = d2.paramsOf("switchToFrame").get("id");
        assertEquals(Map.of(RemoteWebDriver.W3C_ELEMENT_KEY, "frame-99"), id);
    }

    @Test
    void switchToNewWindowSwitchesToReturnedHandle() {
        RecordingDriver d = new RecordingDriver(Map.of("newWindow", Map.of("handle", "new-h")));
        d.switchTo().newWindow(WindowType.TAB);
        assertEquals(Map.of("type", "tab"), d.paramsOf("newWindow"));
        assertEquals(Map.of("handle", "new-h"), d.paramsOf("switchToWindow"));
    }

    @Test
    void switchToActiveElementReturnsWebElement() {
        RecordingDriver d = new RecordingDriver(
                Map.of("getActiveElement", Map.of(RemoteWebDriver.W3C_ELEMENT_KEY, "active-1")));
        WebElement el = d.switchTo().activeElement();
        assertEquals("active-1", el.id());
        assertTrue(d.sent("getActiveElement"));
    }

    @Test
    void switchToAlertReadsTextAndActs() {
        RecordingDriver d = new RecordingDriver(Map.of("getAlertText", "Are you sure?"));
        Alert alert = d.switchTo().alert();
        assertInstanceOf(Alert.class, alert);
        // accessing .alert() eagerly reads text (mainstream behaviour)
        assertTrue(d.sent("getAlertText"));
        assertEquals("Are you sure?", alert.getText());
        alert.accept();
        alert.dismiss();
        alert.sendKeys("typed");
        assertTrue(d.sent("acceptAlert"));
        assertTrue(d.sent("dismissAlert"));
        assertEquals(Map.of("text", "typed"), d.paramsOf("setAlertValue"));
    }

    // ---- manage() facade ----

    @Test
    void manageCookiesIssueRightCommands() {
        RecordingDriver d = new RecordingDriver();
        d.manage().addCookie(new Cookie("flavor", "mint"));
        Map<String, Object> added = d.paramsOf("addCookie");
        @SuppressWarnings("unchecked")
        Map<String, Object> cookie = (Map<String, Object>) added.get("cookie");
        assertEquals("flavor", cookie.get("name"));
        assertEquals("mint", cookie.get("value"));

        d.manage().deleteCookieNamed("flavor");
        assertEquals(Map.of("name", "flavor"), d.paramsOf("deleteCookie"));

        d.manage().deleteAllCookies();
        assertTrue(d.sent("deleteAllCookies"));
    }

    @Test
    void manageGetCookiesReturnsCookieSet() {
        RecordingDriver d = new RecordingDriver(Map.of(
                "getCookies", List.of(Map.of("name", "a", "value", "1", "secure", false, "httpOnly", false))));
        var cookies = d.manage().getCookies();
        assertEquals(1, cookies.size());
        Cookie c = cookies.iterator().next();
        assertEquals("a", c.getName());
        assertEquals("1", c.getValue());
    }

    @Test
    void manageTimeoutsUseDuration() {
        RecordingDriver d = new RecordingDriver();
        d.manage().timeouts().implicitlyWait(Duration.ofSeconds(10));
        d.manage().timeouts().pageLoadTimeout(Duration.ofSeconds(30));
        d.manage().timeouts().scriptTimeout(Duration.ofSeconds(5));

        assertEquals(Map.of("implicit", 10000L), d.paramsOf("setTimeout"));
        // getters echo the set values
        assertEquals(Duration.ofSeconds(10), d.manage().timeouts().implicitlyWait(Duration.ofSeconds(10)).getImplicitWaitTimeout());
    }

    @Test
    void manageWindowSizeAndPosition() {
        RecordingDriver d = new RecordingDriver(
                Map.of("getWindowRect", Map.of("x", 1.0, "y", 2.0, "width", 800.0, "height", 600.0)));
        Dimension size = d.manage().window().getSize();
        assertEquals(800, size.getWidth());
        assertEquals(600, size.getHeight());
        Point pos = d.manage().window().getPosition();
        assertEquals(1, pos.getX());
        assertEquals(2, pos.getY());

        d.manage().window().setSize(new Dimension(1024, 768));
        Map<String, Object> rect = d.paramsOf("setWindowRect");
        assertEquals(1024, rect.get("width"));
        assertEquals(768, rect.get("height"));

        d.manage().window().maximize();
        assertTrue(d.sent("maximizeWindow"));
    }

    // ---- getWindowHandles / getWindowHandle / close ----

    @Test
    void windowHandleFacadeForms() {
        RecordingDriver d = new RecordingDriver(Map.of(
                "getWindowHandles", List.of("h1", "h2"),
                "getCurrentWindowHandle", "h1"));
        assertEquals(java.util.Set.of("h1", "h2"), d.getWindowHandles());
        assertEquals("h1", d.getWindowHandle());
        d.close();
        assertTrue(d.sent("close"));
    }

    // ---- getScreenshotAs(OutputType) ----

    @Test
    void screenshotAsBase64AndBytes() {
        // base64 of a 4-byte payload
        String b64 = java.util.Base64.getEncoder().encodeToString(new byte[]{1, 2, 3, 4});
        RecordingDriver d = new RecordingDriver(Map.of("screenshot", b64));
        assertEquals(b64, d.getScreenshotAs(OutputType.BASE64));
        byte[] bytes = d.getScreenshotAs(OutputType.BYTES);
        assertEquals(4, bytes.length);
        assertTrue(d instanceof TakesScreenshot);
    }

    // ---- WebElement additions ----

    @Test
    void sendKeysVariadicAcceptsKeys() {
        RecordingDriver d = new RecordingDriver();
        WebElement el = new RemoteWebElement(d, "e1");
        el.sendKeys("ab", "c", Keys.ENTER);
        Map<String, Object> params = d.paramsOf("sendKeysToElement");
        assertEquals("ab" + "c" + Keys.ENTER, params.get("text"));
        assertEquals(List.of("a", "b", "c", Keys.ENTER.toString()), params.get("value"));
        assertEquals("e1", params.get("id"));
    }

    @Test
    void elementGetRectLocationSize() {
        RecordingDriver d = new RecordingDriver(
                Map.of("getElementRect", Map.of("x", 1.0, "y", 2.0, "width", 3.0, "height", 4.0)));
        WebElement el = new RemoteWebElement(d, "e1");
        Rectangle r = el.getRect();
        assertInstanceOf(Rectangle.class, r);
        assertEquals(1, r.getX());
        assertEquals(2, r.getY());
        assertEquals(3, r.getWidth());
        assertEquals(4, r.getHeight());
        assertEquals(new Point(1, 2), el.getLocation());
        assertEquals(new Dimension(3, 4), el.getSize());
    }

    @Test
    void elementGetScreenshotAs() {
        String b64 = java.util.Base64.getEncoder().encodeToString(new byte[]{9, 9});
        RecordingDriver d = new RecordingDriver(Map.of("takeElementScreenshot", b64));
        WebElement el = new RemoteWebElement(d, "e1");
        assertEquals(b64, el.getScreenshotAs(OutputType.BASE64));
    }

    @Test
    void elementAttributeAccessorsReturnString() {
        RecordingDriver d = new RecordingDriver(Map.of(
                "getDomAttribute", "raw",
                "getElementValueOfCssProperty", "rgb(0, 0, 0)",
                "getAriaRole", "button",
                "getAccessibleName", "Submit"));
        WebElement el = new RemoteWebElement(d, "e1");
        String dom = el.getDomAttribute("x");
        assertEquals("raw", dom);
        assertEquals("rgb(0, 0, 0)", el.getCssValue("color"));
        assertEquals("button", el.getAriaRole());
        assertEquals("Submit", el.getAccessibleName());
    }

    // ---- Keys code points match upstream exactly ----

    @Test
    void keysCodePointsMatchUpstream() {
        assertEquals("", Keys.ENTER.toString());
        assertEquals("", Keys.RETURN.toString());
        assertEquals("", Keys.SHIFT.toString());
        assertEquals(Keys.SHIFT.toString(), Keys.LEFT_SHIFT.toString());
        assertEquals("", Keys.RIGHT_SHIFT.toString());
        assertEquals("", Keys.RIGHT_CONTROL.toString());
        assertEquals("", Keys.RIGHT_ALT.toString());
        assertEquals("", Keys.RIGHT_COMMAND.toString());
        assertEquals("", Keys.META.toString());
        assertEquals(Keys.META.toString(), Keys.COMMAND.toString());
        assertEquals(Keys.ALT.toString(), Keys.OPTION.toString());
        assertEquals("", Keys.ZENKAKU_HANKAKU.toString());
        // Keys is a CharSequence usable directly
        CharSequence cs = Keys.TAB;
        assertEquals(1, cs.length());
        assertEquals('', cs.charAt(0));
        // chord appends NULL
        assertTrue(Keys.chord(Keys.CONTROL, "a").endsWith(Keys.NULL.toString()));
    }

    // ---- ChromeOptions ----

    @Test
    void chromeOptionsToCapabilities() {
        ChromeOptions opts = new ChromeOptions();
        opts.addArguments("--headless=new", "--no-sandbox");
        opts.setExperimentalOption("prefs", Map.of("download.default_directory", "/tmp"));
        opts.setBinary("/usr/bin/chromium");
        opts.setCapability("acceptInsecureCerts", true);

        Map<String, Object> caps = opts.asMap();
        assertEquals("chrome", caps.get("browserName"));
        assertEquals(true, caps.get("acceptInsecureCerts"));
        @SuppressWarnings("unchecked")
        Map<String, Object> goog = (Map<String, Object>) caps.get("goog:chromeOptions");
        assertEquals(List.of("--headless=new", "--no-sandbox"), goog.get("args"));
        assertEquals("/usr/bin/chromium", goog.get("binary"));
        assertEquals(Map.of("download.default_directory", "/tmp"), goog.get("prefs"));
        // ChromeOptions is a Capabilities
        assertInstanceOf(Capabilities.class, opts);
        assertInstanceOf(MutableCapabilities.class, opts);
    }

    @Test
    void chromeOptionsMerge() {
        ChromeOptions base = new ChromeOptions().addArguments("--a");
        ChromeOptions merged = base.merge(new ImmutableCapabilities("acceptInsecureCerts", true));
        assertEquals(true, merged.asMap().get("acceptInsecureCerts"));
        @SuppressWarnings("unchecked")
        Map<String, Object> goog = (Map<String, Object>) merged.asMap().get("goog:chromeOptions");
        assertEquals(List.of("--a"), goog.get("args"));
    }

    // ---- Capabilities family ----

    @Test
    void capabilitiesHelpers() {
        MutableCapabilities caps = new MutableCapabilities();
        caps.setCapability("browserName", "chrome");
        caps.setCapability("acceptInsecureCerts", true);
        assertEquals("chrome", caps.getBrowserName());
        assertTrue(caps.is("acceptInsecureCerts"));
        assertFalse(caps.is("nope"));
        assertTrue(caps.getCapabilityNames().contains("browserName"));

        ImmutableCapabilities imm = new ImmutableCapabilities("browserName", "chrome");
        assertEquals("chrome", imm.getCapability("browserName"));
        Capabilities merged = imm.merge(new ImmutableCapabilities("x", 1));
        assertEquals(1, merged.getCapability("x"));
    }

    // ---- Actions builder emits a W3C actions array ----

    @Test
    void actionsClickEmitsPointerDevice() {
        RecordingDriver d = new RecordingDriver();
        WebElement el = new RemoteWebElement(d, "e1");
        new Actions(d).moveToElement(el).click().perform();
        assertEquals("actions", d.lastCommand());
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> devices = (List<Map<String, Object>>) d.paramsOf("actions").get("actions");
        assertTrue(devices.stream().anyMatch(dev -> "pointer".equals(dev.get("type"))));
    }

    @Test
    void actionsScrollEmitsWheelDevice() {
        RecordingDriver d = new RecordingDriver();
        new Actions(d).scrollByAmount(0, 200).perform();
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> devices = (List<Map<String, Object>>) d.paramsOf("actions").get("actions");
        assertTrue(devices.stream().anyMatch(dev -> "wheel".equals(dev.get("type"))));
    }

    @Test
    void actionsSendKeysEmitsKeyDevice() {
        RecordingDriver d = new RecordingDriver();
        new Actions(d).sendKeys("hi").perform();
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> devices = (List<Map<String, Object>>) d.paramsOf("actions").get("actions");
        assertTrue(devices.stream().anyMatch(dev -> "key".equals(dev.get("type"))));
    }

    // ---- WebDriverWait poll loop ----

    @Test
    void webDriverWaitReturnsWhenConditionHolds() {
        RecordingDriver d = new RecordingDriver();
        WebDriverWait wait = new WebDriverWait(d, Duration.ofSeconds(2), Duration.ofMillis(10));
        int[] tries = {0};
        String value = wait.until(driver -> ++tries[0] >= 2 ? "ready" : null);
        assertEquals("ready", value);
        assertTrue(tries[0] >= 2);
    }

    @Test
    void webDriverWaitTimesOut() {
        RecordingDriver d = new RecordingDriver();
        WebDriverWait wait = new WebDriverWait(d, Duration.ofMillis(50), Duration.ofMillis(10));
        assertThrows(TimeoutException.class, () -> wait.until(driver -> null));
    }

    @Test
    void expectedConditionsPresenceUsesFindElement() {
        RemoteWebElement found = null;
        RecordingDriver d = new RecordingDriver();
        WebElement el = ExpectedConditions.presenceOfElementLocated(By.id("hdr")).apply(d);
        assertNotNull(el);
        assertTrue(d.sent("findElement"));
    }

    // ---- Select drives <option> children ----

    @Test
    void selectByVisibleTextClicksMatchingOption() {
        RecordingDriver d = new RecordingDriver();
        // A fake <select> element whose options we control.
        RecordingSelectElement select = new RecordingSelectElement(d, "sel", false);
        Select s = new Select(select);
        s.selectByVisibleText("Spain");
        assertTrue(select.clickedOption != null && "Spain".equals(select.clickedOption.text));
    }

    // A WebElement stand-in for Select tests: reports tag "select" and yields options.
    static final class RecordingSelectElement extends RemoteWebElementStub {
        Option clickedOption;

        RecordingSelectElement(RemoteWebDriver d, String id, boolean multiple) {
            super(d, id);
            this.tag = "select";
            this.attributes.put("multiple", multiple ? "true" : null);
            this.options = List.of(new Option("France", this), new Option("Spain", this));
        }
    }

    static class Option {
        final String text;
        final RecordingSelectElement parent;
        boolean selected = false;

        Option(String text, RecordingSelectElement parent) {
            this.text = text;
            this.parent = parent;
        }
    }

    // Minimal WebElement stub for Select — only the methods Select touches.
    static class RemoteWebElementStub implements WebElement {
        final RemoteWebDriver driver;
        final String id;
        String tag = "div";
        final java.util.Map<String, String> attributes = new java.util.HashMap<>();
        List<Option> options = List.of();

        RemoteWebElementStub(RemoteWebDriver driver, String id) {
            this.driver = driver;
            this.id = id;
        }

        @Override public String id() { return id; }
        @Override public String getTagName() { return tag; }
        @Override public String getAttribute(String name) { return attributes.get(name); }

        @Override
        public List<WebElement> findElements(By by) {
            List<WebElement> out = new ArrayList<>();
            for (Option o : options) {
                out.add(new OptionElement(driver, o));
            }
            return out;
        }

        @Override public WebElement findElement(By by) { return findElements(by).get(0); }

        // unused surface
        @Override public void click() {}
        @Override public void submit() {}
        @Override public void sendKeys(CharSequence... k) {}
        @Override public void clear() {}
        @Override public String getText() { return ""; }
        @Override public boolean isDisplayed() { return true; }
        @Override public String getDomAttribute(String n) { return null; }
        @Override public String getDomProperty(String n) { return null; }
        @Override public Object getProperty(String n) { return null; }
        @Override public String getCssValue(String n) { return null; }
        @Override public String getAriaRole() { return null; }
        @Override public String getAccessibleName() { return null; }
        @Override public SearchContext getShadowRoot() { return null; }
        @Override public boolean isEnabled() { return true; }
        @Override public boolean isSelected() { return false; }
        @Override public Map<String, Object> rect() { return Map.of(); }
        @Override public Rectangle getRect() { return new Rectangle(0, 0, 0, 0); }
        @Override public Point getLocation() { return new Point(0, 0); }
        @Override public Dimension getSize() { return new Dimension(0, 0); }
        @Override public <X> X getScreenshotAs(OutputType<X> t) { return t.convertFromBase64Png(""); }
    }

    static final class OptionElement extends RemoteWebElementStub {
        final Option option;

        OptionElement(RemoteWebDriver driver, Option option) {
            super(driver, "opt-" + option.text);
            this.option = option;
            this.tag = "option";
        }

        @Override public String getText() { return option.text; }
        @Override public boolean isSelected() { return option.selected; }

        @Override
        public void click() {
            option.selected = !option.selected;
            option.parent.clickedOption = option;
        }
    }
}
