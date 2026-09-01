;;;; selenium.lfe — idiomatic LFE (Lisp Flavoured Erlang) over the shared NIF.
;;;;
;;;; There is NO second FFI here. The one BEAM binding to the shared Aether
;;;; WebDriver engine is the Erlang NIF `selenium_nif` (owned by erlang/, built
;;;; once as the OTP app; priv/selenium_nif.so links the engine). Everything here
;;;; is ordinary LFE-on-BEAM interop calling that module — exactly as Elixir and
;;;; Gleam ride the SAME NIF (no second C source, no second .so). An LFE-specific
;;;; FFI would be a second copy of the marshalling rules to keep in sync with
;;;; selenium_core/embed.ae.
(defmodule selenium
  (export
   ;; pure engine helpers (no session) — shared with every binding
   (route 1)
   (error-code 1)
   (locator 2)
   ;; Selenium-style By factory (returns {Strategy, Value} locator tuples)
   (by-id 1)
   (by-name 1)
   (by-class-name 1)
   (by-css 1)
   (by-tag-name 1)
   (by-link-text 1)
   (by-partial-link-text 1)
   (by-xpath 1)
   ;; session lifecycle
   (open 1)
   (execute 3)
   (find-element 2)
   (last-value 1)
   (last-error-code 1)
   (session-id 1)
   (close 1)))

(defun w3c-element-key () #"element-6066-11e4-a52e-4f735466cecf")

;; ---- pure helpers (delegate straight to the NIF) ----

(defun route (command)
  (selenium_nif:route (to-bin command)))

(defun error-code (w3c-error)
  (selenium_nif:error_code (to-bin w3c-error)))

(defun locator (by value)
  (selenium_nif:by_locator (to-bin by) (to-bin value)))

;; ---- By factory (Selenium-style) ----
;; Each returns a #(Strategy Value) locator tuple that find-element/2 accepts,
;; mirroring Selenium's By.id(...)/By.className(...). class-name maps to the
;; W3C "class name" (matching every other Selenium binding).

(defun by-id (value) (tuple #"id" (to-bin value)))
(defun by-name (value) (tuple #"name" (to-bin value)))
(defun by-class-name (value) (tuple #"class name" (to-bin value)))
(defun by-css (value) (tuple #"css selector" (to-bin value)))
(defun by-tag-name (value) (tuple #"tag name" (to-bin value)))
(defun by-link-text (value) (tuple #"link text" (to-bin value)))
(defun by-partial-link-text (value) (tuple #"partial link text" (to-bin value)))
(defun by-xpath (value) (tuple #"xpath" (to-bin value)))

;; ---- session ----

(defun open (base-url)
  (selenium_nif:open (to-bin base-url)))

(defun execute (handle command params-json)
  (selenium_nif:execute handle (to-bin command) (to-bin params-json)))

;; Selenium-style one-arg find: pass a #(Strategy Value) locator from the by-*
;; factory. Returns #(ok ElementId) | #(error #(Code Msg)). The locator NIF
;; yields the W3C {"using","value"} JSON, which is exactly the findElement
;; params; the element reference is extracted from the response value.
(defun find-element (handle locator)
  (let* ((`#(,strategy ,value) locator)
         (params (selenium_nif:by_locator (to-bin strategy) (to-bin value)))
         (rc (selenium_nif:execute handle #"findElement" params)))
    (if (=:= rc 0)
        (extract-element-id (selenium_nif:last_value handle))
        (tuple 'error (tuple (selenium_nif:last_error_code handle)
                             (selenium_nif:last_error handle))))))

;; Pull the element-reference id out of a findElement value JSON binary. The
;; value looks like {"element-6066-...":"<id>"}; a small textual extraction
;; keeps this dependency-free (mirrors the Gleam binding).
(defun extract-element-id (json)
  (let ((needle (erlang:iolist_to_binary
                  (list #"\"" (w3c-element-key) #"\":\""))))
    (case (binary:split json needle)
      (`(,_ ,rest)
       (case (binary:split rest #"\"")
         (`(,id ,_) (tuple 'ok id))
         (_ (tuple 'error (tuple 17 #"element reference key missing")))))
      (_ (tuple 'error (tuple 17 #"element reference key missing"))))))

(defun last-value (handle)
  (selenium_nif:last_value handle))

(defun last-error-code (handle)
  (selenium_nif:last_error_code handle))

(defun session-id (handle)
  (selenium_nif:session_id handle))

(defun close (handle)
  (selenium_nif:close handle))

;; ---- internals ----

(defun to-bin
  ((b) (when (is_binary b)) b)
  ((l) (when (is_list l)) (list_to_binary l))
  ((a) (when (is_atom a)) (atom_to_binary a 'utf8)))
