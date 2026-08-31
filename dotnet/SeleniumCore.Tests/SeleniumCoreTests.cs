using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Threading;
using SeleniumCore;
using Xunit;
using Shouldly;

namespace SeleniumCore.Tests
{
    // FFI facts — no browser: the pure engine helpers + the transport-error
    // path. The engine .so is found via SELENIUM_CORE_LIB, set by the aeb node.
    public class FfiTests
    {
        [Fact] public void RouteGet() =>
            WebDriver.Route("get").ShouldBe("POST /session/:sessionId/url");

        [Fact] public void RouteUnknown() =>
            WebDriver.Route("nope").ShouldBe("");

        [Fact] public void ErrorCodeNoSuchElement() =>
            WebDriver.ErrorCode("no such element").ShouldBe(17);

        [Fact] public void ErrorCodeSuccess() =>
            WebDriver.ErrorCode("").ShouldBe(0);

        [Fact] public void LocatorCss() =>
            WebDriver.Locator(By.CssSelector, "div.foo")
                .ShouldBe("{\"using\":\"css selector\",\"value\":\"div.foo\"}");

        [Fact] public void LocatorIdRewrite() =>
            WebDriver.Locator(By.Id, "main")
                .ShouldBe("{\"using\":\"css selector\",\"value\":\"*[id=\\\"main\\\"]\"}");

        [Fact]
        public void TransportFailureIsWebDriverErrorMinusOne()
        {
            var ex = Should.Throw<WebDriverError>(() => WebDriver.Chrome("http://127.0.0.1:1"));
            ex.Code.ShouldBe(-1);
        }
    }

    // Live surface — a real headless-Chrome session driven end to end through
    // the engine, against an in-process content server. Skipped (not failed)
    // when chromedriver is absent, so the suite is green on a box without a
    // browser. One ordered session, so it is one fact, not many.
    public class LiveSurfaceTests
    {
        [SkippableFact]
        public void HeadlessChromeSurface()
        {
            string? driver = Which("chromedriver");
            Skip.If(driver is null, "chromedriver not on PATH");

            int webPort = FreePort();
            using var webCts = new System.Threading.CancellationTokenSource();
            StartContentServer(webPort, webCts.Token);
            string baseUrl = $"http://127.0.0.1:{webPort}";

            int cdPort = FreePort();
            var cd = Process.Start(new ProcessStartInfo(driver!, $"--port={cdPort}")
                { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true })!;
            try
            {
                Skip.IfNot(WaitUp(cdPort, 10000), "chromedriver did not come up");

                // Headless Chrome; point at an explicit binary when SEL_CHROME_BINARY
                // is set (a box with no system Chrome but a cached Chrome-for-Testing).
                var chromeArgs = new List<object?> { "--headless=new", "--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage" };
                var chromeOpts = new Dictionary<string, object?> { ["args"] = chromeArgs };
                string? chromeBin = Environment.GetEnvironmentVariable("SEL_CHROME_BINARY");
                if (!string.IsNullOrEmpty(chromeBin)) chromeOpts["binary"] = chromeBin;
                var d = WebDriver.Chrome($"http://127.0.0.1:{cdPort}",
                    new Dictionary<string, object?> { ["goog:chromeOptions"] = chromeOpts });
                try
                {
                    d.SessionId.Length.ShouldBeGreaterThan(0);

                    d.Get(baseUrl + "/one");
                    d.Title.ShouldBe("Page One");
                    d.FindElement(By.Id, "hdr").Text.ShouldBe("One");
                    d.FindElement(By.CssSelector, "#go").TagName.ToLowerInvariant().ShouldBe("a");

                    d.FindElement(By.Id, "go").Click();
                    d.Title.ShouldBe("Page Two");
                    d.Back();
                    d.Title.ShouldBe("Page One");
                    d.Forward();
                    d.Title.ShouldBe("Page Two");
                    d.Back();

                    d.DeleteAllCookies();
                    d.AddCookie(new Dictionary<string, object?> { ["name"] = "flavor", ["value"] = "mint" });
                    d.GetCookie("flavor")!.Value.GetProperty("value").GetString().ShouldBe("mint");
                    d.DeleteCookie("flavor");

                    var handles = d.WindowHandles;
                    handles.Count.ShouldBeGreaterThanOrEqualTo(1);
                    handles.ShouldContain(d.CurrentWindowHandle);
                    d.SetWindowRect(new Dictionary<string, object?> { ["width"] = 900, ["height"] = 650 });
                    d.GetWindowRect()!.Value.GetProperty("width").GetInt32().ShouldBe(900);

                    d.ExecuteScript("return 6*7;")!.Value.GetInt32().ShouldBe(42);
                    d.ExecuteScript("return 'hi';")!.Value.GetString().ShouldBe("hi");
                    d.ExecuteScript("return arguments[0]+arguments[1];", 40, 2)!.Value.GetInt32().ShouldBe(42);

                    JsonElement rect = d.FindElement(By.Id, "btn").Rect;
                    int cx = (int)(rect.GetProperty("x").GetDouble() + rect.GetProperty("width").GetDouble() / 2);
                    int cy = (int)(rect.GetProperty("y").GetDouble() + rect.GetProperty("height").GetDouble() / 2);
                    d.PerformActions(new List<object?>
                    {
                        new Dictionary<string, object?>
                        {
                            ["type"] = "pointer",
                            ["id"] = "mouse",
                            ["parameters"] = new Dictionary<string, object?> { ["pointerType"] = "mouse" },
                            ["actions"] = new List<object?>
                            {
                                new Dictionary<string, object?> { ["type"] = "pointerMove", ["duration"] = 0, ["x"] = cx, ["y"] = cy },
                                new Dictionary<string, object?> { ["type"] = "pointerDown", ["button"] = 0 },
                                new Dictionary<string, object?> { ["type"] = "pointerUp", ["button"] = 0 },
                            },
                        },
                    });
                    d.FindElement(By.Id, "hdr").Text.ShouldBe("clicked");
                    d.ClearActions();

                    byte[] png = Convert.FromBase64String(d.ScreenshotBase64());
                    (png.Length > 8 && png[1] == 'P' && png[2] == 'N' && png[3] == 'G').ShouldBeTrue();

                    Should.Throw<NoSuchElementError>(() => d.FindElement(By.Id, "does-not-exist"));
                }
                finally { d.Quit(); }
            }
            finally
            {
                try { cd.Kill(); } catch { /* already gone */ }
                webCts.Cancel();
            }
        }

        // WebDriver-BiDi over the same engine: subscribe to console log entries,
        // emit one via the classic script channel, and receive the event
        // asynchronously over the demux — the bidirectional half, driven from C#.
        [SkippableFact]
        public void HeadlessChromeBidi()
        {
            string? driver = Which("chromedriver");
            Skip.If(driver is null, "chromedriver not on PATH");

            int cdPort = FreePort();
            var cd = Process.Start(new ProcessStartInfo(driver!, $"--port={cdPort}")
                { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true })!;
            try
            {
                Skip.IfNot(WaitUp(cdPort, 10000), "chromedriver did not come up");

                // Headless Chrome; point at an explicit binary when SEL_CHROME_BINARY
                // is set (a box with no system Chrome but a cached Chrome-for-Testing).
                var chromeArgs = new List<object?> { "--headless=new", "--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage" };
                var chromeOpts = new Dictionary<string, object?> { ["args"] = chromeArgs };
                string? chromeBin = Environment.GetEnvironmentVariable("SEL_CHROME_BINARY");
                if (!string.IsNullOrEmpty(chromeBin)) chromeOpts["binary"] = chromeBin;
                var d = WebDriver.Chrome($"http://127.0.0.1:{cdPort}",
                    new Dictionary<string, object?> { ["goog:chromeOptions"] = chromeOpts });
                try
                {
                    d.BidiAvailable.ShouldBeTrue();
                    d.Get("data:text/html,<!doctype html><title>BiDi</title><h1>bidi</h1>");

                    var ack = d.Bidi.Subscribe(BidiEvent.LogEntryAdded);
                    ack["type"].ShouldBe("success");

                    d.ExecuteScript("console.log('bidi-hello');");

                    var ev = d.Bidi.NextEvent(BidiEvent.LogEntryAdded, 8000);
                    ev.ShouldNotBeNull();
                    ev!["method"].ShouldBe(BidiEvent.LogEntryAdded);
                    JsonSerializer.Serialize(ev).ShouldContain("bidi-hello");

                    var status = d.Bidi.Command("session.status");
                    status["type"].ShouldBe("success");

                    // script.evaluate — the richer alternative to ExecuteScript.
                    d.Bidi.TopContext().ShouldNotBeNull();
                    Convert.ToInt32(d.Bidi.EvaluateValue("6*7")).ShouldBe(42);
                    // awaitPromise: a resolved promise's value comes back unwrapped.
                    Convert.ToInt32(d.Bidi.EvaluateValue("Promise.resolve(41+1)")).ShouldBe(42);

                    // network interception — observe + release a paused request.
                    d.Bidi.Subscribe(BidiEvent.BeforeRequestSent);
                    string? intercept = d.Bidi.AddIntercept();  // all URLs, beforeRequestSent
                    intercept.ShouldNotBeNull();
                    d.ExecuteScript("fetch('https://example.com/blocked').catch(() => {});");
                    var netEv = d.Bidi.NextEvent(BidiEvent.BeforeRequestSent, 8000);
                    netEv.ShouldNotBeNull();
                    string? rid = BiDi.EventRequestId(netEv!);
                    rid.ShouldNotBeNull();
                    d.Bidi.ContinueRequest(rid!)["type"].ShouldBe("success");

                    // request mocking — provideResponse fulfills a paused request with a fake body.
                    d.ExecuteScript("window.__mock='';fetch('https://example.com/api').then(r => r.text()).then(t => {window.__mock=t;}).catch(() => {});");
                    var netEv2 = d.Bidi.NextEvent(BidiEvent.BeforeRequestSent, 8000);
                    string? rid2 = BiDi.EventRequestId(netEv2!);
                    rid2.ShouldNotBeNull();
                    d.Bidi.ProvideResponse(rid2!, status: 200, contentType: "text/plain", body: "MOCKED-BODY")["type"].ShouldBe("success");
                    string mocked = "";
                    for (int i = 0; i < 25; i++)
                    {
                        mocked = d.ExecuteScript("return window.__mock;")?.GetString() ?? "";
                        if (mocked.Contains("MOCKED-BODY")) break;
                        System.Threading.Thread.Sleep(200);
                    }
                    mocked.ShouldContain("MOCKED-BODY");

                    // network.setCacheBehavior — disable then restore the session HTTP cache.
                    d.Bidi.SetCacheBehavior("bypass")["type"].ShouldBe("success");
                    d.Bidi.SetCacheBehavior("default")["type"].ShouldBe("success");
                }
                finally { d.Quit(); }
            }
            finally
            {
                try { cd.Kill(); } catch { /* already gone */ }
            }
        }

        // Atom-backed commands (isDisplayed / getAttribute / relative locators)
        // run in-page via the shared engine atoms, from C# through the C ABI.
        [SkippableFact]
        public void HeadlessChromeAtoms()
        {
            string? driver = Which("chromedriver");
            Skip.If(driver is null, "chromedriver not on PATH");

            int cdPort = FreePort();
            var cd = Process.Start(new ProcessStartInfo(driver!, $"--port={cdPort}")
                { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true })!;
            try
            {
                Skip.IfNot(WaitUp(cdPort, 10000), "chromedriver did not come up");

                var chromeArgs = new List<object?> { "--headless=new", "--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage" };
                var chromeOpts = new Dictionary<string, object?> { ["args"] = chromeArgs };
                string? chromeBin = Environment.GetEnvironmentVariable("SEL_CHROME_BINARY");
                if (!string.IsNullOrEmpty(chromeBin)) chromeOpts["binary"] = chromeBin;
                var d = WebDriver.Chrome($"http://127.0.0.1:{cdPort}",
                    new Dictionary<string, object?> { ["goog:chromeOptions"] = chromeOpts });
                try
                {
                    d.Get("data:text/html,<!doctype html><title>Atoms</title>"
                        + "<h1 id='hdr'>H</h1><button id='btn'>b</button>"
                        + "<p id='gone' style='display:none'>x</p>"
                        + "<a id='lnk' href='https://example.com/x'>l</a>");

                    d.FindElement(By.Id, "hdr").IsDisplayed().ShouldBeTrue();
                    d.FindElement(By.Id, "gone").IsDisplayed().ShouldBeFalse();

                    string? href = d.FindElement(By.Id, "lnk").GetAttribute("href");
                    href.ShouldNotBeNull();
                    href!.ShouldContain("example.com/x");

                    var rel = d.FindRelative("button",
                        new Dictionary<string, object?> { ["kind"] = "below", ["sel"] = "#hdr" });
                    rel.Count.ShouldBeGreaterThanOrEqualTo(1);
                    rel[0].TagName.ToLowerInvariant().ShouldBe("button");
                }
                finally { d.Quit(); }
            }
            finally
            {
                try { cd.Kill(); } catch { /* already gone */ }
            }
        }

        // --- in-process content server (two pages: /one links to /two) -------
        private static void StartContentServer(int port, System.Threading.CancellationToken ct)
        {
            const string two = "<!doctype html><title>Page Two</title><h1 id=\"hdr\">Two</h1>";
            const string one = "<!doctype html><title>Page One</title><h1 id=\"hdr\">One</h1>"
                + "<a id=\"go\" href=\"/two\">to two</a>"
                + "<button id=\"btn\" onclick=\"document.getElementById('hdr').textContent='clicked'\">b</button>";
            var listener = new HttpListener();
            listener.Prefixes.Add($"http://127.0.0.1:{port}/");
            listener.Start();
            var t = new Thread(() =>
            {
                try
                {
                    while (!ct.IsCancellationRequested)
                    {
                        var ctx = listener.GetContext();
                        string body = ctx.Request.Url!.AbsolutePath.StartsWith("/two") ? two : one;
                        byte[] buf = Encoding.UTF8.GetBytes(body);
                        ctx.Response.ContentType = "text/html; charset=utf-8";
                        ctx.Response.OutputStream.Write(buf, 0, buf.Length);
                        ctx.Response.Close();
                    }
                }
                catch { /* listener stopped */ }
                finally { try { listener.Stop(); } catch { } }
            }) { IsBackground = true };
            t.Start();
        }

        private static string? Which(string cmd)
        {
            foreach (var dir in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(':'))
            {
                var p = Path.Combine(dir, cmd);
                if (File.Exists(p)) return p;
            }
            return null;
        }

        private static int FreePort()
        {
            var l = new TcpListener(IPAddress.Loopback, 0);
            l.Start();
            int port = ((IPEndPoint)l.LocalEndpoint).Port;
            l.Stop();
            return port;
        }

        private static bool WaitUp(int port, int timeoutMs)
        {
            var until = DateTime.UtcNow.AddMilliseconds(timeoutMs);
            while (DateTime.UtcNow < until)
            {
                try { using var c = new TcpClient(); c.Connect("127.0.0.1", port); return true; }
                catch { Thread.Sleep(100); }
            }
            return false;
        }
    }
}
