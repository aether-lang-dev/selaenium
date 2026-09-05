using System;
using System.IO;

namespace OpenQA.Selenium;

/// <summary>
/// A page (or element) screenshot, as returned by
/// <see cref="ITakesScreenshot.GetScreenshot"/>. Mirrors Selenium 4.x's
/// <c>OpenQA.Selenium.Screenshot</c> (which derives from <c>EncodedFile</c>): it
/// carries a base64-encoded PNG and can hand it back as a string, as raw bytes, or
/// save it to a file.
/// </summary>
[Serializable]
public class Screenshot
{
    private readonly string _base64Encoded;
    private readonly byte[] _bytes;

    /// <summary>Construct from a base64-encoded PNG (the wire form the engine returns).</summary>
    public Screenshot(string base64EncodedScreenshot)
    {
        _base64Encoded = base64EncodedScreenshot ?? throw new ArgumentNullException(nameof(base64EncodedScreenshot));
        _bytes = Convert.FromBase64String(_base64Encoded);
    }

    /// <summary>The screenshot as a base64-encoded string.</summary>
    public string AsBase64EncodedString => _base64Encoded;

    /// <summary>The screenshot as raw PNG bytes.</summary>
    public byte[] AsByteArray => _bytes;

    /// <summary>Save the screenshot to <paramref name="fileName"/> as a PNG.</summary>
    public virtual void SaveAsFile(string fileName)
    {
        File.WriteAllBytes(fileName, _bytes);
    }

    /// <summary>The base64-encoded string form (matches upstream's <c>ToString</c>).</summary>
    public override string ToString() => _base64Encoded;
}
