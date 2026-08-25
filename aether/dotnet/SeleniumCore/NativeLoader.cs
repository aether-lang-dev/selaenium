using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Threading;

namespace SeleniumCore;

/// <summary>
/// Resolves the native Selenium core library across the layouts it can ship in:
/// an explicit <see cref="Configure"/> path, the <c>SELENIUM_CORE_LIB</c> env
/// override, a <c>native/</c> dir or a <c>runtimes/&lt;rid&gt;/native</c> layout
/// next to the assembly (a NuGet package), or the OS loader. Registered as the
/// DllImport resolver via a module initializer so it is in effect before the
/// first P/Invoke.
/// </summary>
internal static class NativeLoader
{
    private static int _registered;
    private static volatile string? _explicitPath;

    /// <summary>Pin an explicit path (wins over env/bundled/OS discovery).</summary>
    public static void Configure(string? path)
    {
        if (!string.IsNullOrEmpty(path))
        {
            _explicitPath = path;
        }
    }

    // The module initializer registers the DllImport resolver before the first
    // P/Invoke. CA2255 warns against ModuleInitializer in libraries in general,
    // but a native-library resolver is exactly the "advanced" case it exempts.
#pragma warning disable CA2255
    [ModuleInitializer]
    internal static void Register()
#pragma warning restore CA2255
    {
        if (Interlocked.Exchange(ref _registered, 1) == 1)
        {
            return;
        }
        NativeLibrary.SetDllImportResolver(typeof(NativeLoader).Assembly, Resolve);
    }

    private static IntPtr Resolve(string libraryName, Assembly assembly, DllImportSearchPath? searchPath)
    {
        if (libraryName != NativeMethods.Lib)
        {
            return IntPtr.Zero;
        }
        foreach (string candidate in CandidatePaths())
        {
            if (!string.IsNullOrEmpty(candidate) && File.Exists(candidate) &&
                NativeLibrary.TryLoad(candidate, out IntPtr handle))
            {
                return handle;
            }
        }
        return NativeLibrary.TryLoad(FileName, out IntPtr os) ? os : IntPtr.Zero;
    }

    private static IEnumerable<string> CandidatePaths()
    {
        if (!string.IsNullOrEmpty(_explicitPath))
        {
            yield return _explicitPath!;
        }
        string? overridePath = Environment.GetEnvironmentVariable("SELENIUM_CORE_LIB");
        if (!string.IsNullOrEmpty(overridePath))
        {
            yield return overridePath!;
        }
        string baseDir = AppContext.BaseDirectory;
        yield return Path.Combine(baseDir, FileName);
        yield return Path.Combine(baseDir, "native", FileName);
        yield return Path.Combine(baseDir, "runtimes", Rid, "native", FileName);
    }

    private static string FileName =>
        RuntimeInformation.IsOSPlatform(OSPlatform.Windows) ? $"{NativeMethods.Lib}.dll"
        : RuntimeInformation.IsOSPlatform(OSPlatform.OSX) ? $"lib{NativeMethods.Lib}.dylib"
        : $"lib{NativeMethods.Lib}.so";

    private static string Rid
    {
        get
        {
            string os =
                RuntimeInformation.IsOSPlatform(OSPlatform.Windows) ? "win"
                : RuntimeInformation.IsOSPlatform(OSPlatform.OSX) ? "osx"
                : "linux";
            string arch = RuntimeInformation.ProcessArchitecture switch
            {
                Architecture.Arm64 => "arm64",
                Architecture.X64 => "x64",
                _ => RuntimeInformation.ProcessArchitecture.ToString().ToLowerInvariant(),
            };
            return $"{os}-{arch}";
        }
    }
}
