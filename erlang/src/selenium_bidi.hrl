%% selenium_bidi.hrl — the common WebDriver-BiDi event names (W3C spec).
%%
%% Pass to selenium:bidi_subscribe/2 and match in selenium:bidi_next_event/3:
%%
%%   -include_lib("selenium_nif/src/selenium_bidi.hrl").
%%   selenium:bidi_subscribe(D, [?BIDI_LOG_ENTRY_ADDED]),
%%   selenium:get(D, Url),
%%   {ok, Ev} = selenium:bidi_next_event(D, ?BIDI_LOG_ENTRY_ADDED, 5000).

-define(BIDI_LOG_ENTRY_ADDED,     <<"log.entryAdded">>).
-define(BIDI_CONTEXT_CREATED,     <<"browsingContext.contextCreated">>).
-define(BIDI_CONTEXT_DESTROYED,   <<"browsingContext.contextDestroyed">>).
-define(BIDI_NAVIGATION_STARTED,  <<"browsingContext.navigationStarted">>).
-define(BIDI_DOM_CONTENT_LOADED,  <<"browsingContext.domContentLoaded">>).
-define(BIDI_LOAD,                <<"browsingContext.load">>).
-define(BIDI_DOWNLOAD_WILL_BEGIN, <<"browsingContext.downloadWillBegin">>).
-define(BIDI_BEFORE_REQUEST_SENT, <<"network.beforeRequestSent">>).
-define(BIDI_AUTH_REQUIRED,       <<"network.authRequired">>).
-define(BIDI_RESPONSE_STARTED,    <<"network.responseStarted">>).
-define(BIDI_RESPONSE_COMPLETED,  <<"network.responseCompleted">>).
-define(BIDI_FETCH_ERROR,         <<"network.fetchError">>).
-define(BIDI_REALM_CREATED,       <<"script.realmCreated">>).
-define(BIDI_REALM_DESTROYED,     <<"script.realmDestroyed">>).
-define(BIDI_MESSAGE,             <<"script.message">>).
