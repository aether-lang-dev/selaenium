(ns selenium
  "Selenium WebDriver for Clojure, over the shared Aether engine.

  There is NO second FFI here. The one JVM binding to the shared engine is the
  Java FFM binding (org.openqa.selenium.*); this namespace is ordinary
  Clojure/Java interop on top of those classes — exactly as one Java jar backs
  the whole JVM family (Kotlin/Scala/Clojure/Groovy). A Clojure-specific FFI
  would be a second copy of the marshalling rules to keep in sync with the
  engine, and the first thing to drift.

  What Clojure adds: keyword-friendly `by`, a `with-chrome` macro that quits the
  session on exit, and value-returning functions over the Java methods. Command
  params are Clojure maps (converted to java.util.Map); results come back as the
  Java binding decodes them (java.util.Map / java.util.List / String / ...)."
  (:import [org.openqa.selenium RemoteWebDriver WebElement By
            WebDriverException NoSuchElementException]
           [java.util Map List]))

;; ---- By strategies as keywords ----
;; Selenium 4.x's By is a FACTORY: each strategy is a static method returning a
;; By locator instance. `by` maps a keyword to the matching factory fn; `by*`
;; produces a By instance for one-arg findElement/findElements.
(def by
  {:id #(By/id %)
   :name #(By/name %)
   :css #(By/cssSelector %)
   :css-selector #(By/cssSelector %)
   :class-name #(By/className %)
   :tag-name #(By/tagName %)
   :link-text #(By/linkText %)
   :partial-link-text #(By/partialLinkText %)
   :xpath #(By/xpath %)})

(defn- by* [k value]
  (if (instance? By k)
    k
    (let [f (get by k)]
      (if f (f value) (throw (IllegalArgumentException. (str "unknown By strategy: " k)))))))

;; ---- Clojure map/seq -> java.util for the Java binding ----
(defn- ->java [v]
  (cond
    (map? v) (let [m (java.util.HashMap.)]
               (doseq [[k val] v] (.put m (if (keyword? k) (name k) (str k)) (->java val)))
               m)
    (sequential? v) (java.util.ArrayList. (map ->java v))
    :else v))

;; ---- pure engine helpers ----
(defn route [command] (RemoteWebDriver/route command))
(defn error-code [w3c-error] (RemoteWebDriver/errorCode w3c-error))
(defn locator [strategy value] (RemoteWebDriver/locator (name strategy) value))

;; ---- session lifecycle ----
(defn chrome
  "Start a Chrome session. `opts` is a map of extra capabilities."
  ([command-executor] (chrome command-executor {}))
  ([command-executor opts] (RemoteWebDriver/chrome command-executor (->java opts))))

(defn headless-chrome [command-executor]
  (chrome command-executor
          {"goog:chromeOptions"
           {"args" ["--headless=new" "--no-sandbox" "--disable-gpu" "--disable-dev-shm-usage"]}}))

(defn quit [^RemoteWebDriver d] (.quit d))
(defn session-id [^RemoteWebDriver d] (.sessionId d))

(defmacro with-chrome
  "Bind a headless Chrome session to `binding`, run `body`, and quit on exit."
  [[binding command-executor] & body]
  `(let [~binding (headless-chrome ~command-executor)]
     (try ~@body (finally (quit ~binding)))))

;; ---- navigation ----
(defn navigate [^RemoteWebDriver d url] (.get d url))
(defn get-title [^RemoteWebDriver d] (.getTitle d))
(defn get-current-url [^RemoteWebDriver d] (.getCurrentUrl d))
(defn back [^RemoteWebDriver d] (.back d))
(defn forward [^RemoteWebDriver d] (.forward d))
(defn refresh [^RemoteWebDriver d] (.refresh d))

;; ---- elements ----
(defn find-element [^RemoteWebDriver d by-kw value] (.findElement d (by* by-kw value)))
(defn find-elements [^RemoteWebDriver d by-kw value] (.findElements d (by* by-kw value)))
(defn click [^WebElement e] (.click e))
(defn text [^WebElement e] (.getText e))
(defn tag-name [^WebElement e] (.getTagName e))
(defn element-rect [^WebElement e] (.rect e))
(defn send-keys [^WebElement e s] (.sendKeys e s))
(defn get-property [^WebElement e name] (.getProperty e name))

;; ---- script ----
(defn execute-script [^RemoteWebDriver d script & args]
  (.executeScript d script (into-array Object (map ->java args))))

;; ---- windows ----
(defn window-handles [^RemoteWebDriver d] (.windowHandles d))
(defn current-window-handle [^RemoteWebDriver d] (.currentWindowHandle d))
(defn set-window-rect [^RemoteWebDriver d rect] (.setWindowRect d (->java rect)))
(defn window-rect [^RemoteWebDriver d] (.getWindowRect d))

;; ---- cookies ----
(defn add-cookie [^RemoteWebDriver d cookie] (.addCookie d (->java cookie)))
(defn cookies [^RemoteWebDriver d] (.getCookies d))
(defn cookie [^RemoteWebDriver d name] (.getCookie d name))
(defn delete-cookie [^RemoteWebDriver d name] (.deleteCookie d name))
(defn delete-all-cookies [^RemoteWebDriver d] (.deleteAllCookies d))

;; ---- actions ----
(defn perform-actions [^RemoteWebDriver d actions] (.performActions d (->java actions)))
(defn clear-actions [^RemoteWebDriver d] (.clearActions d))

;; ---- screenshots ----
(defn screenshot-base64 [^RemoteWebDriver d] (.screenshotBase64 d))
