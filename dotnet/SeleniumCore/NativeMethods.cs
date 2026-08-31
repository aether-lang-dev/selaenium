using System;
using System.Runtime.InteropServices;

namespace SeleniumCore;

/// <summary>
/// Raw P/Invoke surface over the native Selenium core library — 1:1 with the
/// <c>aether_sel_embed_*</c> C ABI exported by the in-repo <c>core/embed.ae</c>
/// (built on the pure-Aether <c>core/selenium_core.ae</c> engine), compiled to
/// <c>libselenium_core.so</c>.
///
/// Handle-based: every call takes the <c>void*</c> handle returned by
/// <see cref="Open"/>, so N independent sessions can run concurrently in one
/// process. Returned <c>char*</c> values are caller-owned and NUL-terminated;
/// <see cref="TakeString"/> copies then frees them via <see cref="FreeString"/>.
/// </summary>
internal static class NativeMethods
{
    internal const string Lib = "selenium_core";

    // ---- lifecycle ----
    [DllImport(Lib, EntryPoint = "aether_sel_embed_open", CharSet = CharSet.Ansi)]
    internal static extern IntPtr Open(string baseUrl);

    [DllImport(Lib, EntryPoint = "aether_sel_embed_close")]
    internal static extern void Close(IntPtr handle);

    // ---- workhorse ----
    [DllImport(Lib, EntryPoint = "aether_sel_embed_execute", CharSet = CharSet.Ansi)]
    internal static extern int Execute(IntPtr handle, string name, string paramsJson);

    // ---- result accessors ----
    [DllImport(Lib, EntryPoint = "aether_sel_embed_last_value")]
    internal static extern IntPtr LastValue(IntPtr handle);

    [DllImport(Lib, EntryPoint = "aether_sel_embed_last_status")]
    internal static extern int LastStatus(IntPtr handle);

    [DllImport(Lib, EntryPoint = "aether_sel_embed_last_error_code")]
    internal static extern int LastErrorCode(IntPtr handle);

    [DllImport(Lib, EntryPoint = "aether_sel_embed_last_error")]
    internal static extern IntPtr LastError(IntPtr handle);

    [DllImport(Lib, EntryPoint = "aether_sel_embed_session_id")]
    internal static extern IntPtr SessionId(IntPtr handle);

    // ---- pure helpers ----
    [DllImport(Lib, EntryPoint = "aether_sel_embed_by_locator", CharSet = CharSet.Ansi)]
    internal static extern IntPtr ByLocator(string strategy, string value);

    [DllImport(Lib, EntryPoint = "aether_sel_embed_route", CharSet = CharSet.Ansi)]
    internal static extern IntPtr Route(string name);

    [DllImport(Lib, EntryPoint = "aether_sel_embed_build_request", CharSet = CharSet.Ansi)]
    internal static extern IntPtr BuildRequest(string name, string sessionId, string paramsJson);

    [DllImport(Lib, EntryPoint = "aether_sel_embed_error_code", CharSet = CharSet.Ansi)]
    internal static extern int ErrorCode(string w3cError);

    // ---- atom-backed commands (isDisplayed/getAttribute/relative locators) ----
    [DllImport(Lib, EntryPoint = "aether_sel_embed_execute_atom", CharSet = CharSet.Ansi)]
    internal static extern int ExecuteAtom(IntPtr handle, string atom, string elemId, string extraJson);

    [DllImport(Lib, EntryPoint = "aether_sel_embed_is_displayed", CharSet = CharSet.Ansi)]
    internal static extern int IsDisplayed(IntPtr handle, string elemId);

    [DllImport(Lib, EntryPoint = "aether_sel_embed_get_attribute", CharSet = CharSet.Ansi)]
    internal static extern int GetAttribute(IntPtr handle, string elemId, string name);

    [DllImport(Lib, EntryPoint = "aether_sel_embed_find_relative", CharSet = CharSet.Ansi)]
    internal static extern int FindRelative(IntPtr handle, string baseCss, string filtersJson);

    // ---- WebDriver-BiDi (over the session's webSocketUrl) ----
    // An opaque BiDi channel handle, independent of the W3C session handle.
    [DllImport(Lib, EntryPoint = "aether_sel_embed_bidi_open", CharSet = CharSet.Ansi)]
    internal static extern IntPtr BidiOpen(string wsUrl);

    [DllImport(Lib, EntryPoint = "aether_sel_embed_bidi_close")]
    internal static extern void BidiClose(IntPtr handle);

    [DllImport(Lib, EntryPoint = "aether_sel_embed_bidi_send", CharSet = CharSet.Ansi)]
    internal static extern int BidiSend(IntPtr handle, int id, string method, string paramsJson);

    [DllImport(Lib, EntryPoint = "aether_sel_embed_bidi_pump")]
    internal static extern int BidiPump(IntPtr handle, int timeoutMs);

    [DllImport(Lib, EntryPoint = "aether_sel_embed_bidi_fd")]
    internal static extern int BidiFd(IntPtr handle);

    [DllImport(Lib, EntryPoint = "aether_sel_embed_bidi_poll_reply")]
    internal static extern IntPtr BidiPollReply(IntPtr handle, int id);

    [DllImport(Lib, EntryPoint = "aether_sel_embed_bidi_poll_event")]
    internal static extern IntPtr BidiPollEvent(IntPtr handle);

    [DllImport(Lib, EntryPoint = "aether_sel_embed_bidi_lost_events")]
    internal static extern int BidiLostEvents(IntPtr handle);

    [DllImport(Lib, EntryPoint = "aether_sel_embed_bidi_cancel")]
    internal static extern void BidiCancel(IntPtr handle, int id);

    [DllImport(Lib, EntryPoint = "aether_sel_embed_bidi_subscribe", CharSet = CharSet.Ansi)]
    internal static extern IntPtr BidiSubscribe(IntPtr handle, int id, string eventsCsv, int timeoutMs);

    [DllImport(Lib, EntryPoint = "aether_sel_embed_bidi_unsubscribe", CharSet = CharSet.Ansi)]
    internal static extern IntPtr BidiUnsubscribe(IntPtr handle, int id, string eventsCsv, int timeoutMs);

    [DllImport(Lib, EntryPoint = "aether_sel_embed_bidi_wait_event", CharSet = CharSet.Ansi)]
    internal static extern IntPtr BidiWaitEvent(IntPtr handle, string method, int timeoutMs);

    [DllImport(Lib, EntryPoint = "aether_sel_embed_bidi_get_tree", CharSet = CharSet.Ansi)]
    internal static extern IntPtr BidiGetTree(IntPtr handle, int id, int timeoutMs);

    [DllImport(Lib, EntryPoint = "aether_sel_embed_bidi_script_evaluate", CharSet = CharSet.Ansi)]
    internal static extern IntPtr BidiScriptEvaluate(IntPtr handle, int id, string expression, string contextId, int timeoutMs);

    [DllImport(Lib, EntryPoint = "aether_sel_embed_bidi_navigate", CharSet = CharSet.Ansi)]
    internal static extern IntPtr BidiNavigate(IntPtr handle, int id, string contextId, string url, int timeoutMs);

    [DllImport(Lib, EntryPoint = "aether_sel_embed_bidi_network_add_intercept", CharSet = CharSet.Ansi)]
    internal static extern IntPtr BidiNetworkAddIntercept(IntPtr handle, int id, string phasesCsv, string urlPattern, int timeoutMs);

    [DllImport(Lib, EntryPoint = "aether_sel_embed_bidi_network_remove_intercept", CharSet = CharSet.Ansi)]
    internal static extern IntPtr BidiNetworkRemoveIntercept(IntPtr handle, int id, string interceptId, int timeoutMs);

    [DllImport(Lib, EntryPoint = "aether_sel_embed_bidi_network_continue_request", CharSet = CharSet.Ansi)]
    internal static extern IntPtr BidiNetworkContinueRequest(IntPtr handle, int id, string requestId, int timeoutMs);

    [DllImport(Lib, EntryPoint = "aether_sel_embed_bidi_network_fail_request", CharSet = CharSet.Ansi)]
    internal static extern IntPtr BidiNetworkFailRequest(IntPtr handle, int id, string requestId, int timeoutMs);

    // ---- string ownership ----
    [DllImport(Lib, EntryPoint = "aether_sel_embed_free_string")]
    internal static extern void FreeString(IntPtr s);

    /// <summary>
    /// Copy a caller-owned native char* into a managed string (UTF-8), then free
    /// the original pointer per the ABI ownership rule. Returns "" for NULL.
    /// </summary>
    internal static string TakeString(IntPtr ptr)
    {
        if (ptr == IntPtr.Zero)
        {
            return string.Empty;
        }
        try
        {
            return Marshal.PtrToStringUTF8(ptr) ?? string.Empty;
        }
        finally
        {
            FreeString(ptr);
        }
    }
}
