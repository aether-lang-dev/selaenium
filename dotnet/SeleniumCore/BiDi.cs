using System;
using System.Collections.Generic;
using System.Text.Json;

namespace SeleniumCore;

/// <summary>
/// The common WebDriver-BiDi event names (W3C spec). Pass to
/// <see cref="BiDi.Subscribe"/> and match in <see cref="BiDi.NextEvent"/>.
/// </summary>
public static class BidiEvent
{
    public const string LogEntryAdded = "log.entryAdded";
    public const string ContextCreated = "browsingContext.contextCreated";
    public const string ContextDestroyed = "browsingContext.contextDestroyed";
    public const string NavigationStarted = "browsingContext.navigationStarted";
    public const string DomContentLoaded = "browsingContext.domContentLoaded";
    public const string Load = "browsingContext.load";
    public const string DownloadWillBegin = "browsingContext.downloadWillBegin";
    public const string BeforeRequestSent = "network.beforeRequestSent";
    public const string ResponseStarted = "network.responseStarted";
    public const string ResponseCompleted = "network.responseCompleted";
    public const string FetchError = "network.fetchError";
    public const string RealmCreated = "script.realmCreated";
    public const string RealmDestroyed = "script.realmDestroyed";
    public const string Message = "script.message";
}

/// <summary>
/// The event-driven BiDi channel for a session (over the demux C ABI).
///
/// Commands and events multiplex over one WebSocket via the engine's shape-C
/// demux (a single reader routes replies to an id table and events to a bounded
/// queue), so replies stay correlated while events stream. Command ids are
/// supplied automatically from a monotonic per-channel counter.
/// </summary>
public sealed class BiDi
{
    private IntPtr _handle;
    private int _nextId = 1;

    internal BiDi(IntPtr handle)
    {
        _handle = handle;
    }

    private int NextId() => _nextId++;

    /// <summary>
    /// session.subscribe to one or more event names; wait for the ack. Returns
    /// the ack payload. After this, matching events arrive on the queue (drain
    /// via <see cref="NextEvent"/>).
    /// </summary>
    public Dictionary<string, object?> Subscribe(params string[] events) => Subscribe(events, 10000);

    public Dictionary<string, object?> Subscribe(string[] events, int timeoutMs)
    {
        string csv = string.Join(",", events);
        string raw = NativeMethods.TakeString(NativeMethods.BidiSubscribe(_handle, NextId(), csv, timeoutMs));
        return ParseObject(raw);
    }

    public Dictionary<string, object?> Unsubscribe(params string[] events) => Unsubscribe(events, 10000);

    public Dictionary<string, object?> Unsubscribe(string[] events, int timeoutMs)
    {
        string csv = string.Join(",", events);
        string raw = NativeMethods.TakeString(NativeMethods.BidiUnsubscribe(_handle, NextId(), csv, timeoutMs));
        return ParseObject(raw);
    }

    /// <summary>
    /// Block until an event whose <paramref name="method"/> matches arrives, or
    /// timeout. Returns the event dictionary, or <c>null</c> on timeout/close.
    /// (Subscribe first.)
    /// </summary>
    public Dictionary<string, object?>? NextEvent(string method, int timeoutMs = 5000)
    {
        string raw = NativeMethods.TakeString(NativeMethods.BidiWaitEvent(_handle, method, timeoutMs));
        return raw.Length == 0 ? null : ParseObject(raw);
    }

    /// <summary>
    /// Issue any BiDi command and return its reply payload. Lets a caller reach
    /// BiDi methods with no dedicated wrapper (script.evaluate,
    /// browsingContext.captureScreenshot, network.*, …).
    /// </summary>
    public Dictionary<string, object?> Command(string method, object? @params = null, int timeoutMs = 10000)
    {
        string paramsJson = JsonSerializer.Serialize(@params ?? new Dictionary<string, object?>());
        // send + pump until this id's reply arrives (the engine's convenience).
        int cid = NextId();
        if (NativeMethods.BidiSend(_handle, cid, method, paramsJson) != 0)
        {
            throw new WebDriverError($"BiDi send failed: {method}", -1);
        }
        int waited = 0, step = 50;
        while (waited < timeoutMs)
        {
            string reply = NativeMethods.TakeString(NativeMethods.BidiPollReply(_handle, cid));
            if (reply.Length != 0)
            {
                return ParseObject(reply);
            }
            if (NativeMethods.BidiPump(_handle, step) < 0)
            {
                break;
            }
            waited += step;
        }
        throw new TimeoutError($"BiDi command timed out: {method}", 0);
    }

    /// <summary>
    /// How many events the bounded queue has dropped since the last call (then
    /// resets) — so a consumer knows it missed events.
    /// </summary>
    public int LostEvents() => NativeMethods.BidiLostEvents(_handle);

    public void Close()
    {
        if (_handle != IntPtr.Zero)
        {
            NativeMethods.BidiClose(_handle);
            _handle = IntPtr.Zero;
        }
    }

    private static Dictionary<string, object?> ParseObject(string raw)
    {
        if (raw.Length == 0)
        {
            return new Dictionary<string, object?>();
        }
        using var doc = JsonDocument.Parse(raw);
        return (Dictionary<string, object?>)Convert(doc.RootElement)!;
    }

    // Recursively materialize a JsonElement into plain CLR objects so the BiDi
    // surface hands back dictionaries/lists rather than JsonElement handles.
    private static object? Convert(JsonElement e) => e.ValueKind switch
    {
        JsonValueKind.Object => ConvertObject(e),
        JsonValueKind.Array => ConvertArray(e),
        JsonValueKind.String => e.GetString(),
        JsonValueKind.Number => e.TryGetInt64(out long l) ? l : e.GetDouble(),
        JsonValueKind.True => true,
        JsonValueKind.False => false,
        _ => null,
    };

    private static Dictionary<string, object?> ConvertObject(JsonElement e)
    {
        var map = new Dictionary<string, object?>();
        foreach (JsonProperty p in e.EnumerateObject())
        {
            map[p.Name] = Convert(p.Value);
        }
        return map;
    }

    private static List<object?> ConvertArray(JsonElement e)
    {
        var list = new List<object?>();
        foreach (JsonElement item in e.EnumerateArray())
        {
            list.Add(Convert(item));
        }
        return list;
    }
}
