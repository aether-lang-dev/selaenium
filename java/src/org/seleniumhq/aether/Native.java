package org.seleniumhq.aether;

import java.lang.foreign.Arena;
import java.lang.foreign.FunctionDescriptor;
import java.lang.foreign.Linker;
import java.lang.foreign.MemoryLayout;
import java.lang.foreign.MemorySegment;
import java.lang.foreign.SymbolLookup;
import java.lang.foreign.ValueLayout;
import java.lang.invoke.MethodHandle;
import java.nio.file.Files;
import java.nio.file.Path;

/**
 * Raw FFM (java.lang.foreign / Panama) downcall surface over the native Selenium
 * core library — 1:1 with the {@code aether_sel_embed_*} C ABI exported by the
 * in-repo {@code core/embed.ae} (built on the pure-Aether
 * {@code core/selenium_core.ae} engine). No JNI, no C shim.
 *
 * <p>Handle-based contract (matching the Aether side): N independent sessions
 * can run concurrently in one process, each keyed by its own {@code void*}
 * handle carried as a {@link MemorySegment} address. Returned {@code char*} are
 * caller-owned and NUL-terminated; {@link #takeString} copies then frees them
 * via {@code aether_sel_embed_free_string}.
 */
final class Native {

    private static final Linker LINKER = Linker.nativeLinker();
    private static final Arena GLOBAL = Arena.global();
    private static volatile String explicitPath;
    private static SymbolLookup lookup;

    private static final ValueLayout.OfInt C_INT = ValueLayout.JAVA_INT;
    private static final java.lang.foreign.AddressLayout C_PTR = ValueLayout.ADDRESS;
    // char* returns: reinterpret to a sized segment before reading up to NUL.
    private static final java.lang.foreign.AddressLayout C_STR =
            ValueLayout.ADDRESS.withTargetLayout(
                    MemoryLayout.sequenceLayout(Long.MAX_VALUE, ValueLayout.JAVA_BYTE));

    private Native() {
    }

    /** Pin an explicit path to the native library (wins over env/bundled). */
    static void configure(String path) {
        if (path != null && !path.isEmpty()) {
            explicitPath = path;
        }
    }

    private static synchronized SymbolLookup lookup() {
        if (lookup == null) {
            lookup = SymbolLookup.libraryLookup(locate(), GLOBAL);
        }
        return lookup;
    }

    private static Path locate() {
        if (explicitPath != null && !explicitPath.isEmpty()) {
            Path p = Path.of(explicitPath);
            if (Files.exists(p)) {
                return p;
            }
            throw new WebDriverError("nativeLib() points at a missing file: " + explicitPath, -1);
        }
        String override = System.getenv("SELENIUM_CORE_LIB");
        if (override != null && !override.isEmpty()) {
            Path p = Path.of(override);
            if (Files.exists(p)) {
                return p;
            }
            throw new WebDriverError("SELENIUM_CORE_LIB points at a missing file: " + override, -1);
        }
        String lib = fileName();
        // Bundled as a classpath resource inside the jar: /native/<libname>.
        // A packaged consumer gets exactly this — extract it to a temp file.
        try (java.io.InputStream in = Native.class.getResourceAsStream("/native/" + lib)) {
            if (in != null) {
                Path tmp = Files.createTempFile("libselenium_core", suffix(lib));
                tmp.toFile().deleteOnExit();
                Files.copy(in, tmp, java.nio.file.StandardCopyOption.REPLACE_EXISTING);
                return tmp;
            }
        } catch (java.io.IOException e) {
            throw new WebDriverError("failed to extract bundled native library: " + e.getMessage(), -1);
        }
        // Bundled next to the classes: java/native/<libname> (dev-tree layout).
        Path bundled = Path.of("native", lib);
        if (Files.exists(bundled)) {
            return bundled.toAbsolutePath();
        }
        // Let the OS loader try the bare name (LD_LIBRARY_PATH / system paths).
        return Path.of(lib);
    }

    private static String suffix(String lib) {
        int dot = lib.lastIndexOf('.');
        return dot >= 0 ? lib.substring(dot) : ".so";
    }

    private static String fileName() {
        String os = System.getProperty("os.name", "").toLowerCase();
        if (os.contains("win")) {
            return "selenium_core.dll";
        }
        if (os.contains("mac") || os.contains("darwin")) {
            return "libselenium_core.dylib";
        }
        return "libselenium_core.so";
    }

    private static MethodHandle down(String symbol, FunctionDescriptor descriptor) {
        MemorySegment addr = lookup().find(symbol)
                .orElseThrow(() -> new WebDriverError("native symbol not found: " + symbol, -1));
        return LINKER.downcallHandle(addr, descriptor);
    }

    // ---- method handles (bound lazily via the holder idiom) ----
    private static final class MH {
        static final MethodHandle OPEN = down("aether_sel_embed_open",
                FunctionDescriptor.of(C_PTR, C_PTR));
        static final MethodHandle CLOSE = down("aether_sel_embed_close",
                FunctionDescriptor.ofVoid(C_PTR));
        static final MethodHandle EXECUTE = down("aether_sel_embed_execute",
                FunctionDescriptor.of(C_INT, C_PTR, C_PTR, C_PTR));
        static final MethodHandle LAST_VALUE = down("aether_sel_embed_last_value",
                FunctionDescriptor.of(C_STR, C_PTR));
        static final MethodHandle LAST_STATUS = down("aether_sel_embed_last_status",
                FunctionDescriptor.of(C_INT, C_PTR));
        static final MethodHandle LAST_ERROR_CODE = down("aether_sel_embed_last_error_code",
                FunctionDescriptor.of(C_INT, C_PTR));
        static final MethodHandle LAST_ERROR = down("aether_sel_embed_last_error",
                FunctionDescriptor.of(C_STR, C_PTR));
        static final MethodHandle SESSION_ID = down("aether_sel_embed_session_id",
                FunctionDescriptor.of(C_STR, C_PTR));
        static final MethodHandle BY_LOCATOR = down("aether_sel_embed_by_locator",
                FunctionDescriptor.of(C_STR, C_PTR, C_PTR));
        static final MethodHandle ROUTE = down("aether_sel_embed_route",
                FunctionDescriptor.of(C_STR, C_PTR));
        static final MethodHandle BUILD_REQUEST = down("aether_sel_embed_build_request",
                FunctionDescriptor.of(C_STR, C_PTR, C_PTR, C_PTR));
        static final MethodHandle ERROR_CODE = down("aether_sel_embed_error_code",
                FunctionDescriptor.of(C_INT, C_PTR));
        static final MethodHandle FREE_STRING = down("aether_sel_embed_free_string",
                FunctionDescriptor.ofVoid(C_PTR));
    }

    // ---- typed wrappers ----

    static MemorySegment open(String baseUrl) {
        try (Arena a = Arena.ofConfined()) {
            return (MemorySegment) MH.OPEN.invokeExact(a.allocateFrom(baseUrl));
        } catch (Throwable t) {
            throw wrap(t, "open");
        }
    }

    static void close(MemorySegment handle) {
        try {
            MH.CLOSE.invokeExact(handle);
        } catch (Throwable t) {
            throw wrap(t, "close");
        }
    }

    static int execute(MemorySegment handle, String name, String paramsJson) {
        try (Arena a = Arena.ofConfined()) {
            return (int) MH.EXECUTE.invokeExact(handle, a.allocateFrom(name), a.allocateFrom(paramsJson));
        } catch (Throwable t) {
            throw wrap(t, "execute");
        }
    }

    static int lastStatus(MemorySegment handle) {
        try {
            return (int) MH.LAST_STATUS.invokeExact(handle);
        } catch (Throwable t) {
            throw wrap(t, "last_status");
        }
    }

    static int lastErrorCode(MemorySegment handle) {
        try {
            return (int) MH.LAST_ERROR_CODE.invokeExact(handle);
        } catch (Throwable t) {
            throw wrap(t, "last_error_code");
        }
    }

    static String lastValue(MemorySegment handle) {
        try {
            return takeString((MemorySegment) MH.LAST_VALUE.invokeExact(handle));
        } catch (Throwable t) {
            throw wrap(t, "last_value");
        }
    }

    static String lastError(MemorySegment handle) {
        try {
            return takeString((MemorySegment) MH.LAST_ERROR.invokeExact(handle));
        } catch (Throwable t) {
            throw wrap(t, "last_error");
        }
    }

    static String sessionId(MemorySegment handle) {
        try {
            return takeString((MemorySegment) MH.SESSION_ID.invokeExact(handle));
        } catch (Throwable t) {
            throw wrap(t, "session_id");
        }
    }

    static String byLocator(String strategy, String value) {
        try (Arena a = Arena.ofConfined()) {
            return takeString((MemorySegment) MH.BY_LOCATOR.invokeExact(
                    a.allocateFrom(strategy), a.allocateFrom(value)));
        } catch (Throwable t) {
            throw wrap(t, "by_locator");
        }
    }

    static String route(String name) {
        try (Arena a = Arena.ofConfined()) {
            return takeString((MemorySegment) MH.ROUTE.invokeExact(a.allocateFrom(name)));
        } catch (Throwable t) {
            throw wrap(t, "route");
        }
    }

    static String buildRequest(String name, String sessionId, String paramsJson) {
        try (Arena a = Arena.ofConfined()) {
            return takeString((MemorySegment) MH.BUILD_REQUEST.invokeExact(
                    a.allocateFrom(name), a.allocateFrom(sessionId), a.allocateFrom(paramsJson)));
        } catch (Throwable t) {
            throw wrap(t, "build_request");
        }
    }

    static int errorCode(String w3cError) {
        try (Arena a = Arena.ofConfined()) {
            return (int) MH.ERROR_CODE.invokeExact(a.allocateFrom(w3cError));
        } catch (Throwable t) {
            throw wrap(t, "error_code");
        }
    }

    static boolean isNull(MemorySegment ptr) {
        return ptr == null || ptr.address() == 0;
    }

    private static String takeString(MemorySegment ptr) {
        if (ptr == null || ptr.address() == 0) {
            return "";
        }
        try {
            return ptr.getString(0);
        } finally {
            try {
                MH.FREE_STRING.invokeExact(MemorySegment.ofAddress(ptr.address()));
            } catch (Throwable t) {
                throw new WebDriverError("free_string failed: " + t.getMessage(), -1);
            }
        }
    }

    private static WebDriverError wrap(Throwable t, String op) {
        if (t instanceof WebDriverError e) {
            return e;
        }
        return new WebDriverError("native call '" + op + "' failed: " + t.getMessage(), -1);
    }
}
