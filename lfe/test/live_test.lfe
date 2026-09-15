;;;; live_test.lfe — LIVE browser facts for the LFE binding.
;;;;
;;;; ffi_test/surface_test prove the shadow finders and the firefox factory are
;;;; EXPORTED — which stays green even when the code behind them is broken. This
;;;; drives real browsers through the engine (the same selenium_nif the Erlang
;;;; binding owns) so the shadow-DOM path and firefox() are actually executed.
;;;;
;;;; Both legs self-orchestrate via the engine's driver ABI (resolve_driver +
;;;; ensure_driver, docs/Driver-Orchestration-ABI.md) — no driver on PATH and no
;;;; Grid — and use data: pages, so no content server is needed.
(defmodule live_test
  (export (main 1)))

(defun main (_args)
  (let ((fails (+ (live-chrome-shadow) (live-firefox))))
    (if (=:= fails 0)
        (progn (io:format "PASS: LFE live tests green~n") (halt 0))
        (progn (io:format "FAILED: ~p LFE live test(s)~n" (list fails)) (halt 1)))))

;; Chrome: host an open shadow root, reach an element inside it, and confirm a
;; non-host element reports W3C code 19.
(defun live-chrome-shadow ()
  (case (selenium_lfe:resolve_driver #"chrome")
    (#"" (progn (io:format "  (live) SKIPPED: no chromedriver resolved~n") 0))
    (_path
     (let ((`#(ok ,dh) (selenium_lfe:ensure_driver #"chrome" #"" 20000)))
       (try
         (let ((`#(ok ,d) (selenium_lfe:headless_chrome (selenium_lfe:driver_url dh))))
           (try
             (+ (ck "chrome session started"
                    (> (byte_size (selenium_lfe:session_id d)) 0))
                (progn
                  (selenium_lfe:get d (++ "data:text/html,%3C!doctype%20html%3E"
                                          "%3Ctitle%3ELfeLive%3C/title%3E"
                                          "%3Ch1%20id=%22hdr%22%3Eplain%3C/h1%3E"
                                          "%3Cdiv%20id=%22host%22%3E%3C/div%3E"))
                  (ck "title" (=:= (selenium_lfe:title d) #(ok #"LfeLive"))))
                (progn
                  ;; ++ is list-only in Erlang; binaries join via iolist_to_binary.
                  (selenium_lfe:execute_script d
                    (erlang:iolist_to_binary
                     (list #"var h=document.getElementById('host');"
                           #"var r=h.attachShadow({mode:'open'});"
                           #"r.innerHTML='<p id=\"sinner\">lfe-shadow</p>';")))
                  (let* ((`#(ok ,host) (selenium_lfe:find_element d (selenium_lfe:by_id "host")))
                         (`#(ok ,sid) (selenium_lfe:shadow_root d host))
                         (`#(ok ,inner) (selenium_lfe:find_element_from_shadow_root
                                         d sid (selenium_lfe:by_css "#sinner")))
                         (`#(ok ,all) (selenium_lfe:find_elements_from_shadow_root
                                       d sid (selenium_lfe:by_css "p"))))
                    (+ (ck "shadow id is a non-empty binary"
                           (and (is_binary sid) (> (byte_size sid) 0)))
                       (ck "shadow findElement reaches inside the shadow root"
                           (=:= (selenium_lfe:element_text d inner) #(ok #"lfe-shadow")))
                       (ck "shadow findElements finds the inner <p>"
                           (=:= (length all) 1))
                       ;; A non-host element has no shadow root: W3C code 19.
                       (let ((`#(ok ,hdr) (selenium_lfe:find_element
                                           d (selenium_lfe:by_id "hdr"))))
                         (ck "non-host element -> code 19"
                             (case (selenium_lfe:shadow_root d hdr)
                               (`#(error #(19 ,_)) 'true)
                               (_ 'false))))))))
             (after (selenium_lfe:quit d))))
         (after (selenium_lfe:stop_driver dh)))))))

;; Firefox: a real headless session over the engine-managed geckodriver.
(defun live-firefox ()
  (case (selenium_lfe:resolve_driver #"firefox")
    (#"" (progn (io:format "  (live firefox) SKIPPED: no geckodriver resolved~n") 0))
    (_path
     (let ((`#(ok ,dh) (selenium_lfe:ensure_driver #"firefox" #"" 20000)))
       (try
         (let ((`#(ok ,d) (selenium_lfe:headless_firefox (selenium_lfe:driver_url dh))))
           (try
             (+ (ck "firefox session started"
                    (> (byte_size (selenium_lfe:session_id d)) 0))
                (progn
                  (selenium_lfe:get d (++ "data:text/html,%3C!doctype%20html%3E"
                                          "%3Ctitle%3EAether%20Firefox%3C/title%3E"
                                          "%3Ch1%20id=%22hdr%22%3EHello%20FF%3C/h1%3E"))
                  (ck "firefox title" (=:= (selenium_lfe:title d) #(ok #"Aether Firefox"))))
                (let ((`#(ok ,hdr) (selenium_lfe:find_element d (selenium_lfe:by_id "hdr"))))
                  (ck "firefox element text"
                      (=:= (selenium_lfe:element_text d hdr) #(ok #"Hello FF")))))
             (after (selenium_lfe:quit d))))
         (after (selenium_lfe:stop_driver dh)))))))

(defun ck (label cond)
  (if cond
      (progn (io:format "  ok: ~s~n" (list label)) 0)
      (progn (io:format "FAIL: ~s~n" (list label)) 1)))
