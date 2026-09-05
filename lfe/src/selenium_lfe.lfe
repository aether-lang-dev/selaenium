;;; selenium_lfe.lfe — the LFE (Lisp Flavoured Erlang) Selenium binding over the
;;; engine, riding the same selenium_nif NIF as the Erlang/Elixir bindings.
;;;
;;; Carries NO protocol logic: the W3C command map, routing, By normalization,
;;; error decode and HTTP round-trip all live in the Aether engine, reached via
;;; `selenium_nif`. This module marshals LFE maps/lists <-> JSON and presents an
;;; idiomatic surface that mirrors the Erlang twin (erlang/src/selenium.erl)
;;; command-for-command over the identical NIF.
;;;
;;; A session handle is an opaque integer. Commands return #(ok Value) |
;;; #(error #(Code Message)). Values are decoded JSON: maps (binary keys),
;;; lists, binaries, numbers, booleans, null (the atom `null`).
;;;
;;; PUBLIC function names use underscores (by_id, error_code, find_element, …).
;;; LFE lets a local def use hyphens, but a *remote* call `selenium_lfe:by-id`
;;; does not resolve to the exported `'by-id'` atom — so any cross-module API
;;; must be underscore-named to be callable. Internal helpers stay hyphenated.
(defmodule selenium_lfe
  (export
   ;; pure engine helpers (no session) — shared with every binding
   (route 1)
   (error_code 1)
   (locator 2)
   ;; JSON marshalling (maps with binary keys <-> JSON binary) — the same codec
   ;; command params/results ride; exported so callers can shape raw payloads.
   (encode 1)
   (decode 1)
   ;; Selenium-style By factory (returns #(Strategy Value) locator tuples)
   (by_id 1)
   (by_name 1)
   (by_class_name 1)
   (by_css 1)
   (by_tag_name 1)
   (by_link_text 1)
   (by_partial_link_text 1)
   (by_xpath 1)
   ;; session lifecycle
   (chrome 1) (chrome 2) (chrome 3) (chrome_tls 3) (headless_chrome 1)
   (open 1)
   (resolve_driver 1) (resolve_driver 2)
   (launch_driver 1) (launch_driver 2)
   (ensure_driver 0) (ensure_driver 1) (ensure_driver 2) (ensure_driver 3)
   (driver_url 1) (driver_pid 1) (stop_driver 1)
   (local_chrome 0) (local_chrome 1)
   (execute 3)
   (session_id 1)
   (quit 1)
   (close 1)
   (last_value 1)
   (last_error_code 1)
   ;; navigation
   (get 2) (current_url 1) (title 1) (page_source 1)
   (back 1) (forward 1) (refresh 1)
   ;; elements
   (find_element 2) (find_elements 2) (find_element 3) (find_elements 3)
   (exists 2) (active_element 1)
   (click 2) (send_keys 3) (clear 2) (submit 2)
   (element_text 2) (tag_name 2) (element_property 3) (get_property 3)
   (element_rect 2) (css_value 3) (value_of_css_property 3) (element_screenshot 2)
   (is_displayed 2) (is_enabled 2) (is_selected 2)
   (get_attribute 3) (dom_attribute 3)
   (find_relative 3) (find_relative_count 3)
   ;; script
   (execute_script 2) (execute_script 3)
   (execute_async_script 2) (execute_async_script 3)
   ;; windows / frames
   (window_handles 1) (current_window_handle 1) (switch_to_window 2)
   (new_window 1) (new_window 2) (close_window 1)
   (switch_to_frame 2) (switch_to_parent_frame 1) (switch_to_default_content 1)
   (maximize_window 1) (minimize_window 1) (fullscreen_window 1)
   (set_window_rect 2) (get_window_rect 1)
   ;; alerts
   (accept_alert 1) (dismiss_alert 1) (alert_text 1) (alert_present 1)
   (send_alert_text 2)
   ;; cookies
   (add_cookie 2) (cookies 1) (cookie 2) (delete_cookie 2) (delete_all_cookies 1)
   ;; actions
   (perform_actions 2) (clear_actions 1)
   (action_click 2) (action_double_click 2) (action_context_click 2)
   (action_move_to 2) (action_drag_and_drop 3)
   (action_click_and_hold 2) (action_release 1)
   (action_key_down 2) (action_key_up 2) (action_chord 3)
   ;; waits
   (wait_for_element 4) (wait_for_visible 4) (wait_for_clickable 4)
   (wait_until 3) (wait_until 4) (wait_until_not 3) (poll_every 3)
   (wait_for_title_contains 3) (wait_for_url_contains 3)
   (wait_for_title_is 3) (wait_for_url_is 3) (wait_until_gone 4)
   (wait_for_text_contains 4)
   ;; Select (native <select> helper)
   (select_by_value 3) (select_by_visible_text 3) (select_by_index 3)
   (all_selected_options 2) (first_selected_option 2)
   (deselect_all 2) (is_multiple 2)
   ;; timeouts / screenshots
   (set_timeouts 2) (set_page_load_timeout 2) (set_script_timeout 2)
   (implicitly_wait 2) (screenshot 1) (print_pdf 1) (print_pdf 2)
   ;; WebDriver-BiDi
   (bidi_available 1) (bidi_subscribe 2) (bidi_unsubscribe 2)
   (bidi_next_event 3) (bidi_command 4) (bidi_lost_events 1)
   (bidi_get_tree 1) (bidi_top_context 1)
   (bidi_evaluate 2) (bidi_evaluate_value 2) (bidi_navigate 2)
   (bidi_add_intercept 2) (bidi_add_intercept 3) (bidi_remove_intercept 2)
   (bidi_continue_request 2) (bidi_fail_request 2) (bidi_event_request_id 1)
   (bidi_provide_response 2) (bidi_provide_response 5)
   (bidi_continue_with_auth 4)
   (bidi_set_cache_behavior 1) (bidi_set_cache_behavior 2)))

(defun w3c-element-key () #"element-6066-11e4-a52e-4f735466cecf")
;; The named ETS table holding per-session BiDi state:
;; {Handle, WsUrl, BidiHandle, NextId}.
(defun bidi-table-name () 'selenium_lfe_bidi)
(defun wait-poll-ms () 500)

;; ---- pure helpers (delegate straight to the NIF) ----

(defun route (command)
  (selenium_nif:route (to-bin command)))

(defun error_code (w3c-error)
  (selenium_nif:error_code (to-bin w3c-error)))

(defun locator (by value)
  (selenium_nif:by_locator (to-bin by) (to-bin value)))

;; ---- By factory (Selenium-style) ----
;; Each returns a #(Strategy Value) locator tuple that find_element/2 accepts,
;; mirroring Selenium's By.id(...)/By.className(...). class_name maps to the
;; W3C "class name" (matching every other Selenium binding).

(defun by_id (value) (tuple #"id" (to-bin value)))
(defun by_name (value) (tuple #"name" (to-bin value)))
(defun by_class_name (value) (tuple #"class name" (to-bin value)))
(defun by_css (value) (tuple #"css selector" (to-bin value)))
(defun by_tag_name (value) (tuple #"tag name" (to-bin value)))
(defun by_link_text (value) (tuple #"link text" (to-bin value)))
(defun by_partial_link_text (value) (tuple #"partial link text" (to-bin value)))
(defun by_xpath (value) (tuple #"xpath" (to-bin value)))

;; ---- session lifecycle ----

(defun chrome (command-executor) (chrome command-executor #M()))

(defun chrome (command-executor options)
  (chrome command-executor options #M()))

;; TlsOpts (optional map): #M(ca_path <<...>> insecure true) — TLS trust config
;; applied on the handle BEFORE newSession. ca_path pins a private-CA bundle;
;; insecure skips verification (self-signed dev/staging Grid).
(defun chrome (command-executor options tls-opts)
  (let ((caps (maps:merge #M(#"browserName" #"chrome") options)))
    (new-session command-executor caps tls-opts)))

;; Named-for-parity alias of chrome/3 (mirrors the reference's chrome_tls).
(defun chrome_tls (command-executor options tls-opts)
  (chrome command-executor options tls-opts))

(defun headless_chrome (command-executor)
  (let* ((args (list #"--headless=new" #"--no-sandbox"
                     #"--disable-gpu" #"--disable-dev-shm-usage"))
         (opts0 (maps:put #"args" args #M()))
         (opts (case (os:getenv "SEL_CHROME_BINARY")
                 ('false opts0)
                 ("" opts0)
                 (bin (maps:put #"binary" (list_to_binary bin) opts0)))))
    (chrome command-executor (maps:put #"goog:chromeOptions" opts #M()))))

;; Low-level open: returns a raw session handle integer (no newSession). Kept
;; for callers driving the engine directly.
(defun open (base-url)
  (selenium_nif:open (to-bin base-url)))

(defun new-session (command-executor caps tls-opts)
  (let ((handle (selenium_nif:open (to-bin command-executor))))
    (if (=:= handle 0)
        (tuple 'error (tuple -1 #"failed to open session handle"))
        (progn
          ;; TLS trust config must land on the handle before newSession.
          (case (maps:get 'ca_path tls-opts 'undefined)
            (ca-path (when (andalso (is_binary ca-path) (> (byte_size ca-path) 0)))
             (selenium_nif:set_ca handle ca-path))
            (_ 'ok))
          (case (maps:get 'insecure tls-opts 'false)
            ('true (selenium_nif:set_insecure handle 1))
            (_ 'ok))
          ;; Request a BiDi channel so bidi_* is available on demand; the
          ;; WebSocket opens lazily (a classic script never opens it).
          (let* ((bidi-caps (maps:put #"webSocketUrl" 'true caps))
                 (payload (maps:put #"capabilities"
                                    (maps:put #"alwaysMatch" bidi-caps #M())
                                    #M())))
            (case (execute handle #"newSession" payload)
              ((tuple 'ok value)
               (bidi-register handle (ws-url-of value))
               (tuple 'ok handle))
              (err (selenium_nif:close handle) err)))))))

;; ---- driver orchestration (spawn/adopt a driver process in-binding) ----

(defun resolve_driver (browser) (resolve_driver browser #""))
(defun resolve_driver (browser hint)
  (selenium_nif:resolve_driver (to-bin browser) (to-bin hint)))

(defun launch_driver (driver-path) (launch_driver driver-path 15000))
(defun launch_driver (driver-path timeout-ms)
  (case (selenium_nif:launch_driver (to-bin driver-path) timeout-ms)
    (0 (tuple 'error 'driver_launch_failed))
    (dh (tuple 'ok dh))))

(defun ensure_driver () (ensure_driver #"chrome"))
(defun ensure_driver (browser) (ensure_driver browser #"" 15000))
(defun ensure_driver (browser hint) (ensure_driver browser hint 15000))
(defun ensure_driver (browser hint timeout-ms)
  (case (selenium_nif:ensure_driver (to-bin browser) (to-bin hint) timeout-ms)
    (0 (tuple 'error 'driver_ensure_failed))
    (dh (tuple 'ok dh))))

(defun driver_url (dh) (selenium_nif:driver_url dh))
(defun driver_pid (dh) (selenium_nif:driver_pid dh))
(defun stop_driver (dh) (selenium_nif:stop_driver dh) 'ok)

;; A Chrome session that spawns its OWN chromedriver via the engine — no driver
;; on PATH, no Grid. Returns #(ok Handle DriverHandle).
(defun local_chrome () (local_chrome #M()))
(defun local_chrome (options)
  (case (ensure_driver #"chrome" #"" 15000)
    ((tuple 'ok dh)
     (let ((url (driver_url dh)))
       (case (chrome url options)
         ((tuple 'ok handle) (tuple 'ok handle dh))
         (err (stop_driver dh) err))))
    (err err)))

;; value.capabilities.webSocketUrl — the BiDi endpoint for this session, or <<>>.
(defun ws-url-of (value)
  (if (is_map value)
      (case (maps:get #"capabilities" value 'undefined)
        (caps (when (is_map caps))
         (case (maps:get #"webSocketUrl" caps 'undefined)
           (url (when (is_binary url)) url)
           (_ #"")))
        (_ #""))
      #""))

;; ---- the FFI seam ----

(defun execute (handle command params)
  (let ((rc (selenium_nif:execute handle (to-bin command) (encode params))))
    (if (=:= rc 0)
        (case (selenium_nif:last_value handle)
          (#"" (tuple 'ok 'null))
          (raw (tuple 'ok (decode raw))))
        (tuple 'error (tuple (selenium_nif:last_error_code handle)
                             (selenium_nif:last_error handle))))))

;; ---- navigation ----
(defun get (h url) (execute h #"get" (maps:put #"url" (to-bin url) #M())))
(defun current_url (h) (execute h #"getCurrentUrl" #M()))
(defun title (h) (execute h #"getTitle" #M()))
(defun page_source (h) (execute h #"getPageSource" #M()))
(defun back (h) (execute h #"goBack" #M()))
(defun forward (h) (execute h #"goForward" #M()))
(defun refresh (h) (execute h #"refresh" #M()))

;; ---- elements ---- (return #(ok ElementId) | #(error _))

;; Selenium-style one-locator find: pass a #(Strategy Value) tuple (from a by_*
;; factory or written literally). find_element/3 stays additive.
(defun find_element (h loc)
  (let ((`#(,strategy ,value) loc))
    (find_element h strategy value)))

(defun find_elements (h loc)
  (let ((`#(,strategy ,value) loc))
    (find_elements h strategy value)))

(defun find_element (h by value)
  (case (execute h #"findElement" (decode-by by value))
    ((tuple 'ok m) (tuple 'ok (maps:get (w3c-element-key) m)))
    (err err)))

(defun find_elements (h by value)
  (case (execute h #"findElements" (decode-by by value))
    ((tuple 'ok l)
     (tuple 'ok (lists:map (lambda (e) (maps:get (w3c-element-key) e)) l)))
    (err err)))

(defun click (h element-id)
  (execute h #"clickElement" (maps:put #"id" element-id #M())))

(defun send_keys (h element-id text)
  (let* ((bin (to-bin text))
         (chars (lists:map (lambda (c) (unicode:characters_to_binary (list c)))
                           (unicode:characters_to_list bin))))
    (execute h #"sendKeysToElement"
             (maps:from_list (list (tuple #"id" element-id)
                                   (tuple #"text" bin)
                                   (tuple #"value" chars))))))

(defun clear (h element-id)
  (execute h #"clearElement" (maps:put #"id" element-id #M())))

(defun element_text (h element-id)
  (execute h #"getElementText" (maps:put #"id" element-id #M())))

(defun tag_name (h element-id)
  (execute h #"getElementTagName" (maps:put #"id" element-id #M())))

;; getElementProperty — route .../property/:name, so the key IS "name".
(defun element_property (h element-id name)
  (execute h #"getElementProperty"
           (maps:from_list (list (tuple #"id" element-id)
                                 (tuple #"name" (to-bin name))))))

;; Mainstream alias of element_property/3 (Selenium's get_property).
(defun get_property (h element-id name) (element_property h element-id name))

(defun element_rect (h element-id)
  (execute h #"getElementRect" (maps:put #"id" element-id #M())))

;; getElementValueOfCssProperty — route .../css/:propertyName, so the param key
;; MUST be "propertyName" (NOT "name") or the placeholder never substitutes.
(defun css_value (h element-id prop)
  (execute h #"getElementValueOfCssProperty"
           (maps:from_list (list (tuple #"id" element-id)
                                 (tuple #"propertyName" (to-bin prop))))))

;; Mainstream alias for css_value/3 (Selenium's value_of_css_property).
(defun value_of_css_property (h element-id prop) (css_value h element-id prop))

;; A PNG screenshot of just this element (takeElementScreenshot), base64.
(defun element_screenshot (h element-id)
  (execute h #"takeElementScreenshot" (maps:put #"id" element-id #M())))

;; Submit the form owning this element — walk to the form and submit it as a
;; real user gesture would (requestSubmit fires validation; submit() fallback).
(defun submit (h element-id)
  (let ((script #"var e=arguments[0];var f=e.form||e.closest('form');if(!f){throw new Error('Element is not within a form');}if(f.requestSubmit){f.requestSubmit();}else{f.submit();}"))
    (execute_script h script
                    (list (maps:put (w3c-element-key) element-id #M())))))

;; The element that currently has focus (W3C getActiveElement).
(defun active_element (h)
  (case (execute h #"getActiveElement" #M())
    ((tuple 'ok m) (when (is_map m)) (tuple 'ok (maps:get (w3c-element-key) m)))
    (err err)))

;; Whether an element matching the locator is present. #(ok true|false); a real
;; error (not "no such element") propagates. Accepts a #(Strategy Value) tuple.
(defun exists (h by)
  (case (find_element h by)
    ((tuple 'ok _) (tuple 'ok 'true))
    ((tuple 'error (tuple 17 _))    ; 17 = no such element
     (tuple 'ok 'false))
    (err err)))

;; ---- atom-backed commands (isDisplayed / getAttribute / relative locators) ----
;; Each runs a shared JS atom in-page via the engine — the SAME atoms every
;; binding uses. Int-returning verbs leave JSON in last_value, drained by
;; atom-result/2 exactly like execute/3.

(defun is_displayed (h element-id)
  (case (atom-result h (selenium_nif:is_displayed h (to-bin element-id)))
    ((tuple 'ok v) (=:= v 'true))
    (err err)))

(defun is_enabled (h element-id)
  (case (execute h #"isElementEnabled" (maps:put #"id" element-id #M()))
    ((tuple 'ok v) (=:= v 'true))
    (err err)))

(defun is_selected (h element-id)
  (case (execute h #"isElementSelected" (maps:put #"id" element-id #M()))
    ((tuple 'ok v) (=:= v 'true))
    (err err)))

;; The classic getAttribute(name): property-or-attribute via the shared atom.
;; Returns binary() | 'undefined (JSON null) | #(error _).
(defun get_attribute (h element-id name)
  (case (atom-result h (selenium_nif:get_attribute h (to-bin element-id) (to-bin name)))
    ((tuple 'ok 'null) 'undefined)
    ((tuple 'ok v) v)
    (err err)))

;; The literal DOM attribute (W3C getDomAttribute), no property fallback.
(defun dom_attribute (h element-id name)
  (execute h #"getDomAttribute"
           (maps:from_list (list (tuple #"id" element-id)
                                 (tuple #"name" (to-bin name))))))

;; Relative locators: elements matching BaseCss filtered by spatial relation to
;; anchors, nearest first. Filters is a list of maps
;; #M(kind above|below|left|right|near sel <<css>>). Returns #(ok [ElementId]).
(defun find_relative (h base-css filters)
  (let ((rc (selenium_nif:find_relative h (to-bin base-css) (encode filters))))
    (case (atom-result h rc)
      ((tuple 'ok 'null) (tuple 'ok ()))
      ((tuple 'ok refs) (when (is_list refs))
       (tuple 'ok (lists:map (lambda (r) (maps:get (w3c-element-key) r)) refs)))
      (err err))))

(defun find_relative_count (h base-css filters)
  (case (find_relative h base-css filters)
    ((tuple 'ok refs) (tuple 'ok (length refs)))
    (err err)))

;; Drain last_value after an atom call, decoding + error-mapping like execute/3.
(defun atom-result (h rc)
  (if (=:= rc 0)
      (case (selenium_nif:last_value h)
        (#"" (tuple 'ok 'null))
        (raw (tuple 'ok (decode raw))))
      (tuple 'error (tuple (selenium_nif:last_error_code h)
                           (selenium_nif:last_error h)))))

;; ---- script ----
(defun execute_script (h script) (execute_script h script ()))
(defun execute_script (h script args)
  (execute h #"executeScript"
           (maps:from_list (list (tuple #"script" (to-bin script))
                                 (tuple #"args" args)))))

(defun execute_async_script (h script) (execute_async_script h script ()))
(defun execute_async_script (h script args)
  (execute h #"executeAsyncScript"
           (maps:from_list (list (tuple #"script" (to-bin script))
                                 (tuple #"args" args)))))

;; ---- windows ----
(defun window_handles (h) (execute h #"getWindowHandles" #M()))
(defun current_window_handle (h) (execute h #"getCurrentWindowHandle" #M()))
(defun switch_to_window (h handle)
  (execute h #"switchToWindow" (maps:put #"handle" (to-bin handle) #M())))

;; Open a new top-level window/tab (W3C newWindow). TypeHint is <<"tab">> or
;; <<"window">>. Returns #(ok Handle) — the new context's handle.
(defun new_window (h) (new_window h #"tab"))
(defun new_window (h type-hint)
  (case (execute h #"newWindow" (maps:put #"type" (to-bin type-hint) #M()))
    ((tuple 'ok m) (when (is_map m)) (tuple 'ok (maps:get #"handle" m #"")))
    (err err)))

;; Close the current window/tab (W3C close). Returns #(ok RemainingHandles).
(defun close_window (h) (execute h #"close" #M()))

;; ---- frames ----
;; switch_to_frame/2 accepts: an index (integer), an element id binary (an
;; <iframe>/<frame> reference), or the atom `default`/`null` for the top context.
(defun switch_to_frame (h frame)
  (cond
   ((orelse (=:= frame 'default) (=:= frame 'null))
    (execute h #"switchToFrame" (maps:put #"id" 'null #M())))
   ((is_integer frame)
    (execute h #"switchToFrame" (maps:put #"id" frame #M())))
   ((is_binary frame)
    (execute h #"switchToFrame"
             (maps:put #"id" (maps:put (w3c-element-key) frame #M()) #M())))))

(defun switch_to_parent_frame (h) (execute h #"switchToFrameParent" #M()))
(defun switch_to_default_content (h) (switch_to_frame h 'null))
(defun maximize_window (h) (execute h #"maximizeWindow" #M()))
(defun minimize_window (h) (execute h #"minimizeWindow" #M()))
(defun fullscreen_window (h) (execute h #"fullscreenWindow" #M()))
(defun set_window_rect (h rect) (execute h #"setWindowRect" rect))
(defun get_window_rect (h) (execute h #"getWindowRect" #M()))

;; ---- alerts ----
(defun accept_alert (h) (execute h #"acceptAlert" #M()))
(defun dismiss_alert (h) (execute h #"dismissAlert" #M()))
(defun alert_text (h) (execute h #"getAlertText" #M()))
(defun send_alert_text (h text)
  (execute h #"setAlertValue" (maps:put #"text" (to-bin text) #M())))

;; Whether a user-prompt / alert dialog is currently open. #(ok true|false);
;; code 15 ("no such alert") maps to false, other errors propagate.
(defun alert_present (h)
  (case (execute h #"getAlertText" #M())
    ((tuple 'ok _) (tuple 'ok 'true))
    ((tuple 'error (tuple 15 _))    ; 15 = no such alert
     (tuple 'ok 'false))
    (err err)))

;; ---- cookies ----
(defun add_cookie (h ck) (execute h #"addCookie" (maps:put #"cookie" ck #M())))
(defun cookies (h) (execute h #"getCookies" #M()))
(defun cookie (h name) (execute h #"getCookie" (maps:put #"name" (to-bin name) #M())))
(defun delete_cookie (h name)
  (execute h #"deleteCookie" (maps:put #"name" (to-bin name) #M())))
(defun delete_all_cookies (h) (execute h #"deleteAllCookies" #M()))

;; ---- actions ----
(defun perform_actions (h actions)
  (execute h #"actions" (maps:put #"actions" actions #M())))
(defun clear_actions (h) (execute h #"clearActions" #M()))

;; Move to the element centre and click through the input-actions device.
(defun action_click (h element-id)
  (perform_actions h (list (ptr-seq (list (ptr-move-origin element-id)
                                          (ptr-down 0) (ptr-up 0))))))

(defun action_double_click (h element-id)
  (perform_actions h (list (ptr-seq (list (ptr-move-origin element-id)
                                          (ptr-down 0) (ptr-up 0)
                                          (ptr-down 0) (ptr-up 0))))))

(defun action_context_click (h element-id)
  (perform_actions h (list (ptr-seq (list (ptr-move-origin element-id)
                                          (ptr-down 2) (ptr-up 2))))))

(defun action_move_to (h element-id)
  (perform_actions h (list (ptr-seq (list (ptr-move-origin element-id))))))

(defun action_drag_and_drop (h source-id target-id)
  (perform_actions h (list (ptr-seq (list (ptr-move-origin source-id) (ptr-down 0)
                                          (ptr-move-origin target-id) (ptr-up 0))))))

;; Press and HOLD the left button (no release) — pair with action_release/1.
(defun action_click_and_hold (h element-id)
  (perform_actions h (list (ptr-seq (list (ptr-move-origin element-id) (ptr-down 0))))))

(defun action_release (h)
  (perform_actions h (list (ptr-seq (list (ptr-up 0))))))

(defun action_key_down (h key)
  (perform_actions h (list (key-seq (list (key-ev #"keyDown" key))))))

(defun action_key_up (h key)
  (perform_actions h (list (key-seq (list (key-ev #"keyUp" key))))))

;; A "chord": hold every key in Keys down (in order), fire the click at
;; ElementId, then release the keys in reverse — e.g. Ctrl+click, Shift+click.
(defun action_chord (h keys element-id)
  (let ((downs (lists:map (lambda (k) (key-ev #"keyDown" k)) keys))
        (ups (lists:map (lambda (k) (key-ev #"keyUp" k)) (lists:reverse keys))))
    (perform_actions h (list
                        (key-seq downs)
                        (ptr-seq (list (ptr-move-origin element-id)
                                       (ptr-down 0) (ptr-up 0)))
                        (key-seq ups)))))

(defun key-seq (actions)
  (maps:from_list (list (tuple #"type" #"key") (tuple #"id" #"keyboard")
                        (tuple #"actions" actions))))

(defun key-ev (type key)
  (maps:from_list (list (tuple #"type" type) (tuple #"value" (to-bin key)))))

(defun ptr-seq (actions)
  (maps:from_list (list (tuple #"type" #"pointer") (tuple #"id" #"mouse")
                        (tuple #"parameters" (maps:put #"pointerType" #"mouse" #M()))
                        (tuple #"actions" actions))))

(defun ptr-move-origin (element-id)
  (maps:from_list (list (tuple #"type" #"pointerMove") (tuple #"duration" 0)
                        (tuple #"x" 0) (tuple #"y" 0)
                        (tuple #"origin" (maps:put (w3c-element-key) element-id #M())))))

(defun ptr-down (button)
  (maps:from_list (list (tuple #"type" #"pointerDown") (tuple #"button" button))))
(defun ptr-up (button)
  (maps:from_list (list (tuple #"type" #"pointerUp") (tuple #"button" button))))

;; ---- explicit waits ----
;; The poll loop lives here because the engine issues single commands and holds
;; no thread; each attempt re-reads the live DOM. Timeouts are milliseconds.

(defun wait_for_element (h by value timeout-ms)
  (wait-element h by value timeout-ms (lambda (_hd _el) 'true)))

(defun wait_for_visible (h by value timeout-ms)
  (wait-element h by value timeout-ms
                (lambda (hd el) (=:= (is_displayed hd el) 'true))))

(defun wait_for_clickable (h by value timeout-ms)
  (wait-element h by value timeout-ms
                (lambda (hd el)
                  (andalso (=:= (is_displayed hd el) 'true)
                           (=:= (is_enabled hd el) 'true)))))

(defun wait-element (h by value timeout-ms pred)
  (wait-element-loop h by value pred (deadline timeout-ms)))

(defun wait-element-loop (h by value pred dl)
  (let ((found (case (find_element h by value)
                 ((tuple 'ok el)
                  (case (funcall pred h el)
                    ('true (tuple 'ok el))
                    (_ 'false)))
                 ((tuple 'error _) 'false))))
    (case found
      ((tuple 'ok _) found)
      ('false
       (if (past-deadline dl)
           (tuple 'error 'timeout)
           (progn (timer:sleep (wait-poll-ms))
                  (wait-element-loop h by value pred dl)))))))

;; Poll a caller predicate fun(Handle)->boolean every WAIT_POLL_MS until true.
(defun wait_until (h timeout-ms pred-fun)
  (wait_until h timeout-ms (wait-poll-ms) pred-fun))

(defun wait_until (h timeout-ms poll-ms pred-fun)
  (wait-until-loop h pred-fun (deadline timeout-ms) 'true (poll-ms poll-ms)))

;; Alias making the poll-interval intent read like the reference: poll_every/3
;; is wait_until/4 with the interval leading. Cond is #(TimeoutMs PredFun).
(defun poll_every (h poll-ms cond)
  (let ((`#(,timeout-ms ,pred-fun) cond))
    (wait_until h timeout-ms poll-ms pred-fun)))

(defun poll-ms (ms)
  (if (andalso (is_integer ms) (> ms 0)) ms (wait-poll-ms)))

;; The inverse: poll until PredFun/1 is NOT true (reference's until_not).
(defun wait_until_not (h timeout-ms pred-fun)
  (wait-until-loop h pred-fun (deadline timeout-ms) 'false (wait-poll-ms)))

(defun wait-until-loop (h pred-fun dl want poll-ms)
  (if (=:= (funcall pred-fun h) want)
      (tuple 'ok 'true)
      (if (past-deadline dl)
          (tuple 'error 'timeout)
          (progn (timer:sleep poll-ms)
                 (wait-until-loop h pred-fun dl want poll-ms)))))

(defun wait_for_title_contains (h substr timeout-ms)
  (let ((want (to-bin substr)))
    (wait_until h timeout-ms (lambda (hd) (value-contains (title hd) want)))))

(defun wait_for_url_contains (h substr timeout-ms)
  (let ((want (to-bin substr)))
    (wait_until h timeout-ms (lambda (hd) (value-contains (current_url hd) want)))))

(defun wait_for_title_is (h ttl timeout-ms)
  (let ((want (to-bin ttl)))
    (wait_until h timeout-ms (lambda (hd) (value-equals (title hd) want)))))

(defun wait_for_url_is (h url timeout-ms)
  (let ((want (to-bin url)))
    (wait_until h timeout-ms (lambda (hd) (value-equals (current_url hd) want)))))

;; Wait until no element matches the locator (reference's wait_until_gone).
(defun wait_until_gone (h by value timeout-ms)
  (wait_until_not h timeout-ms
                  (lambda (hd)
                    (case (find_element hd by value)
                      ((tuple 'ok _) 'true)
                      (_ 'false)))))

(defun wait_for_text_contains (h element-id substr timeout-ms)
  (let ((want (to-bin substr)))
    (wait_until h timeout-ms
                (lambda (hd) (value-contains (element_text hd element-id) want)))))

(defun value-contains (result want)
  (case result
    ((tuple 'ok v) (when (is_binary v)) (=/= (binary:match v want) 'nomatch))
    (_ 'false)))

(defun value-equals (result want)
  (case result
    ((tuple 'ok v) (when (is_binary v)) (=:= v want))
    (_ 'false)))

;; Monotonic deadline in ms; immune to wall-clock changes.
(defun deadline (timeout-ms)
  (+ (erlang:monotonic_time 'millisecond) timeout-ms))

(defun past-deadline (dl)
  (> (erlang:monotonic_time 'millisecond) dl))

;; ---- Select (native <select> dropdown helper) ----
;; Drive a <select> by finding/clicking its <option> children — the same
;; approach mainstream Selenium's Select uses. For single-select; on a
;; multi-select each call toggles one option on.

(defun select_by_value (h select-id value)
  (let ((want (to-bin value)))
    (select-option h select-id
                   (lambda (opt)
                     (case (get_attribute h opt #"value")
                       (v (when (is_binary v)) (=:= v want))
                       (_ 'false))))))

(defun select_by_visible_text (h select-id text)
  (let ((want (to-bin text)))
    (select-option h select-id
                   (lambda (opt)
                     (case (element_text h opt)
                       ((tuple 'ok tx) (=:= tx want))
                       (_ 'false))))))

(defun select_by_index (h select-id index)
  (case (options-of h select-id)
    ((tuple 'ok opts) (when (andalso (>= index 0) (< index (length opts))))
     (click-option h (lists:nth (+ index 1) opts)))
    ((tuple 'ok _) (tuple 'error 'no_such_option))
    (err err)))

;; The <option> element ids of a <select> — findChildElements scoped to the
;; select, so the tag-name search stays inside THIS <select>.
(defun options-of (h select-id)
  (let ((params (maps:put #"id" select-id (decode-by #"tag name" #"option"))))
    (case (execute h #"findChildElements" params)
      ((tuple 'ok l)
       (tuple 'ok (lists:map (lambda (e) (maps:get (w3c-element-key) e)) l)))
      (err err))))

(defun select-option (h select-id pred)
  (case (options-of h select-id)
    ((tuple 'ok opts) (select-first h opts pred))
    (err err)))

(defun select-first
  ((_h () _pred) (tuple 'error 'no_such_option))
  ((h (cons opt rest) pred)
   (if (funcall pred opt)
       (click-option h opt)
       (select-first h rest pred))))

(defun click-option (h opt)
  (if (=:= (is_selected h opt) 'true)
      (tuple 'ok opt)
      (case (click h opt)
        ((tuple 'ok _) (tuple 'ok opt))
        (err err))))

;; All currently-selected <option> ids, in document order.
(defun all_selected_options (h select-id)
  (case (options-of h select-id)
    ((tuple 'ok opts)
     (tuple 'ok (lists:filter (lambda (o) (=:= (is_selected h o) 'true)) opts)))
    (err err)))

(defun first_selected_option (h select-id)
  (case (all_selected_options h select-id)
    ((tuple 'ok (cons first _)) (tuple 'ok first))
    ((tuple 'ok ()) (tuple 'error 'no_such_option))
    (err err)))

;; Whether the <select> allows multiple selection (the `multiple` attribute).
(defun is_multiple (h select-id)
  (case (get_attribute h select-id #"multiple")
    ('undefined (tuple 'ok 'false))
    ('false (tuple 'ok 'false))
    ((tuple 'error e) (tuple 'error e))
    (_ (tuple 'ok 'true))))

;; Deselect every selected option — only valid on a multi-select (mirrors the
;; reference, which errors on a single-select).
(defun deselect_all (h select-id)
  (case (is_multiple h select-id)
    ((tuple 'ok 'true)
     (case (all_selected_options h select-id)
       ((tuple 'ok sel) (deselect-each h sel))
       (err err)))
    ((tuple 'ok 'false) (tuple 'error 'not_a_multi_select))
    (err err)))

(defun deselect-each
  ((_h ()) (tuple 'ok 'true))
  ((h (cons opt rest))
   (case (click h opt)
     ((tuple 'ok _) (deselect-each h rest))
     (err err))))

;; ---- timeouts / screenshots ----
(defun set_timeouts (h timeouts) (execute h #"setTimeout" timeouts))
(defun set_page_load_timeout (h ms)
  (execute h #"setTimeout" (maps:put #"pageLoad" ms #M())))
(defun set_script_timeout (h ms)
  (execute h #"setTimeout" (maps:put #"script" ms #M())))
(defun implicitly_wait (h ms)
  (execute h #"setTimeout" (maps:put #"implicit" ms #M())))
(defun screenshot (h) (execute h #"screenshot" #M()))

;; Print the current page to PDF (W3C printPage), base64. print_pdf/2 takes an
;; options map (page size, margins, orientation, …).
(defun print_pdf (h) (print_pdf h #M()))
(defun print_pdf (h options) (execute h #"printPage" options))

;; ---- lifecycle ----
(defun session_id (h) (selenium_nif:session_id h))
(defun last_value (h) (selenium_nif:last_value h))
(defun last_error_code (h) (selenium_nif:last_error_code h))

(defun quit (h)
  (bidi-shutdown h)
  (let ((r (execute h #"quit" #M())))
    (selenium_nif:close h)
    r))

(defun close (h) (selenium_nif:close h))

;; ---- WebDriver-BiDi ----
;; The event-driven surface for a session, multiplexed over one WebSocket by the
;; engine's demux. The channel opens lazily over the negotiated webSocketUrl on
;; first use; command ids are supplied automatically.

(defun bidi_available (h)
  (case (bidi-lookup h)
    ((tuple 'ok ws-url _ _) (=/= ws-url #""))
    ('error 'false)))

(defun bidi_subscribe (h events)
  (with-bidi h
             (lambda (bh)
               (let ((id (bidi-next-id h)))
                 (tuple 'ok (ack (selenium_nif:bidi_subscribe
                                  bh id (join-events events) 10000)))))))

(defun bidi_unsubscribe (h events)
  (with-bidi h
             (lambda (bh)
               (let ((id (bidi-next-id h)))
                 (tuple 'ok (ack (selenium_nif:bidi_unsubscribe
                                  bh id (join-events events) 10000)))))))

;; Block until an event whose method matches arrives, or timeout. #(ok EventMap)
;; | #(ok timeout) on timeout/close | #(error _).
(defun bidi_next_event (h method timeout-ms)
  (with-bidi h
             (lambda (bh)
               (case (selenium_nif:bidi_wait_event bh (to-bin method) timeout-ms)
                 (#"" (tuple 'ok 'timeout))
                 (raw (tuple 'ok (decode raw)))))))

;; Issue any BiDi command; reaches methods with no dedicated wrapper.
(defun bidi_command (h method params timeout-ms)
  (with-bidi h
             (lambda (bh)
               (let ((id (bidi-next-id h)))
                 (case (selenium_nif:bidi_send bh id (to-bin method) (encode params))
                   (0 (bidi-await-reply bh id timeout-ms 50 0 method))
                   (_ (tuple 'error (tuple -1 (iolist_to_binary
                                               (list #"BiDi send failed: "
                                                     (to-bin method)))))))))))

(defun bidi-await-reply (bh id timeout-ms step waited method)
  (if (>= waited timeout-ms)
      (tuple 'error (tuple 24 (iolist_to_binary
                               (list #"BiDi command timed out: " (to-bin method)))))
      (case (selenium_nif:bidi_poll_reply bh id)
        (#""
         (let ((rc (selenium_nif:bidi_pump bh step)))
           (if (< rc 0)
               (tuple 'error (tuple -1 #"BiDi channel closed"))
               (bidi-await-reply bh id timeout-ms step (+ waited step) method))))
        (raw (tuple 'ok (decode raw))))))

(defun bidi_lost_events (h)
  (with-bidi h (lambda (bh) (tuple 'ok (selenium_nif:bidi_lost_events bh)))))

;; ---- typed BiDi convenience commands ----

(defun bidi_get_tree (h)
  (with-bidi h
             (lambda (bh)
               (tuple 'ok (decode (selenium_nif:bidi_get_tree bh (bidi-next-id h) 10000))))))

(defun bidi_top_context (h)
  (case (bidi_get_tree h)
    ((tuple 'ok tree)
     (case tree
       ((map #"result" (map #"contexts" (cons (map #"context" ctx) _))) ctx)
       (_ 'undefined)))
    (_ 'undefined)))

(defun bidi_evaluate (h expr)
  (case (bidi_top_context h)
    ('undefined (tuple 'error (tuple 0 #"no browsing context for script.evaluate")))
    (ctx
     (with-bidi h
                (lambda (bh)
                  (tuple 'ok (decode (selenium_nif:bidi_script_evaluate
                                      bh (bidi-next-id h) (to-bin expr) ctx 30000))))))))

(defun bidi_evaluate_value (h expr)
  (case (bidi_evaluate h expr)
    ((tuple 'ok (map #"result" (map #"result" (map #"value" v)))) (tuple 'ok v))
    ((tuple 'ok _) (tuple 'ok 'undefined))
    (err err)))

(defun bidi_navigate (h url)
  (case (bidi_top_context h)
    ('undefined (tuple 'error (tuple 0 #"no browsing context for navigate")))
    (ctx
     (with-bidi h
                (lambda (bh)
                  (tuple 'ok (decode (selenium_nif:bidi_navigate
                                      bh (bidi-next-id h) ctx (to-bin url) 30000))))))))

;; ---- network interception ----

(defun bidi_add_intercept (h url-pattern)
  (bidi_add_intercept h url-pattern #"beforeRequestSent"))
(defun bidi_add_intercept (h url-pattern phases)
  (with-bidi h
             (lambda (bh)
               (let ((reply (decode (selenium_nif:bidi_network_add_intercept
                                     bh (bidi-next-id h) (to-bin phases)
                                     (to-bin url-pattern) 10000))))
                 (case reply
                   ((map #"result" (map #"intercept" ic)) (tuple 'ok ic))
                   (_ (tuple 'error (tuple 0 #"no intercept id"))))))))

(defun bidi_remove_intercept (h intercept-id)
  (with-bidi h
             (lambda (bh)
               (tuple 'ok (decode (selenium_nif:bidi_network_remove_intercept
                                   bh (bidi-next-id h) (to-bin intercept-id) 10000))))))

(defun bidi_continue_request (h request-id)
  (with-bidi h
             (lambda (bh)
               (tuple 'ok (decode (selenium_nif:bidi_network_continue_request
                                   bh (bidi-next-id h) (to-bin request-id) 10000))))))

(defun bidi_fail_request (h request-id)
  (with-bidi h
             (lambda (bh)
               (tuple 'ok (decode (selenium_nif:bidi_network_fail_request
                                   bh (bidi-next-id h) (to-bin request-id) 10000))))))

;; Fulfill a paused request with a MOCK response (never hits the network).
(defun bidi_provide_response (h request-id)
  (bidi_provide_response h request-id 200 #"" #""))
(defun bidi_provide_response (h request-id status content-type body)
  (with-bidi h
             (lambda (bh)
               (tuple 'ok (decode (selenium_nif:bidi_network_provide_response
                                   bh (bidi-next-id h) (to-bin request-id) status
                                   (to-bin content-type) (to-bin body) 10000))))))

(defun bidi_continue_with_auth (h request-id username password)
  (with-bidi h
             (lambda (bh)
               (tuple 'ok (decode (selenium_nif:bidi_network_continue_with_auth
                                   bh (bidi-next-id h) (to-bin request-id)
                                   (to-bin username) (to-bin password) 10000))))))

(defun bidi_set_cache_behavior (h) (bidi_set_cache_behavior h #"bypass"))
(defun bidi_set_cache_behavior (h behavior)
  (with-bidi h
             (lambda (bh)
               (tuple 'ok (decode (selenium_nif:bidi_network_set_cache_behavior
                                   bh (bidi-next-id h) (to-bin behavior) 10000))))))

;; The network.request id out of a network event: params.request.request.
(defun bidi_event_request_id (event)
  (case event
    ((map #"params" (map #"request" (map #"request" rid))) rid)
    (_ 'undefined)))

;; ---- BiDi internals (ETS-backed per-session state) ----

(defun bidi-table ()
  (case (ets:info (bidi-table-name) 'name)
    ('undefined
     (try
       (progn (ets:new (bidi-table-name) '(named_table public set))
              (bidi-table-name))
       (catch ((tuple 'error 'badarg _) (bidi-table-name)))))
    (_ (bidi-table-name))))

(defun bidi-register (handle ws-url)
  (ets:insert (bidi-table) (tuple handle ws-url 'undefined 1)))

(defun bidi-lookup (handle)
  (case (ets:info (bidi-table-name) 'name)
    ('undefined 'error)
    (_ (case (ets:lookup (bidi-table-name) handle)
         ((list (tuple h ws-url bidi-handle next-id)) (when (=:= h handle))
          (tuple 'ok ws-url bidi-handle next-id))
         (() 'error)))))

;; Ensure the BiDi WebSocket is open (lazily) then run Fun with its handle.
(defun with-bidi (handle fun)
  (case (bidi-channel handle)
    ((tuple 'ok bh) (funcall fun bh))
    ((= err (tuple 'error _)) err)))

(defun bidi-channel (handle)
  (case (bidi-lookup handle)
    ((tuple 'ok #"" _ _)
     (tuple 'error (tuple 0 #"BiDi not available: no webSocketUrl negotiated")))
    ((tuple 'ok _ws-url bidi-handle _next-id) (when (=/= bidi-handle 'undefined))
     (tuple 'ok bidi-handle))
    ((tuple 'ok ws-url 'undefined _next-id)
     (case (selenium_nif:bidi_open ws-url)
       (0 (tuple 'error (tuple -1 #"BiDi channel failed to open")))
       (bh (ets:update_element (bidi-table-name) handle (tuple 3 bh))
           (tuple 'ok bh))))
    ('error
     (tuple 'error (tuple 0 #"BiDi not available: unknown session handle")))))

;; Atomic monotonic per-channel command id (field 4 in the ETS row), from 1.
(defun bidi-next-id (handle)
  (- (ets:update_counter (bidi-table-name) handle (tuple 4 1)) 1))

(defun bidi-shutdown (handle)
  (case (bidi-lookup handle)
    ((tuple 'ok _ws-url bidi-handle _next-id) (when (=/= bidi-handle 'undefined))
     (selenium_nif:bidi_close bidi-handle))
    (_ 'ok))
  (case (ets:info (bidi-table-name) 'name)
    ('undefined 'ok)
    (_ (ets:delete (bidi-table-name) handle) 'ok)))

(defun join-events (events)
  (if (is_list events)
      (lists:join #"," (lists:map (lambda (e) (to-bin e)) events))
      (to-bin events)))

(defun ack
  ((#"") #M())
  ((raw) (decode raw)))

;; ---- pure engine helpers / By decode ----

(defun decode-by (by value)
  (decode (selenium_nif:by_locator (to-bin by) (to-bin value))))

(defun to-bin
  ((b) (when (is_binary b)) b)
  ((l) (when (is_list l)) (unicode:characters_to_binary l))
  ((a) (when (is_atom a)) (atom_to_binary a 'utf8)))

;; ==== minimal JSON (maps with binary keys <-> JSON) ====
;;
;; Mirrors the Erlang twin's codec (erlang/src/selenium.erl). Works on the
;; binary by 0-based index with binary:at/2 + binary:part/2 — plain function
;; calls, no fragile binary-literal pattern matching. Decode returns the same
;; shapes as the twin: maps (binary keys), lists, binaries, integers, floats,
;; and the atoms 'null / 'true / 'false.

(defun encode (v) (iolist_to_binary (enc v)))

(defun enc (v)
  (cond
   ((=:= v 'null) #"null")
   ((=:= v 'true) #"true")
   ((=:= v 'false) #"false")
   ((is_binary v) (list #"\"" (esc v) #"\""))
   ((is_integer v) (integer_to_binary v))
   ((is_float v) (float_to_binary v (list (tuple 'decimals 10) 'compact)))
   ((is_map v)
    (let ((pairs (lists:map
                  (lambda (kv)
                    (let ((`#(,k ,val) kv))
                      (list #"\"" (esc (to-bin k)) #"\":" (enc val))))
                  (maps:to_list v))))
      (list #"{" (lists:join #"," pairs) #"}")))
   ((is_list v)
    (list #"[" (lists:join #"," (lists:map (lambda (e) (enc e)) v)) #"]"))))

;; Escape the JSON-significant bytes. Runs char-by-char via a code-point list —
;; the payloads here are ASCII command params, and multibyte UTF-8 bytes pass
;; through unchanged (each >127 byte is emitted verbatim).
(defun esc (b)
  (iolist_to_binary
   (lists:map
    (lambda (c)
      (cond
       ((=:= c #\") #"\\\"")
       ((=:= c #\\) #"\\\\")
       ((=:= c 10) #"\\n")
       ((=:= c 13) #"\\r")
       ((=:= c 9) #"\\t")
       ('true c)))
    (binary_to_list b))))

;; ---- decode: index-based recursive descent ----

(defun decode (b)
  (let ((`#(,v ,_i) (dec b (skip-ws b 0))))
    v))

;; Return the first index >= I that is not whitespace.
(defun skip-ws (b i)
  (if (>= i (byte_size b))
      i
      (let ((c (binary:at b i)))
        (if (orelse (=:= c 32) (orelse (=:= c 9)
                    (orelse (=:= c 10) (=:= c 13))))
            (skip-ws b (+ i 1))
            i))))

;; dec/3 -> #(Value NextIndex). I points at the first non-ws byte of a value.
(defun dec (b i)
  (let ((c (binary:at b i)))
    (cond
     ((=:= c #\") (dec-str b (+ i 1) ()))
     ((=:= c #\{) (dec-obj b (skip-ws b (+ i 1)) #M()))
     ((=:= c #\[) (dec-arr b (skip-ws b (+ i 1)) ()))
     ((=:= c #\n) (tuple 'null (+ i 4)))    ; null
     ((=:= c #\t) (tuple 'true (+ i 4)))    ; true
     ((=:= c #\f) (tuple 'false (+ i 5)))   ; false
     ('true (dec-num b i i)))))

;; Accumulate string bytes (reversed code-point list in Acc) until the closing
;; quote. Returns #(Binary NextIndex).
(defun dec-str (b i acc)
  (let ((c (binary:at b i)))
    (cond
     ((=:= c #\") (tuple (list_to_binary (lists:reverse acc)) (+ i 1)))
     ((=:= c #\\)
      (let ((e (binary:at b (+ i 1))))
        (if (=:= e #\u)
            (let* ((hex (binary:part b (+ i 2) 4))
                   (cp (binary_to_integer hex 16)))
              (dec-str b (+ i 6) (append-utf8 acc cp)))
            (dec-str b (+ i 2) (cons (unesc e) acc)))))
     ('true (dec-str b (+ i 1) (cons c acc))))))

(defun unesc (e)
  (cond
   ((=:= e #\") #\")
   ((=:= e #\\) #\\)
   ((=:= e #\/) #\/)
   ((=:= e #\n) 10)
   ((=:= e #\r) 13)
   ((=:= e #\t) 9)
   ((=:= e #\b) 8)
   ((=:= e #\f) 12)
   ('true e)))

;; Prepend a code point to the reversed byte-accumulator as UTF-8 bytes (kept in
;; forward order among themselves so lists:reverse restores them correctly).
(defun append-utf8 (acc cp)
  (let ((bytes (binary_to_list (unicode:characters_to_binary (list cp)))))
    (lists:foldl (lambda (byte a) (cons byte a)) acc bytes)))

(defun dec-obj (b i m)
  (if (=:= (binary:at b i) #\})
      (tuple m (+ i 1))
      (let* ((`#(,key ,i1) (dec-str b (+ i 1) ()))   ; i points at opening quote
             (i2 (+ (skip-ws b i1) 1))               ; past the ':'
             (`#(,val ,i3) (dec b (skip-ws b i2)))
             (m2 (maps:put key val m))
             (i4 (skip-ws b i3)))
        (if (=:= (binary:at b i4) #\,)
            (dec-obj b (skip-ws b (+ i4 1)) m2)
            (tuple m2 (+ i4 1))))))                   ; the '}'

(defun dec-arr (b i l)
  (if (=:= (binary:at b i) #\])
      (tuple (lists:reverse l) (+ i 1))
      (let* ((`#(,v ,i1) (dec b i))
             (i2 (skip-ws b i1)))
        (if (=:= (binary:at b i2) #\,)
            (dec-arr b (skip-ws b (+ i2 1)) (cons v l))
            (tuple (lists:reverse (cons v l)) (+ i2 1))))))  ; the ']'

;; Scan a number token from Start; End is the first index past it.
(defun dec-num (b start i)
  (if (andalso (< i (byte_size b)) (num-byte? (binary:at b i)))
      (dec-num b start (+ i 1))
      (let ((tok (binary:part b start (- i start))))
        (tuple (parse-num tok) i))))

(defun num-byte? (c)
  (orelse (andalso (>= c #\0) (=< c #\9))
          (orelse (=:= c #\-) (orelse (=:= c #\+)
                  (orelse (=:= c #\.) (orelse (=:= c #\e) (=:= c #\E)))))))

(defun parse-num (tok)
  (case (binary:match tok (list #"." #"e" #"E"))
    ('nomatch (binary_to_integer tok))
    (_ (binary_to_float tok))))
