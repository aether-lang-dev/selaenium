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

import SeleniumCore

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
  transport <- try (chrome "http://127.0.0.1:1" "{\"browserName\":\"chrome\"}")
  case transport of
    Left (WebDriverError code _) -> check (code == -1) "transport failure -> code -1"
    Right _ -> check False "transport failure"

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
  hdr <- findElement d ById "hdr"
  txt <- elementText d hdr
  check (txt == "One") "hdr text"

  -- navigation history
  go <- findElement d ById "go"
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

  -- negative path
  nse <- try (findElement d ById "does-not-exist")
  case nse of
    Left (WebDriverError code _) -> check (code == 17) "no such element error"
    Right _ -> check False "no such element error"

  quit d
