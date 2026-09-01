package org.openqa.selenium;

/**
 * The common WebDriver-BiDi event names (W3C spec). Pass to
 * {@link BiDi#subscribe(String...)} and match in
 * {@link BiDi#nextEvent(String, int)}.
 */
public final class BidiEvent {

    private BidiEvent() {
    }

    public static final String LOG_ENTRY_ADDED = "log.entryAdded";
    public static final String CONTEXT_CREATED = "browsingContext.contextCreated";
    public static final String CONTEXT_DESTROYED = "browsingContext.contextDestroyed";
    public static final String NAVIGATION_STARTED = "browsingContext.navigationStarted";
    public static final String DOM_CONTENT_LOADED = "browsingContext.domContentLoaded";
    public static final String LOAD = "browsingContext.load";
    public static final String DOWNLOAD_WILL_BEGIN = "browsingContext.downloadWillBegin";
    public static final String BEFORE_REQUEST_SENT = "network.beforeRequestSent";
    public static final String AUTH_REQUIRED = "network.authRequired";
    public static final String RESPONSE_STARTED = "network.responseStarted";
    public static final String RESPONSE_COMPLETED = "network.responseCompleted";
    public static final String FETCH_ERROR = "network.fetchError";
    public static final String REALM_CREATED = "script.realmCreated";
    public static final String REALM_DESTROYED = "script.realmDestroyed";
    public static final String MESSAGE = "script.message";
}
