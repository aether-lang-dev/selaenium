using System.Text.Json.Serialization;

namespace OpenQA.Selenium;

/// <summary>A browser cookie as returned by GetCookies/GetCookie and accepted by
/// <see cref="ICookieJar.AddCookie"/>. Fields absent from the wire payload keep their
/// default (Expiry null = session cookie). Mainstream-shaped constructors
/// (<c>new Cookie("name", "value")</c>) coexist with the JSON init-only properties.</summary>
public sealed record Cookie
{
    /// <summary>An empty cookie (used by deserialization and as a "not found" sentinel).</summary>
    public Cookie() { }

    /// <summary>A name/value cookie (mainstream <c>new Cookie(name, value)</c>).</summary>
    public Cookie(string name, string value)
    {
        Name = name;
        Value = value;
    }

    /// <summary>A cookie with domain/path/expiry (mainstream overload).</summary>
    public Cookie(string name, string value, string? domain, string? path, System.DateTime? expiry)
    {
        Name = name;
        Value = value;
        Domain = domain;
        Path = path;
        // W3C expiry is a UNIX epoch second count.
        Expiry = expiry.HasValue ? new System.DateTimeOffset(expiry.Value.ToUniversalTime()).ToUnixTimeSeconds() : null;
    }

    [JsonPropertyName("name")] public string Name { get; init; } = "";
    [JsonPropertyName("value")] public string Value { get; init; } = "";
    [JsonPropertyName("domain")] public string? Domain { get; init; }
    [JsonPropertyName("path")] public string? Path { get; init; }
    [JsonPropertyName("expiry")] public long? Expiry { get; init; }
    [JsonPropertyName("secure")] public bool Secure { get; init; }
    [JsonPropertyName("httpOnly")] public bool HttpOnly { get; init; }
    [JsonPropertyName("sameSite")] public string? SameSite { get; init; }
}

/// <summary>A window or element bounding rectangle ({x,y,width,height}).</summary>
public sealed record Rect
{
    [JsonPropertyName("x")] public double X { get; init; }
    [JsonPropertyName("y")] public double Y { get; init; }
    [JsonPropertyName("width")] public double Width { get; init; }
    [JsonPropertyName("height")] public double Height { get; init; }
}
