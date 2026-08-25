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
