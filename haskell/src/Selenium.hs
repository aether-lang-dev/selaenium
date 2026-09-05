-- | Selenium WebDriver for Haskell, over the shared pure-Aether engine.
--
-- Carries NO protocol logic: the W3C command map, routing, By normalization,
-- error decode and HTTP round-trip all live in the Aether engine, reached
-- through "Selenium.Native" (which links @libselenium_core.so@). This module
-- marshals strings across the boundary.
--
-- Command params are passed as JSON strings (build them with @aeson@ if you
-- like), and command results come back as the raw JSON string of the response
-- @value@ — keeping the binding dependency-light (base + bytestring only). The
-- engine is the source of truth for every wire shape.
--
-- Element commands take the opaque W3C element id string ('findElement'
-- returns) as their first argument, mirroring the reference bindings' one-arg
-- @findElement@ + element-scoped verbs.
module Selenium
  ( WebDriver
  , WebDriverError (..)
  , By (..)
  , byString
  , Locator (..)
  , byId
  , byName
  , byCss
  , byClassName
  , byTagName
  , byLinkText
  , byPartialLinkText
  , byXpath
    -- * Session lifecycle
  , chrome
  , headlessChrome
  , execute
  , sessionId
  , quit
    -- * Navigation
  , get
  , currentUrl
  , title
  , pageSource
  , back
  , forward
  , refresh
    -- * Elements
  , findElement
  , findElements
  , findChildElement
  , findChildElements
  , activeElement
  , exists
  , elementClick
  , elementClear
  , elementSendKeys
  , elementText
  , elementTagName
  , elementIsEnabled
  , elementIsSelected
  , elementRect
  , getDomAttribute
  , getProperty
  , getAttribute
  , isDisplayed
  , cssValue
  , valueOfCssProperty
  , elementScreenshot
  , submit
  , findRelative
  , findRelativeCount
    -- * Script
  , executeScript
  , executeAsyncScript
    -- * Windows
  , windowHandles
  , currentWindowHandle
  , switchToWindow
  , newWindow
  , closeWindow
  , getWindowRect
  , setWindowRect
  , maximizeWindow
  , minimizeWindow
  , fullscreenWindow
    -- * Frames
  , Frame (..)
  , switchToFrame
  , switchToParentFrame
  , switchToDefaultContent
    -- * Alerts
  , acceptAlert
  , dismissAlert
  , alertText
  , sendAlertText
  , alertPresent
    -- * Cookies
  , addCookie
  , getCookies
  , getCookie
  , deleteCookie
  , deleteAllCookies
    -- * Actions
  , performActions
  , clearActions
    -- * Timeouts
  , setTimeouts
  , setPageLoadTimeout
  , setScriptTimeout
  , implicitlyWait
    -- * Screenshots / print
  , screenshotBase64
  , printPdf
    -- * Select helper
  , selectByVisibleText
  , selectByValue
  , selectByIndex
  , selectedOptions
  , firstSelectedOption
  , deselectAll
    -- * Waits
  , waitUntil
  , waitForElement
  , waitForTitleIs
  , waitForTitleContains
  , waitForUrlIs
  , waitForUrlContains
  , waitUntilGone
    -- * TLS trust config
  , setCa
  , setInsecure
    -- * Driver-process orchestration
  , DriverProcess
  , resolveDriver
  , browserBinary
  , ensureDriver
  , launchDriver
  , driverUrl
  , driverPid
  , stopDriver
    -- * WebDriver-BiDi
  , BiDi
  , bidiOpen
  , bidiClose
  , bidiSend
  , bidiPump
  , bidiFd
  , bidiPollReply
  , bidiPollEvent
  , bidiLostEvents
  , bidiCancel
  , bidiCommand
  , bidiSubscribe
  , bidiUnsubscribe
  , bidiWaitEvent
  , bidiGetTree
  , bidiScriptEvaluate
  , bidiNavigate
  , bidiAddIntercept
  , bidiRemoveIntercept
  , bidiContinueRequest
  , bidiFailRequest
  , bidiProvideResponse
  , bidiContinueWithAuth
  , bidiSetCacheBehavior
    -- * Pure engine helpers
  , route
  , errorCode
  , locator
  , keysChord
  ) where

import Control.Concurrent (threadDelay)
import Control.Exception (Exception, throwIO, try)
import Data.List (isInfixOf, isPrefixOf)
import Foreign.Ptr (Ptr, nullPtr)
import System.Environment (lookupEnv)

import qualified Selenium.Native as N

-- | A live WebDriver session.
newtype WebDriver = WebDriver (Ptr ())

-- | A protocol error: the engine's W3C code (0 success, -1 transport) + message.
data WebDriverError = WebDriverError
  { errCode :: Int
  , errMessage :: String
  }
  deriving (Show, Eq)

instance Exception WebDriverError

-- | Locator strategies.
data By = ById | ByName | ByCss | ByClassName | ByTagName | ByLinkText | ByPartialLinkText | ByXpath

byString :: By -> String
byString ById = "id"
byString ByName = "name"
byString ByCss = "css selector"
byString ByClassName = "class name"
byString ByTagName = "tag name"
byString ByLinkText = "link text"
byString ByPartialLinkText = "partial link text"
byString ByXpath = "xpath"

-- | A locator carrying a (strategy, value) pair — what the @by*@ smart
-- constructors return and what 'findElement' takes (Selenium 4.x one-arg find).
data Locator = Locator
  { locStrategy :: String
  , locValue :: String
  }
  deriving (Show, Eq)

-- Smart constructors mirroring Java's @By.id("x")@ etc. Each returns a
-- 'Locator'. @byClassName@ carries the W3C @"class name"@ strategy.
byId, byName, byCss, byClassName, byTagName, byLinkText, byPartialLinkText, byXpath
  :: String -> Locator
byId = Locator (byString ById)
byName = Locator (byString ByName)
byCss = Locator (byString ByCss)
byClassName = Locator (byString ByClassName)
byTagName = Locator (byString ByTagName)
byLinkText = Locator (byString ByLinkText)
byPartialLinkText = Locator (byString ByPartialLinkText)
byXpath = Locator (byString ByXpath)

w3cElementKey :: String
w3cElementKey = "element-6066-11e4-a52e-4f735466cecf"

-- ---- pure engine helpers ----

route :: String -> IO String
route = N.selRoute

errorCode :: String -> IO Int
errorCode = N.selErrorCode

-- | The @{"using","value"}@ locator JSON for a (by, value) pair.
locator :: By -> String -> IO String
locator by value = N.selByLocator (byString by) value

-- | Build a modifier chord string (e.g. @keysChord "\xE009" "a"@ for Ctrl+A):
-- the modifier, the text, then a trailing NULL key that releases held
-- modifiers — mirroring @Keys.chord@ in the reference bindings.
keysChord :: String -> String -> String
keysChord modifier text = modifier ++ text ++ "\xE000"

-- ---- session lifecycle ----

-- | Start a Chrome session. @capsJson@ is the alwaysMatch capabilities object
-- as a JSON string.
chrome :: String -> String -> IO WebDriver
chrome commandExecutor capsJson = do
  h <- N.selOpen commandExecutor
  if h == nullPtr
    then throwIO (WebDriverError (-1) "failed to open session handle")
    else do
      let d = WebDriver h
      _ <- execute d "newSession" ("{\"capabilities\":{\"alwaysMatch\":" ++ capsJson ++ "}}")
      pure d

-- | A headless Chrome session with the standard launch args. Honors
-- @SEL_CHROME_BINARY@ when set (a box with no system Chrome but a cached
-- Chrome-for-Testing), adding @goog:chromeOptions.binary@.
headlessChrome :: String -> IO WebDriver
headlessChrome commandExecutor = do
  mbin <- lookupEnv "SEL_CHROME_BINARY"
  let binField = case mbin of
        Just bin | not (null bin) -> ",\"binary\":\"" ++ bin ++ "\""
        _ -> ""
      args = "\"args\":[\"--headless=new\",\"--no-sandbox\",\"--disable-gpu\",\"--disable-dev-shm-usage\"]"
  chrome commandExecutor
    ("{\"browserName\":\"chrome\",\"goog:chromeOptions\":{" ++ args ++ binField ++ "}}")

-- | Execute a command by name with a JSON params object string. Returns the
-- response @value@ as a JSON string, or throws 'WebDriverError'.
execute :: WebDriver -> String -> String -> IO String
execute (WebDriver h) command paramsJson = do
  rc <- N.selExecute h command paramsJson
  if rc /= 0
    then do
      code <- N.selLastErrorCode h
      msg <- N.selLastError h
      if rc == (-1) && code == 0
        then throwIO (WebDriverError (-1) (if null msg then "transport failure" else msg))
        else throwIO (WebDriverError code msg)
    else N.selLastValue h

-- | @execute@ for commands whose response value we don't need — discards it.
execute_ :: WebDriver -> String -> String -> IO ()
execute_ d command paramsJson = execute d command paramsJson >> pure ()

-- ---- navigation ----

get :: WebDriver -> String -> IO ()
get d url = execute_ d "get" ("{\"url\":" ++ jsonStr url ++ "}")

currentUrl :: WebDriver -> IO String
currentUrl d = jsonUnquote <$> execute d "getCurrentUrl" "{}"

title :: WebDriver -> IO String
title d = jsonUnquote <$> execute d "getTitle" "{}"

pageSource :: WebDriver -> IO String
pageSource d = jsonUnquote <$> execute d "getPageSource" "{}"

back :: WebDriver -> IO ()
back d = execute_ d "goBack" "{}"

forward :: WebDriver -> IO ()
forward d = execute_ d "goForward" "{}"

refresh :: WebDriver -> IO ()
refresh d = execute_ d "refresh" "{}"

-- ---- elements ----

-- | Find one element by a 'Locator' (Selenium 4.x one-arg find):
--
-- > findElement d (byId "hdr")
--
-- Returns the opaque W3C element id string, or throws 'WebDriverError' 17 when
-- the response carries no element reference.
findElement :: WebDriver -> Locator -> IO String
findElement d (Locator strategy value) = do
  loc <- N.selByLocator strategy value
  v <- execute d "findElement" loc
  case extractElementId v of
    Just eid -> pure eid
    Nothing -> throwIO (WebDriverError 17 "element reference key missing")

-- | Find all elements matching a 'Locator'. Returns the list of element ids
-- (possibly empty).
findElements :: WebDriver -> Locator -> IO [String]
findElements d (Locator strategy value) = do
  loc <- N.selByLocator strategy value
  v <- execute d "findElements" loc
  pure (extractElementIds v)

-- | Find one descendant of @eid@ matching a 'Locator' (element-scoped
-- @findChildElement@).
findChildElement :: WebDriver -> String -> Locator -> IO String
findChildElement d eid (Locator strategy value) = do
  loc <- N.selByLocator strategy value
  -- The engine's findChildElement route takes the parent id plus the locator's
  -- using/value; merge the parent id into the locator object.
  v <- execute d "findChildElement" (mergeId eid loc)
  case extractElementId v of
    Just cid -> pure cid
    Nothing -> throwIO (WebDriverError 17 "element reference key missing")

-- | Find all descendants of @eid@ matching a 'Locator' (element-scoped
-- @findChildElements@).
findChildElements :: WebDriver -> String -> Locator -> IO [String]
findChildElements d eid (Locator strategy value) = do
  loc <- N.selByLocator strategy value
  v <- execute d "findChildElements" (mergeId eid loc)
  pure (extractElementIds v)

-- | The active (focused) element id (@getActiveElement@).
activeElement :: WebDriver -> IO String
activeElement d = do
  v <- execute d "getActiveElement" "{}"
  case extractElementId v of
    Just eid -> pure eid
    Nothing -> throwIO (WebDriverError 17 "element reference key missing")

-- | True if at least one element matching the locator is present right now — an
-- immediate presence check. A clean not-found resolves to @False@; a
-- transport-level failure still throws.
exists :: WebDriver -> Locator -> IO Bool
exists d loc = do
  r <- try (findElement d loc)
  case r of
    Right _ -> pure True
    Left e@(WebDriverError code _)
      | code == 17 -> pure False
      | otherwise -> throwIO e

elementClick :: WebDriver -> String -> IO ()
elementClick d eid = execute_ d "clickElement" ("{\"id\":" ++ jsonStr eid ++ "}")

elementClear :: WebDriver -> String -> IO ()
elementClear d eid = execute_ d "clearElement" ("{\"id\":" ++ jsonStr eid ++ "}")

-- | Type @text@ into the element. Sends both the whole string and the
-- character array the W3C @value@ field expects.
elementSendKeys :: WebDriver -> String -> String -> IO ()
elementSendKeys d eid text =
  execute_ d "sendKeysToElement"
    ("{\"id\":" ++ jsonStr eid ++ ",\"text\":" ++ jsonStr text
      ++ ",\"value\":" ++ jsonCharArray text ++ "}")

elementText :: WebDriver -> String -> IO String
elementText d eid = jsonUnquote <$> execute d "getElementText" ("{\"id\":" ++ jsonStr eid ++ "}")

elementTagName :: WebDriver -> String -> IO String
elementTagName d eid = jsonUnquote <$> execute d "getElementTagName" ("{\"id\":" ++ jsonStr eid ++ "}")

elementIsEnabled :: WebDriver -> String -> IO Bool
elementIsEnabled d eid = jsonBool <$> execute d "isElementEnabled" ("{\"id\":" ++ jsonStr eid ++ "}")

elementIsSelected :: WebDriver -> String -> IO Bool
elementIsSelected d eid = jsonBool <$> execute d "isElementSelected" ("{\"id\":" ++ jsonStr eid ++ "}")

-- | The element's bounding rect as the raw JSON string @{x,y,width,height}@.
elementRect :: WebDriver -> String -> IO String
elementRect d eid = execute d "getElementRect" ("{\"id\":" ++ jsonStr eid ++ "}")

-- | The literal DOM attribute (W3C @getDomAttribute@), no property fallback.
-- Returns the raw JSON value (a quoted string or @null@).
getDomAttribute :: WebDriver -> String -> String -> IO String
getDomAttribute d eid name =
  execute d "getDomAttribute" ("{\"id\":" ++ jsonStr eid ++ ",\"name\":" ++ jsonStr name ++ "}")

-- | The element's JS property (@getElementProperty@) as the raw JSON value.
getProperty :: WebDriver -> String -> String -> IO String
getProperty d eid name =
  execute d "getElementProperty" ("{\"id\":" ++ jsonStr eid ++ ",\"name\":" ++ jsonStr name ++ "}")

-- Drain an atom/relative rc (0 ok) the same way 'execute' drains a command rc:
-- the last_value JSON on success, a thrown 'WebDriverError' otherwise.
drainRc :: WebDriver -> Int -> IO String
drainRc (WebDriver h) rc
  | rc /= 0 = do
      code <- N.selLastErrorCode h
      msg <- N.selLastError h
      if rc == (-1) && code == 0
        then throwIO (WebDriverError (-1) (if null msg then "transport failure" else msg))
        else throwIO (WebDriverError code msg)
  | otherwise = N.selLastValue h

-- | The classic @getAttribute(name)@ (property-or-attribute semantics), via the
-- engine's dedicated @getAttribute@ atom (the ONE shared atom source). Returns
-- the raw JSON value (a quoted string or @null@).
getAttribute :: WebDriver -> String -> String -> IO String
getAttribute d@(WebDriver h) eid name = N.selGetAttribute h eid name >>= drainRc d

-- | Is the element displayed? Uses the engine's dedicated @isDisplayed@ atom.
isDisplayed :: WebDriver -> String -> IO Bool
isDisplayed d@(WebDriver h) eid = jsonBool <$> (N.selIsDisplayed h eid >>= drainRc d)

-- | Relative locators (@findElementsRelative@ atom): CSS candidates matching
-- @baseSel@, filtered by spatial relations. @filtersJson@ is a JSON array of
-- @{kind, sel[, dist]}@ with kind in above\/below\/left\/right\/near. Returns the
-- matching element-reference ids (nearest anchor first).
findRelative :: WebDriver -> String -> String -> IO [String]
findRelative d@(WebDriver h) baseSel filtersJson =
  extractElementIds <$> (N.selFindRelative h baseSel filtersJson >>= drainRc d)

-- | The number of elements matching a relative-locator query.
findRelativeCount :: WebDriver -> String -> String -> IO Int
findRelativeCount d baseSel filtersJson = length <$> findRelative d baseSel filtersJson

-- | The computed value of a CSS property (@getElementValueOfCssProperty@).
cssValue :: WebDriver -> String -> String -> IO String
cssValue d eid prop =
  jsonUnquote
    <$> execute d "getElementValueOfCssProperty"
          ("{\"id\":" ++ jsonStr eid ++ ",\"propertyName\":" ++ jsonStr prop ++ "}")

-- | Classic-Selenium-named alias of 'cssValue'.
valueOfCssProperty :: WebDriver -> String -> String -> IO String
valueOfCssProperty = cssValue

-- | A base64 PNG screenshot of just this element (@takeElementScreenshot@).
elementScreenshot :: WebDriver -> String -> IO String
elementScreenshot d eid =
  jsonUnquote <$> execute d "takeElementScreenshot" ("{\"id\":" ++ jsonStr eid ++ "}")

-- | Submit the form the element belongs to. W3C removed the dedicated @submit@
-- endpoint, so — like the reference binding and modern Selenium — this walks up
-- to the enclosing @<form>@ and calls @requestSubmit()@ (falling back to
-- @submit()@) via an injected script. Throws (code 13/other) if not in a form.
submit :: WebDriver -> String -> IO ()
submit d eid =
  let script =
        "var e=arguments[0];var f=e.form||e.closest('form');"
          ++ "if(!f){throw new Error('Element is not within a form');}"
          ++ "if(f.requestSubmit){f.requestSubmit();}else{f.submit();}"
      arg = "{" ++ jsonStr w3cElementKey ++ ":" ++ jsonStr eid ++ "}"
   in executeScript d script ("[" ++ arg ++ "]") >> pure ()

-- ---- script ----

-- | @executeScript d script argsJson@; @argsJson@ is a JSON array string.
executeScript :: WebDriver -> String -> String -> IO String
executeScript d script argsJson =
  execute d "executeScript" ("{\"script\":" ++ jsonStr script ++ ",\"args\":" ++ argsJson ++ "}")

-- | Run an async script: the page signals completion via the injected callback
-- (@arguments[arguments.length - 1]@). Returns the callback value.
executeAsyncScript :: WebDriver -> String -> String -> IO String
executeAsyncScript d script argsJson =
  execute d "executeAsyncScript" ("{\"script\":" ++ jsonStr script ++ ",\"args\":" ++ argsJson ++ "}")

-- ---- windows ----

windowHandles :: WebDriver -> IO [String]
windowHandles d = extractStrings <$> execute d "getWindowHandles" "{}"

currentWindowHandle :: WebDriver -> IO String
currentWindowHandle d = jsonUnquote <$> execute d "getCurrentWindowHandle" "{}"

switchToWindow :: WebDriver -> String -> IO ()
switchToWindow d handle = execute_ d "switchToWindow" ("{\"handle\":" ++ jsonStr handle ++ "}")

-- | Open a new top-level browsing context. @typeHint@ is @"tab"@ or @"window"@.
-- Returns the new window's handle (@""@ if the remote end sent none).
newWindow :: WebDriver -> String -> IO String
newWindow d typeHint = do
  v <- execute d "newWindow" ("{\"type\":" ++ jsonStr typeHint ++ "}")
  pure (extractField "handle" v)

-- | Close the current window/tab. Returns the remaining window handles.
closeWindow :: WebDriver -> IO [String]
closeWindow d = extractStrings <$> execute d "close" "{}"

getWindowRect :: WebDriver -> IO String
getWindowRect d = execute d "getWindowRect" "{}"

-- | Set the window rect. @rectJson@ is a @{x,y,width,height}@ JSON object.
setWindowRect :: WebDriver -> String -> IO String
setWindowRect d rectJson = execute d "setWindowRect" rectJson

maximizeWindow :: WebDriver -> IO String
maximizeWindow d = execute d "maximizeWindow" "{}"

minimizeWindow :: WebDriver -> IO String
minimizeWindow d = execute d "minimizeWindow" "{}"

fullscreenWindow :: WebDriver -> IO String
fullscreenWindow d = execute d "fullscreenWindow" "{}"

-- ---- frames ----

-- | A frame target for 'switchToFrame': by 0-based index, by @<iframe>@ element
-- id, or the top-level context.
data Frame = FrameIndex Int | FrameElement String | FrameDefault

frameIdJson :: Frame -> String
frameIdJson (FrameIndex i) = show i
frameIdJson (FrameElement eid) = "{" ++ jsonStr w3cElementKey ++ ":" ++ jsonStr eid ++ "}"
frameIdJson FrameDefault = "null"

-- | Switch focus to a frame. All subsequent element commands run inside the
-- chosen frame until the next frame switch.
switchToFrame :: WebDriver -> Frame -> IO ()
switchToFrame d frame = execute_ d "switchToFrame" ("{\"id\":" ++ frameIdJson frame ++ "}")

-- | Switch to the parent of the current frame (one level out).
switchToParentFrame :: WebDriver -> IO ()
switchToParentFrame d = execute_ d "switchToFrameParent" "{}"

-- | Return focus to the top-level browsing context.
switchToDefaultContent :: WebDriver -> IO ()
switchToDefaultContent d = switchToFrame d FrameDefault

-- ---- alerts ----

acceptAlert :: WebDriver -> IO ()
acceptAlert d = execute_ d "acceptAlert" "{}"

dismissAlert :: WebDriver -> IO ()
dismissAlert d = execute_ d "dismissAlert" "{}"

alertText :: WebDriver -> IO String
alertText d = jsonUnquote <$> execute d "getAlertText" "{}"

-- | Type @text@ into the current prompt dialog's input field.
sendAlertText :: WebDriver -> String -> IO ()
sendAlertText d text =
  execute_ d "setAlertValue" ("{\"text\":" ++ jsonStr text ++ ",\"value\":" ++ jsonCharArray text ++ "}")

-- | True if a user-prompt / alert dialog is currently present (probed via
-- @getAlertText@). A clean "no such alert" (code 15) resolves to @False@; a
-- transport-level failure still throws.
alertPresent :: WebDriver -> IO Bool
alertPresent d = do
  r <- try (execute d "getAlertText" "{}")
  case r of
    Right _ -> pure True
    Left e@(WebDriverError code _)
      | code == 15 -> pure False
      | otherwise -> throwIO e

-- ---- cookies ----

-- | Add a cookie. @cookieJson@ is a cookie object as a JSON string
-- (@{"name":...,"value":...}@ + optional fields).
addCookie :: WebDriver -> String -> IO ()
addCookie d cookieJson = execute_ d "addCookie" ("{\"cookie\":" ++ cookieJson ++ "}")

getCookies :: WebDriver -> IO String
getCookies d = execute d "getCookies" "{}"

getCookie :: WebDriver -> String -> IO String
getCookie d name = execute d "getCookie" ("{\"name\":" ++ jsonStr name ++ "}")

deleteCookie :: WebDriver -> String -> IO ()
deleteCookie d name = execute_ d "deleteCookie" ("{\"name\":" ++ jsonStr name ++ "}")

deleteAllCookies :: WebDriver -> IO ()
deleteAllCookies d = execute_ d "deleteAllCookies" "{}"

-- ---- actions ----

-- | Post a W3C @actions@ sequence. @actionsJson@ is the JSON array string of
-- input-source objects (pointer/key/wheel virtual devices).
performActions :: WebDriver -> String -> IO ()
performActions d actionsJson = execute_ d "actions" ("{\"actions\":" ++ actionsJson ++ "}")

clearActions :: WebDriver -> IO ()
clearActions d = execute_ d "clearActions" "{}"

-- ---- timeouts (all in milliseconds) ----

-- | Set timeouts from a raw @{implicit,pageLoad,script}@ JSON object.
setTimeouts :: WebDriver -> String -> IO ()
setTimeouts d timeoutsJson = execute_ d "setTimeout" timeoutsJson

setPageLoadTimeout :: WebDriver -> Int -> IO ()
setPageLoadTimeout d ms = execute_ d "setTimeout" ("{\"pageLoad\":" ++ show ms ++ "}")

setScriptTimeout :: WebDriver -> Int -> IO ()
setScriptTimeout d ms = execute_ d "setTimeout" ("{\"script\":" ++ show ms ++ "}")

implicitlyWait :: WebDriver -> Int -> IO ()
implicitlyWait d ms = execute_ d "setTimeout" ("{\"implicit\":" ++ show ms ++ "}")

-- ---- screenshots / print ----

screenshotBase64 :: WebDriver -> IO String
screenshotBase64 d = jsonUnquote <$> execute d "screenshot" "{}"

-- | Print the current page to PDF (@printPage@), returning base64. @optionsJson@
-- is the W3C print-options object, or @"{}"@ for defaults.
printPdf :: WebDriver -> String -> IO String
printPdf d optionsJson = jsonUnquote <$> execute d "printPage" optionsJson

-- ---- Select helper ----
-- Drives a <select> by finding + clicking its <option> children, the same way
-- mainstream Selenium's Select does (W3C has no dedicated select endpoint).

-- | All @<option>@ children of the @<select>@ element @eid@, in document order.
selectOptions :: WebDriver -> String -> IO [String]
selectOptions d eid = findChildElements d eid (byTagName "option")

-- | Select the option whose visible text equals @text@. Throws (code 17) if
-- none matches.
selectByVisibleText :: WebDriver -> String -> String -> IO ()
selectByVisibleText d eid text = do
  opts <- selectOptions d eid
  chooseBy d opts text elementText

-- | Select the option whose @value@ attribute equals @value@. Throws (code 17)
-- if none matches.
selectByValue :: WebDriver -> String -> String -> IO ()
selectByValue d eid value = do
  opts <- selectOptions d eid
  chooseBy d opts value (\drv o -> jsonUnquote <$> getDomAttribute drv o "value")

-- | Select the option at @index@ (0-based, document order). Throws (code 17) if
-- out of range.
selectByIndex :: WebDriver -> String -> Int -> IO ()
selectByIndex d eid index = do
  opts <- selectOptions d eid
  if index < 0 || index >= length opts
    then throwIO (WebDriverError 17 ("no option at index " ++ show index))
    else selectOption d (opts !! index)

-- | The option ids currently selected within the @<select>@ @eid@.
selectedOptions :: WebDriver -> String -> IO [String]
selectedOptions d eid = do
  opts <- selectOptions d eid
  filterM (elementIsSelected d) opts

-- | The first selected option id. Throws (code 17) if none is selected.
firstSelectedOption :: WebDriver -> String -> IO String
firstSelectedOption d eid = do
  sel <- selectedOptions d eid
  case sel of
    (o : _) -> pure o
    [] -> throwIO (WebDriverError 17 "no option is selected")

-- | Deselect every selected option (multi-select). On a single-select this is a
-- no-op after clicking would just re-toggle; callers should use it only on a
-- @<select multiple>@.
deselectAll :: WebDriver -> String -> IO ()
deselectAll d eid = do
  opts <- selectOptions d eid
  mapM_ (\o -> do s <- elementIsSelected d o; if s then elementClick d o else pure ()) opts

-- Click an option only if not already selected (a second click on a selected
-- single-select is a no-op; on a multi-select it would toggle off).
selectOption :: WebDriver -> String -> IO ()
selectOption d o = do
  s <- elementIsSelected d o
  if s then pure () else elementClick d o

-- First option whose projected field equals @want@, then select it.
chooseBy :: WebDriver -> [String] -> String -> (WebDriver -> String -> IO String) -> IO ()
chooseBy _ [] want _ = throwIO (WebDriverError 17 ("no option matching " ++ show want))
chooseBy d (o : os) want project = do
  v <- project d o
  if v == want then selectOption d o else chooseBy d os want project

-- ---- waits ----
-- The poll loop lives here in the binding — the engine issues single commands
-- and holds no thread, exactly as the reference aether/webdriver.ae waits do.

pollIntervalMicros :: Int
pollIntervalMicros = 500 * 1000 -- 500ms, mainstream default

-- | Poll @cond driver@ until it returns @True@ or @timeoutMs@ elapses. Throws
-- 'WebDriverError' 21 (timeout) if the deadline passes. A code-17 (no such
-- element) error from @cond@ is swallowed and retried.
waitUntil :: WebDriver -> Int -> (WebDriver -> IO Bool) -> IO ()
waitUntil d timeoutMs cond = go (max 0 timeoutMs)
  where
    go remaining = do
      r <- try (cond d)
      settled <- case r of
        Right True -> pure True
        Right False -> pure False
        Left e@(WebDriverError code _)
          | code == 17 -> pure False
          | otherwise -> throwIO e
      if settled
        then pure ()
        else
          if remaining <= 0
            then throwIO (WebDriverError 21 ("waited " ++ show timeoutMs ++ "ms for condition"))
            else do
              threadDelay pollIntervalMicros
              go (remaining - 500)

-- | Block until an element matching the locator is present; return its id.
waitForElement :: WebDriver -> Locator -> Int -> IO String
waitForElement d loc timeoutMs = do
  waitUntil d timeoutMs (\drv -> exists drv loc)
  findElement d loc

waitForTitleIs :: WebDriver -> String -> Int -> IO ()
waitForTitleIs d want timeoutMs = waitUntil d timeoutMs (\drv -> (== want) <$> title drv)

waitForTitleContains :: WebDriver -> String -> Int -> IO ()
waitForTitleContains d sub timeoutMs = waitUntil d timeoutMs (\drv -> isInfixOf sub <$> title drv)

waitForUrlIs :: WebDriver -> String -> Int -> IO ()
waitForUrlIs d want timeoutMs = waitUntil d timeoutMs (\drv -> (== want) <$> currentUrl drv)

waitForUrlContains :: WebDriver -> String -> Int -> IO ()
waitForUrlContains d sub timeoutMs = waitUntil d timeoutMs (\drv -> isInfixOf sub <$> currentUrl drv)

-- | Block until NO element matches the locator (it is absent/removed).
waitUntilGone :: WebDriver -> Locator -> Int -> IO ()
waitUntilGone d loc timeoutMs = waitUntil d timeoutMs (\drv -> not <$> exists drv loc)

-- ---- lifecycle ----

sessionId :: WebDriver -> IO String
sessionId (WebDriver h) = N.selSessionId h

quit :: WebDriver -> IO ()
quit d@(WebDriver h) = do
  _ <- execute d "quit" "{}"
  N.selClose h

-- ---- TLS trust config (call before the first execute / newSession) ----

-- | Pin the peer certificate against a private CA file (@""@ reverts to the
-- system store). For a Grid served over HTTPS with its own CA.
setCa :: WebDriver -> String -> IO ()
setCa (WebDriver h) caPath = N.selSetCa h caPath

-- | Skip TLS verification (self-signed dev\/staging Grid). @True@ to skip.
setInsecure :: WebDriver -> Bool -> IO ()
setInsecure (WebDriver h) on = N.selSetInsecure h on

-- ---- driver-process orchestration ----

-- | A driver process (chromedriver\/geckodriver\/…) launched by the engine. Owns
-- the opaque driver handle; call 'stopDriver' to kill + reap it.
newtype DriverProcess = DriverProcess (Ptr ())

-- | Resolve the driver binary path for @browser@ (v1: the conventional driver on
-- PATH). @""@ when none is found. @hint@ is a reserved opts\/JSON string.
resolveDriver :: String -> String -> IO String
resolveDriver = N.selResolveDriver

-- | A self-provisioned browser binary path for @browser@ (downloads Chrome-for-
-- Testing on first call if no system Chrome), or @""@ when a system browser exists.
browserBinary :: String -> String -> IO String
browserBinary = N.selBrowserBinary

-- | resolve + launch a driver for @browser@. @Nothing@ when no driver could be
-- started (the caller's cue to SKIP a live test).
ensureDriver :: String -> String -> Int -> IO (Maybe DriverProcess)
ensureDriver browser hint timeoutMs = do
  p <- N.selEnsureDriver browser hint timeoutMs
  pure (if p == nullPtr then Nothing else Just (DriverProcess p))

-- | Launch an explicit driver binary on a free port. @Nothing@ if it never came up.
launchDriver :: String -> Int -> IO (Maybe DriverProcess)
launchDriver path timeoutMs = do
  p <- N.selLaunchDriver path timeoutMs
  pure (if p == nullPtr then Nothing else Just (DriverProcess p))

-- | The @http:\/\/127.0.0.1:\<port\>@ to pass to 'chrome'\/'headlessChrome'.
driverUrl :: DriverProcess -> IO String
driverUrl (DriverProcess p) = N.selDriverUrl p

-- | The driver's spawn token \/ pid (diagnostics). -1 if the handle is null.
driverPid :: DriverProcess -> IO Int
driverPid (DriverProcess p) = N.selDriverPid p

-- | Kill + reap the driver process. NULL-safe.
stopDriver :: DriverProcess -> IO ()
stopDriver (DriverProcess p) = N.selStopDriver p

-- ---- WebDriver-BiDi (central demux, non-blocking poll) ----
--
-- The multiplexed BiDi transport over a session's webSocketUrl. The engine owns
-- the ONE demux; the caller drives the wait (pump\/fd) then drains replies+events.
-- Open a channel from a session whose newSession requested @webSocketUrl:true@
-- (the caps object), reading the returned value's webSocketUrl.

-- | A WebDriver-BiDi channel. Strings returned are the raw reply\/event JSON.
newtype BiDi = BiDi (Ptr ())

-- | Open a channel to a session's @webSocketUrl@. Throws on connect failure.
bidiOpen :: String -> IO BiDi
bidiOpen wsUrl = do
  p <- N.selBidiOpen wsUrl
  if p == nullPtr
    then throwIO (WebDriverError (-1) ("BiDi connect failed: " ++ wsUrl))
    else pure (BiDi p)

bidiClose :: BiDi -> IO ()
bidiClose (BiDi p) = N.selBidiClose p

-- | Send one command with a caller-managed id. Returns 0 sent \/ -1 error.
bidiSend :: BiDi -> Int -> String -> String -> IO Int
bidiSend (BiDi p) cid method params = N.selBidiSend p cid method params

-- | Advance the demux one step (read ≤1 frame, route it). 1 routed \/ 0 timed
-- out \/ -1 closed.
bidiPump :: BiDi -> Int -> IO Int
bidiPump (BiDi p) timeoutMs = N.selBidiPump p timeoutMs

-- | The readable socket fd, for a native event loop. Readiness is a HINT; on wake
-- always drain via @bidiPump b 0@ until it returns 0.
bidiFd :: BiDi -> IO Int
bidiFd (BiDi p) = N.selBidiFd p

-- | The reply JSON for a command id if it has arrived (consumes it), else @""@.
bidiPollReply :: BiDi -> Int -> IO String
bidiPollReply (BiDi p) cid = N.selBidiPollReply p cid

-- | The next queued event JSON (dequeues), or @""@.
bidiPollEvent :: BiDi -> IO String
bidiPollEvent (BiDi p) = N.selBidiPollEvent p

-- | How many events the bounded queue dropped since the last check (then resets).
bidiLostEvents :: BiDi -> IO Int
bidiLostEvents (BiDi p) = N.selBidiLostEvents p

-- | Drop a pending-reply slot so a late reply is discarded.
bidiCancel :: BiDi -> Int -> IO ()
bidiCancel (BiDi p) cid = N.selBidiCancel p cid

-- | Send @method@ with @cid@ then pump until its reply arrives (or @timeoutMs@).
-- Returns the reply JSON, or @""@ on timeout\/close.
bidiCommand :: BiDi -> Int -> String -> String -> Int -> IO String
bidiCommand b cid method params timeoutMs = do
  _ <- bidiSend b cid method params
  loop timeoutMs
  where
    loop remaining
      | remaining <= 0 = bidiCancel b cid >> pure ""
      | otherwise = do
          let step = min remaining 250
          r <- bidiPump b step
          reply <- bidiPollReply b cid
          if not (null reply)
            then pure reply
            else if r == (-1) then pure "" else loop (remaining - step)

bidiSubscribe :: BiDi -> Int -> String -> Int -> IO String
bidiSubscribe (BiDi p) cid events timeoutMs = N.selBidiSubscribe p cid events timeoutMs

bidiUnsubscribe :: BiDi -> Int -> String -> Int -> IO String
bidiUnsubscribe (BiDi p) cid events timeoutMs = N.selBidiUnsubscribe p cid events timeoutMs

bidiWaitEvent :: BiDi -> String -> Int -> IO String
bidiWaitEvent (BiDi p) method timeoutMs = N.selBidiWaitEvent p method timeoutMs

bidiGetTree :: BiDi -> Int -> Int -> IO String
bidiGetTree (BiDi p) cid timeoutMs = N.selBidiGetTree p cid timeoutMs

bidiScriptEvaluate :: BiDi -> Int -> String -> String -> Int -> IO String
bidiScriptEvaluate (BiDi p) cid expr ctx timeoutMs = N.selBidiScriptEvaluate p cid expr ctx timeoutMs

bidiNavigate :: BiDi -> Int -> String -> String -> Int -> IO String
bidiNavigate (BiDi p) cid ctx url timeoutMs = N.selBidiNavigate p cid ctx url timeoutMs

-- BiDi network interception
bidiAddIntercept :: BiDi -> Int -> String -> String -> Int -> IO String
bidiAddIntercept (BiDi p) cid phases urlPat timeoutMs = N.selBidiNetAddIntercept p cid phases urlPat timeoutMs

bidiRemoveIntercept :: BiDi -> Int -> String -> Int -> IO String
bidiRemoveIntercept (BiDi p) cid interceptId timeoutMs = N.selBidiNetRemoveIntercept p cid interceptId timeoutMs

bidiContinueRequest :: BiDi -> Int -> String -> Int -> IO String
bidiContinueRequest (BiDi p) cid reqId timeoutMs = N.selBidiNetContinueRequest p cid reqId timeoutMs

bidiFailRequest :: BiDi -> Int -> String -> Int -> IO String
bidiFailRequest (BiDi p) cid reqId timeoutMs = N.selBidiNetFailRequest p cid reqId timeoutMs

bidiProvideResponse :: BiDi -> Int -> String -> Int -> String -> String -> Int -> IO String
bidiProvideResponse (BiDi p) cid reqId status ct body timeoutMs =
  N.selBidiNetProvideResponse p cid reqId status ct body timeoutMs

bidiContinueWithAuth :: BiDi -> Int -> String -> String -> String -> Int -> IO String
bidiContinueWithAuth (BiDi p) cid reqId user pass timeoutMs =
  N.selBidiNetContinueWithAuth p cid reqId user pass timeoutMs

bidiSetCacheBehavior :: BiDi -> Int -> String -> Int -> IO String
bidiSetCacheBehavior (BiDi p) cid behavior timeoutMs = N.selBidiNetSetCacheBehavior p cid behavior timeoutMs

-- ---- tiny string helpers (dependency-free) ----

-- | A dependency-free @mapMaybe (filter)@ over an IO predicate.
filterM :: (a -> IO Bool) -> [a] -> IO [a]
filterM _ [] = pure []
filterM p (x : xs) = do
  keep <- p x
  rest <- filterM p xs
  pure (if keep then x : rest else rest)

-- | Merge an element @id@ into a locator JSON object (@{"using":..,"value":..}@)
-- so the engine's findChildElement route sees the parent id. The locator JSON
-- always starts with @{@; splice the id field in right after it.
mergeId :: String -> String -> String
mergeId eid loc =
  case loc of
    ('{' : rest) -> "{\"id\":" ++ jsonStr eid ++ "," ++ rest
    _ -> loc

-- | JSON-encode a string (quote + escape " and \\).
jsonStr :: String -> String
jsonStr s = '"' : concatMap esc s ++ "\""
  where
    esc '"' = "\\\""
    esc '\\' = "\\\\"
    esc c = [c]

-- | Encode a string as a JSON array of single-character strings — the shape the
-- W3C @value@ field of sendKeys/setAlertValue expects.
jsonCharArray :: String -> String
jsonCharArray s = "[" ++ intercalate "," (map (\c -> jsonStr [c]) s) ++ "]"
  where
    intercalate _ [] = ""
    intercalate _ [x] = x
    intercalate sep (x : xs) = x ++ sep ++ intercalate sep xs

-- | Strip surrounding quotes from a JSON string value (best-effort, for simple
-- scalar results like a title). Non-strings pass through unchanged.
jsonUnquote :: String -> String
jsonUnquote ('"' : rest) = unesc (init rest)
  where
    unesc [] = []
    unesc ('\\' : c : cs) = c : unesc cs
    unesc (c : cs) = c : unesc cs
jsonUnquote other = other

-- | Interpret a JSON scalar as a boolean: @true@ is True, everything else False.
jsonBool :: String -> Bool
jsonBool s = case dropWhile (== ' ') s of
  ('t' : _) -> True
  _ -> False

-- | Pull the element-reference id out of a findElement value JSON string, which
-- looks like @{"element-6066-...":"<id>"}@. Textual extraction keeps this
-- dependency-free for the common case.
extractElementId :: String -> Maybe String
extractElementId v =
  let needle = "\"" ++ w3cElementKey ++ "\":\""
   in if needle `isInfixOf` v
        then Just (takeWhile (/= '"') (drop (length needle) (afterInfix needle v)))
        else Nothing

-- | Pull every element-reference id out of a findElements value JSON string
-- (an array of @{"element-6066-...":"<id>"}@ objects).
extractElementIds :: String -> [String]
extractElementIds = go
  where
    needle = "\"" ++ w3cElementKey ++ "\":\""
    go s
      | needle `isInfixOf` s =
          let afterKey = drop (length needle) (afterInfix needle s)
              (eid, restAfter) = spanId afterKey
           in eid : go restAfter
      | otherwise = []
    spanId s = let e = takeWhile (/= '"') s in (e, drop (length e) s)

-- | Pull every JSON string element out of a top-level string array (e.g. window
-- handles): grab the contents of each @"..."@ pair.
extractStrings :: String -> [String]
extractStrings = go
  where
    go s = case dropWhile (/= '"') s of
      ('"' : rest) ->
        let (str, after) = spanStr rest
         in str : go after
      _ -> []
    spanStr s = let e = takeWhile (/= '"') s in (e, drop 1 (drop (length e) s))

-- | The quoted string value of a top-level JSON field @name@ (e.g. the
-- @"handle"@ of a newWindow reply), or @""@ if absent.
extractField :: String -> String -> String
extractField name v =
  let needle = "\"" ++ name ++ "\":\""
   in if needle `isInfixOf` v
        then takeWhile (/= '"') (drop (length needle) (afterInfix needle v))
        else ""

-- Return the suffix of @hay@ starting just after the first occurrence of @n@.
afterInfix :: String -> String -> String
afterInfix n hay = go hay
  where
    go [] = []
    go s@(_ : t)
      | n `isPrefixOf` s = drop (length n) s
      | otherwise = go t
