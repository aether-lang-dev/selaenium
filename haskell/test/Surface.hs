-- Surface.hs — no-browser ABI-surface guard for the Haskell binding.
--
-- Pins the pure, browser-free facts of the full-feature surface (the engine
-- helpers, the By smart constructors, Keys.chord) AND — via the `surface` value
-- below — forces the compiler to type-check that every public method exists with
-- its expected signature. Adding this module to the cabal `surface` test-suite
-- means a rename or accidental removal of any listed symbol breaks the build,
-- exactly like the crystal/swift surface specs. Needs only the engine .so link
-- (for `route`/`errorCode`/`locator` to resolve); it never opens a session.
module Main (main) where

import Data.IORef
import Data.List (isInfixOf)
import System.Exit (exitFailure)

import Selenium

main :: IO ()
main = do
  fails <- newIORef (0 :: Int)
  let check cond label =
        if cond then putStrLn ("  ok: " ++ label)
        else do putStrLn ("FAIL: " ++ label); modifyIORef' fails (+ 1)

  -- ---- pure engine helpers (no browser) ----
  r <- route "get"
  check (r == "POST /session/:sessionId/url") "route get"
  ec <- errorCode "no such element"
  check (ec == 17) "errorCode no such element"
  loc <- locator ById "main"
  -- locator hands the strategy to the engine RAW; normalization happens in the
  -- engine, inside execute, where the session is known. AGENTS.md: "A test
  -- asserting By.id(...) yields CSS is testing the wrong layer." Asserting
  -- "*[id=" here pinned the binding to browser-only behaviour, which is why
  -- desktop locators could not survive the trip.
  check (loc == "{\"using\":\"id\",\"value\":\"main\"}") "locator passes the strategy through raw"

  -- ---- By smart constructors (Selenium 4.x shape) ----
  check (locStrategy (byId "x") == "id") "byId"
  check (locStrategy (byName "x") == "name") "byName"
  check (locStrategy (byCss "x") == "css selector") "byCss"
  check (locStrategy (byClassName "x") == "class name") "byClassName -> class name"
  check (locStrategy (byTagName "x") == "tag name") "byTagName"
  check (locStrategy (byLinkText "x") == "link text") "byLinkText"
  check (locStrategy (byPartialLinkText "x") == "partial link text") "byPartialLinkText"
  check (locStrategy (byXpath "x") == "xpath") "byXpath"

  -- ---- Keys.chord: modifier + text + trailing NULL (U+E000) ----
  check (keysChord "\xE009" "a" == "\xE009\&a\xE000") "keysChord ctrl+a shape"

  -- `_refs` below never runs; referencing it here ties the compile-time surface
  -- witness into `main` so GHC keeps type-checking it.
  check (_refs `seq` True) "public surface type-checks"

  n <- readIORef fails
  if n == 0
    then putStrLn "PASS: Haskell ABI-surface guard green"
    else do putStrLn ("FAILED: " ++ show n ++ " surface check(s)"); exitFailure

-- | A never-evaluated witness that every public method of the binding exists
-- with the signature the surface promises. Each `fn :: <sig>` forces `fn` to
-- exist with that type; if any is renamed/removed or its type drifts, this fails
-- to COMPILE — the guard, exactly like the crystal/swift surface specs. The
-- leaves are the real functions (never called): `seq` forces only the outer
-- tuple to WHNF, so no engine command runs. Grouped to mirror the export list.
_refs :: ()
_refs = _all `seq` ()
  where
    _sessions =
      ( chrome :: String -> String -> IO WebDriver
      , headlessChrome :: String -> IO WebDriver
      , firefox :: String -> String -> IO WebDriver
      , headlessFirefox :: String -> IO WebDriver
      , edge :: String -> String -> IO WebDriver
      , headlessEdge :: String -> IO WebDriver
      , safari :: String -> String -> IO WebDriver
      , execute :: WebDriver -> String -> String -> IO String
      , sessionId :: WebDriver -> IO String
      , quit :: WebDriver -> IO ()
      )
    _navigation =
      ( get :: WebDriver -> String -> IO ()
      , currentUrl :: WebDriver -> IO String
      , title :: WebDriver -> IO String
      , pageSource :: WebDriver -> IO String
      , back :: WebDriver -> IO ()
      , forward :: WebDriver -> IO ()
      , refresh :: WebDriver -> IO ()
      )
    _elements =
      ( findElement :: WebDriver -> Locator -> IO String
      , findElements :: WebDriver -> Locator -> IO [String]
      , findChildElement :: WebDriver -> String -> Locator -> IO String
      , findChildElements :: WebDriver -> String -> Locator -> IO [String]
      , getShadowRoot :: WebDriver -> String -> IO ShadowRoot
      , shadowFindElement :: WebDriver -> ShadowRoot -> Locator -> IO String
      , activeElement :: WebDriver -> IO String
      , exists :: WebDriver -> Locator -> IO Bool
      )
    _elementOps =
      ( elementClick :: WebDriver -> String -> IO ()
      , elementClear :: WebDriver -> String -> IO ()
      , elementSendKeys :: WebDriver -> String -> String -> IO ()
      , elementText :: WebDriver -> String -> IO String
      , elementTagName :: WebDriver -> String -> IO String
      , elementIsEnabled :: WebDriver -> String -> IO Bool
      , elementIsSelected :: WebDriver -> String -> IO Bool
      , elementRect :: WebDriver -> String -> IO String
      , getDomAttribute :: WebDriver -> String -> String -> IO String
      , getProperty :: WebDriver -> String -> String -> IO String
      , getAttribute :: WebDriver -> String -> String -> IO String
      , isDisplayed :: WebDriver -> String -> IO Bool
      , cssValue :: WebDriver -> String -> String -> IO String
      , valueOfCssProperty :: WebDriver -> String -> String -> IO String
      , elementScreenshot :: WebDriver -> String -> IO String
      , submit :: WebDriver -> String -> IO ()
      , findRelative :: WebDriver -> String -> String -> IO [String]
      , findRelativeCount :: WebDriver -> String -> String -> IO Int
      )
    _script =
      ( executeScript :: WebDriver -> String -> String -> IO String
      , executeAsyncScript :: WebDriver -> String -> String -> IO String
      )
    _windows =
      ( windowHandles :: WebDriver -> IO [String]
      , currentWindowHandle :: WebDriver -> IO String
      , switchToWindow :: WebDriver -> String -> IO ()
      , newWindow :: WebDriver -> String -> IO String
      , closeWindow :: WebDriver -> IO [String]
      , getWindowRect :: WebDriver -> IO String
      , setWindowRect :: WebDriver -> String -> IO String
      , maximizeWindow :: WebDriver -> IO String
      , minimizeWindow :: WebDriver -> IO String
      , fullscreenWindow :: WebDriver -> IO String
      )
    _frames =
      ( switchToFrame :: WebDriver -> Frame -> IO ()
      , switchToParentFrame :: WebDriver -> IO ()
      , switchToDefaultContent :: WebDriver -> IO ()
      )
    _alerts =
      ( acceptAlert :: WebDriver -> IO ()
      , dismissAlert :: WebDriver -> IO ()
      , alertText :: WebDriver -> IO String
      , sendAlertText :: WebDriver -> String -> IO ()
      , alertPresent :: WebDriver -> IO Bool
      )
    _cookies =
      ( addCookie :: WebDriver -> String -> IO ()
      , getCookies :: WebDriver -> IO String
      , getCookie :: WebDriver -> String -> IO String
      , deleteCookie :: WebDriver -> String -> IO ()
      , deleteAllCookies :: WebDriver -> IO ()
      )
    _actions =
      ( performActions :: WebDriver -> String -> IO ()
      , clearActions :: WebDriver -> IO ()
      , moveToElement :: WebDriver -> String -> IO ()
      , clickAndHold :: WebDriver -> String -> IO ()
      , release :: WebDriver -> IO ()
      , contextClick :: WebDriver -> String -> IO ()
      , doubleClick :: WebDriver -> String -> IO ()
      , dragAndDrop :: WebDriver -> String -> String -> IO ()
      , keyDown :: WebDriver -> String -> IO ()
      , keyUp :: WebDriver -> String -> IO ()
      )
    _timeouts =
      ( setTimeouts :: WebDriver -> String -> IO ()
      , setPageLoadTimeout :: WebDriver -> Int -> IO ()
      , setScriptTimeout :: WebDriver -> Int -> IO ()
      , implicitlyWait :: WebDriver -> Int -> IO ()
      )
    _shots =
      ( screenshotBase64 :: WebDriver -> IO String
      , printPdf :: WebDriver -> String -> IO String
      )
    _select =
      ( selectByVisibleText :: WebDriver -> String -> String -> IO ()
      , selectByValue :: WebDriver -> String -> String -> IO ()
      , selectByIndex :: WebDriver -> String -> Int -> IO ()
      , selectedOptions :: WebDriver -> String -> IO [String]
      , firstSelectedOption :: WebDriver -> String -> IO String
      , isMultiple :: WebDriver -> String -> IO Bool
      , deselectAll :: WebDriver -> String -> IO ()
      )
    _waits =
      ( waitUntil :: WebDriver -> Int -> (WebDriver -> IO Bool) -> IO ()
      , waitUntilEvery :: WebDriver -> Int -> Int -> (WebDriver -> IO Bool) -> IO ()
      , waitForElement :: WebDriver -> Locator -> Int -> IO String
      , waitForVisible :: WebDriver -> Locator -> Int -> IO String
      , waitForClickable :: WebDriver -> Locator -> Int -> IO String
      , waitForTitleIs :: WebDriver -> String -> Int -> IO ()
      , waitForTitleContains :: WebDriver -> String -> Int -> IO ()
      , waitForUrlIs :: WebDriver -> String -> Int -> IO ()
      , waitForUrlContains :: WebDriver -> String -> Int -> IO ()
      , waitUntilGone :: WebDriver -> Locator -> Int -> IO ()
      )
    _tls =
      ( setCa :: WebDriver -> String -> IO ()
      , setInsecure :: WebDriver -> Bool -> IO ()
      )
    _driverMgmt =
      ( resolveDriver :: String -> String -> IO String
      , browserBinary :: String -> String -> IO String
      , ensureDriver :: String -> String -> Int -> IO (Maybe DriverProcess)
      , launchDriver :: String -> Int -> IO (Maybe DriverProcess)
      , localChrome :: String -> Int -> IO (Maybe (WebDriver, DriverProcess))
      , driverUrl :: DriverProcess -> IO String
      , driverPid :: DriverProcess -> IO Int
      , stopDriver :: DriverProcess -> IO ()
      )
    _bidi =
      ( bidiOpen :: String -> IO BiDi
      , bidiClose :: BiDi -> IO ()
      , bidiSend :: BiDi -> Int -> String -> String -> IO Int
      , bidiPump :: BiDi -> Int -> IO Int
      , bidiCommand :: BiDi -> Int -> String -> String -> Int -> IO String
      , bidiSubscribe :: BiDi -> Int -> String -> Int -> IO String
      , bidiUnsubscribe :: BiDi -> Int -> String -> Int -> IO String
      , bidiWaitEvent :: BiDi -> String -> Int -> IO String
      , bidiNextEvent :: BiDi -> String -> Int -> IO (Maybe String)
      , bidiGetTree :: BiDi -> Int -> Int -> IO String
      , bidiTopContext :: BiDi -> Int -> Int -> IO (Maybe String)
      , bidiScriptEvaluate :: BiDi -> Int -> String -> String -> Int -> IO String
      , bidiNavigate :: BiDi -> Int -> String -> String -> Int -> IO String
      , bidiAddIntercept :: BiDi -> Int -> String -> String -> Int -> IO String
      , bidiProvideResponse :: BiDi -> Int -> String -> Int -> String -> String -> Int -> IO String
      , bidiContinueWithAuth :: BiDi -> Int -> String -> String -> String -> Int -> IO String
      , bidiSetCacheBehavior :: BiDi -> Int -> String -> Int -> IO String
      )
    -- Force each group to be resolved (never evaluated at runtime).
    _all = ( _sessions, _navigation, _elements, _elementOps, _script, _windows
           , _frames, _alerts, _cookies, _actions, _timeouts, _shots, _select
           , _waits, _tls, _driverMgmt, _bidi )
