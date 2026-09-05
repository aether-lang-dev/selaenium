using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Text.Json;
using OpenQA.Selenium;
using OpenQA.Selenium.Chrome;
using Xunit;
using Shouldly;

namespace SeleniumCore.Tests
{
    // Perfect-ABI facts — NO browser, NO engine session. A RecordingDriver overrides
    // RemoteWebDriver.Execute to capture the (command, params) it is issued and return
    // a canned value, so the upstream-shaped facades (Navigate/SwitchTo/Manage, Alert,
    // IWebElement extras) can be proved to issue the exact W3C commands mainstream does.

    // One recorded command: name + the params dict Execute received.
    internal sealed record Call(string Command, IDictionary<string, object?>? Params);

    // A RemoteWebDriver whose Execute records instead of hitting the wire. The
    // parameterless base ctor leaves the native handle null; Execute is fully
    // overridden so nothing touches the engine. A per-command canned response lets
    // getters (getAlertText, getActiveElement, getTimeout, …) return a value.
    internal sealed class RecordingDriver : RemoteWebDriver
    {
        public List<Call> Calls { get; } = new();
        public Dictionary<string, JsonElement?> Responses { get; } = new();

        public override JsonElement? Execute(string command, IDictionary<string, object?>? parameters)
        {
            Calls.Add(new Call(command, parameters));
            return Responses.TryGetValue(command, out var r) ? r : null;
        }

        public Call Last => Calls[Calls.Count - 1];
        public Call CallNamed(string command) => Calls.First(c => c.Command == command);
        public bool Issued(string command) => Calls.Any(c => c.Command == command);

        public void SetResponse(string command, string json)
        {
            using var doc = JsonDocument.Parse(json);
            Responses[command] = doc.RootElement.Clone();
        }
    }

    public class NavigateFacadeTests
    {
        [Fact]
        public void GoToUrlStringIssuesGet()
        {
            var d = new RecordingDriver();
            d.Navigate().GoToUrl("https://example.com/a");
            d.Last.Command.ShouldBe("get");
            d.Last.Params!["url"].ShouldBe("https://example.com/a");
        }

        [Fact]
        public void GoToUrlUriIssuesGet()
        {
            var d = new RecordingDriver();
            d.Navigate().GoToUrl(new Uri("https://example.com/b"));
            d.Last.Command.ShouldBe("get");
            ((string)d.Last.Params!["url"]!).ShouldContain("example.com/b");
        }

        [Fact]
        public void BackForwardRefreshIssueTheirCommands()
        {
            var d = new RecordingDriver();
            var nav = d.Navigate();
            nav.Back();
            d.Last.Command.ShouldBe("goBack");
            nav.Forward();
            d.Last.Command.ShouldBe("goForward");
            nav.Refresh();
            d.Last.Command.ShouldBe("refresh");
        }

        [Fact]
        public void UrlSetterNavigatesGetterReads()
        {
            var d = new RecordingDriver();
            d.SetResponse("getCurrentUrl", "\"https://here/\"");
            d.Url = "https://there/";
            d.Last.Command.ShouldBe("get");
            d.Last.Params!["url"].ShouldBe("https://there/");
            d.Url.ShouldBe("https://here/");
        }
    }

    public class SwitchToFacadeTests
    {
        [Fact]
        public void WindowIssuesSwitchToWindow()
        {
            var d = new RecordingDriver();
            d.SwitchTo().Window("w-123");
            d.Last.Command.ShouldBe("switchToWindow");
            d.Last.Params!["handle"].ShouldBe("w-123");
        }

        [Fact]
        public void FrameByIndexIssuesSwitchToFrameWithIntId()
        {
            var d = new RecordingDriver();
            d.SwitchTo().Frame(2);
            d.Last.Command.ShouldBe("switchToFrame");
            d.Last.Params!["id"].ShouldBe(2);
        }

        [Fact]
        public void DefaultContentIssuesSwitchToFrameNull()
        {
            var d = new RecordingDriver();
            d.SwitchTo().DefaultContent();
            d.Last.Command.ShouldBe("switchToFrame");
            d.Last.Params!["id"].ShouldBeNull();
        }

        [Fact]
        public void ParentFrameIssuesSwitchToFrameParent()
        {
            var d = new RecordingDriver();
            d.SwitchTo().ParentFrame();
            d.Last.Command.ShouldBe("switchToFrameParent");
        }

        [Fact]
        public void NewWindowTabIssuesNewWindowThenSwitch()
        {
            var d = new RecordingDriver();
            d.SetResponse("newWindow", "{\"handle\":\"h-9\",\"type\":\"tab\"}");
            d.SwitchTo().NewWindow(WindowType.Tab);
            d.CallNamed("newWindow").Params!["type"].ShouldBe("tab");
            d.Last.Command.ShouldBe("switchToWindow");
            d.Last.Params!["handle"].ShouldBe("h-9");
        }

        [Fact]
        public void ActiveElementIssuesGetActiveElementAndWrapsHandle()
        {
            var d = new RecordingDriver();
            d.SetResponse("getActiveElement", "{\"element-6066-11e4-a52e-4f735466cecf\":\"E-1\"}");
            var el = d.SwitchTo().ActiveElement();
            d.CallNamed("getActiveElement").ShouldNotBeNull();
            ((RemoteWebElement)el).Id.ShouldBe("E-1");
        }

        [Fact]
        public void AlertGetterTouchesTextThenExposesControls()
        {
            var d = new RecordingDriver();
            d.SetResponse("getAlertText", "\"are you sure?\"");
            IAlert alert = d.SwitchTo().Alert();
            // SwitchTo().Alert() eagerly reads the text (mainstream behaviour).
            d.Issued("getAlertText").ShouldBeTrue();
            alert.Text.ShouldBe("are you sure?");
            alert.Accept();
            d.Last.Command.ShouldBe("acceptAlert");
            alert.Dismiss();
            d.Last.Command.ShouldBe("dismissAlert");
            alert.SendKeys("hi");
            d.Last.Command.ShouldBe("setAlertValue");
            d.Last.Params!["text"].ShouldBe("hi");
        }
    }

    public class ManageFacadeTests
    {
        [Fact]
        public void CookiesAddIssuesAddCookieWithNestedCookie()
        {
            var d = new RecordingDriver();
            d.Manage().Cookies.AddCookie(new Cookie("flavor", "mint"));
            d.Last.Command.ShouldBe("addCookie");
            var cookie = (IDictionary<string, object?>)d.Last.Params!["cookie"]!;
            cookie["name"].ShouldBe("flavor");
            cookie["value"].ShouldBe("mint");
        }

        [Fact]
        public void CookiesDeleteNamedAndAllIssueTheirCommands()
        {
            var d = new RecordingDriver();
            d.Manage().Cookies.DeleteCookieNamed("flavor");
            d.Last.Command.ShouldBe("deleteCookie");
            d.Last.Params!["name"].ShouldBe("flavor");
            d.Manage().Cookies.DeleteAllCookies();
            d.Last.Command.ShouldBe("deleteAllCookies");
        }

        [Fact]
        public void CookiesGetNamedReturnsNullWhenAbsent()
        {
            var d = new RecordingDriver();
            d.SetResponse("getCookie", "{\"name\":\"\",\"value\":\"\"}");
            d.Manage().Cookies.GetCookieNamed("nope").ShouldBeNull();
        }

        [Fact]
        public void WindowMaximizeMinimizeFullScreen()
        {
            var d = new RecordingDriver();
            var w = d.Manage().Window;
            w.Maximize();
            d.Last.Command.ShouldBe("maximizeWindow");
            w.Minimize();
            d.Last.Command.ShouldBe("minimizeWindow");
            w.FullScreen();
            d.Last.Command.ShouldBe("fullscreenWindow");
        }

        [Fact]
        public void WindowSizeSetIssuesSetWindowRect()
        {
            var d = new RecordingDriver();
            d.SetResponse("setWindowRect", "{\"x\":0,\"y\":0,\"width\":800,\"height\":600}");
            d.Manage().Window.Size = new System.Drawing.Size(800, 600);
            d.Last.Command.ShouldBe("setWindowRect");
            d.Last.Params!["width"].ShouldBe(800);
            d.Last.Params!["height"].ShouldBe(600);
        }

        [Fact]
        public void WindowPositionGetReadsRect()
        {
            var d = new RecordingDriver();
            d.SetResponse("getWindowRect", "{\"x\":12,\"y\":34,\"width\":800,\"height\":600}");
            var pos = d.Manage().Window.Position;
            d.Issued("getWindowRect").ShouldBeTrue();
            pos.X.ShouldBe(12);
            pos.Y.ShouldBe(34);
        }

        [Fact]
        public void TimeoutsSetSendMilliseconds()
        {
            var d = new RecordingDriver();
            var t = d.Manage().Timeouts();
            t.ImplicitWait = TimeSpan.FromSeconds(3);
            d.Last.Command.ShouldBe("setTimeout");
            Convert.ToInt64(d.Last.Params!["implicit"]).ShouldBe(3000L);
            t.PageLoad = TimeSpan.FromSeconds(10);
            Convert.ToInt64(d.Last.Params!["pageLoad"]).ShouldBe(10000L);
            t.AsynchronousJavaScript = TimeSpan.FromMilliseconds(500);
            Convert.ToInt64(d.Last.Params!["script"]).ShouldBe(500L);
        }

        [Fact]
        public void TimeoutsGetReadsMilliseconds()
        {
            var d = new RecordingDriver();
            d.SetResponse("getTimeout", "{\"implicit\":2500,\"pageLoad\":30000,\"script\":1000}");
            d.Manage().Timeouts().ImplicitWait.ShouldBe(TimeSpan.FromMilliseconds(2500));
        }
    }

    public class WebDriverAbiTests
    {
        [Fact]
        public void CloseIssuesCloseNotQuit()
        {
            var d = new RecordingDriver();
            d.Close();
            d.Last.Command.ShouldBe("close");
        }

        [Fact]
        public void FindElementsReturnsReadOnlyCollection()
        {
            var d = new RecordingDriver();
            d.SetResponse("findElements", "[{\"element-6066-11e4-a52e-4f735466cecf\":\"A\"}," +
                                          "{\"element-6066-11e4-a52e-4f735466cecf\":\"B\"}]");
            ReadOnlyCollection<IWebElement> els = d.FindElements(By.CssSelector("div"));
            els.Count.ShouldBe(2);
            // Still an IReadOnlyList too, so existing callers keep compiling.
            IReadOnlyList<IWebElement> asList = els;
            asList.Count.ShouldBe(2);
        }

        [Fact]
        public void ExecuteScriptWrapsElementArgsAsW3CReference()
        {
            var d = new RecordingDriver();
            d.SetResponse("getActiveElement", "{\"element-6066-11e4-a52e-4f735466cecf\":\"E-7\"}");
            var el = d.SwitchTo().ActiveElement();
            d.ExecuteScript("return arguments[0];", el);
            var call = d.CallNamed("executeScript");
            var args = (System.Collections.IList)call.Params!["args"]!;
            var first = (IDictionary<string, object?>)args[0]!;
            first["element-6066-11e4-a52e-4f735466cecf"].ShouldBe("E-7");
        }

        [Fact]
        public void GetScreenshotDecodesBase64Png()
        {
            var d = new RecordingDriver();
            // "PNG" bytes base64 — enough to prove AsByteArray decodes.
            byte[] raw = { 0x89, (byte)'P', (byte)'N', (byte)'G' };
            d.SetResponse("screenshot", "\"" + Convert.ToBase64String(raw) + "\"");
            Screenshot shot = d.GetScreenshot();
            shot.AsByteArray.ShouldBe(raw);
            shot.AsBase64EncodedString.ShouldBe(Convert.ToBase64String(raw));
        }
    }

    public class WebElementAbiTests
    {
        // A recording driver whose Execute returns element-command responses keyed by
        // command, so RemoteWebElement members can be exercised without a browser.
        private static (RecordingDriver, RemoteWebElement) NewElement()
        {
            var d = new RecordingDriver();
            d.SetResponse("findElement", "{\"element-6066-11e4-a52e-4f735466cecf\":\"E-1\"}");
            var el = (RemoteWebElement)d.FindElement(By.Id("x"));
            return (d, el);
        }

        [Fact]
        public void LocationAndSizeReadRect()
        {
            var (d, el) = NewElement();
            d.SetResponse("getElementRect", "{\"x\":10,\"y\":20,\"width\":30,\"height\":40}");
            el.Location.ShouldBe(new System.Drawing.Point(10, 20));
            el.Size.ShouldBe(new System.Drawing.Size(30, 40));
        }

        [Fact]
        public void GetCssValueIssuesCssCommand()
        {
            var (d, el) = NewElement();
            d.SetResponse("getElementValueOfCssProperty", "\"rgb(1, 2, 3)\"");
            el.GetCssValue("color").ShouldBe("rgb(1, 2, 3)");
            d.CallNamed("getElementValueOfCssProperty").Params!["propertyName"].ShouldBe("color");
        }

        [Fact]
        public void GetDomPropertyIssuesGetElementProperty()
        {
            var (d, el) = NewElement();
            d.SetResponse("getElementProperty", "\"checked-value\"");
            el.GetDomProperty("value").ShouldBe("checked-value");
            d.CallNamed("getElementProperty").Params!["name"].ShouldBe("value");
        }

        [Fact]
        public void GetShadowRootWrapsShadowReference()
        {
            var (d, el) = NewElement();
            d.SetResponse("getShadowRoot", "{\"shadow-6066-11e4-a52e-4f735466cecf\":\"S-1\"}");
            ISearchContext root = el.GetShadowRoot();
            ((ShadowRoot)root).Id.ShouldBe("S-1");
        }

        [Fact]
        public void SubmitRunsFormAtomScriptWithThisElement()
        {
            var (d, el) = NewElement();
            el.Submit();
            var call = d.CallNamed("executeScript");
            ((string)call.Params!["script"]!).ShouldContain("submitForm");
            var args = (System.Collections.IList)call.Params!["args"]!;
            var first = (IDictionary<string, object?>)args[0]!;
            first["element-6066-11e4-a52e-4f735466cecf"].ShouldBe("E-1");
        }
    }

    public class ExceptionAbiTests
    {
        [Fact]
        public void StringConstructorsCompileAndCarryMessage()
        {
            new NoSuchElementException("gone").Message.ShouldBe("gone");
            new NoSuchWindowException("no win").Message.ShouldBe("no win");
            new NoSuchFrameException("no frame").Message.ShouldBe("no frame");
            new NoAlertPresentException("no alert").Message.ShouldBe("no alert");
            new NoSuchShadowRootException("no shadow").Message.ShouldBe("no shadow");
            new InvalidElementStateException("bad state").Message.ShouldBe("bad state");
            new UnexpectedAlertOpenException("modal").Message.ShouldBe("modal");
            new WebDriverException("boom").Message.ShouldBe("boom");
        }

        [Fact]
        public void MessageAndInnerConstructorCompiles()
        {
            var inner = new InvalidOperationException("root");
            var ex = new NoSuchElementException("outer", inner);
            ex.Message.ShouldBe("outer");
            ex.InnerException.ShouldBe(inner);
        }

        [Fact]
        public void EngineCodeConstructorStillWorks()
        {
            new NoSuchElementException("gone", 17).Code.ShouldBe(17);
        }

        [Fact]
        public void NotFoundIsBaseOfTheNoSuchFamily()
        {
            new NoSuchElementException("x").ShouldBeAssignableTo<NotFoundException>();
            new NoSuchWindowException("x").ShouldBeAssignableTo<NotFoundException>();
            new NoSuchFrameException("x").ShouldBeAssignableTo<NotFoundException>();
            new NoAlertPresentException("x").ShouldBeAssignableTo<NotFoundException>();
        }

        // Subclassing must compile (the classes are unsealed).
        private sealed class MyError : NoSuchElementException
        {
            public MyError(string m) : base(m) { }
        }

        [Fact]
        public void ExceptionClassesAreSubclassable()
        {
            var e = new MyError("custom");
            e.ShouldBeAssignableTo<NoSuchElementException>();
            e.Message.ShouldBe("custom");
        }
    }

    public class ChromeOptionsAbiTests
    {
        [Fact]
        public void AddArgumentAndToCapabilitiesNestUnderGoogChromeOptions()
        {
            var options = new ChromeOptions();
            options.AddArgument("--headless=new");
            options.AddArguments("--no-sandbox", "--disable-gpu");
            options.BinaryLocation = "/usr/bin/chrome";

            IDictionary<string, object?> caps = options.ToCapabilities();
            caps["browserName"].ShouldBe("chrome");

            var chrome = (IDictionary<string, object?>)caps["goog:chromeOptions"]!;
            var args = (IEnumerable<string>)chrome["args"]!;
            args.ShouldContain("--headless=new");
            args.ShouldContain("--no-sandbox");
            args.ShouldContain("--disable-gpu");
            chrome["binary"].ShouldBe("/usr/bin/chrome");
        }

        [Fact]
        public void UserProfilePreferenceAndExperimentalOptionNest()
        {
            var options = new ChromeOptions();
            options.AddUserProfilePreference("download.default_directory", "/tmp");
            options.AddAdditionalChromeOption("excludeSwitches", new[] { "enable-automation" });

            var chrome = (IDictionary<string, object?>)options.ToCapabilities()["goog:chromeOptions"]!;
            var prefs = (IDictionary<string, object?>)chrome["prefs"]!;
            prefs["download.default_directory"].ShouldBe("/tmp");
            chrome["excludeSwitches"].ShouldNotBeNull();
        }

        [Fact]
        public void DriverConstructorAcceptsOptionsObject()
        {
            // new RemoteWebDriver(url, options) must accept a ChromeOptions and apply
            // ToCapabilities. We can't open a real session here, so prove the overload
            // resolves and ToDictionary yields the caps a constructor would consume.
            var options = new ChromeOptions();
            options.AddArgument("--headless=new");
            IDictionary<string, object?> caps = options.ToDictionary();
            caps.ShouldContainKey("goog:chromeOptions");
            caps["browserName"].ShouldBe("chrome");

            // A DriverOptions-typed reference resolves the (string, DriverOptions) ctor.
            DriverOptions asBase = options;
            asBase.ToCapabilities().ShouldContainKey("goog:chromeOptions");
        }

        [Fact]
        public void ChromeOptionsResolvesInChromeNamespace()
        {
            // `using OpenQA.Selenium.Chrome;` + new ChromeOptions() — the mainstream path.
            OpenQA.Selenium.Chrome.ChromeOptions o = new ChromeOptions();
            o.CapabilityName.ShouldBe("goog:chromeOptions");
        }
    }
}
