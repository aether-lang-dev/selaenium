using System;
using System.IO;

namespace OpenQA.Selenium;

/// <summary>
/// A base64-encoded binary artifact returned by the driver (screenshot / printed
/// document). Mirrors mainstream <c>OpenQA.Selenium.EncodedFile</c>.
/// </summary>
public abstract class EncodedFile
{
    protected EncodedFile(string base64EncodedFile)
    {
        AsBase64EncodedString = base64EncodedFile ?? throw new ArgumentNullException(nameof(base64EncodedFile));
        AsByteArray = Convert.FromBase64String(base64EncodedFile);
    }

    /// <summary>The artifact as a base64-encoded string.</summary>
    public string AsBase64EncodedString { get; }

    /// <summary>The decoded bytes of the artifact.</summary>
    public byte[] AsByteArray { get; }

    /// <summary>Save the artifact to a file.</summary>
    public abstract void SaveAsFile(string fileName);

    public override string ToString() => AsBase64EncodedString;
}

/// <summary>
/// A rendered PDF returned by <see cref="RemoteWebDriver.Print(PrintOptions)"/>.
/// Mirrors mainstream <c>OpenQA.Selenium.PrintDocument</c>.
/// </summary>
public class PrintDocument : EncodedFile
{
    public PrintDocument(string base64EncodedDocument) : base(base64EncodedDocument)
    {
    }

    /// <summary>Save the printed document to a PDF file.</summary>
    public override void SaveAsFile(string fileName)
    {
        File.WriteAllBytes(fileName, AsByteArray);
    }
}
