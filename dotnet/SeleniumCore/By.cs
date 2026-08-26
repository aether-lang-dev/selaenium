namespace SeleniumCore;

/// <summary>
/// Locator strategies. Values match the engine's by_locator strategy strings;
/// Id/Name/ClassName are rewritten to CSS in the engine.
/// </summary>
public static class By
{
    public const string Id = "id";
    public const string Name = "name";
    public const string CssSelector = "css selector";
    public const string ClassName = "className";
    public const string TagName = "tag name";
    public const string LinkText = "link text";
    public const string PartialLinkText = "partial link text";
    public const string XPath = "xpath";
}
