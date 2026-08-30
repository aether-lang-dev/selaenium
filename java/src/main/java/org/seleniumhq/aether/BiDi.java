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
