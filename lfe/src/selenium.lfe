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
   ;; session lifecycle
   (open 1)
   (execute 3)
   (last-value 1)
   (last-error-code 1)
   (session-id 1)
   (close 1)))

;; ---- pure helpers (delegate straight to the NIF) ----

(defun route (command)
  (selenium_nif:route (to-bin command)))

(defun error-code (w3c-error)
  (selenium_nif:error_code (to-bin w3c-error)))

(defun locator (by value)
  (selenium_nif:by_locator (to-bin by) (to-bin value)))

;; ---- session ----

(defun open (base-url)
  (selenium_nif:open (to-bin base-url)))

(defun execute (handle command params-json)
  (selenium_nif:execute handle (to-bin command) (to-bin params-json)))

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
