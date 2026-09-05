using System.Globalization;

namespace OpenQA.Selenium.Support.UI;

/// <summary>
/// Raised when a convenience wrapper is handed an element of the wrong tag (e.g.
/// <see cref="SelectElement"/> on a non-<c>&lt;select&gt;</c>). Mirrors Selenium 4.x's
/// <c>OpenQA.Selenium.Support.UI.UnexpectedTagNameException</c>.
/// </summary>
public class UnexpectedTagNameException : WebDriverException
{
    public UnexpectedTagNameException(string expected, string actual)
        : base(string.Format(CultureInfo.InvariantCulture, "Element should have been {0} but was {1}", expected, actual), 0)
    {
    }

    public UnexpectedTagNameException(string message)
        : base(message, 0)
    {
    }
}
