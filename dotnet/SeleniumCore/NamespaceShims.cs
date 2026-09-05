using System.Collections.Generic;

// Mainstream Selenium-.NET places RemoteWebDriver under OpenQA.Selenium.Remote and
// ChromeDriver under OpenQA.Selenium.Chrome. This binding's primary types live in
// OpenQA.Selenium; these thin subclasses make the mainstream import paths resolve so
// an unmodified script's `using OpenQA.Selenium.Remote;` / `using OpenQA.Selenium.Chrome;`
// compiles and `new Remote.RemoteWebDriver(...)` / `new Chrome.ChromeDriver(...)` works.
// One source of truth — they only forward to the base constructors.

namespace OpenQA.Selenium.Remote
{
    /// <summary>
    /// <c>OpenQA.Selenium.Remote.RemoteWebDriver</c> at the mainstream import path.
    /// A thin subclass of <see cref="OpenQA.Selenium.RemoteWebDriver"/> forwarding to
    /// its constructors.
    /// </summary>
    public class RemoteWebDriver : OpenQA.Selenium.RemoteWebDriver
    {
        public RemoteWebDriver(string commandExecutor, IDictionary<string, object?> capabilities)
            : base(commandExecutor, capabilities)
        {
        }

        public RemoteWebDriver(string commandExecutor, DriverOptions options)
            : base(commandExecutor, options)
        {
        }
    }
}

namespace OpenQA.Selenium.Chrome
{
    /// <summary>
    /// <c>OpenQA.Selenium.Chrome.ChromeDriver</c> at the mainstream import path.
    /// A thin subclass of <see cref="OpenQA.Selenium.ChromeDriver"/> forwarding to
    /// its self-launching constructors.
    /// </summary>
    public class ChromeDriver : OpenQA.Selenium.ChromeDriver
    {
        public ChromeDriver() : base()
        {
        }

        public ChromeDriver(IDictionary<string, object?>? options) : base(options)
        {
        }

        public ChromeDriver(DriverOptions options) : base(options)
        {
        }
    }
}
