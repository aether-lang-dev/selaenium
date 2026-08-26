using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using SeleniumCore;

// Console test harness for the .NET binding. No xunit — a plain Main() with
// assertions, so it builds/runs offline with no NuGet restore. Two modes:
//   ffi  — no browser: pure engine helpers + transport-error round-trip.
//   live — real headless Chrome + full surface, served by an in-process
//          HttpListener. Skips (exit 0) if chromedriver is absent.
// Default runs both.

internal static class Program
{
    private static int _failures;

    private static void Check(bool cond, string label)
    {
        if (cond)
        {
            Console.WriteLine("  ok: " + label);
        }
        else
        {
            Console.WriteLine("FAIL: " + label);
            _failures++;
        }
    }

    private static int Main(string[] args)
    {
        string mode = args.Length > 0 ? args[0] : "all";
        if (mode is "ffi" or "all")
        {
            ModeFfi();
        }
        if (mode is "live" or "all")
        {
            ModeLive();
        }
        if (_failures == 0)
        {
            Console.WriteLine("PASS: .NET tests green");
            return 0;
        }
        Console.WriteLine($"FAILED: {_failures} .NET test(s)");
        return 1;
    }

    private static void ModeFfi()
    {
        Console.WriteLine("== .NET FFI ==");
        Check(WebDriver.Route("get") == "POST /session/:sessionId/url", "route get");
        Check(WebDriver.Route("nope") == "", "route unknown");
        Check(WebDriver.ErrorCode("no such element") == 17, "errorCode no such element");
        Check(WebDriver.ErrorCode("") == 0, "errorCode success");
        Check(WebDriver.Locator(By.CssSelector, "div.foo") == "{\"using\":\"css selector\",\"value\":\"div.foo\"}", "locator css");
        Check(WebDriver.Locator(By.Id, "main") == "{\"using\":\"css selector\",\"value\":\"*[id=\\\"main\\\"]\"}", "locator id rewrite");
        bool threw = false;
        try
        {
            WebDriver.Chrome("http://127.0.0.1:1");
        }
        catch (WebDriverError e)
        {
            threw = e.Code == -1;
        }
        Check(threw, "transport failure -> WebDriverError(-1)");
    }

    private static void ModeLive()
    {
        Console.WriteLine("== .NET live surface ==");
        string? driverBin = Which("chromedriver");
        if (driverBin == null)
        {
            Console.WriteLine("SKIPPED: chromedriver not on PATH");
            return;
        }

        const string pageOne =
            "<!doctype html><title>Page One</title><h1 id=\"hdr\">One</h1>"
            + "<a id=\"go\" href=\"/two\">to two</a>"
            + "<button id=\"btn\" onclick=\"document.getElementById('hdr').textContent='clicked'\">b</button>";
        const string pageTwo = "<!doctype html><title>Page Two</title><h1 id=\"hdr\">Two</h1>";

        int webPort = FreePort();
        var listener = new HttpListener();
        listener.Prefixes.Add($"http://127.0.0.1:{webPort}/");
        listener.Start();
        var webCts = new System.Threading.CancellationTokenSource();
        var webTask = System.Threading.Tasks.Task.Run(() =>
        {
            while (!webCts.IsCancellationRequested)
            {
                HttpListenerContext ctx;
                try
                {
                    ctx = listener.GetContext();
                }
                catch
                {
                    break;
                }
                byte[] body = Encoding.UTF8.GetBytes(ctx.Request.Url!.AbsolutePath.StartsWith("/two") ? pageTwo : pageOne);
                ctx.Response.ContentType = "text/html; charset=utf-8";
                ctx.Response.ContentLength64 = body.Length;
                ctx.Response.OutputStream.Write(body, 0, body.Length);
                ctx.Response.OutputStream.Close();
            }
        });
        string baseUrl = $"http://127.0.0.1:{webPort}";

        int cdPort = FreePort();
        var cd = Process.Start(new ProcessStartInfo(driverBin, $"--port={cdPort}")
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        })!;
        try
        {
            if (!WaitUp(cdPort, 10000))
            {
                Console.WriteLine("SKIPPED: chromedriver did not come up");
                return;
            }
            var d = WebDriver.HeadlessChrome($"http://127.0.0.1:{cdPort}");
            try
            {
                Check(d.SessionId.Length > 0, "session started");

                d.Get(baseUrl + "/one");
                Check(d.Title == "Page One", "title");
                Check(d.FindElement(By.Id, "hdr").Text == "One", "hdr text");
                Check(d.FindElement(By.CssSelector, "#go").TagName.ToLowerInvariant() == "a", "tag name");

                // navigation history
                d.FindElement(By.Id, "go").Click();
                Check(d.Title == "Page Two", "after click");
                d.Back();
                Check(d.Title == "Page One", "after back");
                d.Forward();
                Check(d.Title == "Page Two", "after forward");
                d.Back();

                // cookies
                d.DeleteAllCookies();
                d.AddCookie(new Dictionary<string, object?> { ["name"] = "flavor", ["value"] = "mint" });
                Check(d.GetCookie("flavor")!.Value.GetProperty("value").GetString() == "mint", "cookie value");
                d.DeleteCookie("flavor");

                // windows
                var handles = d.WindowHandles;
                Check(handles.Count >= 1, "window handles");
                Check(handles.Contains(d.CurrentWindowHandle), "current handle in list");
                d.SetWindowRect(new Dictionary<string, object?> { ["width"] = 900, ["height"] = 650 });
                Check(d.GetWindowRect()!.Value.GetProperty("width").GetInt32() == 900, "window width");

                // execute_script shapes
                Check(d.ExecuteScript("return 6*7;")!.Value.GetInt32() == 42, "script scalar");
                Check(d.ExecuteScript("return 'hi';")!.Value.GetString() == "hi", "script string");
                Check(d.ExecuteScript("return arguments[0]+arguments[1];", 40, 2)!.Value.GetInt32() == 42, "script args");

                // W3C actions: pointer click on the button.
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
                Check(d.FindElement(By.Id, "hdr").Text == "clicked", "actions click fired");
                d.ClearActions();

                // screenshot -> PNG
                byte[] png = Convert.FromBase64String(d.ScreenshotBase64());
                Check(png.Length > 8 && png[1] == 'P' && png[2] == 'N' && png[3] == 'G', "screenshot is PNG");

                // negative path
                bool nse = false;
                try
                {
                    d.FindElement(By.Id, "does-not-exist");
                }
                catch (NoSuchElementError)
                {
                    nse = true;
                }
                Check(nse, "NoSuchElement raised");
            }
            finally
            {
                d.Quit();
            }
        }
        finally
        {
            try { cd.Kill(); } catch { /* already gone */ }
            webCts.Cancel();
            listener.Stop();
        }
    }

    private static string? Which(string cmd)
    {
        string? path = Environment.GetEnvironmentVariable("PATH");
        if (path == null)
        {
            return null;
        }
        foreach (string dir in path.Split(':'))
        {
            string full = System.IO.Path.Combine(dir, cmd);
            if (System.IO.File.Exists(full))
            {
                return full;
            }
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
        var deadline = DateTime.UtcNow.AddMilliseconds(timeoutMs);
        while (DateTime.UtcNow < deadline)
        {
            try
            {
                using var c = new TcpClient();
                c.Connect(IPAddress.Loopback, port);
                return true;
            }
            catch
            {
                System.Threading.Thread.Sleep(100);
            }
        }
        return false;
    }
}
