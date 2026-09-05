using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace OpenQA.Selenium.Support.UI;

/// <summary>
/// Convenience wrapper for an HTML <c>&lt;select&gt;</c> element. Mirrors Selenium 4.x's
/// <c>OpenQA.Selenium.Support.UI.SelectElement</c>: it drives options through the same
/// element commands (<see cref="IWebElement.Click"/>, <see cref="IWebElement.Selected"/>,
/// <see cref="IWebElement.FindElements(By)"/>) this binding already exposes, so it
/// carries no protocol of its own.
/// </summary>
public class SelectElement : IWrapsElement
{
    /// <summary>Wrap <paramref name="element"/>, verifying it is a
    /// <c>&lt;select&gt;</c> and recording whether it allows multiple selection.</summary>
    /// <exception cref="ArgumentNullException">If <paramref name="element"/> is null.</exception>
    /// <exception cref="UnexpectedTagNameException">If it is not a <c>&lt;select&gt;</c>.</exception>
    public SelectElement(IWebElement element)
    {
        if (element is null)
        {
            throw new ArgumentNullException(nameof(element), "element cannot be null");
        }

        string tagName = element.TagName;

        if (string.IsNullOrEmpty(tagName) || !string.Equals(tagName, "select", StringComparison.OrdinalIgnoreCase))
        {
            throw new UnexpectedTagNameException("select", tagName);
        }

        this.WrappedElement = element;

        // Determine whether this is a multi-select.
        string? attribute = element.GetAttribute("multiple");
        this.IsMultiple = attribute != null && !attribute.Equals("false", StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>The wrapped <c>&lt;select&gt;</c> element.</summary>
    public IWebElement WrappedElement { get; }

    /// <summary>Whether the select supports multiple selections.</summary>
    public bool IsMultiple { get; }

    /// <summary>All <c>&lt;option&gt;</c> elements of the select.</summary>
    public IList<IWebElement> Options => new List<IWebElement>(this.WrappedElement.FindElements(By.TagName("option")));

    /// <summary>The first selected option.</summary>
    /// <exception cref="NoSuchElementException">If no option is selected.</exception>
    public IWebElement SelectedOption
    {
        get
        {
            foreach (IWebElement option in this.Options)
            {
                if (option.Selected)
                {
                    return option;
                }
            }

            throw new NoSuchElementException("No option is selected", 17);
        }
    }

    /// <summary>Every selected option.</summary>
    public IList<IWebElement> AllSelectedOptions
    {
        get
        {
            List<IWebElement> returnValue = new List<IWebElement>();
            foreach (IWebElement option in this.Options)
            {
                if (option.Selected)
                {
                    returnValue.Add(option);
                }
            }

            return returnValue;
        }
    }

    /// <summary>Select the option(s) whose visible text matches
    /// <paramref name="text"/>.</summary>
    /// <exception cref="ArgumentNullException">If <paramref name="text"/> is null.</exception>
    /// <exception cref="NoSuchElementException">If no matching option exists.</exception>
    public void SelectByText(string text, bool partialMatch = false)
    {
        if (text is null)
        {
            throw new ArgumentNullException(nameof(text), "text must not be null");
        }

        bool matched = false;
        IReadOnlyList<IWebElement> options;

        if (!partialMatch)
        {
            options = this.WrappedElement.FindElements(By.XPath(".//option[normalize-space(.) = " + EscapeQuotes(text) + "]"));
        }
        else
        {
            options = this.WrappedElement.FindElements(By.XPath(".//option[contains(normalize-space(.),  " + EscapeQuotes(text) + ")]"));
        }

        foreach (IWebElement option in options)
        {
            SetSelected(option, true);
            if (!this.IsMultiple)
            {
                return;
            }

            matched = true;
        }

        if (options.Count == 0 && text.Contains(" "))
        {
            string substringWithoutSpace = GetLongestSubstringWithoutSpace(text);
            IList<IWebElement> candidates;
            if (string.IsNullOrEmpty(substringWithoutSpace))
            {
                candidates = new List<IWebElement>(this.WrappedElement.FindElements(By.TagName("option")));
            }
            else
            {
                candidates = new List<IWebElement>(this.WrappedElement.FindElements(By.XPath(".//option[contains(., " + EscapeQuotes(substringWithoutSpace) + ")]")));
            }

            foreach (IWebElement option in candidates)
            {
                if (text == option.Text)
                {
                    SetSelected(option, true);
                    if (!this.IsMultiple)
                    {
                        return;
                    }

                    matched = true;
                }
            }
        }

        if (!matched)
        {
            throw new NoSuchElementException("Cannot locate element with text: " + text, 17);
        }
    }

    /// <summary>Select the option(s) whose <c>value</c> attribute matches
    /// <paramref name="value"/>.</summary>
    /// <exception cref="NoSuchElementException">If no matching option exists.</exception>
    public void SelectByValue(string value)
    {
        StringBuilder builder = new StringBuilder(".//option[@value = ");
        builder.Append(EscapeQuotes(value));
        builder.Append("]");
        IReadOnlyList<IWebElement> options = this.WrappedElement.FindElements(By.XPath(builder.ToString()));

        bool matched = false;
        foreach (IWebElement option in options)
        {
            SetSelected(option, true);
            if (!this.IsMultiple)
            {
                return;
            }

            matched = true;
        }

        if (!matched)
        {
            throw new NoSuchElementException("Cannot locate option with value: " + value, 17);
        }
    }

    /// <summary>Select the option at the given zero-based index.</summary>
    /// <exception cref="NoSuchElementException">If no option has that index.</exception>
    public void SelectByIndex(int index)
    {
        string match = index.ToString(CultureInfo.InvariantCulture);

        foreach (IWebElement option in this.Options)
        {
            if (option.GetAttribute("index") == match)
            {
                SetSelected(option, true);
                return;
            }
        }

        throw new NoSuchElementException("Cannot locate option with index: " + index, 17);
    }

    /// <summary>Deselect all options (multi-select only).</summary>
    /// <exception cref="InvalidOperationException">On a single-select.</exception>
    public void DeselectAll()
    {
        if (!this.IsMultiple)
        {
            throw new InvalidOperationException("You may only deselect all options if multi-select is supported");
        }

        foreach (IWebElement option in this.Options)
        {
            SetSelected(option, false);
        }
    }

    /// <summary>Deselect the option(s) whose visible text matches
    /// <paramref name="text"/> (multi-select only).</summary>
    public void DeselectByText(string text)
    {
        if (!this.IsMultiple)
        {
            throw new InvalidOperationException("You may only deselect option if multi-select is supported");
        }

        bool matched = false;
        StringBuilder builder = new StringBuilder(".//option[normalize-space(.) = ");
        builder.Append(EscapeQuotes(text));
        builder.Append("]");
        IReadOnlyList<IWebElement> options = this.WrappedElement.FindElements(By.XPath(builder.ToString()));
        foreach (IWebElement option in options)
        {
            SetSelected(option, false);
            matched = true;
        }

        if (!matched)
        {
            throw new NoSuchElementException("Cannot locate option with text: " + text, 17);
        }
    }

    /// <summary>Deselect the option(s) whose <c>value</c> matches
    /// <paramref name="value"/> (multi-select only).</summary>
    public void DeselectByValue(string value)
    {
        if (!this.IsMultiple)
        {
            throw new InvalidOperationException("You may only deselect option if multi-select is supported");
        }

        bool matched = false;
        StringBuilder builder = new StringBuilder(".//option[@value = ");
        builder.Append(EscapeQuotes(value));
        builder.Append("]");
        IReadOnlyList<IWebElement> options = this.WrappedElement.FindElements(By.XPath(builder.ToString()));
        foreach (IWebElement option in options)
        {
            SetSelected(option, false);
            matched = true;
        }

        if (!matched)
        {
            throw new NoSuchElementException("Cannot locate option with value: " + value, 17);
        }
    }

    /// <summary>Deselect the option at the given index (multi-select only).</summary>
    public void DeselectByIndex(int index)
    {
        if (!this.IsMultiple)
        {
            throw new InvalidOperationException("You may only deselect option if multi-select is supported");
        }

        string match = index.ToString(CultureInfo.InvariantCulture);
        foreach (IWebElement option in this.Options)
        {
            if (match == option.GetAttribute("index"))
            {
                SetSelected(option, false);
                return;
            }
        }

        throw new NoSuchElementException("Cannot locate option with index: " + index, 17);
    }

    private static string EscapeQuotes(string toEscape)
    {
        // foo'"bar -> concat("foo'", '"', "bar")
        if (toEscape.IndexOf("\"", StringComparison.OrdinalIgnoreCase) > -1 && toEscape.IndexOf("'", StringComparison.OrdinalIgnoreCase) > -1)
        {
            bool quoteIsLast = false;
            if (toEscape.LastIndexOf("\"", StringComparison.OrdinalIgnoreCase) == toEscape.Length - 1)
            {
                quoteIsLast = true;
            }

            List<string> substrings = new List<string>(toEscape.Split('\"'));
            if (quoteIsLast && string.IsNullOrEmpty(substrings[substrings.Count - 1]))
            {
                substrings.RemoveAt(substrings.Count - 1);
            }

            StringBuilder quoted = new StringBuilder("concat(");
            for (int i = 0; i < substrings.Count; i++)
            {
                quoted.Append("\"").Append(substrings[i]).Append("\"");
                if (i == substrings.Count - 1)
                {
                    if (quoteIsLast)
                    {
                        quoted.Append(", '\"')");
                    }
                    else
                    {
                        quoted.Append(")");
                    }
                }
                else
                {
                    quoted.Append(", '\"', ");
                }
            }

            return quoted.ToString();
        }

        // f"oo -> 'f"oo'
        if (toEscape.IndexOf("\"", StringComparison.OrdinalIgnoreCase) > -1)
        {
            return string.Format(CultureInfo.InvariantCulture, "'{0}'", toEscape);
        }

        return string.Format(CultureInfo.InvariantCulture, "\"{0}\"", toEscape);
    }

    private static string GetLongestSubstringWithoutSpace(string s)
    {
        string result = string.Empty;
        foreach (string substring in s.Split(' '))
        {
            if (substring.Length > result.Length)
            {
                result = substring;
            }
        }

        return result;
    }

    private static void SetSelected(IWebElement option, bool select)
    {
        if (select && !option.Enabled)
        {
            throw new InvalidOperationException("You may not select a disabled option");
        }

        bool isSelected = option.Selected;
        if ((!isSelected && select) || (isSelected && !select))
        {
            option.Click();
        }
    }
}
