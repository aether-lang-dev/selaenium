using System;
using System.Collections.Generic;
using System.Globalization;

namespace OpenQA.Selenium;

/// <summary>Page orientation for <see cref="PrintOptions"/>.</summary>
public enum PrintOrientation
{
    Portrait,
    Landscape,
}

/// <summary>
/// Options for <see cref="RemoteWebDriver.Print(PrintOptions)"/> — the W3C
/// print-page command. Mirrors mainstream <c>OpenQA.Selenium.PrintOptions</c>:
/// only non-default values are serialized (see <see cref="ToDictionary"/>).
/// </summary>
public class PrintOptions
{
    private const double DefaultPageHeight = 27.94;
    private const double DefaultPageWidth = 21.59;
    private const double DefaultMarginSize = 1.0;

    private double scale = 1.0;
    private PageSize pageSize = new() { Height = DefaultPageHeight, Width = DefaultPageWidth };
    private Margins margins = new();
    private readonly List<string> pageRanges = new();

    public PrintOrientation Orientation { get; set; } = PrintOrientation.Portrait;

    public double ScaleFactor
    {
        get => scale;
        set
        {
            if (value < 0.1 || value > 2.0)
            {
                throw new ArgumentOutOfRangeException(nameof(value), "Scale factor must be between 0.1 and 2.0.");
            }

            scale = value;
        }
    }

    public bool OutputBackgroundImages { get; set; }

    public bool ShrinkToFit { get; set; } = true;

    public PageSize PageDimensions
    {
        get => pageSize;
        set => pageSize = value ?? throw new ArgumentNullException(nameof(value));
    }

    public Margins PageMargins
    {
        get => margins;
        set => margins = value ?? throw new ArgumentNullException(nameof(value));
    }

    /// <summary>Add a single page number to the set of pages to print.</summary>
    public void AddPageToPrint(int pageNumber)
    {
        if (pageNumber < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(pageNumber), "Page number must be non-negative.");
        }

        string asString = pageNumber.ToString(CultureInfo.InvariantCulture);
        if (!pageRanges.Contains(asString))
        {
            pageRanges.Add(asString);
        }
    }

    /// <summary>Add a page range (e.g. "1-3" or "2") to the set of pages to print.</summary>
    public void AddPageRangeToPrint(string pageRange)
    {
        if (string.IsNullOrEmpty(pageRange))
        {
            throw new ArgumentException("Page range cannot be null or empty.", nameof(pageRange));
        }

        pageRanges.Add(pageRange.Trim());
    }

    internal Dictionary<string, object?> ToDictionary()
    {
        Dictionary<string, object?> toReturn = new();

        if (Orientation != PrintOrientation.Portrait)
        {
            toReturn["orientation"] = Orientation.ToString().ToLowerInvariant();
        }

        if (scale != 1.0)
        {
            toReturn["scale"] = scale;
        }

        if (OutputBackgroundImages)
        {
            toReturn["background"] = OutputBackgroundImages;
        }

        if (!ShrinkToFit)
        {
            toReturn["shrinkToFit"] = ShrinkToFit;
        }

        if (pageSize.Height != DefaultPageHeight || pageSize.Width != DefaultPageWidth)
        {
            toReturn["page"] = new Dictionary<string, object?>
            {
                ["width"] = pageSize.Width,
                ["height"] = pageSize.Height,
            };
        }

        if (margins.Top != DefaultMarginSize || margins.Bottom != DefaultMarginSize
            || margins.Left != DefaultMarginSize || margins.Right != DefaultMarginSize)
        {
            toReturn["margin"] = new Dictionary<string, object?>
            {
                ["top"] = margins.Top,
                ["bottom"] = margins.Bottom,
                ["left"] = margins.Left,
                ["right"] = margins.Right,
            };
        }

        if (pageRanges.Count > 0)
        {
            toReturn["pageRanges"] = new List<object?>(pageRanges);
        }

        return toReturn;
    }

    /// <summary>Paper size in centimetres. Mirrors mainstream nested PageSize.</summary>
    public class PageSize
    {
        public static PageSize A4 => new() { Width = 21.0, Height = 29.7 };
        public static PageSize Legal => new() { Width = 21.59, Height = 35.56 };
        public static PageSize Letter => new() { Width = 21.59, Height = 27.94 };
        public static PageSize Tabloid => new() { Width = 27.94, Height = 43.18 };

        public double Height { get; set; } = DefaultPageHeight;

        public double Width { get; set; } = DefaultPageWidth;
    }

    /// <summary>Page margins in centimetres. Mirrors mainstream nested Margins.</summary>
    public class Margins
    {
        public double Top { get; set; } = DefaultMarginSize;

        public double Bottom { get; set; } = DefaultMarginSize;

        public double Left { get; set; } = DefaultMarginSize;

        public double Right { get; set; } = DefaultMarginSize;
    }
}
