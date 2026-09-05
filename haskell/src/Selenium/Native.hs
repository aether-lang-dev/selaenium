{-# LANGUAGE ForeignFunctionInterface #-}

-- | Raw FFI surface over the Selenium core C ABI (the @aether_sel_embed_*@
-- symbols from @core\/embed.ae@, linked from @libselenium_core.so@). This module
-- is the ONLY place in the Haskell binding that knows about the C ABI;
-- "Selenium" is idiomatic Haskell on top of it. No protocol logic lives here
-- — the engine is @core\/selenium_core.ae@, shared by every language binding.
--
-- Like Go\/cgo, Nim and Zig, this binding LINKS the engine (see the .cabal
-- @extra-libraries@\/@ld-options@) rather than dlopen'ing it, so
-- @libselenium_core.so@ must exist at BUILD time.
--
-- Ownership: every @CString@ this ABI returns is caller-owned and goes through
-- exactly one helper, 'takeString', which copies it into a Haskell 'String' and
-- frees the original via @aether_sel_embed_free_string@.
module Selenium.Native
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
  -- TLS trust config
  , selSetCa
  , selSetInsecure
  -- atom-backed element commands
  , selExecuteAtom
  , selIsDisplayed
  , selGetAttribute
  , selFindRelative
  -- driver-process orchestration
  , selResolveDriver
  , selLaunchDriver
  , selBrowserBinary
  , selEnsureDriver
  , selDriverUrl
  , selDriverPid
  , selStopDriver
  -- WebDriver-BiDi channel
  , selBidiOpen
  , selBidiClose
  , selBidiSend
  , selBidiPump
  , selBidiFd
  , selBidiPollReply
  , selBidiPollEvent
  , selBidiLostEvents
  , selBidiCancel
  , selBidiSubscribe
  , selBidiUnsubscribe
  , selBidiWaitEvent
  , selBidiGetTree
  , selBidiScriptEvaluate
  , selBidiNavigate
  -- BiDi network interception
  , selBidiNetAddIntercept
  , selBidiNetRemoveIntercept
  , selBidiNetContinueRequest
  , selBidiNetFailRequest
  , selBidiNetProvideResponse
  , selBidiNetContinueWithAuth
  , selBidiNetSetCacheBehavior
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

-- TLS trust config
foreign import ccall unsafe "aether_sel_embed_set_ca"
  c_set_ca :: Ptr () -> CString -> IO ()
foreign import ccall unsafe "aether_sel_embed_set_insecure"
  c_set_insecure :: Ptr () -> CInt -> IO ()

-- atom-backed element commands (rc; drain via last_value)
foreign import ccall safe "aether_sel_embed_execute_atom"
  c_execute_atom :: Ptr () -> CString -> CString -> CString -> IO CInt
foreign import ccall safe "aether_sel_embed_is_displayed"
  c_is_displayed :: Ptr () -> CString -> IO CInt
foreign import ccall safe "aether_sel_embed_get_attribute"
  c_get_attribute :: Ptr () -> CString -> CString -> IO CInt
foreign import ccall safe "aether_sel_embed_find_relative"
  c_find_relative :: Ptr () -> CString -> CString -> IO CInt

-- driver-process orchestration
foreign import ccall safe "aether_sel_embed_resolve_driver"
  c_resolve_driver :: CString -> CString -> IO CString
foreign import ccall safe "aether_sel_embed_launch_driver"
  c_launch_driver :: CString -> CInt -> IO (Ptr ())
foreign import ccall safe "aether_sel_embed_browser_binary"
  c_browser_binary :: CString -> CString -> IO CString
foreign import ccall safe "aether_sel_embed_ensure_driver"
  c_ensure_driver :: CString -> CString -> CInt -> IO (Ptr ())
foreign import ccall unsafe "aether_sel_embed_driver_url"
  c_driver_url :: Ptr () -> IO CString
foreign import ccall unsafe "aether_sel_embed_driver_pid"
  c_driver_pid :: Ptr () -> IO CInt
foreign import ccall safe "aether_sel_embed_stop_driver"
  c_stop_driver :: Ptr () -> IO ()

-- WebDriver-BiDi channel
foreign import ccall unsafe "aether_sel_embed_bidi_open"
  c_bidi_open :: CString -> IO (Ptr ())
foreign import ccall unsafe "aether_sel_embed_bidi_close"
  c_bidi_close :: Ptr () -> IO ()
foreign import ccall safe "aether_sel_embed_bidi_send"
  c_bidi_send :: Ptr () -> CInt -> CString -> CString -> IO CInt
foreign import ccall safe "aether_sel_embed_bidi_pump"
  c_bidi_pump :: Ptr () -> CInt -> IO CInt
foreign import ccall unsafe "aether_sel_embed_bidi_fd"
  c_bidi_fd :: Ptr () -> IO CInt
foreign import ccall unsafe "aether_sel_embed_bidi_poll_reply"
  c_bidi_poll_reply :: Ptr () -> CInt -> IO CString
foreign import ccall unsafe "aether_sel_embed_bidi_poll_event"
  c_bidi_poll_event :: Ptr () -> IO CString
foreign import ccall unsafe "aether_sel_embed_bidi_lost_events"
  c_bidi_lost_events :: Ptr () -> IO CInt
foreign import ccall unsafe "aether_sel_embed_bidi_cancel"
  c_bidi_cancel :: Ptr () -> CInt -> IO ()
foreign import ccall safe "aether_sel_embed_bidi_subscribe"
  c_bidi_subscribe :: Ptr () -> CInt -> CString -> CInt -> IO CString
foreign import ccall safe "aether_sel_embed_bidi_unsubscribe"
  c_bidi_unsubscribe :: Ptr () -> CInt -> CString -> CInt -> IO CString
foreign import ccall safe "aether_sel_embed_bidi_wait_event"
  c_bidi_wait_event :: Ptr () -> CString -> CInt -> IO CString
foreign import ccall safe "aether_sel_embed_bidi_get_tree"
  c_bidi_get_tree :: Ptr () -> CInt -> CInt -> IO CString
foreign import ccall safe "aether_sel_embed_bidi_script_evaluate"
  c_bidi_script_evaluate :: Ptr () -> CInt -> CString -> CString -> CInt -> IO CString
foreign import ccall safe "aether_sel_embed_bidi_navigate"
  c_bidi_navigate :: Ptr () -> CInt -> CString -> CString -> CInt -> IO CString

-- BiDi network interception
foreign import ccall safe "aether_sel_embed_bidi_network_add_intercept"
  c_bidi_net_add_intercept :: Ptr () -> CInt -> CString -> CString -> CInt -> IO CString
foreign import ccall safe "aether_sel_embed_bidi_network_remove_intercept"
  c_bidi_net_remove_intercept :: Ptr () -> CInt -> CString -> CInt -> IO CString
foreign import ccall safe "aether_sel_embed_bidi_network_continue_request"
  c_bidi_net_continue_request :: Ptr () -> CInt -> CString -> CInt -> IO CString
foreign import ccall safe "aether_sel_embed_bidi_network_fail_request"
  c_bidi_net_fail_request :: Ptr () -> CInt -> CString -> CInt -> IO CString
foreign import ccall safe "aether_sel_embed_bidi_network_provide_response"
  c_bidi_net_provide_response :: Ptr () -> CInt -> CString -> CInt -> CString -> CString -> CInt -> IO CString
foreign import ccall safe "aether_sel_embed_bidi_network_continue_with_auth"
  c_bidi_net_continue_with_auth :: Ptr () -> CInt -> CString -> CString -> CString -> CInt -> IO CString
foreign import ccall safe "aether_sel_embed_bidi_network_set_cache_behavior"
  c_bidi_net_set_cache_behavior :: Ptr () -> CInt -> CString -> CInt -> IO CString

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

-- ---- TLS trust config (call before the first execute / newSession) ----

selSetCa :: Ptr () -> String -> IO ()
selSetCa h caPath = withC caPath (c_set_ca h)

selSetInsecure :: Ptr () -> Bool -> IO ()
selSetInsecure h on = c_set_insecure h (if on then 1 else 0)

-- ---- atom-backed element commands (rc; drain via 'selLastValue') ----

-- | Run an atom (isDisplayed / getAttribute / getText / …) against an element.
-- @extraJson@ is a JSON array of extra args (@"[]"@\/@""@ for none). Returns the
-- W3C rc (0 ok).
selExecuteAtom :: Ptr () -> String -> String -> String -> IO Int
selExecuteAtom h atom elemId extra =
  withC atom $ \a -> withC elemId $ \e -> withC extra $ \x ->
    fromIntegral <$> c_execute_atom h a e x

selIsDisplayed :: Ptr () -> String -> IO Int
selIsDisplayed h elemId = withC elemId (fmap fromIntegral . c_is_displayed h)

selGetAttribute :: Ptr () -> String -> String -> IO Int
selGetAttribute h elemId name =
  withC elemId $ \e -> withC name $ \n -> fromIntegral <$> c_get_attribute h e n

selFindRelative :: Ptr () -> String -> String -> IO Int
selFindRelative h baseSel filters =
  withC baseSel $ \b -> withC filters $ \f -> fromIntegral <$> c_find_relative h b f

-- ---- driver-process orchestration ----

selResolveDriver :: String -> String -> IO String
selResolveDriver browser hint =
  withC browser $ \b -> withC hint $ \x -> c_resolve_driver b x >>= takeString

selLaunchDriver :: String -> Int -> IO (Ptr ())
selLaunchDriver path timeoutMs =
  withC path $ \p -> c_launch_driver p (fromIntegral timeoutMs)

selBrowserBinary :: String -> String -> IO String
selBrowserBinary browser hint =
  withC browser $ \b -> withC hint $ \x -> c_browser_binary b x >>= takeString

selEnsureDriver :: String -> String -> Int -> IO (Ptr ())
selEnsureDriver browser hint timeoutMs =
  withC browser $ \b -> withC hint $ \x -> c_ensure_driver b x (fromIntegral timeoutMs)

selDriverUrl :: Ptr () -> IO String
selDriverUrl dh = c_driver_url dh >>= takeString

selDriverPid :: Ptr () -> IO Int
selDriverPid dh = fromIntegral <$> c_driver_pid dh

selStopDriver :: Ptr () -> IO ()
selStopDriver = c_stop_driver

-- ---- WebDriver-BiDi channel (strings are raw reply/event JSON) ----

selBidiOpen :: String -> IO (Ptr ())
selBidiOpen wsUrl = withC wsUrl c_bidi_open

selBidiClose :: Ptr () -> IO ()
selBidiClose = c_bidi_close

selBidiSend :: Ptr () -> Int -> String -> String -> IO Int
selBidiSend h cid method params =
  withC method $ \m -> withC params $ \p ->
    fromIntegral <$> c_bidi_send h (fromIntegral cid) m p

selBidiPump :: Ptr () -> Int -> IO Int
selBidiPump h timeoutMs = fromIntegral <$> c_bidi_pump h (fromIntegral timeoutMs)

selBidiFd :: Ptr () -> IO Int
selBidiFd h = fromIntegral <$> c_bidi_fd h

selBidiPollReply :: Ptr () -> Int -> IO String
selBidiPollReply h cid = c_bidi_poll_reply h (fromIntegral cid) >>= takeString

selBidiPollEvent :: Ptr () -> IO String
selBidiPollEvent h = c_bidi_poll_event h >>= takeString

selBidiLostEvents :: Ptr () -> IO Int
selBidiLostEvents h = fromIntegral <$> c_bidi_lost_events h

selBidiCancel :: Ptr () -> Int -> IO ()
selBidiCancel h cid = c_bidi_cancel h (fromIntegral cid)

selBidiSubscribe :: Ptr () -> Int -> String -> Int -> IO String
selBidiSubscribe h cid events timeoutMs =
  withC events $ \e -> c_bidi_subscribe h (fromIntegral cid) e (fromIntegral timeoutMs) >>= takeString

selBidiUnsubscribe :: Ptr () -> Int -> String -> Int -> IO String
selBidiUnsubscribe h cid events timeoutMs =
  withC events $ \e -> c_bidi_unsubscribe h (fromIntegral cid) e (fromIntegral timeoutMs) >>= takeString

selBidiWaitEvent :: Ptr () -> String -> Int -> IO String
selBidiWaitEvent h method timeoutMs =
  withC method $ \m -> c_bidi_wait_event h m (fromIntegral timeoutMs) >>= takeString

selBidiGetTree :: Ptr () -> Int -> Int -> IO String
selBidiGetTree h cid timeoutMs =
  c_bidi_get_tree h (fromIntegral cid) (fromIntegral timeoutMs) >>= takeString

selBidiScriptEvaluate :: Ptr () -> Int -> String -> String -> Int -> IO String
selBidiScriptEvaluate h cid expr ctx timeoutMs =
  withC expr $ \e -> withC ctx $ \c ->
    c_bidi_script_evaluate h (fromIntegral cid) e c (fromIntegral timeoutMs) >>= takeString

selBidiNavigate :: Ptr () -> Int -> String -> String -> Int -> IO String
selBidiNavigate h cid ctx url timeoutMs =
  withC ctx $ \c -> withC url $ \u ->
    c_bidi_navigate h (fromIntegral cid) c u (fromIntegral timeoutMs) >>= takeString

-- ---- BiDi network interception ----

selBidiNetAddIntercept :: Ptr () -> Int -> String -> String -> Int -> IO String
selBidiNetAddIntercept h cid phases urlPat timeoutMs =
  withC phases $ \p -> withC urlPat $ \u ->
    c_bidi_net_add_intercept h (fromIntegral cid) p u (fromIntegral timeoutMs) >>= takeString

selBidiNetRemoveIntercept :: Ptr () -> Int -> String -> Int -> IO String
selBidiNetRemoveIntercept h cid interceptId timeoutMs =
  withC interceptId $ \i ->
    c_bidi_net_remove_intercept h (fromIntegral cid) i (fromIntegral timeoutMs) >>= takeString

selBidiNetContinueRequest :: Ptr () -> Int -> String -> Int -> IO String
selBidiNetContinueRequest h cid reqId timeoutMs =
  withC reqId $ \r ->
    c_bidi_net_continue_request h (fromIntegral cid) r (fromIntegral timeoutMs) >>= takeString

selBidiNetFailRequest :: Ptr () -> Int -> String -> Int -> IO String
selBidiNetFailRequest h cid reqId timeoutMs =
  withC reqId $ \r ->
    c_bidi_net_fail_request h (fromIntegral cid) r (fromIntegral timeoutMs) >>= takeString

selBidiNetProvideResponse :: Ptr () -> Int -> String -> Int -> String -> String -> Int -> IO String
selBidiNetProvideResponse h cid reqId status contentType body timeoutMs =
  withC reqId $ \r -> withC contentType $ \ct -> withC body $ \b ->
    c_bidi_net_provide_response h (fromIntegral cid) r (fromIntegral status) ct b (fromIntegral timeoutMs) >>= takeString

selBidiNetContinueWithAuth :: Ptr () -> Int -> String -> String -> String -> Int -> IO String
selBidiNetContinueWithAuth h cid reqId user pass timeoutMs =
  withC reqId $ \r -> withC user $ \u -> withC pass $ \p ->
    c_bidi_net_continue_with_auth h (fromIntegral cid) r u p (fromIntegral timeoutMs) >>= takeString

selBidiNetSetCacheBehavior :: Ptr () -> Int -> String -> Int -> IO String
selBidiNetSetCacheBehavior h cid behavior timeoutMs =
  withC behavior $ \b ->
    c_bidi_net_set_cache_behavior h (fromIntegral cid) b (fromIntegral timeoutMs) >>= takeString
