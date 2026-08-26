{-# LANGUAGE ForeignFunctionInterface #-}

-- | Raw FFI surface over the Selenium core C ABI (the @aether_sel_embed_*@
-- symbols from @core\/embed.ae@, linked from @libselenium_core.so@). This module
-- is the ONLY place in the Haskell binding that knows about the C ABI;
-- "SeleniumCore" is idiomatic Haskell on top of it. No protocol logic lives here
-- — the engine is @core\/selenium_core.ae@, shared by every language binding.
--
-- Like Go\/cgo, Nim and Zig, this binding LINKS the engine (see the .cabal
-- @extra-libraries@\/@ld-options@) rather than dlopen'ing it, so
-- @libselenium_core.so@ must exist at BUILD time.
--
-- Ownership: every @CString@ this ABI returns is caller-owned and goes through
-- exactly one helper, 'takeString', which copies it into a Haskell 'String' and
-- frees the original via @aether_sel_embed_free_string@.
module SeleniumCore.Native
  ( selOpen
  , selClose
  , selExecute
  , selLastValue
  , selLastStatus
  , selLastErrorCode
  , selLastError
  , selSessionId
  , selByLocator
  , selRoute
  , selErrorCode
  , takeString
  , withC
  ) where

import Foreign.C.String (CString, newCString, peekCString)
import Foreign.C.Types (CInt (..))
import Foreign.Ptr (Ptr, nullPtr)
import Foreign.Marshal.Alloc (free)
import Control.Exception (bracket)

-- The opaque session handle.
foreign import ccall unsafe "aether_sel_embed_open"
  c_open :: CString -> IO (Ptr ())
foreign import ccall unsafe "aether_sel_embed_close"
  c_close :: Ptr () -> IO ()
foreign import ccall safe "aether_sel_embed_execute"
  c_execute :: Ptr () -> CString -> CString -> IO CInt
foreign import ccall unsafe "aether_sel_embed_last_value"
  c_last_value :: Ptr () -> IO CString
foreign import ccall unsafe "aether_sel_embed_last_status"
  c_last_status :: Ptr () -> IO CInt
foreign import ccall unsafe "aether_sel_embed_last_error_code"
  c_last_error_code :: Ptr () -> IO CInt
foreign import ccall unsafe "aether_sel_embed_last_error"
  c_last_error :: Ptr () -> IO CString
foreign import ccall unsafe "aether_sel_embed_session_id"
  c_session_id :: Ptr () -> IO CString
foreign import ccall unsafe "aether_sel_embed_by_locator"
  c_by_locator :: CString -> CString -> IO CString
foreign import ccall unsafe "aether_sel_embed_route"
  c_route :: CString -> IO CString
foreign import ccall unsafe "aether_sel_embed_error_code"
  c_error_code :: CString -> IO CInt
foreign import ccall unsafe "aether_sel_embed_free_string"
  c_free_string :: CString -> IO ()

-- | Marshal a Haskell 'String' to a temporary @CString@ for the call.
withC :: String -> (CString -> IO a) -> IO a
withC s = bracket (newCString s) free

-- | Copy an ABI-returned @CString@ into a Haskell 'String' and free the
-- original via the engine's allocator. @""@ for NULL.
takeString :: CString -> IO String
takeString p
  | p == nullPtr = pure ""
  | otherwise = do
      s <- peekCString p
      c_free_string p
      pure s

selOpen :: String -> IO (Ptr ())
selOpen url = withC url c_open

selClose :: Ptr () -> IO ()
selClose = c_close

selExecute :: Ptr () -> String -> String -> IO Int
selExecute h name params =
  withC name $ \n -> withC params $ \p -> fromIntegral <$> c_execute h n p

selLastValue :: Ptr () -> IO String
selLastValue h = c_last_value h >>= takeString

selLastStatus :: Ptr () -> IO Int
selLastStatus h = fromIntegral <$> c_last_status h

selLastErrorCode :: Ptr () -> IO Int
selLastErrorCode h = fromIntegral <$> c_last_error_code h

selLastError :: Ptr () -> IO String
selLastError h = c_last_error h >>= takeString

selSessionId :: Ptr () -> IO String
selSessionId h = c_session_id h >>= takeString

selByLocator :: String -> String -> IO String
selByLocator strategy value =
  withC strategy $ \s -> withC value $ \v -> c_by_locator s v >>= takeString

selRoute :: String -> IO String
selRoute name = withC name c_route >>= takeString

selErrorCode :: String -> IO Int
selErrorCode e = withC e (fmap fromIntegral . c_error_code)
