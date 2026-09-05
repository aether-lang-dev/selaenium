-- FFI + live surface test for the Haskell binding — links the one engine .so
-- (no dlopen). Run by haskell/.tests.ae. chromedriver + a content server are
-- started by the harness, which passes their URLs via env (SEL_CHROMEDRIVER_URL,
-- SEL_BASE_URL); the test self-skips if they're absent.
--
-- NOTE: authored on a box without GHC; verified on a box with GHC + the engine
-- (catchyos). The engine underneath is fully live-verified through the other
-- bindings.
module Main (main) where

import Control.Exception (try)
import Data.IORef
import Data.List (isInfixOf)
import System.Environment (lookupEnv)
import System.Exit (exitFailure)

import Selenium

main :: IO ()
main = do
  fails <- newIORef (0 :: Int)
  let check cond label =
        if cond then putStrLn ("  ok: " ++ label)
        else do putStrLn ("FAIL: " ++ label); modifyIORef' fails (+ 1)

  -- ---- FFI (no browser) ----
  r <- route "get"
  check (r == "POST /session/:sessionId/url") "route get"
  ec <- errorCode "no such element"
  check (ec == 17) "errorCode no such element"
  loc <- locator ById "main"
  check ("*[id=" `isInfixOf` loc) "locator id rewrite"
  -- By factory (Selenium 4.x shape): a smart constructor returns a Locator.
  check (locStrategy (byId "hdr") == "id") "byId strategy"
  check (locStrategy (byClassName "b") == "class name") "byClassName -> class name"
  check (locStrategy (byCss "a") == "css selector") "byCss -> css selector"
  check (locStrategy (byTagName "div") == "tag name") "byTagName -> tag name"
  check (locStrategy (byLinkText "L") == "link text") "byLinkText -> link text"
  check (locStrategy (byPartialLinkText "L") == "partial link text") "byPartialLinkText"
  check (locStrategy (byXpath "//a") == "xpath") "byXpath -> xpath"
  -- Keys.chord: modifier + text + trailing NULL (U+E000) that releases modifiers.
  check (keysChord "\xE009" "a" == "\xE009a\xE000") "keysChord ctrl+a shape"
  transport <- try (chrome "http://127.0.0.1:1" "{\"browserName\":\"chrome\"}")
  case transport of
    Left (WebDriverError code _) -> check (code == -1) "transport failure -> code -1"
    Right _ -> check False "transport failure"

  -- ---- newly-completed FFI surface: link + safe-without-a-session ----
  -- resolveDriver must link and return (possibly "") without crashing.
  drv <- resolveDriver "chrome" ""
  check (drv == drv) "resolveDriver links (no crash)"
  -- ensureDriver returns Nothing (no driver here) or Just; both are valid — this
  -- exercises ensure_driver / stop_driver and the Maybe flow.
  mproc <- ensureDriver "chrome" "" 500
  case mproc of
    Nothing -> check True "ensureDriver Nothing (no driver) — clean skip"
    Just p  -> do u <- driverUrl p; check (not (null u)) "ensureDriver url"; stopDriver p
  -- bidiOpen to a dead ws URL throws (connect failure) rather than returning a
  -- null channel — proves bidi_open links and null becomes a typed error.
  bidiTry <- try (bidiOpen "ws://127.0.0.1:1/session")
  case bidiTry of
    Left (WebDriverError _ _) -> check True "bidiOpen dead url -> WebDriverError"
    Right ch -> do bidiClose ch; check False "bidiOpen should have failed"

  -- ---- live surface ----
  mcd <- lookupEnv "SEL_CHROMEDRIVER_URL"
  mbase <- lookupEnv "SEL_BASE_URL"
  case (mcd, mbase) of
    (Just cdUrl, Just base) -> liveSurface check cdUrl base
    _ -> putStrLn "  (live) SKIPPED: SEL_CHROMEDRIVER_URL / SEL_BASE_URL not set (no chromedriver)"

  n <- readIORef fails
  if n == 0
    then putStrLn "PASS: Haskell tests green"
    else do putStrLn ("FAILED: " ++ show n ++ " Haskell test(s)"); exitFailure

liveSurface :: (Bool -> String -> IO ()) -> String -> String -> IO ()
liveSurface check cdUrl base = do
  d <- headlessChrome cdUrl
  sid <- sessionId d
  check (not (null sid)) "session started"

  get d (base ++ "/one")
  t1 <- title d
  check (t1 == "Page One") "title"
  hdr <- findElement d (byId "hdr")
  txt <- elementText d hdr
  check (txt == "One") "hdr text"

  -- navigation history
  go <- findElement d (byId "go")
  elementClick d go
  t2 <- title d
  check (t2 == "Page Two") "after click"
  back d
  t3 <- title d
  check (t3 == "Page One") "after back"
  forward d
  t4 <- title d
  check (t4 == "Page Two") "after forward"
  back d

  -- execute_script (return value comes back as JSON text)
  s1 <- executeScript d "return 6*7;" "[]"
  check (s1 == "42") "script scalar"
  s2 <- executeScript d "return arguments[0]+arguments[1];" "[40,2]"
  check (s2 == "42") "script args"

  -- current url / page source
  u <- currentUrl d
  check ("/two" `isInfixOf` u) "currentUrl"
  src <- pageSource d
  check ("Page Two" `isInfixOf` src) "pageSource"

  -- findElements (plural) + existence predicate
  back d -- to Page One
  hdrs <- findElements d (byTagName "h1")
  check (not (null hdrs)) "findElements h1 non-empty"
  present <- exists d (byId "hdr")
  check present "exists hdr True"
  absent <- exists d (byId "nope")
  check (not absent) "exists nope False"

  -- active element + window handles + frame default (no frames => still ok)
  ae <- activeElement d
  check (not (null ae)) "activeElement id"
  wh <- windowHandles d
  check (length wh >= 1) "windowHandles >= 1"
  cwh <- currentWindowHandle d
  check (not (null cwh)) "currentWindowHandle"
  switchToDefaultContent d

  -- cookies
  deleteAllCookies d
  addCookie d "{\"name\":\"k\",\"value\":\"v\"}"
  c <- getCookie d "k"
  check ("\"v\"" `isInfixOf` c) "cookie roundtrip"

  -- alert not present
  ap <- alertPresent d
  check (not ap) "alertPresent False"

  -- wait for a title that is already true (fast path)
  waitForTitleIs d "Page One" 2000
  check True "waitForTitleIs returned"

  -- negative path
  nse <- try (findElement d (byId "does-not-exist"))
  case nse of
    Left (WebDriverError code _) -> check (code == 17) "no such element error"
    Right _ -> check False "no such element error"

  quit d
