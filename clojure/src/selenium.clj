(ns selenium-core
  "Selenium WebDriver for Clojure, over the shared Aether engine.

  There is NO second FFI here. The one JVM binding to the shared engine is the
  Java FFM binding (org.seleniumhq.aether.*); this namespace is ordinary
  Clojure/Java interop on top of those classes — exactly as one Java jar backs
  the whole JVM family (Kotlin/Scala/Clojure/Groovy). A Clojure-specific FFI
  would be a second copy of the marshalling rules to keep in sync with the
  engine, and the first thing to drift.

  What Clojure adds: keyword-friendly `by`, a `with-chrome` macro that quits the
  session on exit, and value-returning functions over the Java methods. Command
  params are Clojure maps (converted to java.util.Map); results come back as the
  Java binding decodes them (java.util.Map / java.util.List / String / ...)."
  (:import [org.seleniumhq.aether WebDriver WebElement By WebDriverError]
           [java.util Map List]))

;; ---- By strategies as keywords ----
(def by
  {:id By/ID
   :name By/NAME
   :css By/CSS_SELECTOR
   :class-name By/CLASS_NAME
   :tag-name By/TAG_NAME
   :link-text By/LINK_TEXT
   :partial-link-text By/PARTIAL_LINK_TEXT
   :xpath By/XPATH})

(defn- by* [k] (if (keyword? k) (get by k (name k)) k))

;; ---- Clojure map/seq -> java.util for the Java binding ----
(defn- ->java [v]
  (cond
    (map? v) (let [m (java.util.HashMap.)]
               (doseq [[k val] v] (.put m (if (keyword? k) (name k) (str k)) (->java val)))
               m)
    (sequential? v) (java.util.ArrayList. (map ->java v))
    :else v))

;; ---- pure engine helpers ----
(defn route [command] (WebDriver/route command))
(defn error-code [w3c-error] (WebDriver/errorCode w3c-error))
(defn locator [by-kw value] (WebDriver/locator (by* by-kw) value))

;; ---- session lifecycle ----
(defn chrome
  "Start a Chrome session. `opts` is a map of extra capabilities."
  ([command-executor] (chrome command-executor {}))
  ([command-executor opts] (WebDriver/chrome command-executor (->java opts))))

(defn headless-chrome [command-executor]
  (chrome command-executor
          {"goog:chromeOptions"
           {"args" ["--headless=new" "--no-sandbox" "--disable-gpu" "--disable-dev-shm-usage"]}}))

(defn quit [^WebDriver d] (.quit d))
(defn session-id [^WebDriver d] (.sessionId d))

(defmacro with-chrome
  "Bind a headless Chrome session to `binding`, run `body`, and quit on exit."
  [[binding command-executor] & body]
  `(let [~binding (headless-chrome ~command-executor)]
     (try ~@body (finally (quit ~binding)))))

;; ---- navigation ----
(defn navigate [^WebDriver d url] (.get d url))
(defn title [^WebDriver d] (.title d))
(defn current-url [^WebDriver d] (.currentUrl d))
(defn back [^WebDriver d] (.back d))
(defn forward [^WebDriver d] (.forward d))
(defn refresh [^WebDriver d] (.refresh d))

;; ---- elements ----
(defn find-element [^WebDriver d by-kw value] (.findElement d (by* by-kw) value))
(defn find-elements [^WebDriver d by-kw value] (.findElements d (by* by-kw) value))
(defn click [^WebElement e] (.click e))
(defn text [^WebElement e] (.text e))
(defn tag-name [^WebElement e] (.tagName e))
(defn element-rect [^WebElement e] (.rect e))
(defn send-keys [^WebElement e s] (.sendKeys e s))
(defn get-property [^WebElement e name] (.getProperty e name))

;; ---- script ----
(defn execute-script [^WebDriver d script & args]
  (.executeScript d script (into-array Object (map ->java args))))

;; ---- windows ----
(defn window-handles [^WebDriver d] (.windowHandles d))
(defn current-window-handle [^WebDriver d] (.currentWindowHandle d))
(defn set-window-rect [^WebDriver d rect] (.setWindowRect d (->java rect)))
(defn window-rect [^WebDriver d] (.getWindowRect d))

;; ---- cookies ----
(defn add-cookie [^WebDriver d cookie] (.addCookie d (->java cookie)))
(defn cookies [^WebDriver d] (.getCookies d))
(defn cookie [^WebDriver d name] (.getCookie d name))
(defn delete-cookie [^WebDriver d name] (.deleteCookie d name))
(defn delete-all-cookies [^WebDriver d] (.deleteAllCookies d))

;; ---- actions ----
(defn perform-actions [^WebDriver d actions] (.performActions d (->java actions)))
(defn clear-actions [^WebDriver d] (.clearActions d))

;; ---- screenshots ----
(defn screenshot-base64 [^WebDriver d] (.screenshotBase64 d))
