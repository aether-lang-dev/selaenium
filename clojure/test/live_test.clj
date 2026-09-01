(ns live-test
  "FFI + live surface test for the Clojure binding — pure JVM interop over the
  one Java FFM binding (no second FFI). Run via clojure/.tests.ae. The live test
  needs chromedriver + a content server (started here via com.sun.net.httpserver
  and ProcessBuilder); skips if chromedriver is absent."
  (:require [selenium :as sel])
  (:import [org.openqa.selenium WebDriverException NoSuchElementException]
           [com.sun.net.httpserver HttpServer HttpHandler]
           [java.net InetSocketAddress ServerSocket Socket InetAddress]
           [java.nio.charset StandardCharsets]
           [java.util Base64]
           [java.io File]))

(def ^:private failures (atom 0))

(defn- check [cond label]
  (if cond
    (println "  ok:" label)
    (do (println "FAIL:" label) (swap! failures inc))))

(def page-one
  (str "<!doctype html><title>Page One</title><h1 id=\"hdr\">One</h1>"
       "<a id=\"go\" href=\"/two\">to two</a>"
       "<button id=\"btn\" onclick=\"document.getElementById('hdr').textContent='clicked'\">b</button>"))
(def page-two "<!doctype html><title>Page Two</title><h1 id=\"hdr\">Two</h1>")

(defn- which [cmd]
  (some (fn [dir]
          (let [f (File. dir cmd)]
            (when (and (.canExecute f) (not (.isDirectory f))) (.getAbsolutePath f))))
        (.split (or (System/getenv "PATH") "") ":")))

(defn- free-port []
  (with-open [s (ServerSocket. 0 0 (InetAddress/getByName "127.0.0.1"))]
    (.getLocalPort s)))

(defn- wait-up [port timeout-ms]
  (let [deadline (+ (System/currentTimeMillis) timeout-ms)]
    (loop []
      (if (< (System/currentTimeMillis) deadline)
        (if (try (.close (Socket. "127.0.0.1" port)) true (catch Exception _ false))
          true
          (do (Thread/sleep 100) (recur)))
        false))))

(defn- content-server []
  (let [server (HttpServer/create (InetSocketAddress. "127.0.0.1" 0) 0)]
    (.createContext server "/"
      (reify HttpHandler
        (handle [_ ex]
          (let [body (.getBytes (if (.startsWith (.getPath (.getRequestURI ex)) "/two") page-two page-one)
                                StandardCharsets/UTF_8)]
            (.add (.getResponseHeaders ex) "Content-Type" "text/html; charset=utf-8")
            (.sendResponseHeaders ex 200 (alength body))
            (with-open [os (.getResponseBody ex)] (.write os body))))))
    (.start server)
    server))

(defn- live-surface [driver-bin]
  (let [web (content-server)
        base (str "http://127.0.0.1:" (.getPort (.getAddress web)))
        cd-port (free-port)
        cd (.start (doto (ProcessBuilder. [driver-bin (str "--port=" cd-port)])
                     (.redirectOutput java.lang.ProcessBuilder$Redirect/DISCARD)
                     (.redirectError java.lang.ProcessBuilder$Redirect/DISCARD)))]
    (try
      (if-not (wait-up cd-port 10000)
        (println "  (live) SKIPPED: chromedriver did not come up")
        (sel/with-chrome [d (str "http://127.0.0.1:" cd-port)]
          (check (pos? (count (sel/session-id d))) "session started")

          (sel/navigate d (str base "/one"))
          (check (= "Page One" (sel/get-title d)) "title")
          (check (= "One" (sel/text (sel/find-element d :id "hdr"))) "hdr text")
          (check (= "a" (.toLowerCase (sel/tag-name (sel/find-element d :css "#go")))) "tag name")

          ;; navigation
          (sel/click (sel/find-element d :id "go"))
          (check (= "Page Two" (sel/get-title d)) "after click")
          (sel/back d) (check (= "Page One" (sel/get-title d)) "after back")
          (sel/forward d) (check (= "Page Two" (sel/get-title d)) "after forward")
          (sel/back d)

          ;; cookies
          (sel/delete-all-cookies d)
          (sel/add-cookie d {:name "flavor" :value "mint"})
          (check (= "mint" (.get (sel/cookie d "flavor") "value")) "cookie value")
          (sel/delete-cookie d "flavor")

          ;; windows
          (check (pos? (count (sel/window-handles d))) "window handles")
          (sel/set-window-rect d {:width 900 :height 650})
          (check (= 900 (.intValue (.get (sel/window-rect d) "width"))) "window width")

          ;; script shapes
          (check (= 42 (.intValue (sel/execute-script d "return 6*7;"))) "script scalar")
          (check (= 42 (.intValue (sel/execute-script d "return arguments[0]+arguments[1];" 40 2))) "script args")

          ;; W3C actions
          (let [r (sel/element-rect (sel/find-element d :id "btn"))
                cx (int (+ (.doubleValue (.get r "x")) (/ (.doubleValue (.get r "width")) 2)))
                cy (int (+ (.doubleValue (.get r "y")) (/ (.doubleValue (.get r "height")) 2)))]
            (sel/perform-actions d
              [{:type "pointer" :id "mouse"
                :parameters {:pointerType "mouse"}
                :actions [{:type "pointerMove" :duration 0 :x cx :y cy}
                          {:type "pointerDown" :button 0}
                          {:type "pointerUp" :button 0}]}]))
          (check (= "clicked" (sel/text (sel/find-element d :id "hdr"))) "actions click fired")
          (sel/clear-actions d)

          ;; screenshot
          (let [png (.decode (Base64/getDecoder) (sel/screenshot-base64 d))]
            (check (and (> (alength png) 8) (= (byte \P) (aget png 1)) (= (byte \N) (aget png 2))) "screenshot is PNG"))

          ;; negative path
          (let [nse (try (sel/find-element d :id "does-not-exist") false
                         (catch NoSuchElementException _ true))]
            (check nse "no such element error"))))
      (finally
        (.destroy cd)
        (.stop web 0)))))

(defn -main [& _]
  (check (= "POST /session/:sessionId/url" (sel/route "get")) "route get")
  (check (= 17 (sel/error-code "no such element")) "errorCode no such element")
  (check (.contains (sel/locator :id "main") "*[id=") "locator id rewrite")
  (let [threw (try (sel/chrome "http://127.0.0.1:1") false
                   (catch WebDriverException e (= -1 (.code e))))]
    (check threw "transport failure -> code -1"))

  (if-let [driver-bin (which "chromedriver")]
    (live-surface driver-bin)
    (println "  (live) SKIPPED: chromedriver not on PATH"))

  (if (zero? @failures)
    (println "PASS: Clojure tests green")
    (do (println "FAILED:" @failures "Clojure test(s)") (System/exit 1))))
