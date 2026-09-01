using System.Text.Json.Serialization;

namespace SeleniumCore;

/// <summary>A browser cookie as returned by GetCookies/GetCookie. Fields absent
/// from the wire payload keep their default (Expiry null = session cookie).</summary>
public sealed record Cookie
{
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
