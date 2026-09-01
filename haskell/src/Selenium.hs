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
  , chrome
  , headlessChrome
  , execute
  , get
  , title
  , back
  , forward
  , findElement
  , elementClick
  , elementText
  , executeScript
  , sessionId
  , quit
  , route
  , errorCode
  , locator
  ) where

import Control.Exception (Exception, throwIO)
import Data.List (isInfixOf)
import Foreign.Ptr (Ptr, nullPtr)

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

-- | A headless Chrome session with the standard launch args.
headlessChrome :: String -> IO WebDriver
headlessChrome commandExecutor =
  chrome commandExecutor
    "{\"browserName\":\"chrome\",\"goog:chromeOptions\":{\"args\":[\"--headless=new\",\"--no-sandbox\",\"--disable-gpu\",\"--disable-dev-shm-usage\"]}}"

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

-- ---- navigation ----

get :: WebDriver -> String -> IO ()
get d url = execute d "get" ("{\"url\":" ++ jsonStr url ++ "}") >> pure ()

title :: WebDriver -> IO String
title d = jsonUnquote <$> execute d "getTitle" "{}"

back :: WebDriver -> IO ()
back d = execute d "goBack" "{}" >> pure ()

forward :: WebDriver -> IO ()
forward d = execute d "goForward" "{}" >> pure ()

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

elementClick :: WebDriver -> String -> IO ()
elementClick d eid = execute d "clickElement" ("{\"id\":" ++ jsonStr eid ++ "}") >> pure ()

elementText :: WebDriver -> String -> IO String
elementText d eid = jsonUnquote <$> execute d "getElementText" ("{\"id\":" ++ jsonStr eid ++ "}")

-- ---- script ----

-- | @executeScript d script argsJson@; @argsJson@ is a JSON array string.
executeScript :: WebDriver -> String -> String -> IO String
executeScript d script argsJson =
  execute d "executeScript" ("{\"script\":" ++ jsonStr script ++ ",\"args\":" ++ argsJson ++ "}")

-- ---- lifecycle ----

sessionId :: WebDriver -> IO String
sessionId (WebDriver h) = N.selSessionId h

quit :: WebDriver -> IO ()
quit d@(WebDriver h) = do
  _ <- execute d "quit" "{}"
  N.selClose h

-- ---- tiny string helpers (dependency-free) ----

-- | JSON-encode a string (quote + escape " and \\).
jsonStr :: String -> String
jsonStr s = '"' : concatMap esc s ++ "\""
  where
    esc '"' = "\\\""
    esc '\\' = "\\\\"
    esc c = [c]

-- | Strip surrounding quotes from a JSON string value (best-effort, for simple
-- scalar results like a title). Non-strings pass through unchanged.
jsonUnquote :: String -> String
jsonUnquote ('"' : rest) = unesc (init rest)
  where
    unesc [] = []
    unesc ('\\' : c : cs) = c : unesc cs
    unesc (c : cs) = c : unesc cs
jsonUnquote other = other

-- | Pull the element-reference id out of a findElement value JSON string, which
-- looks like @{"element-6066-...":"<id>"}@. Textual extraction keeps this
-- dependency-free for the common case.
extractElementId :: String -> Maybe String
extractElementId v =
  let needle = "\"" ++ w3cElementKey ++ "\":\""
   in if needle `isInfixOf` v
        then Just (takeWhile (/= '"') (drop (length needle) (afterInfix needle v)))
        else Nothing
  where
    afterInfix n hay = go hay
      where
        go [] = []
        go s@(_ : t)
          | n `isPrefixOf'` s = drop (length n) s
          | otherwise = go t
    isPrefixOf' pfx str = take (length pfx) str == pfx
