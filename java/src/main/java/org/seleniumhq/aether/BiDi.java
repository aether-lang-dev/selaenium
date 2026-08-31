package org.seleniumhq.aether;

import java.lang.foreign.MemorySegment;
import java.util.Map;

/**
 * The event-driven BiDi channel for a session (over the demux C ABI).
 *
 * <p>Commands and events multiplex over one WebSocket via the engine's shape-C
 * demux (a single reader routes replies to an id table and events to a bounded
 * queue), so replies stay correlated while events stream. Command ids are
 * supplied automatically from a monotonic per-channel counter (starting at 1).
 *
 * <p>Opened lazily by {@link WebDriver#bidi()} over the session's negotiated
 * {@code webSocketUrl} — a classic script never opens the WebSocket.
 */
public final class BiDi {

    private MemorySegment handle;
    private int nextId = 1;

    BiDi(MemorySegment handle) {
        this.handle = handle;
    }

    private int id() {
        return nextId++;
    }

    /**
     * {@code session.subscribe} to one or more event names; wait for the ack.
     * Returns the ack payload. After this, matching events arrive on the queue
     * (drain via {@link #nextEvent(String, int)}).
     */
    public Map<String, Object> subscribe(String... events) {
        return subscribe(10000, events);
    }

    @SuppressWarnings("unchecked")
    public Map<String, Object> subscribe(int timeoutMs, String... events) {
        String raw = Native.bidiSubscribe(handle, id(), String.join(",", events), timeoutMs);
        return raw.isEmpty() ? Map.of() : (Map<String, Object>) Json.decode(raw);
    }

    public Map<String, Object> unsubscribe(String... events) {
        return unsubscribe(10000, events);
    }

    @SuppressWarnings("unchecked")
    public Map<String, Object> unsubscribe(int timeoutMs, String... events) {
        String raw = Native.bidiUnsubscribe(handle, id(), String.join(",", events), timeoutMs);
        return raw.isEmpty() ? Map.of() : (Map<String, Object>) Json.decode(raw);
    }

    /**
     * Block until an event whose {@code method} matches arrives, or timeout.
     * Returns the event map, or {@code null} on timeout/close. (Subscribe first.)
     */
    @SuppressWarnings("unchecked")
    public Map<String, Object> nextEvent(String method, int timeoutMs) {
        String raw = Native.bidiWaitEvent(handle, method, timeoutMs);
        return raw.isEmpty() ? null : (Map<String, Object>) Json.decode(raw);
    }

    /**
     * Issue any BiDi command and return its reply payload. Lets a caller reach
     * BiDi methods with no dedicated wrapper (script.evaluate,
     * browsingContext.captureScreenshot, network.*, …).
     */
    @SuppressWarnings("unchecked")
    public Map<String, Object> command(String method, Map<String, Object> params, int timeoutMs) {
        int cid = id();
        if (Native.bidiSend(handle, cid, method, Json.encode(params == null ? Map.of() : params)) != 0) {
            throw new WebDriverError("BiDi send failed: " + method, -1);
        }
        int waited = 0;
        int step = 50;
        while (waited < timeoutMs) {
            String reply = Native.bidiPollReply(handle, cid);
            if (!reply.isEmpty()) {
                return (Map<String, Object>) Json.decode(reply);
            }
            if (Native.bidiPump(handle, step) < 0) {
                break;
            }
            waited += step;
        }
        throw new WebDriverError.Timeout("BiDi command timed out: " + method, 0);
    }

    // ---- typed convenience commands ----

    /** {@code browsingContext.getTree} — the browsing contexts (each with a "context" id). */
    @SuppressWarnings("unchecked")
    public Map<String, Object> getTree(int timeoutMs) {
        String raw = Native.bidiGetTree(handle, id(), timeoutMs);
        return raw.isEmpty() ? Map.of() : (Map<String, Object>) Json.decode(raw);
    }

    /** The top-level browsing context id (the anchor for evaluate/navigate), or null. */
    @SuppressWarnings("unchecked")
    public String topContext(int timeoutMs) {
        Object result = getTree(timeoutMs).get("result");
        if (!(result instanceof Map<?, ?> r)) {
            return null;
        }
        Object contexts = r.get("contexts");
        if (!(contexts instanceof java.util.List<?> list) || list.isEmpty()) {
            return null;
        }
        Object first = list.get(0);
        if (first instanceof Map<?, ?> m) {
            Object ctx = m.get("context");
            return ctx == null ? null : ctx.toString();
        }
        return null;
    }

    /**
     * {@code script.evaluate} an expression in the top context's realm, awaiting a
     * returned promise. Returns the reply; {@code ["result"]["result"]} is the
     * BiDi-typed value (e.g. {@code {"type":"number","value":42}}). BiDi's richer
     * alternative to executeScript — real realms, promise-awaiting, structured types.
     */
    @SuppressWarnings("unchecked")
    public Map<String, Object> evaluate(String expr, int timeoutMs) {
        String ctx = topContext(timeoutMs);
        if (ctx == null) {
            throw new WebDriverError("no browsing context for script.evaluate", 0);
        }
        String raw = Native.bidiScriptEvaluate(handle, id(), expr, ctx, timeoutMs);
        return raw.isEmpty() ? Map.of() : (Map<String, Object>) Json.decode(raw);
    }

    /**
     * {@code script.evaluate}, returning just the unwrapped value (the {@code .value}
     * of the BiDi-typed result), or null if it wasn't a simple value.
     */
    public Object evaluateValue(String expr, int timeoutMs) {
        Object result = evaluate(expr, timeoutMs).get("result");
        if (!(result instanceof Map<?, ?> outer)) {
            return null;
        }
        Object inner = outer.get("result");
        if (!(inner instanceof Map<?, ?> m)) {
            return null;
        }
        return m.get("value");
    }

    /** {@code browsingContext.navigate} the top context to url (wait: complete). */
    @SuppressWarnings("unchecked")
    public Map<String, Object> navigate(String url, int timeoutMs) {
        String ctx = topContext(timeoutMs);
        if (ctx == null) {
            throw new WebDriverError("no browsing context for navigate", 0);
        }
        String raw = Native.bidiNavigate(handle, id(), ctx, url, timeoutMs);
        return raw.isEmpty() ? Map.of() : (Map<String, Object>) Json.decode(raw);
    }

    // ---- network interception (observe / release / block requests) ----

    /**
     * {@code network.addIntercept} for a URL pattern (a full parseable URL as a
     * "string" pattern; empty intercepts all) at the given comma-separated
     * phases (e.g. {@code "beforeRequestSent"}). Subscribe to the matching
     * {@code network.*} event first if you want the paused-request events.
     * Returns the intercept id, or {@code null}.
     */
    @SuppressWarnings("unchecked")
    public String addIntercept(String phasesCsv, String urlPattern, int timeoutMs) {
        String raw = Native.bidiNetworkAddIntercept(handle, id(), phasesCsv, urlPattern, timeoutMs);
        if (raw.isEmpty()) {
            return null;
        }
        Object reply = Json.decode(raw);
        if (!(reply instanceof Map<?, ?> m) || !(m.get("result") instanceof Map<?, ?> r)) {
            return null;
        }
        Object intercept = r.get("intercept");
        return intercept == null ? null : intercept.toString();
    }

    @SuppressWarnings("unchecked")
    public Map<String, Object> removeIntercept(String interceptId, int timeoutMs) {
        String raw = Native.bidiNetworkRemoveIntercept(handle, id(), interceptId, timeoutMs);
        return raw.isEmpty() ? Map.of() : (Map<String, Object>) Json.decode(raw);
    }

    /**
     * Let a paused (intercepted) request proceed unchanged. The {@code requestId}
     * comes from a network event's {@code params.request.request} (see
     * {@link #eventRequestId(Map)}).
     */
    @SuppressWarnings("unchecked")
    public Map<String, Object> continueRequest(String requestId, int timeoutMs) {
        String raw = Native.bidiNetworkContinueRequest(handle, id(), requestId, timeoutMs);
        return raw.isEmpty() ? Map.of() : (Map<String, Object>) Json.decode(raw);
    }

    /** Block a paused request (the ad/tracker-blocking case). */
    @SuppressWarnings("unchecked")
    public Map<String, Object> failRequest(String requestId, int timeoutMs) {
        String raw = Native.bidiNetworkFailRequest(handle, id(), requestId, timeoutMs);
        return raw.isEmpty() ? Map.of() : (Map<String, Object>) Json.decode(raw);
    }

    /**
     * Fulfill a paused request with a MOCK response ({@code network.provideResponse}),
     * never hitting the network — mock an API, serve stub content, or test an error
     * status. The mock auto-allows any origin to read the body. The {@code requestId}
     * comes from a network event's {@code params.request.request} (see
     * {@link #eventRequestId(Map)}).
     */
    @SuppressWarnings("unchecked")
    public Map<String, Object> provideResponse(String requestId, int status, String contentType,
            String body, int timeoutMs) {
        String raw = Native.bidiNetworkProvideResponse(
                handle, id(), requestId, status, contentType, body, timeoutMs);
        return raw.isEmpty() ? Map.of() : (Map<String, Object>) Json.decode(raw);
    }

    /**
     * The {@code network.request} id out of a {@code network.beforeRequestSent}
     * (or other network) event: {@code params.request.request}, or {@code null}.
     */
    public static String eventRequestId(Map<String, Object> event) {
        if (event == null || !(event.get("params") instanceof Map<?, ?> params)) {
            return null;
        }
        if (!(params.get("request") instanceof Map<?, ?> request)) {
            return null;
        }
        Object rid = request.get("request");
        return rid == null ? null : rid.toString();
    }

    /**
     * How many events the bounded queue has dropped since the last call (then
     * resets) — so a consumer knows it missed events.
     */
    public int lostEvents() {
        return Native.bidiLostEvents(handle);
    }

    public void close() {
        if (handle != null && !Native.isNull(handle)) {
            Native.bidiClose(handle);
            handle = null;
        }
    }
}
