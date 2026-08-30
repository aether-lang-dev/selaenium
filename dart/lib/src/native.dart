/// The 1:1 dart:ffi symbol table for the Selenium core C ABI (`core/embed.ae`,
/// built on the pure-Aether `core/selenium_core.ae` engine). This library is the
/// ONLY place in the Dart binding that knows about the C ABI; everything above
/// it is idiomatic Dart. No protocol logic lives here or anywhere in this
/// package — the engine is shared by every language binding.
///
/// `core/embed.ae` names its exports `sel_embed_<name>`; `--emit=lib` mangles
/// them to `aether_sel_embed_<name>`, the names looked up here. Every `char*`
/// this ABI returns is caller-owned and must be freed via
/// `aether_sel_embed_free_string` — [takeString] does that.
library;

import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart' as pkgffi;

typedef _OpenC = ffi.Pointer<ffi.Void> Function(ffi.Pointer<pkgffi.Utf8>);
typedef _Open = ffi.Pointer<ffi.Void> Function(ffi.Pointer<pkgffi.Utf8>);

typedef _CloseC = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _Close = void Function(ffi.Pointer<ffi.Void>);

typedef _ExecuteC = ffi.Int Function(
    ffi.Pointer<ffi.Void>, ffi.Pointer<pkgffi.Utf8>, ffi.Pointer<pkgffi.Utf8>);
typedef _Execute = int Function(
    ffi.Pointer<ffi.Void>, ffi.Pointer<pkgffi.Utf8>, ffi.Pointer<pkgffi.Utf8>);

typedef _HandleToStrC = ffi.Pointer<pkgffi.Utf8> Function(ffi.Pointer<ffi.Void>);
typedef _HandleToStr = ffi.Pointer<pkgffi.Utf8> Function(ffi.Pointer<ffi.Void>);

typedef _HandleToIntC = ffi.Int Function(ffi.Pointer<ffi.Void>);
typedef _HandleToInt = int Function(ffi.Pointer<ffi.Void>);

typedef _StrToStrC = ffi.Pointer<pkgffi.Utf8> Function(ffi.Pointer<pkgffi.Utf8>);
typedef _StrToStr = ffi.Pointer<pkgffi.Utf8> Function(ffi.Pointer<pkgffi.Utf8>);

typedef _Str2ToStrC = ffi.Pointer<pkgffi.Utf8> Function(
    ffi.Pointer<pkgffi.Utf8>, ffi.Pointer<pkgffi.Utf8>);
typedef _Str2ToStr = ffi.Pointer<pkgffi.Utf8> Function(
    ffi.Pointer<pkgffi.Utf8>, ffi.Pointer<pkgffi.Utf8>);

typedef _StrToIntC = ffi.Int Function(ffi.Pointer<pkgffi.Utf8>);
typedef _StrToInt = int Function(ffi.Pointer<pkgffi.Utf8>);

typedef _FreeStringC = ffi.Void Function(ffi.Pointer<pkgffi.Utf8>);
typedef _FreeString = void Function(ffi.Pointer<pkgffi.Utf8>);

// ---- WebDriver-BiDi (over the session's webSocketUrl) ----
// The BiDi channel handle (void*) is opaque and independent of the W3C handle.
typedef _BidiPumpC = ffi.Int Function(ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _BidiPump = int Function(ffi.Pointer<ffi.Void>, int);

typedef _BidiSendC = ffi.Int Function(ffi.Pointer<ffi.Void>, ffi.Int32,
    ffi.Pointer<pkgffi.Utf8>, ffi.Pointer<pkgffi.Utf8>);
typedef _BidiSend = int Function(
    ffi.Pointer<ffi.Void>, int, ffi.Pointer<pkgffi.Utf8>, ffi.Pointer<pkgffi.Utf8>);

typedef _BidiPollReplyC = ffi.Pointer<pkgffi.Utf8> Function(
    ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _BidiPollReply = ffi.Pointer<pkgffi.Utf8> Function(
    ffi.Pointer<ffi.Void>, int);

typedef _BidiCancelC = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _BidiCancel = void Function(ffi.Pointer<ffi.Void>, int);

typedef _BidiSubC = ffi.Pointer<pkgffi.Utf8> Function(
    ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Pointer<pkgffi.Utf8>, ffi.Int32);
typedef _BidiSub = ffi.Pointer<pkgffi.Utf8> Function(
    ffi.Pointer<ffi.Void>, int, ffi.Pointer<pkgffi.Utf8>, int);

typedef _BidiWaitEventC = ffi.Pointer<pkgffi.Utf8> Function(
    ffi.Pointer<ffi.Void>, ffi.Pointer<pkgffi.Utf8>, ffi.Int32);
typedef _BidiWaitEvent = ffi.Pointer<pkgffi.Utf8> Function(
    ffi.Pointer<ffi.Void>, ffi.Pointer<pkgffi.Utf8>, int);

/// A loaded engine: the [ffi.DynamicLibrary] plus every symbol bound once.
class Native {
  final _Open open;
  final _Close close;
  final _Execute execute;
  final _HandleToStr lastValue;
  final _HandleToInt lastStatus;
  final _HandleToInt lastErrorCode;
  final _HandleToStr lastError;
  final _HandleToStr sessionId;
  final _Str2ToStr byLocator;
  final _StrToStr route;
  final _StrToInt errorCode;
  final _FreeString freeString;

  // ---- WebDriver-BiDi ----
  final _Open bidiOpen;
  final _Close bidiClose;
  final _BidiSend bidiSend;
  final _BidiPump bidiPump;
  final _HandleToInt bidiFd;
  final _BidiPollReply bidiPollReply;
  final _HandleToStr bidiPollEvent;
  final _HandleToInt bidiLostEvents;
  final _BidiCancel bidiCancel;
  final _BidiSub bidiSubscribe;
  final _BidiSub bidiUnsubscribe;
  final _BidiWaitEvent bidiWaitEvent;

  Native._(ffi.DynamicLibrary lib)
      : open = lib.lookupFunction<_OpenC, _Open>('aether_sel_embed_open'),
        close = lib.lookupFunction<_CloseC, _Close>('aether_sel_embed_close'),
        execute =
            lib.lookupFunction<_ExecuteC, _Execute>('aether_sel_embed_execute'),
        lastValue = lib.lookupFunction<_HandleToStrC, _HandleToStr>(
            'aether_sel_embed_last_value'),
        lastStatus = lib.lookupFunction<_HandleToIntC, _HandleToInt>(
            'aether_sel_embed_last_status'),
        lastErrorCode = lib.lookupFunction<_HandleToIntC, _HandleToInt>(
            'aether_sel_embed_last_error_code'),
        lastError = lib.lookupFunction<_HandleToStrC, _HandleToStr>(
            'aether_sel_embed_last_error'),
        sessionId = lib.lookupFunction<_HandleToStrC, _HandleToStr>(
            'aether_sel_embed_session_id'),
        byLocator = lib.lookupFunction<_Str2ToStrC, _Str2ToStr>(
            'aether_sel_embed_by_locator'),
        route =
            lib.lookupFunction<_StrToStrC, _StrToStr>('aether_sel_embed_route'),
        errorCode = lib.lookupFunction<_StrToIntC, _StrToInt>(
            'aether_sel_embed_error_code'),
        freeString = lib.lookupFunction<_FreeStringC, _FreeString>(
            'aether_sel_embed_free_string'),
        bidiOpen =
            lib.lookupFunction<_OpenC, _Open>('aether_sel_embed_bidi_open'),
        bidiClose =
            lib.lookupFunction<_CloseC, _Close>('aether_sel_embed_bidi_close'),
        bidiSend = lib.lookupFunction<_BidiSendC, _BidiSend>(
            'aether_sel_embed_bidi_send'),
        bidiPump = lib.lookupFunction<_BidiPumpC, _BidiPump>(
            'aether_sel_embed_bidi_pump'),
        bidiFd = lib.lookupFunction<_HandleToIntC, _HandleToInt>(
            'aether_sel_embed_bidi_fd'),
        bidiPollReply = lib.lookupFunction<_BidiPollReplyC, _BidiPollReply>(
            'aether_sel_embed_bidi_poll_reply'),
        bidiPollEvent = lib.lookupFunction<_HandleToStrC, _HandleToStr>(
            'aether_sel_embed_bidi_poll_event'),
        bidiLostEvents = lib.lookupFunction<_HandleToIntC, _HandleToInt>(
            'aether_sel_embed_bidi_lost_events'),
        bidiCancel = lib.lookupFunction<_BidiCancelC, _BidiCancel>(
            'aether_sel_embed_bidi_cancel'),
        bidiSubscribe = lib.lookupFunction<_BidiSubC, _BidiSub>(
            'aether_sel_embed_bidi_subscribe'),
        bidiUnsubscribe = lib.lookupFunction<_BidiSubC, _BidiSub>(
            'aether_sel_embed_bidi_unsubscribe'),
        bidiWaitEvent = lib.lookupFunction<_BidiWaitEventC, _BidiWaitEvent>(
            'aether_sel_embed_bidi_wait_event');

  static Native? _instance;
  static String? _explicitPath;

  /// Pin an explicit library path (wins over env/bundled).
  static void configure(String? path) {
    if (path != null && path.isNotEmpty && _instance == null) {
      _explicitPath = path;
    }
  }

  static Native get instance => _instance ??= Native._(_load());

  static String _fileName() {
    if (Platform.isWindows) return 'selenium_core.dll';
    if (Platform.isMacOS) return 'libselenium_core.dylib';
    return 'libselenium_core.so';
  }

  static ffi.DynamicLibrary _load() {
    for (final candidate in _candidates()) {
      try {
        return ffi.DynamicLibrary.open(candidate);
      } catch (_) {
        // try next
      }
    }
    // Bare name (OS loader).
    return ffi.DynamicLibrary.open(_fileName());
  }

  static Iterable<String> _candidates() sync* {
    if (_explicitPath != null && _explicitPath!.isNotEmpty) yield _explicitPath!;
    final env = Platform.environment['SELENIUM_CORE_LIB'];
    if (env != null && env.isNotEmpty) yield env;
    // Bundled next to the package: <pkg>/native/<lib>. Resolve relative to the
    // script's package when possible; else a plain relative path.
    yield 'native/${_fileName()}';
  }

  /// Copy a caller-owned native char* into a Dart String, then free it.
  String takeString(ffi.Pointer<pkgffi.Utf8> ptr) {
    if (ptr == ffi.nullptr) return '';
    try {
      return ptr.toDartString();
    } finally {
      freeString(ptr);
    }
  }
}
