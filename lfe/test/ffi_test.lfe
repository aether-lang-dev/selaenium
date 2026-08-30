;;;; ffi_test.lfe — no-browser FFI facts for the LFE binding.
;;;;
;;;; Proves the LFE binding drives the ONE Erlang NIF (selenium_nif) — no second
;;;; FFI — and that the shared engine helpers marshal correctly over the BEAM.
;;;; A plain `(main args)` conformance runner (erlc-alike run via -eval), no test
;;;; framework. The NIF .so is resolved via ERL_LIBS (the erlang/.build.ae app).
(defmodule ffi_test
  (export (main 1)))

(defun main (_args)
  (let ((fails (+ (ck "route get"
                      (=:= (selenium:route "get") #"POST /session/:sessionId/url"))
                  (ck "route unknown"
                      (=:= (selenium:route "nope") #""))
                  (ck "errorCode no such element"
                      (=:= (selenium:error-code "no such element") 17))
                  (ck "errorCode success"
                      (=:= (selenium:error-code "") 0))
                  (ck "locator css"
                      (=:= (selenium:locator "css selector" "div.foo")
                           #"{\"using\":\"css selector\",\"value\":\"div.foo\"}"))
                  (ck "locator id rewrite"
                      (=/= (binary:match (selenium:locator "id" "main") #"*[id=")
                           'nomatch)))))
    (if (=:= fails 0)
        (progn (io:format "PASS: LFE FFI tests green~n") (halt 0))
        (progn (io:format "FAILED: ~p LFE FFI test(s)~n" (list fails)) (halt 1)))))

;; return 0 on pass, 1 on fail (sum in main — no mutable state).
(defun ck (label cond)
  (if cond
      (progn (io:format "  ok: ~s~n" (list label)) 0)
      (progn (io:format "FAIL: ~s~n" (list label)) 1)))
