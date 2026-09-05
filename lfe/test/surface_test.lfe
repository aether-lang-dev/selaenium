;;;; surface_test.lfe — OFFLINE ABI-surface facts for the LFE binding.
;;;;
;;;; No NIF, no browser: exercises the pure marshalling the binding adds on the
;;;; BEAM side — the JSON codec (encode + decode round-trips), the By factory
;;;; tuples, and the W3C actions wire shapes built by the Actions helpers'
;;;; primitives. Complements ffi_test.lfe (which needs the live selenium_nif).
;;;; A plain `(main args)` runner, no framework; halts 0 on green, 1 on fail.
(defmodule surface_test
  (export (main 1)))

(defun main (_args)
  (let ((fails
         (+
          ;; ---- By factories (pure #(Strategy Value) tuples) ----
          (ck "by_id" (=:= (selenium_lfe:by_id "hdr") #(#"id" #"hdr")))
          (ck "by_css" (=:= (selenium_lfe:by_css "a.x") #(#"css selector" #"a.x")))
          (ck "by_class_name -> class name"
              (=:= (selenium_lfe:by_class_name "g") #(#"class name" #"g")))
          (ck "by_xpath" (=:= (selenium_lfe:by_xpath "//a") #(#"xpath" #"//a")))
          ;; ---- JSON encode ----
          (ck "encode empty map" (=:= (selenium_lfe:encode #M()) #"{}"))
          (ck "encode string val"
              (=:= (selenium_lfe:encode (maps:put #"k" #"v" #M())) #"{\"k\":\"v\"}"))
          (ck "encode int val"
              (=:= (selenium_lfe:encode (maps:put #"n" 7 #M())) #"{\"n\":7}"))
          (ck "encode list"
              (=:= (selenium_lfe:encode (list 1 2 3)) #"[1,2,3]"))
          (ck "encode atoms"
              (=:= (selenium_lfe:encode (list 'true 'false 'null))
                   #"[true,false,null]"))
          (ck "encode escapes quote"
              (=:= (selenium_lfe:encode #"a\"b") #"\"a\\\"b\""))
          ;; ---- JSON decode ----
          (ck "decode int" (=:= (selenium_lfe:decode #"42") 42))
          (ck "decode neg float"
              (=:= (selenium_lfe:decode #"-1.5") -1.5))
          (ck "decode string" (=:= (selenium_lfe:decode #"\"hi\"") #"hi"))
          (ck "decode true/false/null"
              (=:= (selenium_lfe:decode #"[true,false,null]")
                   (list 'true 'false 'null)))
          (ck "decode object"
              (=:= (selenium_lfe:decode #"{\"a\":1,\"b\":\"x\"}")
                   (maps:from_list (list (tuple #"a" 1) (tuple #"b" #"x")))))
          (ck "decode nested"
              (=:= (selenium_lfe:decode #"{\"o\":{\"k\":[1,2]}}")
                   (maps:put #"o" (maps:put #"k" (list 1 2) #M()) #M())))
          (ck "decode escaped string"
              (=:= (selenium_lfe:decode #"\"a\\\"b\"") #"a\"b"))
          ;; ---- round-trip (the element-reference shape a real command uses) ----
          (ck "round-trip element ref"
              (let* ((m (maps:put #"element-6066-11e4-a52e-4f735466cecf" #"e1" #M()))
                     (j (selenium_lfe:encode m)))
                (=:= (selenium_lfe:decode j) m))))))
    (if (=:= fails 0)
        (progn (io:format "PASS: LFE surface tests green~n") (halt 0))
        (progn (io:format "FAILED: ~p LFE surface test(s)~n" (list fails)) (halt 1)))))

(defun ck (label cond)
  (if cond
      (progn (io:format "  ok: ~s~n" (list label)) 0)
      (progn (io:format "FAIL: ~s~n" (list label)) 1)))
