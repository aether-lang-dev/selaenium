using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net.Sockets;
using SeleniumCore;

// Third-party consumer example. References the INSTALLED SeleniumCore NuGet
// package (restored from a local feed — NOT the source tree) and proves the
// bundled engine .so (shipped under runtimes/linux-x64/native/) loads and drives
// the protocol, with SELENIUM_CORE_LIB unset so only the package's own bundled
// .so can satisfy the load.
//   ffi | discovery | live
internal static class Program
{
    private static int Main(string[] args)
    {
        string mode = args.Length > 0 ? args[0] : "ffi";
        switch (mode)
        {
            case "ffi":
                ModeFfi();
                break;
            case "discovery":
                ModeDiscovery();
                break;
            case "live":
                ModeLive();
                break;
            default:
                Console.Error.WriteLine("unknown mode: " + mode);
                return 1;
        }
        return 0;
    }

    private static void Fail(string msg)
    {
        Console.Error.WriteLine("FAIL: " + msg);
        Environment.Exit(1);
    }

    private static void ModeFfi()
    {
        if (WebDriver.Route("get") != "POST /session/:sessionId/url") Fail("route mismatch");
        if (WebDriver.ErrorCode("no such element") != 17) Fail("errorCode mismatch");
        if (!WebDriver.Locator(By.Id, "main").Contains("*[id=")) Fail("locator mismatch");
        bool threw = false;
        try
        {
            WebDriver.Chrome("http://127.0.0.1:1");
        }
        catch (WebDriverError e)
        {
            threw = e.Code == -1;
        }
        if (!threw) Fail("expected transport failure");
        Console.WriteLine("consumer(ffi): OK — installed package loaded its bundled .so and marshalled");
    }

    private static void ModeDiscovery()
    {
        string? env = Environment.GetEnvironmentVariable("SELENIUM_CORE_LIB");
        if (!string.IsNullOrEmpty(env)) Fail("SELENIUM_CORE_LIB set; discovery must run without it");
        // Forcing a native call proves the bundled .so (runtimes/.../native) loaded.
        if (WebDriver.Route("newSession") != "POST /session") Fail("route mismatch (bundled .so did not load)");
        Console.WriteLine("consumer(discovery): OK — zero-config bundled-.so discovery works");
    }

    private static void ModeLive()
    {
        string? driver = Which("chromedriver");
        if (driver == null)
        {
            Console.WriteLine("consumer(live): SKIPPED — chromedriver not on PATH");
            return;
        }
        int port;
        var l = new TcpListener(System.Net.IPAddress.Loopback, 0);
        l.Start();
        port = ((System.Net.IPEndPoint)l.LocalEndpoint).Port;
        l.Stop();
        var cd = Process.Start(new ProcessStartInfo(driver, $"--port={port}")
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        })!;
        try
        {
            if (!WaitUp(port, 10000))
            {
                Console.WriteLine("consumer(live): SKIPPED — chromedriver did not come up");
                return;
            }
            var d = WebDriver.HeadlessChrome($"http://127.0.0.1:{port}");
            try
            {
                string html = "<!doctype html><title>Installed</title><h1 id=\"h\">Hi</h1>";
                d.Get("data:text/html;charset=utf-8," + Uri.EscapeDataString(html));
                if (d.Title != "Installed") Fail("title=" + d.Title);
                if (d.FindElement(By.Id, "h").Text != "Hi") Fail("text mismatch");
                Console.WriteLine("consumer(live): OK — installed package drove real headless Chrome");
            }
            finally
            {
                d.Quit();
            }
        }
        finally
        {
            try { cd.Kill(); } catch { /* gone */ }
        }
    }

    private static string? Which(string cmd)
    {
        string? path = Environment.GetEnvironmentVariable("PATH");
        if (path == null) return null;
        foreach (string dir in path.Split(':'))
        {
            string full = Path.Combine(dir, cmd);
            if (File.Exists(full)) return full;
        }
        return null;
    }

    private static bool WaitUp(int port, int timeoutMs)
    {
        var deadline = DateTime.UtcNow.AddMilliseconds(timeoutMs);
        while (DateTime.UtcNow < deadline)
        {
            try
            {
                using var c = new TcpClient();
                c.Connect(System.Net.IPAddress.Loopback, port);
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
