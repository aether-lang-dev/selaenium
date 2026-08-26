#if defined(__MINGW32__) && !defined(__USE_MINGW_ANSI_STDIO)
#define __USE_MINGW_ANSI_STDIO 1
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdatomic.h>
#include <stdint.h>
#include <time.h>
#include <setjmp.h>
#include "aether_panic.h"
#include "aether_stringseq.h"
#ifdef _WIN32
#define NOMINMAX
#include <windows.h>
#include <io.h>      // _setmode, _fileno
#include <fcntl.h>   // _O_BINARY
#elif defined(__EMSCRIPTEN__)
#include <emscripten.h>
#else
#include <unistd.h>
#include <sched.h>
#endif
#ifdef _WIN32
#  define aether_aligned_alloc(align, size) _aligned_malloc((size), (align))
#else
#  define aether_aligned_alloc(align, size) aligned_alloc((align), (size))
#endif
#ifndef likely
#  if defined(__GNUC__) || defined(__clang__)
#    define likely(x)   __builtin_expect(!!(x), 1)
#    define unlikely(x) __builtin_expect(!!(x), 0)
#  else
#    define likely(x)   (x)
#    define unlikely(x) (x)
#  endif
#endif
#ifndef AETHER_MAYBE_UNUSED
#  if defined(__GNUC__) || defined(__clang__)
#    define AETHER_MAYBE_UNUSED __attribute__((unused))
#  else
#    define AETHER_MAYBE_UNUSED
#  endif
#endif
#ifndef AETHER_GCC_COMPAT
#  if (defined(__GNUC__) || defined(__clang__)) && !defined(__EMSCRIPTEN__)
#    define AETHER_GCC_COMPAT 1
#  else
#    define AETHER_GCC_COMPAT 0
#  endif
#endif
#if defined(__GNUC__) || defined(__clang__)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-function"
#endif
#ifdef _WIN32
static inline int64_t _aether_clock_ns(void) {
    LARGE_INTEGER freq, now;
    QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&now);
    return (int64_t)((double)now.QuadPart / freq.QuadPart * 1000000000.0);
}
#elif defined(__EMSCRIPTEN__)
static inline int64_t _aether_clock_ns(void) {
    return (int64_t)(emscripten_get_now() * 1000000.0);
}
#elif defined(__STDC_HOSTED__) && (__STDC_HOSTED__ == 0)
static inline int64_t _aether_clock_ns(void) { return 0; }
#else
static inline int64_t _aether_clock_ns(void) {
    struct timespec _ts;
    clock_gettime(CLOCK_MONOTONIC, &_ts);
    return (int64_t)_ts.tv_sec * 1000000000LL + _ts.tv_nsec;
}
#endif
#include <string.h>
#include <stdlib.h>
#include <stddef.h>
extern void* aether_caps_malloc(size_t bytes);
extern void* string_new_with_length(const char* data, int length);
static inline const char* aether_uniform_heap_str(const char* s, int is_heap) {
    if (!s) return (const char*)0;
    if (is_heap) return s;
    /* AetherString-aware length probe, see is_aether_string in
     * std/string/aether_string.h. Byte-by-byte to stay ASan-clean
     * on short literal allocations (e.g. "x"). */
    const unsigned char* _p = (const unsigned char*)s;
    const char* _data = s;
    size_t _n;
    if (_p[0] == 0xDE && _p[1] == 0xC0 && _p[2] == 0x57 && _p[3] == 0xAE) {
        /* Struct layout: magic(u32), ref_count(i32), length(size_t),
         * capacity(size_t), data(char*). Read length and data via
         * a typed view, the struct's data pointer is what we copy. */
        struct _AeStrHdr { unsigned int magic; int ref_count; size_t length; size_t capacity; char* data; };
        const struct _AeStrHdr* _h = (const struct _AeStrHdr*)s;
        _n = _h->length;
        _data = _h->data ? _h->data : s;
    } else {
        _n = strlen(s);
    }
    return (const char*)string_new_with_length(_data, (int)_n);
}
extern void string_release(const char*);
typedef void (*AetherUnwindFree)(const void*);
extern void aether_unwind_track(const void*, AetherUnwindFree);
extern void aether_unwind_track_if(const void*, int, AetherUnwindFree);
extern void aether_unwind_forget(const void*);
static inline void aether_heap_str_free(const char* s) {
    if (!s) return;
    aether_unwind_forget(s);
    const unsigned char* _hp = (const unsigned char*)s;
    if (_hp[0] == 0xDE && _hp[1] == 0xC0 && _hp[2] == 0x57 && _hp[3] == 0xAE) {
        string_release(s);
    } else {
        free((void*)s);
    }
}
static void aether_unwind_free_str(const void* p) {
    aether_heap_str_free((const char*)p);
}
static inline void aether_unwind_track_str(const char* s) {
    aether_unwind_track(s, aether_unwind_free_str);
}
static inline void aether_unwind_track_str_if(const char* s, int owned) {
    if (owned) aether_unwind_track(s, aether_unwind_free_str);
}
extern void string_retain(const char*);
extern const char* aether_string_capture_owned(const char*);
extern void aether_string_release_captured(const char*);
static inline const char* aether_str_capture(const char* s) {
    return aether_string_capture_owned(s);
}
int string_char_at(const char*, int);
int string_equals(const char*, const char*);
int list_add_closure_owned(void*, void*);
#include <stdarg.h>
extern void* string_alloc_inline(size_t length);
extern char* aether_string_mutable_data(void* s);
static void* _aether_interp(const char* fmt, ...) {
    va_list args, args2;
    va_start(args, fmt);
    va_copy(args2, args);
    int len = vsnprintf(NULL, 0, fmt, args);
    va_end(args);
    if (len < 0) { va_end(args2); return (void*)0; }
    void* owned = string_alloc_inline((size_t)len);
    if (!owned) { va_end(args2); return (void*)0; }
    vsnprintf(aether_string_mutable_data(owned), (size_t)len + 1, fmt, args2);
    va_end(args2);
    return owned;
}
extern const char* aether_string_data(const void* s);
extern size_t aether_string_length(const void* s);
extern void* string_new_with_length(const char* data, int length);
extern int list_add_string_adopted(void* list, void* item);
extern int map_put_string_adopted(void* map, const char* key, void* value);
static inline const char* _aether_list_add_adopted(void* list, void* item) {
    return list_add_string_adopted(list, item) ? "" : "list.add failed";
}
static inline const char* _aether_map_put_adopted(void* map, const char* key, void* value) {
    return map_put_string_adopted(map, key, value) ? "" : "map.put failed";
}
static inline const char* _aether_list_add_closure(void* list, void* box) {
    return list_add_closure_owned(list, box) ? "" : "list.add failed";
}
static inline const char* _aether_safe_str(const void* s) {
    if (!s) return "(null)";
    return aether_string_data(s);
}
static inline int _aether_println_owned(const char* s) {
    int _n = printf("%s\n", _aether_safe_str(s));
    aether_heap_str_free((void*)s);
    return _n;
}
static inline int _aether_print_owned(const char* s) {
    int _n = printf("%s", _aether_safe_str(s));
    aether_heap_str_free((void*)s);
    return _n;
}
#define AE_DUR_BUFS 8
static inline const char* _aether_duration_repr(int64_t ns) {
    static char _bufs[AE_DUR_BUFS][64];
    static unsigned _slot = 0;
    char* _buf = _bufs[_slot];
    _slot = (_slot + 1) % AE_DUR_BUFS;
    int64_t abs_ns = ns < 0 ? -ns : ns;
    struct _du { const char* suffix; int64_t scale; } units[] = {
        {"d", 86400000000000LL}, {"h", 3600000000000LL},
        {"m", 60000000000LL}, {"s", 1000000000LL},
        {"ms", 1000000LL}, {"us", 1000LL}, {"ns", 1LL}
    };
    for (size_t i = 0; i < sizeof(units) / sizeof(units[0]); i++) {
        if (abs_ns >= units[i].scale || units[i].scale == 1) {
            if (ns % units[i].scale == 0) {
                snprintf(_buf, 64, "%lld%s", (long long)(ns / units[i].scale), units[i].suffix);
            } else {
                double v = (double)ns / (double)units[i].scale;
                snprintf(_buf, 64, "%.9g%s", v, units[i].suffix);
            }
            return _buf;
        }
    }
    return "0ns";
}
extern void aether_sleep_ms(int ms);
#if !AETHER_GCC_COMPAT
static void* _aether_ref_new(intptr_t val) { intptr_t* r = malloc(sizeof(intptr_t)); *r = val; return (void*)r; }
#endif
typedef struct { void (*fn)(void); void* env; } _AeClosure;
typedef struct { void (*fn)(void); void* env; unsigned long long tag; } _AeClosureBox;
#define _AE_CLOSURE_TAG 0xAEC105EDB0CEDULL
static inline void* _aether_box_closure(_AeClosure c) {
    _AeClosureBox* p = (_AeClosureBox*)malloc(sizeof(_AeClosureBox));
    if (!p) return (void*)0;
    p->fn = c.fn; p->env = c.env; p->tag = _AE_CLOSURE_TAG;
    return (void*)p;
}
static inline _AeClosure _aether_unbox_closure(void* p) {
    if (!p || ((const _AeClosureBox*)p)->tag != _AE_CLOSURE_TAG) {
        aether_panic("unbox_closure() on a value that was never boxed. "
                     "A bare function stored into a `ptr` slot stays a raw code "
                     "pointer; only a value that crossed an `fn`-typed boundary or "
                     "went through box_closure() carries an environment. Declare the "
                     "slot `fn`, or box explicitly before storing it.");
    }
    _AeClosure c;
    c.fn = ((const _AeClosureBox*)p)->fn;
    c.env = ((const _AeClosureBox*)p)->env;
    return c;
}
typedef struct { _AeClosure compute; intptr_t value; int evaluated; } _AeThunk;
static inline void* _aether_thunk_new(_AeClosure c) { _AeThunk* t = malloc(sizeof(_AeThunk)); t->compute = c; t->value = 0; t->evaluated = 0; return (void*)t; }
static inline intptr_t _aether_thunk_force(void* p) { _AeThunk* t = (_AeThunk*)p; if (!t->evaluated) { t->value = (intptr_t)((intptr_t(*)(void*))t->compute.fn)(t->compute.env); t->evaluated = 1; } return t->value; }
static inline void _aether_thunk_free(void* p) { if (p) free(p); }
#if !defined(_WIN32) && !defined(__EMSCRIPTEN__) && defined(__STDC_HOSTED__) && (__STDC_HOSTED__ == 1) && !defined(__arm__) && !defined(__thumb__)
#include <termios.h>
static struct termios _aether_orig_termios;
static void _aether_raw_mode(void) {
    tcgetattr(0, &_aether_orig_termios);
    struct termios raw = _aether_orig_termios;
    raw.c_lflag &= ~(ICANON | ECHO);
    tcsetattr(0, TCSANOW, &raw);
}
static void _aether_cooked_mode(void) {
    tcsetattr(0, TCSANOW, &_aether_orig_termios);
}
#else
static void _aether_raw_mode(void) {}
static void _aether_cooked_mode(void) {}
#endif
static void* _aether_ctx_stack[64];
static int _aether_ctx_depth = 0;
static inline void _aether_ctx_push(void* ctx) { if (_aether_ctx_depth < 64) _aether_ctx_stack[_aether_ctx_depth++] = ctx; }
static inline void _aether_ctx_pop(void) { if (_aether_ctx_depth > 0) _aether_ctx_depth--; }
static inline void* _aether_ctx_get(void) { return _aether_ctx_depth > 0 ? _aether_ctx_stack[_aether_ctx_depth-1] : (void*)0; }

#if defined(__GNUC__) || defined(__clang__)
#pragma GCC diagnostic pop
#endif

void aether_args_init(int argc, char** argv);
void aether_capsicum_autosandbox(void);



typedef struct LocalTime LocalTime;
typedef struct LocalTime {
    int year;
    int month;
    int day;
    int hour;
    int minute;
    int second;
    int nanos;
    int tz_offset_minutes;
} LocalTime;

typedef struct { int _0; const char* _1; } _tuple_int_string;
typedef struct { const char* _0; int _1; const char* _2; } _tuple_string_int_string;
typedef struct { const char* _0; const char* _1; } _tuple_string_string;
typedef struct { int _0; int _1; const char* _2; } _tuple_int_int_string;
typedef struct { int _0; int _1; int _2; const char* _3; } _tuple_int_int_int_string;
typedef struct { const char* _0; const char* _1; int _2; const char* _3; } _tuple_string_string_int_string;
typedef struct { int _0; int _1; int _2; int _3; } _tuple_int_int_int_int;
typedef struct { void* _0; const char* _1; } _tuple_ptr_string;
static const int fs_KIND_OK = (0);
static const int fs_KIND_NOT_FOUND = (1);
static const int fs_KIND_PERMISSION_DENIED = (2);
static const int fs_KIND_EXISTS = (3);
static const int fs_KIND_CROSS_DEVICE = (4);
static const int fs_KIND_IO = (5);
static const int fs_KIND_INVALID = (6);
static const int fs_KIND_LOOP = (7);
static const int fs_KIND_NAME_TOO_LONG = (8);
static const int fs_KIND_NO_SPACE = (9);
static const int fs_KIND_IS_DIR = (10);
static const int fs_KIND_NOT_DIR = (11);
static const int fs_KIND_UNAVAILABLE = (99);
static const int fs_STAT_KIND_FILE = (1);
static const int fs_STAT_KIND_DIR = (2);
static const int fs_STAT_KIND_SYMLINK = (3);
static const int fs_STAT_KIND_OTHER = (4);
static const int fs_STAT_KIND_SOCKET = (5);
static const int fs_STAT_KIND_FIFO = (6);
static const int fs_STAT_KIND_DEVICE = (7);
// Forward declarations
static AETHER_MAYBE_UNUSED void* build_session(const char*);
static AETHER_MAYBE_UNUSED const char* build__label_buildtype(const char*);
static AETHER_MAYBE_UNUSED const char* build__label_dir(const char*);
static AETHER_MAYBE_UNUSED void build_done(void*, const char*);
static AETHER_MAYBE_UNUSED void build__mark_failed(void*, const char*, const char*);
static AETHER_MAYBE_UNUSED int build_record_status(void*, const char*, int);
static AETHER_MAYBE_UNUSED void* build_session_handle(void*);
static AETHER_MAYBE_UNUSED const char* build_status_of(void*, const char*);
static AETHER_MAYBE_UNUSED int build_any_failed(void*);
static AETHER_MAYBE_UNUSED const char* build__host_os(void);
static AETHER_MAYBE_UNUSED int build__is_windows(void);
static AETHER_MAYBE_UNUSED int build__has_windows_drive_prefix(const char*);
static AETHER_MAYBE_UNUSED int build__is_abs_path(const char*);
static AETHER_MAYBE_UNUSED int build__path_is_sep(const char*);
static AETHER_MAYBE_UNUSED const char* build__path_rstrip_seps(const char*);
static AETHER_MAYBE_UNUSED int build__path_last_sep(const char*);
static AETHER_MAYBE_UNUSED const char* build__dirname(const char*);
static AETHER_MAYBE_UNUSED const char* build__path_join(const char*, const char*);
static AETHER_MAYBE_UNUSED const char* build__sh_quote(const char*);
static AETHER_MAYBE_UNUSED const char* build__cmd_caret_escape(const char*);
static AETHER_MAYBE_UNUSED const char* build__sh_wrap(const char*);
static AETHER_MAYBE_UNUSED const char* build__sh_slashes(const char*);
static AETHER_MAYBE_UNUSED int build__sh_hash(const char*);
static AETHER_MAYBE_UNUSED const char* build__cygpath_m_via_sh(const char*);
static AETHER_MAYBE_UNUSED const char* build__sh_script_path(const char*);
static AETHER_MAYBE_UNUSED void build__sh_trace(const char*);
static AETHER_MAYBE_UNUSED _tuple_string_string build__sh_capture(const char*);
static AETHER_MAYBE_UNUSED const char* build__aether_dev_root(const char*);
static AETHER_MAYBE_UNUSED const char* build__resolve_aether_dir(void);
static AETHER_MAYBE_UNUSED const char* build__to_native_path(const char*);
static AETHER_MAYBE_UNUSED int build__is_abs_native(const char*);
static AETHER_MAYBE_UNUSED const char* build__aether_dev_bin_dir(const char*);
static AETHER_MAYBE_UNUSED const char* build__resolve_libaether_dir(const char*);
static AETHER_MAYBE_UNUSED void build__mkdirs(const char*);
static AETHER_MAYBE_UNUSED void* build__get(void*, const char*);
static AETHER_MAYBE_UNUSED void* build_target_dir(void*);
static AETHER_MAYBE_UNUSED void* build_source_dir(void*);
static AETHER_MAYBE_UNUSED void* build_root(void*);
static AETHER_MAYBE_UNUSED const char* build__dep_target_dir(const char*, const char*);
static AETHER_MAYBE_UNUSED int build__last_slash(const char*);
static AETHER_MAYBE_UNUSED const char* build__project_run_cmd(const char*, void*, void*);
static AETHER_MAYBE_UNUSED const char* build__run_project_cmd(const char*, const char*, void*, const char*);
static AETHER_MAYBE_UNUSED void build__record_cache(void*, const char*);
static AETHER_MAYBE_UNUSED const char* build__read_cache_outcome(const char*);
static AETHER_MAYBE_UNUSED _tuple_string_string build__tar_dir(const char*);
static AETHER_MAYBE_UNUSED const char* build__tar_local_flag(void);
static AETHER_MAYBE_UNUSED void build__record_test_result(void*, int, int);
static AETHER_MAYBE_UNUSED int build__int_key(void*, const char*);
static AETHER_MAYBE_UNUSED const char* build__str_key(void*, const char*);
static AETHER_MAYBE_UNUSED void build__record_test_result_r(void*, int, int, int, int);
static AETHER_MAYBE_UNUSED _tuple_int_int_int_int build__read_test_result(const char*);
static AETHER_MAYBE_UNUSED int build__read_test_report_flag(const char*);
static AETHER_MAYBE_UNUSED const char* build__read_test_failures(const char*);
static AETHER_MAYBE_UNUSED const char* build__exec_chain_cmd(void*, const char*, void*);
static AETHER_MAYBE_UNUSED int build__exec_chain_is_passthrough(void*, void*);
static AETHER_MAYBE_UNUSED const char* build__exec_chain_body(void*, const char*, void*);
static AETHER_MAYBE_UNUSED const char* build__label_to_target_dir(const char*, const char*);
static AETHER_MAYBE_UNUSED const char* build__label_display(const char*);
static AETHER_MAYBE_UNUSED int build__status_is_failed(const char*);
static AETHER_MAYBE_UNUSED const char* build__format_telemetry_line(const char*, const char*, int, const char*, int, int, int, const char*);
static AETHER_MAYBE_UNUSED const char* build_render_telemetry(void*, int);
static AETHER_MAYBE_UNUSED const char* build__json_escape(const char*);
static AETHER_MAYBE_UNUSED const char* build__json_str(const char*);
static AETHER_MAYBE_UNUSED const char* build__record_json(void*);
static AETHER_MAYBE_UNUSED const char* build__telemetry_status(void*);
static AETHER_MAYBE_UNUSED const char* build_render_telemetry_json(void*, int);
static AETHER_MAYBE_UNUSED const char* build_render_tests_json(void*);
static AETHER_MAYBE_UNUSED const char* build_render_artifacts_json(const char*, void*);
static AETHER_MAYBE_UNUSED const char* build__collect_file_list(const char*);
static AETHER_MAYBE_UNUSED _tuple_int_string string_to_int(const char*);
static AETHER_MAYBE_UNUSED const char* string_copy(const char*);
static AETHER_MAYBE_UNUSED _tuple_string_string io_read_file(const char*);
static AETHER_MAYBE_UNUSED const char* io_write_file(const char*, const char*);
static AETHER_MAYBE_UNUSED const char* io_append_file(const char*, const char*);
static AETHER_MAYBE_UNUSED const char* io_delete_file(const char*);
static AETHER_MAYBE_UNUSED _tuple_string_int_string io_fd_read_n(int, int);
static AETHER_MAYBE_UNUSED _tuple_string_string io_fd_read_line(int);
static AETHER_MAYBE_UNUSED int os_args_count(void);
static AETHER_MAYBE_UNUSED _tuple_string_string os_exec(const char*);
static AETHER_MAYBE_UNUSED const char* os_platform(void);
static AETHER_MAYBE_UNUSED const char* os_temp_dir(void);
static AETHER_MAYBE_UNUSED int os_getpid(void);
static AETHER_MAYBE_UNUSED int64_t os_now_monotonic_ns(void);
static AETHER_MAYBE_UNUSED int file_fd(void*);
static AETHER_MAYBE_UNUSED _tuple_string_string fs_read(const char*);
static AETHER_MAYBE_UNUSED const char* fs_delete(const char*);
static AETHER_MAYBE_UNUSED int fs_exists(const char*);
static AETHER_MAYBE_UNUSED const char* fs_create_dir(const char*);
static AETHER_MAYBE_UNUSED const char* fs_delete_dir(const char*);
static AETHER_MAYBE_UNUSED const char* fs_mkdir_p(const char*);
static AETHER_MAYBE_UNUSED _tuple_ptr_string fs_list_dir(const char*);
static AETHER_MAYBE_UNUSED _tuple_ptr_string fs_glob(const char*);
static AETHER_MAYBE_UNUSED const char* fs_write_atomic(const char*, const char*, int);
static AETHER_MAYBE_UNUSED int fs_is_within_base(const char*, const char*);
static AETHER_MAYBE_UNUSED int fs_fd(void*);
static AETHER_MAYBE_UNUSED const char* list_add(void*, void*);
static AETHER_MAYBE_UNUSED _tuple_ptr_string list_get(void*, int);
static AETHER_MAYBE_UNUSED const char* map_put(void*, const char*, void*);
static AETHER_MAYBE_UNUSED _tuple_ptr_string map_get(void*, const char*);
static AETHER_MAYBE_UNUSED _tuple_ptr_string dir_list(const char*);

// Extern C function: string_new
void* string_new(const char*);

// Extern C function: string_from_cstr
void* string_from_cstr(const char*);

// Extern C function: string_from_literal
void* string_from_literal(const char*);

// Extern C function: string_new_with_length
void* string_new_with_length(const char*, int);

// Extern C function: string_empty
void* string_empty(void);

// Extern C function: string_retain
void string_retain(const char*);

// Extern C function: string_release
void string_release(const char*);

// Extern C function: string_free
void string_free(const char*);

// Extern C function: string_concat
const char* string_concat(const char*, const char*);

// Extern C function: string_concat_wrapped
const char* string_concat_wrapped(const char*, const char*);

// Extern C function: string_length
int string_length(const char*);

// Extern C function: string_char_at
int string_char_at(const char*, int);

// Extern C function: string_equals
int string_equals(const char*, const char*);

// Extern C function: string_compare
int string_compare(const char*, const char*);

// Extern C function: string_starts_with
int string_starts_with(const char*, const char*);

// Extern C function: string_ends_with
int string_ends_with(const char*, const char*);

// Extern C function: string_contains
int string_contains(const char*, const char*);

// Extern C function: string_index_of
int string_index_of(const char*, const char*);

// Extern C function: string_index_of_from
int string_index_of_from(const char*, const char*, int);

// Extern C function: string_replace
const char* string_replace(const char*, const char*, const char*);

// Extern C function: string_replace_all
const char* string_replace_all(const char*, const char*, const char*);

// Extern C function: string_substring
const char* string_substring(const char*, int, int);

// Extern C function: string_substring_n
const char* string_substring_n(const char*, int, int, int);

// Extern C function: string_length_n
int string_length_n(const char*, int);

// Extern C function: string_char_at_n
int string_char_at_n(const char*, int, int);

// Extern C function: string_index_of_from_n
int string_index_of_from_n(const char*, int, const char*, int);

// Extern C function: string_from_char
void* string_from_char(int);

// Extern C function: string_to_upper
const char* string_to_upper(const char*);

// Extern C function: string_to_lower
const char* string_to_lower(const char*);

// Extern C function: string_trim
const char* string_trim(const char*);

// Extern C function: string_split
void* string_split(const char*, const char*);

// Extern C function: string_array_size
int string_array_size(void*);

// Extern C function: string_array_get
void* string_array_get(void*, int);

// Extern C function: string_array_free
void string_array_free(void*);

// Extern C function: string_split_to_seq
StringSeq* string_split_to_seq(const char*, const char*);

// Extern C function: string_join
const char* string_join(StringSeq*, const char*);

// Extern C function: string_seq_empty
StringSeq* string_seq_empty(void);

// Extern C function: string_seq_cons
StringSeq* string_seq_cons(const char*, StringSeq*);

// Extern C function: string_seq_head
const char* string_seq_head(StringSeq*);

// Extern C function: string_seq_tail
StringSeq* string_seq_tail(StringSeq*);

// Extern C function: string_seq_is_empty
int string_seq_is_empty(StringSeq*);

// Extern C function: string_seq_length
int string_seq_length(StringSeq*);

// Extern C function: string_seq_retain
StringSeq* string_seq_retain(StringSeq*);

// Extern C function: string_seq_free
void string_seq_free(StringSeq*);

// Extern C function: string_seq_from_array
StringSeq* string_seq_from_array(void*, int);

// Extern C function: string_seq_to_array
void* string_seq_to_array(StringSeq*);

// Extern C function: string_seq_reverse
StringSeq* string_seq_reverse(StringSeq*);

// Extern C function: string_seq_concat
StringSeq* string_seq_concat(StringSeq*, StringSeq*);

// Extern C function: string_seq_join
const char* string_seq_join(StringSeq*, const char*);

// Extern C function: string_seq_take
StringSeq* string_seq_take(StringSeq*, int);

// Extern C function: string_seq_drop
StringSeq* string_seq_drop(StringSeq*, int);

// Extern C function: string_seq_each
void string_seq_each(StringSeq*, void*);

// Extern C function: string_seq_map
StringSeq* string_seq_map(StringSeq*, void*);

// Extern C function: string_seq_filter
StringSeq* string_seq_filter(StringSeq*, void*);

// Extern C function: string_seq_reduce
void* string_seq_reduce(StringSeq*, void*, void*);

// Extern C function: string_seq_zip_each
void string_seq_zip_each(StringSeq*, StringSeq*, void*);

// Extern C function: string_to_cstr
const char* string_to_cstr(const char*);

// Extern C function: string_from_int
void* string_from_int(int);

// Extern C function: string_from_long
void* string_from_long(int64_t);

// Extern C function: string_from_float
void* string_from_float(double);

// Extern C function: string_from_double
const char* string_from_double(double);

// Extern C function: string_from_int_radix
void* string_from_int_radix(int64_t, int);

// Extern C function: string_pad_start
void* string_pad_start(const char*, int, int);

// Extern C function: string_pad_end
void* string_pad_end(const char*, int, int);

// Extern C function: string_to_int_raw
int string_to_int_raw(const char*, void*);

// Extern C function: string_to_long_raw
int string_to_long_raw(const char*, void*);

// Extern C function: string_to_float_raw
int string_to_float_raw(const char*, void*);

// Extern C function: string_to_double_raw
int string_to_double_raw(const char*, void*);

// Extern C function: string_to_int_radix_raw
int string_to_int_radix_raw(const char*, int, void*);

// Extern C function: string_try_int
int string_try_int(const char*);

// Extern C function: string_get_int
int string_get_int(const char*);

// Extern C function: string_try_long
int string_try_long(const char*);

// Extern C function: string_get_long
int64_t string_get_long(const char*);

// Extern C function: string_try_float
int string_try_float(const char*);

// Extern C function: string_get_float
double string_get_float(const char*);

// Extern C function: string_try_double
int string_try_double(const char*);

// Extern C function: string_get_double
double string_get_double(const char*);

// Extern C function: string_try_int_radix
int string_try_int_radix(const char*, int);

// Extern C function: string_get_int_radix
int64_t string_get_int_radix(const char*, int);

// Extern C function: string_format_list
void* string_format_list(const char*, void*);

// Extern C function: string_glob_match_raw
int string_glob_match_raw(const char*, const char*, int);

// Extern C function: io_print
void io_print(const char*);

// Extern C function: io_print_line
void io_print_line(const char*);

// Extern C function: io_print_int
void io_print_int(int);

// Extern C function: io_print_float
void io_print_float(double);

// Extern C function: io_read_file_raw
const char* io_read_file_raw(const char*);

// Extern C function: io_write_file_raw
int io_write_file_raw(const char*, const char*);

// Extern C function: io_append_file_raw
int io_append_file_raw(const char*, const char*);

// Extern C function: io_file_exists
int io_file_exists(const char*);

// Extern C function: io_delete_file_raw
int io_delete_file_raw(const char*);

// Extern C function: io_file_info_raw
void* io_file_info_raw(const char*);

// Extern C function: io_file_info_free
void io_file_info_free(void*);

// Extern C function: io_getenv
const char* io_getenv(const char*);

// Extern C function: io_setenv_raw
int io_setenv_raw(const char*, const char*);

// Extern C function: io_unsetenv_raw
int io_unsetenv_raw(const char*);

// Extern C function: io_stderr_write_raw
int io_stderr_write_raw(const char*, int);

// Extern C function: io_stdout_write_raw
int io_stdout_write_raw(const char*, int);

// Extern C function: io_perror_raw
void io_perror_raw(const char*);

// Extern C function: io_errno_message_raw
const char* io_errno_message_raw(void);

// Extern C function: io_fd_open_read_tuple
_tuple_int_string io_fd_open_read_tuple(const char*);

// Extern C function: io_fd_open_write_tuple
_tuple_int_string io_fd_open_write_tuple(const char*);

// Extern C function: io_fd_close_raw
const char* io_fd_close_raw(int);

// Extern C function: io_fd_write_n
int io_fd_write_n(int, const char*, int);

// Extern C function: io_fd_read_n_tuple
_tuple_string_int_string io_fd_read_n_tuple(int, int);

// Extern C function: io_fd_read_into_raw
int io_fd_read_into_raw(int, void*, int);

// Extern C function: io_fd_read_line_tuple
_tuple_string_string io_fd_read_line_tuple(int);

// Extern C function: string_concat
const char* string_concat(const char*, const char*);

// Extern C function: os_system
int os_system(const char*);

// Extern C function: os_exec_raw
const char* os_exec_raw(const char*);

// Extern C function: os_run
int os_run(const char*, void*, void*);

// Extern C function: os_run_capture_raw
const char* os_run_capture_raw(const char*, void*, void*);

// Extern C function: os_run_capture_status_raw
_tuple_string_int_string os_run_capture_status_raw(const char*, void*, void*);

// Extern C function: os_run_pipe_raw
_tuple_int_int_string os_run_pipe_raw(const char*, void*, void*);

// Extern C function: os_wait_pid_raw
_tuple_int_string os_wait_pid_raw(int);

// Extern C function: os_run_pipe_drain_and_wait_raw
_tuple_string_int_string os_run_pipe_drain_and_wait_raw(const char*, void*, void*);

// Extern C function: os_spawn_raw
_tuple_int_string os_spawn_raw(const char*, void*, void*);

// Extern C function: os_wait_raw
_tuple_int_string os_wait_raw(int);

// Extern C function: os_wait_any_raw
_tuple_int_int_string os_wait_any_raw(void*);

// Extern C function: os_wait_any_timeout_raw
_tuple_int_int_int_string os_wait_any_timeout_raw(void*, int);

// Extern C function: os_getenv
const char* os_getenv(const char*);

// Extern C function: io_setenv_raw
int io_setenv_raw(const char*, const char*);

// Extern C function: io_unsetenv_raw
int io_unsetenv_raw(const char*);

// Extern C function: os_which
const char* os_which(const char*);

// Extern C function: aether_args_count
int aether_args_count(void);

// Extern C function: aether_args_get
const char* aether_args_get(int);

// Extern C function: aether_argv0
const char* aether_argv0(void);

// Extern C function: aether_argv_raw
void* aether_argv_raw(void);

// Extern C function: aether_args_seal
void aether_args_seal(void);

// Extern C function: aether_args_sealed
int aether_args_sealed(void);

// Extern C function: os_execv
int os_execv(const char*, void*);

// Extern C function: string_concat
const char* string_concat(const char*, const char*);

// Extern C function: os_kill_raw
int os_kill_raw(int, int);

// Extern C function: os_wait_pid_timeout_raw
_tuple_int_int_string os_wait_pid_timeout_raw(int, int);

// Extern C function: os_run_supervised_raw
_tuple_int_string os_run_supervised_raw(const char*, void*, void*, int, int, int, int);

// Extern C function: string_length
int string_length(const char*);

// Extern C function: os_run_full_raw
_tuple_string_string_int_string os_run_full_raw(const char*, void*, void*, const char*, int);

// Extern C function: os_chdir_raw
int os_chdir_raw(const char*);

// Extern C function: os_getcwd_raw
const char* os_getcwd_raw(void);

// Extern C function: os_now_utc_iso8601_raw
const char* os_now_utc_iso8601_raw(void);

// Extern C function: os_now_local_fill_raw
void os_now_local_fill_raw(void*);

// Extern C function: os_now_local_iso8601_raw
const char* os_now_local_iso8601_raw(void);

// Extern C function: malloc (libc-provided, declaration skipped)
// Extern C function: os_platform_raw
const char* os_platform_raw(void);

// Extern C function: os_temp_dir_raw
const char* os_temp_dir_raw(void);

// Extern C function: os_getpid_raw
int os_getpid_raw(void);

// Extern C function: os_user_id_raw
int os_user_id_raw(void);

// Extern C function: exit (libc-provided, declaration skipped)
// Extern C function: os_wall_seconds_raw
int64_t os_wall_seconds_raw(void);

// Extern C function: os_wall_micros_raw
int os_wall_micros_raw(void);

// Extern C function: os_now_monotonic_ms_raw
int64_t os_now_monotonic_ms_raw(void);

// Extern C function: os_now_monotonic_ns_raw
int64_t os_now_monotonic_ns_raw(void);

// Extern C function: os_now_unix_ms_raw
int64_t os_now_unix_ms_raw(void);

// Extern C function: file_open_raw
void* file_open_raw(const char*, const char*);

// Extern C function: file_close
int file_close(void*);

// Extern C function: file_read_all_raw
const char* file_read_all_raw(void*);

// Extern C function: file_write_raw
int file_write_raw(void*, const char*, int);

// Extern C function: file_exists
int file_exists(const char*);

// Extern C function: file_delete_raw
int file_delete_raw(const char*);

// Extern C function: file_size_raw
int64_t file_size_raw(const char*);

// Extern C function: file_fd_raw
int file_fd_raw(void*);

// Extern C function: string_concat
const char* string_concat(const char*, const char*);

// Extern C function: string_length
int string_length(const char*);

// Extern C function: file_open_raw
void* file_open_raw(const char*, const char*);

// Extern C function: file_close
int file_close(void*);

// Extern C function: file_read_all_raw
const char* file_read_all_raw(void*);

// Extern C function: file_write_raw
int file_write_raw(void*, const char*, int);

// Extern C function: file_exists
int file_exists(const char*);

// Extern C function: fs_path_exists
int fs_path_exists(const char*);

// Extern C function: file_delete_raw
int file_delete_raw(const char*);

// Extern C function: file_size_raw
int64_t file_size_raw(const char*);

// Extern C function: file_mtime
int64_t file_mtime(const char*);

// Extern C function: file_mtime_raw
int64_t file_mtime_raw(const char*);

// Extern C function: dir_exists
int dir_exists(const char*);

// Extern C function: dir_create_raw
int dir_create_raw(const char*);

// Extern C function: dir_create_mode_raw
int dir_create_mode_raw(const char*, int);

// Extern C function: dir_delete_raw
int dir_delete_raw(const char*);

// Extern C function: dir_list_raw
void* dir_list_raw(const char*);

// Extern C function: fs_mkdir_p_raw
int fs_mkdir_p_raw(const char*);

// Extern C function: fs_symlink_raw
int fs_symlink_raw(const char*, const char*);

// Extern C function: fs_readlink_raw
const char* fs_readlink_raw(const char*);

// Extern C function: fs_is_symlink
int fs_is_symlink(const char*);

// Extern C function: fs_is_socket
int fs_is_socket(const char*);

// Extern C function: fs_unlink_raw
int fs_unlink_raw(const char*);

// Extern C function: fs_write_binary_raw
int fs_write_binary_raw(const char*, const char*, int);

// Extern C function: fs_write_atomic_raw
int fs_write_atomic_raw(const char*, const char*, int);

// Extern C function: fs_rename_raw
int fs_rename_raw(const char*, const char*);

// Extern C function: fs_last_os_error
int fs_last_os_error(void);

// Extern C function: fs_error_message
const char* fs_error_message(const char*, const char*);

// Extern C function: fs_try_stat
int fs_try_stat(const char*);

// Extern C function: fs_get_stat_kind
int fs_get_stat_kind(void);

// Extern C function: fs_get_stat_size
int64_t fs_get_stat_size(void);

// Extern C function: fs_get_stat_mtime
int64_t fs_get_stat_mtime(void);

// Extern C function: fs_try_statvfs
int fs_try_statvfs(const char*);

// Extern C function: fs_get_statvfs_total
int64_t fs_get_statvfs_total(void);

// Extern C function: fs_get_statvfs_free
int64_t fs_get_statvfs_free(void);

// Extern C function: fs_get_statvfs_avail
int64_t fs_get_statvfs_avail(void);

// Extern C function: fs_try_mounts
int fs_try_mounts(void);

// Extern C function: fs_get_mount_count
int fs_get_mount_count(void);

// Extern C function: fs_get_mount_source
const char* fs_get_mount_source(int);

// Extern C function: fs_get_mount_point
const char* fs_get_mount_point(int);

// Extern C function: fs_get_mount_fstype
const char* fs_get_mount_fstype(int);

// Extern C function: fs_get_mount_options
const char* fs_get_mount_options(int);

// Extern C function: fs_release_mounts
void fs_release_mounts(void);

// Extern C function: fs_try_block_info
int fs_try_block_info(const char*);

// Extern C function: fs_get_block_size_bytes
int64_t fs_get_block_size_bytes(void);

// Extern C function: fs_get_block_removable
int fs_get_block_removable(void);

// Extern C function: fs_get_block_transport
const char* fs_get_block_transport(void);

// Extern C function: fs_try_read_binary
int fs_try_read_binary(const char*);

// Extern C function: fs_get_read_binary
const char* fs_get_read_binary(void);

// Extern C function: fs_get_read_binary_length
int fs_get_read_binary_length(void);

// Extern C function: fs_release_read_binary
void fs_release_read_binary(void);

// Extern C function: fs_read_binary_tuple
_tuple_string_int_string fs_read_binary_tuple(const char*);

// Extern C function: fs_copy_raw
_tuple_int_int_string fs_copy_raw(const char*, const char*);

// Extern C function: fs_move_raw
_tuple_int_int_string fs_move_raw(const char*, const char*);

// Extern C function: fs_realpath_raw
_tuple_string_int_string fs_realpath_raw(const char*);

// Extern C function: fs_chmod_raw
_tuple_int_int_string fs_chmod_raw(const char*, int);

// Extern C function: dir_list_count
int dir_list_count(void*);

// Extern C function: dir_list_get
const char* dir_list_get(void*, int);

// Extern C function: dir_list_kind
int dir_list_kind(void*, int);

// Extern C function: dir_list_free
void dir_list_free(void*);

// Extern C function: path_join
const char* path_join(const char*, const char*);

// Extern C function: path_dirname
const char* path_dirname(const char*);

// Extern C function: path_basename
const char* path_basename(const char*);

// Extern C function: path_extension
const char* path_extension(const char*);

// Extern C function: path_is_absolute
int path_is_absolute(const char*);

// Extern C function: path_clean
const char* path_clean(const char*);

// Extern C function: path_is_within_base
int path_is_within_base(const char*, const char*);

// Extern C function: path_rel
const char* path_rel(const char*, const char*);

// Extern C function: path_separator
const char* path_separator(void);

// Extern C function: fs_pwrite_raw
int64_t fs_pwrite_raw(void*, const char*, int, int64_t);

// Extern C function: fs_pread_raw
int fs_pread_raw(void*, int, int64_t);

// Extern C function: fs_pread_into_raw
int fs_pread_into_raw(void*, void*, int, int64_t);

// Extern C function: fs_get_pread
const char* fs_get_pread(void);

// Extern C function: fs_get_pread_length
int fs_get_pread_length(void);

// Extern C function: fs_release_pread
void fs_release_pread(void);

// Extern C function: fs_ftruncate_raw
const char* fs_ftruncate_raw(void*, int64_t);

// Extern C function: fs_fsync_raw
const char* fs_fsync_raw(void*);

// Extern C function: file_fd_raw
int file_fd_raw(void*);

// Extern C function: fs_glob_raw
void* fs_glob_raw(const char*);

// Extern C function: fs_glob_multi_raw
void* fs_glob_multi_raw(void*);

// Extern C function: fs_walk_raw
int fs_walk_raw(const char*, void*);

// Extern C function: fs_watch_open_raw
void* fs_watch_open_raw(const char*);

// Extern C function: fs_watch_wait
int fs_watch_wait(void*, int);

// Extern C function: fs_watch_close
void fs_watch_close(void*);

// Extern C function: string_concat
const char* string_concat(const char*, const char*);

// Extern C function: string_length
int string_length(const char*);

// Extern C function: string_char_at
int string_char_at(const char*, int);

// Extern C function: string_substring
const char* string_substring(const char*, int, int);

// Extern C function: string_new_with_length
void* string_new_with_length(const char*, int);

// Extern C function: list_new
void* list_new(void);

// Extern C function: list_new_in
void* list_new_in(void*);

// Extern C function: list_add_raw
int list_add_raw(void*, void*);

// Extern C function: list_add_string_owned
int list_add_string_owned(void*, void*);

// Extern C function: list_get_raw
void* list_get_raw(void*, int);

// Extern C function: list_set
void list_set(void*, int, void*);

// Extern C function: list_size
int list_size(void*);

// Extern C function: list_remove
void list_remove(void*, int);

// Extern C function: list_clear
void list_clear(void*);

// Extern C function: list_free
void list_free(void*);

// Extern C function: map_new
void* map_new(void);

// Extern C function: map_put_raw
int map_put_raw(void*, const char*, void*);

// Extern C function: map_put_string_owned
int map_put_string_owned(void*, const char*, void*);

// Extern C function: map_get_raw
void* map_get_raw(void*, const char*);

// Extern C function: map_has
int map_has(void*, const char*);

// Extern C function: map_remove
void map_remove(void*, const char*);

// Extern C function: map_size
int map_size(void*);

// Extern C function: map_clear
void map_clear(void*);

// Extern C function: map_free
void map_free(void*);

// Extern C function: map_keys_raw
void* map_keys_raw(void*);

// Extern C function: map_keys_free
void map_keys_free(void*);

// Extern C function: map_keys_size_raw
int map_keys_size_raw(void*);

// Extern C function: map_keys_get_raw
const char* map_keys_get_raw(void*, int);

// Extern C function: string_length
int string_length(const char*);

// Extern C function: path_join
const char* path_join(const char*, const char*);

// Extern C function: path_dirname
const char* path_dirname(const char*);

// Extern C function: path_basename
const char* path_basename(const char*);

// Extern C function: path_extension
const char* path_extension(const char*);

// Extern C function: path_is_absolute
int path_is_absolute(const char*);

// Extern C function: path_clean
const char* path_clean(const char*);

// Extern C function: path_rel
const char* path_rel(const char*, const char*);

// Extern C function: path_is_within_base
int path_is_within_base(const char*, const char*);

// Extern C function: path_separator
const char* path_separator(void);

// Extern C function: dir_exists
int dir_exists(const char*);

// Extern C function: dir_create_raw
int dir_create_raw(const char*);

// Extern C function: dir_delete_raw
int dir_delete_raw(const char*);

// Extern C function: dir_list_raw
void* dir_list_raw(const char*);

// Extern C function: dir_list_count
int dir_list_count(void*);

// Extern C function: dir_list_get
const char* dir_list_get(void*, int);

// Extern C function: dir_list_kind
int dir_list_kind(void*, int);

// Extern C function: dir_list_free
void dir_list_free(void*);

// Extern C function: exit (libc-provided, declaration skipped)
// Extern C function: ae_D_tests_D_ae
int ae_D_tests_D_ae(void*);


// Import: build
// Import: std.string
// Import: std.io
// Import: std.os
// Import: std.file
// Import: std.fs
// Import: std.list
// Import: std.map
// Import: std.path
// Import: std.dir
#line 29 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED void* build_session(const char* root_path) {
    int _heap__e1 = 0; (void)_heap__e1;
    const char* _e1 = NULL;
    int _heap__e2 = 0; (void)_heap__e2;
    const char* _e2 = NULL;
    int _heap__e3 = 0; (void)_heap__e3;
    const char* _e3 = NULL;
    int _heap__e4 = 0; (void)_heap__e4;
    const char* _e4 = NULL;
    int _heap__e5 = 0; (void)_heap__e5;
    const char* _e5 = NULL;
#line 30 "/home/paul/.local/share/aeb/lib/build/module.ae"
void* s = map_new();
#line 31 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = _e1; _e1 = map_put(s, "root", (void*)(root_path)); if (_heap__e1) aether_heap_str_free(_tmp_old); _heap__e1 = 0; aether_unwind_track_str_if(_e1, _heap__e1); }
#line 32 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = _e2; _e2 = map_put(s, "visited", map_new()); if (_heap__e2) aether_heap_str_free(_tmp_old); _heap__e2 = 0; aether_unwind_track_str_if(_e2, _heap__e2); }
#line 38 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = _e3; _e3 = map_put(s, "status", map_new()); if (_heap__e3) aether_heap_str_free(_tmp_old); _heap__e3 = 0; aether_unwind_track_str_if(_e3, _heap__e3); }
#line 39 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = _e4; _e4 = map_put(s, "reason", map_new()); if (_heap__e4) aether_heap_str_free(_tmp_old); _heap__e4 = 0; aether_unwind_track_str_if(_e4, _heap__e4); }
#line 40 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = _e5; _e5 = map_put(s, "failed", list_new()); if (_heap__e5) aether_heap_str_free(_tmp_old); _heap__e5 = 0; aether_unwind_track_str_if(_e5, _heap__e5); }
#line 41 "/home/paul/.local/share/aeb/lib/build/module.ae"
    void* _builder_ret = s;
    /* deferred */ if (_heap__e5) { aether_heap_str_free(_e5); _e5 = NULL; _heap__e5 = 0; }
    /* deferred */ if (_heap__e4) { aether_heap_str_free(_e4); _e4 = NULL; _heap__e4 = 0; }
    /* deferred */ if (_heap__e3) { aether_heap_str_free(_e3); _e3 = NULL; _heap__e3 = 0; }
    /* deferred */ if (_heap__e2) { aether_heap_str_free(_e2); _e2 = NULL; _heap__e2 = 0; }
    /* deferred */ if (_heap__e1) { aether_heap_str_free(_e1); _e1 = NULL; _heap__e1 = 0; }
    return _builder_ret;
    /* deferred */ if (_heap__e5) { aether_heap_str_free(_e5); _e5 = NULL; _heap__e5 = 0; }
    /* deferred */ if (_heap__e4) { aether_heap_str_free(_e4); _e4 = NULL; _heap__e4 = 0; }
    /* deferred */ if (_heap__e3) { aether_heap_str_free(_e3); _e3 = NULL; _heap__e3 = 0; }
    /* deferred */ if (_heap__e2) { aether_heap_str_free(_e2); _e2 = NULL; _heap__e2 = 0; }
    /* deferred */ if (_heap__e1) { aether_heap_str_free(_e1); _e1 = NULL; _heap__e1 = 0; }
}

#line 50 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build__label_buildtype(const char* label) {
#line 51 "/home/paul/.local/share/aeb/lib/build/module.ae"
int colon = string_index_of(label, ":");
if (colon < 0) {
        {
#line 52 "/home/paul/.local/share/aeb/lib/build/module.ae"
            return aether_uniform_heap_str((const char*)("build"), 0);
        }
    }
#line 53 "/home/paul/.local/share/aeb/lib/build/module.ae"
    return aether_uniform_heap_str((const char*)(string_substring(label, 0, colon)), 1);
}

#line 57 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build__label_dir(const char* label) {
#line 58 "/home/paul/.local/share/aeb/lib/build/module.ae"
int colon = string_index_of(label, ":");
if (colon < 0) {
        {
#line 59 "/home/paul/.local/share/aeb/lib/build/module.ae"
            return aether_uniform_heap_str((const char*)(label), 0);
        }
    }
#line 60 "/home/paul/.local/share/aeb/lib/build/module.ae"
    return aether_uniform_heap_str((const char*)(string_substring(label, (colon + 1), string_length(label))), 1);
}

#line 124 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED void build_done(void* s, const char* module_dir) {
    int _heap__e = 0; (void)_heap__e;
    const char* _e = NULL;
#line 125 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_ptr_string _tup0 = map_get(s, "visited");
    void* visited = _tup0._0;
#line 126 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = _e; _e = map_put(visited, module_dir, "1"); if (_heap__e) aether_heap_str_free(_tmp_old); _heap__e = 0; aether_unwind_track_str_if(_e, _heap__e); }
    /* deferred */ if (_heap__e) { aether_heap_str_free(_e); _e = NULL; _heap__e = 0; }
}

#line 148 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED void build__mark_failed(void* s, const char* label, const char* reason) {
    int _heap__e1 = 0; (void)_heap__e1;
    const char* _e1 = NULL;
    int _heap__e2 = 0; (void)_heap__e2;
    const char* _e2 = NULL;
    int _heap__e3 = 0; (void)_heap__e3;
    const char* _e3 = NULL;
#line 149 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_ptr_string _tup1 = map_get(s, "status");
    void* st = _tup1._0;
#line 150 "/home/paul/.local/share/aeb/lib/build/module.ae"
int already = 0;
if (map_has(st, aether_string_data(label)) == 1) {
        {
#line 152 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_ptr_string _tup2 = map_get(st, label);
            void* cur = _tup2._0;
if (string_equals(cur, "failed") == 1) {
                {
#line 153 "/home/paul/.local/share/aeb/lib/build/module.ae"
already = 1;
                }
            }
        }
    }
#line 155 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = _e1; _e1 = map_put(st, label, "failed"); if (_heap__e1) aether_heap_str_free(_tmp_old); _heap__e1 = 0; aether_unwind_track_str_if(_e1, _heap__e1); }
if (string_length(reason) > 0) {
        {
#line 157 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_ptr_string _tup3 = map_get(s, "reason");
            void* rm = _tup3._0;
#line 158 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = _e2; _e2 = map_put(rm, label, (void*)(reason)); if (_heap__e2) aether_heap_str_free(_tmp_old); _heap__e2 = 0; aether_unwind_track_str_if(_e2, _heap__e2); }
        }
    }
if (already == 0) {
        {
#line 161 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_ptr_string _tup4 = map_get(s, "failed");
            void* failed = _tup4._0;
#line 162 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = _e3; _e3 = _aether_list_add_adopted(failed, (void*)string_copy(label)); if (_heap__e3) aether_heap_str_free(_tmp_old); _heap__e3 = 0; aether_unwind_track_str_if(_e3, _heap__e3); }
        }
    }
    /* deferred */ if (_heap__e3) { aether_heap_str_free(_e3); _e3 = NULL; _heap__e3 = 0; }
    /* deferred */ if (_heap__e2) { aether_heap_str_free(_e2); _e2 = NULL; _heap__e2 = 0; }
    /* deferred */ if (_heap__e1) { aether_heap_str_free(_e1); _e1 = NULL; _heap__e1 = 0; }
}

#line 184 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED int build_record_status(void* s, const char* label, int rc) {
    int _heap__e = 0; (void)_heap__e;
    const char* _e = NULL;
#line 185 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_ptr_string _tup5 = map_get(s, "status");
    void* st = _tup5._0;
if (map_has(st, aether_string_data(label)) == 1) {
        {
#line 187 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_ptr_string _tup6 = map_get(st, label);
            void* cur = _tup6._0;
if (string_equals(cur, "failed") == 1) {
                {
#line 188 "/home/paul/.local/share/aeb/lib/build/module.ae"
                    int _builder_ret = 0;
                    /* deferred */ if (_heap__e) { aether_heap_str_free(_e); _e = NULL; _heap__e = 0; }
                    return _builder_ret;
                }
            }
        }
    }
if (rc == 0) {
        {
#line 191 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = _e; _e = map_put(st, label, "passed"); if (_heap__e) aether_heap_str_free(_tmp_old); _heap__e = 0; aether_unwind_track_str_if(_e, _heap__e); }
        }
    } else {
        {
#line 193 "/home/paul/.local/share/aeb/lib/build/module.ae"
build__mark_failed(s, label, ({ char* _ad_0 = (char*)(string_from_int(rc)); const char* _ad_r = string_concat("builder returned exit ", _ad_0); aether_heap_str_free(_ad_0); _ad_r; }));
        }
    }
#line 195 "/home/paul/.local/share/aeb/lib/build/module.ae"
    int _builder_ret = 0;
    /* deferred */ if (_heap__e) { aether_heap_str_free(_e); _e = NULL; _heap__e = 0; }
    return _builder_ret;
    /* deferred */ if (_heap__e) { aether_heap_str_free(_e); _e = NULL; _heap__e = 0; }
}

#line 200 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED void* build_session_handle(void* ctx) {
if (map_has(ctx, aether_string_data("_session")) == 0) {
        {
#line 201 "/home/paul/.local/share/aeb/lib/build/module.ae"
            return NULL;
        }
    }
#line 202 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_ptr_string _tup7 = map_get(ctx, "_session");
    void* s = _tup7._0;
#line 203 "/home/paul/.local/share/aeb/lib/build/module.ae"
    return s;
}

#line 208 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build_status_of(void* s, const char* label) {
#line 209 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_ptr_string _tup8 = map_get(s, "status");
    void* st = _tup8._0;
if (map_has(st, aether_string_data(label)) == 0) {
        {
#line 210 "/home/paul/.local/share/aeb/lib/build/module.ae"
            return "";
        }
    }
#line 211 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_ptr_string _tup9 = map_get(st, label);
    void* v = _tup9._0;
#line 212 "/home/paul/.local/share/aeb/lib/build/module.ae"
    return v;
}

#line 216 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED int build_any_failed(void* s) {
#line 217 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_ptr_string _tup10 = map_get(s, "failed");
    void* failed = _tup10._0;
if (list_size(failed) > 0) {
        {
#line 218 "/home/paul/.local/share/aeb/lib/build/module.ae"
            return 1;
        }
    }
#line 219 "/home/paul/.local/share/aeb/lib/build/module.ae"
    return 0;
}

#line 794 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build__host_os(void) {
    int _heap_p = 0; (void)_heap_p;
    const char* p = NULL;
#line 795 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = p; p = os_platform(); if (_heap_p) aether_heap_str_free(_tmp_old); _heap_p = 1; aether_unwind_track_str_if(p, _heap_p); }
if (strcmp(_aether_safe_str(p), _aether_safe_str("darwin")) == 0) {
        {
#line 797 "/home/paul/.local/share/aeb/lib/build/module.ae"
            const char* _builder_ret = "macos";
            /* deferred */ if (_heap_p) { aether_heap_str_free(p); p = NULL; _heap_p = 0; }
            return _builder_ret;
        }
    }
if (strcmp(_aether_safe_str(p), _aether_safe_str("linux")) == 0) {
        {
#line 800 "/home/paul/.local/share/aeb/lib/build/module.ae"
            const char* _builder_ret = "linux";
            /* deferred */ if (_heap_p) { aether_heap_str_free(p); p = NULL; _heap_p = 0; }
            return _builder_ret;
        }
    }
if (strcmp(_aether_safe_str(p), _aether_safe_str("freebsd")) == 0) {
        {
#line 803 "/home/paul/.local/share/aeb/lib/build/module.ae"
            const char* _builder_ret = "freebsd";
            /* deferred */ if (_heap_p) { aether_heap_str_free(p); p = NULL; _heap_p = 0; }
            return _builder_ret;
        }
    }
if (strcmp(_aether_safe_str(p), _aether_safe_str("windows")) == 0) {
        {
#line 806 "/home/paul/.local/share/aeb/lib/build/module.ae"
            const char* _builder_ret = "windows";
            /* deferred */ if (_heap_p) { aether_heap_str_free(p); p = NULL; _heap_p = 0; }
            return _builder_ret;
        }
    }
#line 808 "/home/paul/.local/share/aeb/lib/build/module.ae"
    const char* _builder_ret = "linux";
    /* deferred */ if (_heap_p) { aether_heap_str_free(p); p = NULL; _heap_p = 0; }
    return _builder_ret;
    /* deferred */ if (_heap_p) { aether_heap_str_free(p); p = NULL; _heap_p = 0; }
}

#line 815 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED int build__is_windows(void) {
#line 816 "/home/paul/.local/share/aeb/lib/build/module.ae"
    return (strcmp(_aether_safe_str(build__host_os()), _aether_safe_str("windows")) == 0);
}

#line 965 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED int build__has_windows_drive_prefix(const char* s) {
    int _heap_c0 = 0; (void)_heap_c0;
    const char* c0 = NULL;
    int _heap_letters = 0; (void)_heap_letters;
    const char* letters = NULL;
    int _heap_c2 = 0; (void)_heap_c2;
    const char* c2 = NULL;
if (string_length(s) < 2) {
        {
#line 966 "/home/paul/.local/share/aeb/lib/build/module.ae"
            int _builder_ret = 0;
            /* deferred */ if (_heap_c2) { aether_heap_str_free(c2); c2 = NULL; _heap_c2 = 0; }
            /* deferred */ if (_heap_letters) { aether_heap_str_free(letters); letters = NULL; _heap_letters = 0; }
            /* deferred */ if (_heap_c0) { aether_heap_str_free(c0); c0 = NULL; _heap_c0 = 0; }
            return _builder_ret;
        }
    }
if (({ char* _ad_1 = (char*)(string_substring(s, 1, 2)); int _ad_r = string_equals(_ad_1, ":"); aether_heap_str_free(_ad_1); _ad_r; }) == 0) {
        {
#line 967 "/home/paul/.local/share/aeb/lib/build/module.ae"
            int _builder_ret = 0;
            /* deferred */ if (_heap_c2) { aether_heap_str_free(c2); c2 = NULL; _heap_c2 = 0; }
            /* deferred */ if (_heap_letters) { aether_heap_str_free(letters); letters = NULL; _heap_letters = 0; }
            /* deferred */ if (_heap_c0) { aether_heap_str_free(c0); c0 = NULL; _heap_c0 = 0; }
            return _builder_ret;
        }
    }
#line 968 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = c0; c0 = string_substring(s, 0, 1); if (_heap_c0) aether_heap_str_free(_tmp_old); _heap_c0 = 1; aether_unwind_track_str_if(c0, _heap_c0); }
#line 969 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = letters; letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"; if (_heap_letters) aether_heap_str_free(_tmp_old); _heap_letters = 0; aether_unwind_track_str_if(letters, _heap_letters); }
if (string_contains(letters, c0) == 0) {
        {
#line 970 "/home/paul/.local/share/aeb/lib/build/module.ae"
            int _builder_ret = 0;
            /* deferred */ if (_heap_c2) { aether_heap_str_free(c2); c2 = NULL; _heap_c2 = 0; }
            /* deferred */ if (_heap_letters) { aether_heap_str_free(letters); letters = NULL; _heap_letters = 0; }
            /* deferred */ if (_heap_c0) { aether_heap_str_free(c0); c0 = NULL; _heap_c0 = 0; }
            return _builder_ret;
        }
    }
if (string_length(s) == 2) {
        {
#line 971 "/home/paul/.local/share/aeb/lib/build/module.ae"
            int _builder_ret = 1;
            /* deferred */ if (_heap_c2) { aether_heap_str_free(c2); c2 = NULL; _heap_c2 = 0; }
            /* deferred */ if (_heap_letters) { aether_heap_str_free(letters); letters = NULL; _heap_letters = 0; }
            /* deferred */ if (_heap_c0) { aether_heap_str_free(c0); c0 = NULL; _heap_c0 = 0; }
            return _builder_ret;
        }
    }
#line 972 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = c2; c2 = string_substring(s, 2, 3); if (_heap_c2) aether_heap_str_free(_tmp_old); _heap_c2 = 1; aether_unwind_track_str_if(c2, _heap_c2); }
if (string_equals(c2, "/") == 1) {
        {
#line 973 "/home/paul/.local/share/aeb/lib/build/module.ae"
            int _builder_ret = 1;
            /* deferred */ if (_heap_c2) { aether_heap_str_free(c2); c2 = NULL; _heap_c2 = 0; }
            /* deferred */ if (_heap_letters) { aether_heap_str_free(letters); letters = NULL; _heap_letters = 0; }
            /* deferred */ if (_heap_c0) { aether_heap_str_free(c0); c0 = NULL; _heap_c0 = 0; }
            return _builder_ret;
        }
    }
if (string_equals(c2, "\\") == 1) {
        {
#line 974 "/home/paul/.local/share/aeb/lib/build/module.ae"
            int _builder_ret = 1;
            /* deferred */ if (_heap_c2) { aether_heap_str_free(c2); c2 = NULL; _heap_c2 = 0; }
            /* deferred */ if (_heap_letters) { aether_heap_str_free(letters); letters = NULL; _heap_letters = 0; }
            /* deferred */ if (_heap_c0) { aether_heap_str_free(c0); c0 = NULL; _heap_c0 = 0; }
            return _builder_ret;
        }
    }
#line 975 "/home/paul/.local/share/aeb/lib/build/module.ae"
    int _builder_ret = 0;
    /* deferred */ if (_heap_c2) { aether_heap_str_free(c2); c2 = NULL; _heap_c2 = 0; }
    /* deferred */ if (_heap_letters) { aether_heap_str_free(letters); letters = NULL; _heap_letters = 0; }
    /* deferred */ if (_heap_c0) { aether_heap_str_free(c0); c0 = NULL; _heap_c0 = 0; }
    return _builder_ret;
    /* deferred */ if (_heap_c2) { aether_heap_str_free(c2); c2 = NULL; _heap_c2 = 0; }
    /* deferred */ if (_heap_letters) { aether_heap_str_free(letters); letters = NULL; _heap_letters = 0; }
    /* deferred */ if (_heap_c0) { aether_heap_str_free(c0); c0 = NULL; _heap_c0 = 0; }
}

#line 987 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED int build__is_abs_path(const char* p) {
if (string_length(p) == 0) {
        {
#line 988 "/home/paul/.local/share/aeb/lib/build/module.ae"
            return 0;
        }
    }
if (string_starts_with(p, "/") == 1) {
        {
#line 989 "/home/paul/.local/share/aeb/lib/build/module.ae"
            return 1;
        }
    }
if (string_starts_with(p, "\\\\") == 1) {
        {
#line 994 "/home/paul/.local/share/aeb/lib/build/module.ae"
            return 1;
        }
    }
if (build__has_windows_drive_prefix(p) == 1) {
        {
#line 995 "/home/paul/.local/share/aeb/lib/build/module.ae"
            return 1;
        }
    }
#line 996 "/home/paul/.local/share/aeb/lib/build/module.ae"
    return 0;
}

#line 1014 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED int build__path_is_sep(const char* ch) {
if (string_equals(ch, "/") == 1) {
        {
#line 1015 "/home/paul/.local/share/aeb/lib/build/module.ae"
            return 1;
        }
    }
if (build__is_windows() == 1) {
        {
if (string_equals(ch, "\\") == 1) {
                {
#line 1017 "/home/paul/.local/share/aeb/lib/build/module.ae"
                    return 1;
                }
            }
        }
    }
#line 1019 "/home/paul/.local/share/aeb/lib/build/module.ae"
    return 0;
}

#line 1024 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build__path_rstrip_seps(const char* path) {
    int _heap_ch = 0; (void)_heap_ch;
    const char* ch = NULL;
#line 1025 "/home/paul/.local/share/aeb/lib/build/module.ae"
int n = string_length(path);
#line 1026 "/home/paul/.local/share/aeb/lib/build/module.ae"
int going = 1;
while (going == 1) {
        {
if (n <= 1) {
                {
#line 1029 "/home/paul/.local/share/aeb/lib/build/module.ae"
going = 0;
                }
            } else {
                {
#line 1032 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = ch; ch = string_substring(path, (n - 1), n); if (_heap_ch) aether_heap_str_free(_tmp_old); _heap_ch = 1; aether_unwind_track_str_if(ch, _heap_ch); }
if (build__path_is_sep(ch) == 1) {
                        {
#line 1034 "/home/paul/.local/share/aeb/lib/build/module.ae"
n = (n - 1);
                        }
                    } else {
                        {
#line 1037 "/home/paul/.local/share/aeb/lib/build/module.ae"
going = 0;
                        }
                    }
                }
            }
        }
    }
#line 1041 "/home/paul/.local/share/aeb/lib/build/module.ae"
    const char* _builder_ret = aether_uniform_heap_str((const char*)(string_substring(path, 0, n)), 1);
    /* deferred */ if (_heap_ch) { aether_heap_str_free(ch); ch = NULL; _heap_ch = 0; }
    return _builder_ret;
    /* deferred */ if (_heap_ch) { aether_heap_str_free(ch); ch = NULL; _heap_ch = 0; }
}

#line 1045 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED int build__path_last_sep(const char* path) {
    int _heap_ch = 0; (void)_heap_ch;
    const char* ch = NULL;
#line 1046 "/home/paul/.local/share/aeb/lib/build/module.ae"
int n = string_length(path);
#line 1047 "/home/paul/.local/share/aeb/lib/build/module.ae"
int last = -1;
#line 1048 "/home/paul/.local/share/aeb/lib/build/module.ae"
int i = 0;
while (i < n) {
        {
#line 1050 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = ch; ch = string_substring(path, i, (i + 1)); if (_heap_ch) aether_heap_str_free(_tmp_old); _heap_ch = 1; aether_unwind_track_str_if(ch, _heap_ch); }
if (build__path_is_sep(ch) == 1) {
                {
#line 1052 "/home/paul/.local/share/aeb/lib/build/module.ae"
last = i;
                }
            }
#line 1054 "/home/paul/.local/share/aeb/lib/build/module.ae"
i = (i + 1);
        }
    }
#line 1056 "/home/paul/.local/share/aeb/lib/build/module.ae"
    int _builder_ret = last;
    /* deferred */ if (_heap_ch) { aether_heap_str_free(ch); ch = NULL; _heap_ch = 0; }
    return _builder_ret;
    /* deferred */ if (_heap_ch) { aether_heap_str_free(ch); ch = NULL; _heap_ch = 0; }
}

#line 1078 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build__dirname(const char* path) {
    int _heap_p = 0; (void)_heap_p;
    const char* p = NULL;
    int _heap_ch = 0; (void)_heap_ch;
    const char* ch = NULL;
#line 1079 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = p; p = build__path_rstrip_seps(path); if (_heap_p) aether_heap_str_free(_tmp_old); _heap_p = 1; aether_unwind_track_str_if(p, _heap_p); }
#line 1080 "/home/paul/.local/share/aeb/lib/build/module.ae"
int last = build__path_last_sep(p);
if (last < 0) {
        {
#line 1082 "/home/paul/.local/share/aeb/lib/build/module.ae"
            const char* _builder_ret = aether_uniform_heap_str((const char*)("."), 0);
            /* deferred */ if (_heap_ch) { aether_heap_str_free(ch); ch = NULL; _heap_ch = 0; }
            /* deferred */ if (_heap_p) { aether_heap_str_free(p); p = NULL; _heap_p = 0; }
            return _builder_ret;
        }
    }
if (last == 0) {
        {
#line 1086 "/home/paul/.local/share/aeb/lib/build/module.ae"
            const char* _builder_ret = aether_uniform_heap_str((const char*)(string_substring(p, 0, 1)), 1);
            /* deferred */ if (_heap_ch) { aether_heap_str_free(ch); ch = NULL; _heap_ch = 0; }
            /* deferred */ if (_heap_p) { aether_heap_str_free(p); p = NULL; _heap_p = 0; }
            return _builder_ret;
        }
    }
#line 1089 "/home/paul/.local/share/aeb/lib/build/module.ae"
int end = last;
#line 1090 "/home/paul/.local/share/aeb/lib/build/module.ae"
int going = 1;
while (going == 1) {
        {
if (end <= 1) {
                {
#line 1093 "/home/paul/.local/share/aeb/lib/build/module.ae"
going = 0;
                }
            } else {
                {
#line 1096 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = ch; ch = string_substring(p, (end - 1), end); if (_heap_ch) aether_heap_str_free(_tmp_old); _heap_ch = 1; aether_unwind_track_str_if(ch, _heap_ch); }
if (build__path_is_sep(ch) == 1) {
                        {
#line 1098 "/home/paul/.local/share/aeb/lib/build/module.ae"
end = (end - 1);
                        }
                    } else {
                        {
#line 1101 "/home/paul/.local/share/aeb/lib/build/module.ae"
going = 0;
                        }
                    }
                }
            }
        }
    }
#line 1105 "/home/paul/.local/share/aeb/lib/build/module.ae"
    const char* _builder_ret = aether_uniform_heap_str((const char*)(string_substring(p, 0, end)), 1);
    /* deferred */ if (_heap_ch) { aether_heap_str_free(ch); ch = NULL; _heap_ch = 0; }
    /* deferred */ if (_heap_p) { aether_heap_str_free(p); p = NULL; _heap_p = 0; }
    return _builder_ret;
    /* deferred */ if (_heap_ch) { aether_heap_str_free(ch); ch = NULL; _heap_ch = 0; }
    /* deferred */ if (_heap_p) { aether_heap_str_free(p); p = NULL; _heap_p = 0; }
}

#line 1133 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build__path_join(const char* a, const char* b) {
    int _heap_bfirst = 0; (void)_heap_bfirst;
    const char* bfirst = NULL;
    int _heap_abase = 0; (void)_heap_abase;
    const char* abase = NULL;
if (string_length(a) == 0) {
        {
#line 1135 "/home/paul/.local/share/aeb/lib/build/module.ae"
            const char* _builder_ret = aether_uniform_heap_str((const char*)(b), 0);
            /* deferred */ if (_heap_abase) { aether_heap_str_free(abase); abase = NULL; _heap_abase = 0; }
            /* deferred */ if (_heap_bfirst) { aether_heap_str_free(bfirst); bfirst = NULL; _heap_bfirst = 0; }
            return _builder_ret;
        }
    }
if (string_length(b) == 0) {
        {
#line 1138 "/home/paul/.local/share/aeb/lib/build/module.ae"
            const char* _builder_ret = aether_uniform_heap_str((const char*)(a), 0);
            /* deferred */ if (_heap_abase) { aether_heap_str_free(abase); abase = NULL; _heap_abase = 0; }
            /* deferred */ if (_heap_bfirst) { aether_heap_str_free(bfirst); bfirst = NULL; _heap_bfirst = 0; }
            return _builder_ret;
        }
    }
#line 1140 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = bfirst; bfirst = string_substring(b, 0, 1); if (_heap_bfirst) aether_heap_str_free(_tmp_old); _heap_bfirst = 1; aether_unwind_track_str_if(bfirst, _heap_bfirst); }
if (build__path_is_sep(bfirst) == 1) {
        {
#line 1142 "/home/paul/.local/share/aeb/lib/build/module.ae"
            const char* _builder_ret = aether_uniform_heap_str((const char*)(b), 0);
            /* deferred */ if (_heap_abase) { aether_heap_str_free(abase); abase = NULL; _heap_abase = 0; }
            /* deferred */ if (_heap_bfirst) { aether_heap_str_free(bfirst); bfirst = NULL; _heap_bfirst = 0; }
            return _builder_ret;
        }
    }
if (build__has_windows_drive_prefix(b) == 1) {
        {
#line 1145 "/home/paul/.local/share/aeb/lib/build/module.ae"
            const char* _builder_ret = aether_uniform_heap_str((const char*)(b), 0);
            /* deferred */ if (_heap_abase) { aether_heap_str_free(abase); abase = NULL; _heap_abase = 0; }
            /* deferred */ if (_heap_bfirst) { aether_heap_str_free(bfirst); bfirst = NULL; _heap_bfirst = 0; }
            return _builder_ret;
        }
    }
#line 1147 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = abase; abase = build__path_rstrip_seps(a); if (_heap_abase) aether_heap_str_free(_tmp_old); _heap_abase = 1; aether_unwind_track_str_if(abase, _heap_abase); }
#line 1148 "/home/paul/.local/share/aeb/lib/build/module.ae"
    const char* _builder_ret = aether_uniform_heap_str((const char*)(({ char* _ad_2 = (char*)(string_concat(abase, "/")); const char* _ad_r = string_concat(_ad_2, b); aether_heap_str_free(_ad_2); _ad_r; })), 1);
    /* deferred */ if (_heap_abase) { aether_heap_str_free(abase); abase = NULL; _heap_abase = 0; }
    /* deferred */ if (_heap_bfirst) { aether_heap_str_free(bfirst); bfirst = NULL; _heap_bfirst = 0; }
    return _builder_ret;
    /* deferred */ if (_heap_abase) { aether_heap_str_free(abase); abase = NULL; _heap_abase = 0; }
    /* deferred */ if (_heap_bfirst) { aether_heap_str_free(bfirst); bfirst = NULL; _heap_bfirst = 0; }
}

#line 1211 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build__sh_quote(const char* s) {
    int _heap_out = 0; (void)_heap_out;
    const char* out = NULL;
    int _heap_rest = 0; (void)_heap_rest;
    const char* rest = NULL;
    int _heap_ch = 0; (void)_heap_ch;
    const char* ch = NULL;
#line 1212 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = "'"; if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 0; aether_unwind_track_str_if(out, _heap_out); }
#line 1213 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = rest; rest = s; if (_heap_rest) aether_heap_str_free(_tmp_old); _heap_rest = 0; aether_unwind_track_str_if(rest, _heap_rest); }
while (string_length(rest) > 0) {
        {
#line 1215 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = ch; ch = string_substring(rest, 0, 1); if (_heap_ch) aether_heap_str_free(_tmp_old); _heap_ch = 1; aether_unwind_track_str_if(ch, _heap_ch); }
#line 1216 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = rest; rest = string_substring(rest, 1, string_length(rest)); if (_heap_rest) aether_heap_str_free(_tmp_old); _heap_rest = 1; aether_unwind_track_str_if(rest, _heap_rest); }
if (string_equals(ch, "'") == 1) {
                {
#line 1218 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, "'\\''"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; aether_unwind_track_str_if(out, _heap_out); }
                }
            } else {
                {
#line 1220 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, ch); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; aether_unwind_track_str_if(out, _heap_out); }
                }
            }
        }
    }
#line 1223 "/home/paul/.local/share/aeb/lib/build/module.ae"
    const char* _builder_ret = aether_uniform_heap_str((const char*)(string_concat(out, "'")), 1);
    /* deferred */ if (_heap_ch) { aether_heap_str_free(ch); ch = NULL; _heap_ch = 0; }
    /* deferred */ if (_heap_rest) { aether_heap_str_free(rest); rest = NULL; _heap_rest = 0; }
    /* deferred */ if (_heap_out) { aether_heap_str_free(out); out = NULL; _heap_out = 0; }
    return _builder_ret;
    /* deferred */ if (_heap_ch) { aether_heap_str_free(ch); ch = NULL; _heap_ch = 0; }
    /* deferred */ if (_heap_rest) { aether_heap_str_free(rest); rest = NULL; _heap_rest = 0; }
    /* deferred */ if (_heap_out) { aether_heap_str_free(out); out = NULL; _heap_out = 0; }
}

#line 1235 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build__cmd_caret_escape(const char* s) {
    int _heap_out = 0; (void)_heap_out;
    const char* out = NULL;
    int _heap_rest = 0; (void)_heap_rest;
    const char* rest = NULL;
    int _heap_ch = 0; (void)_heap_ch;
    const char* ch = NULL;
#line 1236 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = ""; if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 0; }
#line 1237 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = rest; rest = s; if (_heap_rest) aether_heap_str_free(_tmp_old); _heap_rest = 0; aether_unwind_track_str_if(rest, _heap_rest); }
while (string_length(rest) > 0) {
        {
#line 1239 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = ch; ch = string_substring(rest, 0, 1); if (_heap_ch) aether_heap_str_free(_tmp_old); _heap_ch = 1; aether_unwind_track_str_if(ch, _heap_ch); }
#line 1240 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = rest; rest = string_substring(rest, 1, string_length(rest)); if (_heap_rest) aether_heap_str_free(_tmp_old); _heap_rest = 1; aether_unwind_track_str_if(rest, _heap_rest); }
if (string_equals(ch, ">") == 1) {
                {
#line 1241 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, "^>"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
                }
            } else {
                {
if (string_equals(ch, "<") == 1) {
                        {
#line 1242 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, "^<"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
                        }
                    } else {
                        {
if (string_equals(ch, "&") == 1) {
                                {
#line 1243 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, "^&"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
                                }
                            } else {
                                {
if (string_equals(ch, "|") == 1) {
                                        {
#line 1244 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, "^|"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
                                        }
                                    } else {
                                        {
if (string_equals(ch, "^") == 1) {
                                                {
#line 1245 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, "^^"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
                                                }
                                            } else {
                                                {
#line 1246 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, ch); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
#line 1248 "/home/paul/.local/share/aeb/lib/build/module.ae"
    const char* _builder_ret = aether_uniform_heap_str((const char*)(out), _heap_out);
    /* deferred */ if (_heap_ch) { aether_heap_str_free(ch); ch = NULL; _heap_ch = 0; }
    /* deferred */ if (_heap_rest) { aether_heap_str_free(rest); rest = NULL; _heap_rest = 0; }
    return _builder_ret;
    /* deferred */ if (_heap_ch) { aether_heap_str_free(ch); ch = NULL; _heap_ch = 0; }
    /* deferred */ if (_heap_rest) { aether_heap_str_free(rest); rest = NULL; _heap_rest = 0; }
}

#line 1262 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build__sh_wrap(const char* cmd) {
if (build__is_windows() == 1) {
        {
#line 1264 "/home/paul/.local/share/aeb/lib/build/module.ae"
            return aether_uniform_heap_str((const char*)(({ char* _ad_3 = (char*)(build__cmd_caret_escape(build__sh_quote(cmd))); const char* _ad_r = string_concat("sh -c ", _ad_3); aether_heap_str_free(_ad_3); _ad_r; })), 1);
        }
    }
#line 1266 "/home/paul/.local/share/aeb/lib/build/module.ae"
    return aether_uniform_heap_str((const char*)(cmd), 0);
}

#line 1272 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build__sh_slashes(const char* s) {
    int _heap_out = 0; (void)_heap_out;
    const char* out = NULL;
    int _heap_rest = 0; (void)_heap_rest;
    const char* rest = NULL;
    int _heap_ch = 0; (void)_heap_ch;
    const char* ch = NULL;
#line 1273 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = ""; if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 0; }
#line 1274 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = rest; rest = s; if (_heap_rest) aether_heap_str_free(_tmp_old); _heap_rest = 0; aether_unwind_track_str_if(rest, _heap_rest); }
while (string_length(rest) > 0) {
        {
#line 1276 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = ch; ch = string_substring(rest, 0, 1); if (_heap_ch) aether_heap_str_free(_tmp_old); _heap_ch = 1; aether_unwind_track_str_if(ch, _heap_ch); }
#line 1277 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = rest; rest = string_substring(rest, 1, string_length(rest)); if (_heap_rest) aether_heap_str_free(_tmp_old); _heap_rest = 1; aether_unwind_track_str_if(rest, _heap_rest); }
if (string_equals(ch, "\\") == 1) {
                {
#line 1278 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, "/"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
                }
            } else {
                {
#line 1279 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, ch); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
                }
            }
        }
    }
#line 1281 "/home/paul/.local/share/aeb/lib/build/module.ae"
    const char* _builder_ret = aether_uniform_heap_str((const char*)(out), _heap_out);
    /* deferred */ if (_heap_ch) { aether_heap_str_free(ch); ch = NULL; _heap_ch = 0; }
    /* deferred */ if (_heap_rest) { aether_heap_str_free(rest); rest = NULL; _heap_rest = 0; }
    return _builder_ret;
    /* deferred */ if (_heap_ch) { aether_heap_str_free(ch); ch = NULL; _heap_ch = 0; }
    /* deferred */ if (_heap_rest) { aether_heap_str_free(rest); rest = NULL; _heap_rest = 0; }
}

#line 1290 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED int build__sh_hash(const char* s) {
    int _heap_rest = 0; (void)_heap_rest;
    const char* rest = NULL;
#line 1291 "/home/paul/.local/share/aeb/lib/build/module.ae"
int h = 5381;
#line 1292 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = rest; rest = s; if (_heap_rest) aether_heap_str_free(_tmp_old); _heap_rest = 0; aether_unwind_track_str_if(rest, _heap_rest); }
    int c;
while (string_length(rest) > 0) {
        {
#line 1294 "/home/paul/.local/share/aeb/lib/build/module.ae"
c = string_char_at(rest, 0);
#line 1295 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = rest; rest = string_substring(rest, 1, string_length(rest)); if (_heap_rest) aether_heap_str_free(_tmp_old); _heap_rest = 1; aether_unwind_track_str_if(rest, _heap_rest); }
#line 1296 "/home/paul/.local/share/aeb/lib/build/module.ae"
h = (((h * 33) + c) & 2147483647);
        }
    }
#line 1298 "/home/paul/.local/share/aeb/lib/build/module.ae"
    int _builder_ret = h;
    /* deferred */ if (_heap_rest) { aether_heap_str_free(rest); rest = NULL; _heap_rest = 0; }
    return _builder_ret;
    /* deferred */ if (_heap_rest) { aether_heap_str_free(rest); rest = NULL; _heap_rest = 0; }
}

#line 1314 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build__cygpath_m_via_sh(const char* posix) {
    int _heap_out = 0; (void)_heap_out;
    const char* out = NULL;
    int _heap_err = 0; (void)_heap_err;
    const char* err = NULL;
#line 1315 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_string_string _tup11 = ({ char* _ad_4 = (char*)(_aether_interp("sh -c \"cygpath -m '%s'\"", _aether_safe_str(posix))); _tuple_string_string _ad_r = os_exec(_ad_4); aether_heap_str_free(_ad_4); _ad_r; });
    { const char* _tmp_old = out; out = _tup11._0; if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; aether_unwind_track_str_if(out, _heap_out); }
    { const char* _tmp_old = err; err = _tup11._1; if (_heap_err) aether_heap_str_free(_tmp_old); _heap_err = 0; aether_unwind_track_str_if(err, _heap_err); }
if (string_length(err) > 0) {
        {
#line 1316 "/home/paul/.local/share/aeb/lib/build/module.ae"
            const char* _builder_ret = aether_uniform_heap_str((const char*)(""), 0);
            /* deferred */ if (_heap_err) { aether_heap_str_free(err); err = NULL; _heap_err = 0; }
            /* deferred */ if (_heap_out) { aether_heap_str_free(out); out = NULL; _heap_out = 0; }
            return _builder_ret;
        }
    }
#line 1317 "/home/paul/.local/share/aeb/lib/build/module.ae"
    const char* _builder_ret = aether_uniform_heap_str((const char*)(string_trim(out)), 1);
    /* deferred */ if (_heap_err) { aether_heap_str_free(err); err = NULL; _heap_err = 0; }
    /* deferred */ if (_heap_out) { aether_heap_str_free(out); out = NULL; _heap_out = 0; }
    return _builder_ret;
    /* deferred */ if (_heap_err) { aether_heap_str_free(err); err = NULL; _heap_err = 0; }
    /* deferred */ if (_heap_out) { aether_heap_str_free(out); out = NULL; _heap_out = 0; }
}

#line 1334 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build__sh_script_path(const char* cmd) {
    int _heap_tmp = 0; (void)_heap_tmp;
    const char* tmp = NULL;
    int _heap_nat = 0; (void)_heap_nat;
    const char* nat = NULL;
    int _heap_name = 0; (void)_heap_name;
    const char* name = NULL;
#line 1335 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = tmp; tmp = build__sh_slashes(os_getenv(aether_string_data("TMP"))); if (_heap_tmp) aether_heap_str_free(_tmp_old); _heap_tmp = 1; aether_unwind_track_str_if(tmp, _heap_tmp); }
if (string_length(tmp) == 0) {
        {
#line 1336 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = tmp; tmp = build__sh_slashes(os_getenv(aether_string_data("TEMP"))); if (_heap_tmp) aether_heap_str_free(_tmp_old); _heap_tmp = 1; aether_unwind_track_str_if(tmp, _heap_tmp); }
        }
    }
if (string_length(tmp) == 0) {
        {
#line 1337 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = tmp; tmp = build__sh_slashes(os_getenv(aether_string_data("TMPDIR"))); if (_heap_tmp) aether_heap_str_free(_tmp_old); _heap_tmp = 1; aether_unwind_track_str_if(tmp, _heap_tmp); }
        }
    }
if (string_length(tmp) == 0) {
        {
#line 1338 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = tmp; tmp = "/tmp"; if (_heap_tmp) aether_heap_str_free(_tmp_old); _heap_tmp = 0; aether_unwind_track_str_if(tmp, _heap_tmp); }
        }
    }
if (build__is_windows() == 1) {
        {
if (build__is_abs_native(tmp) == 0) {
                {
#line 1342 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = nat; nat = build__cygpath_m_via_sh(tmp); if (_heap_nat) aether_heap_str_free(_tmp_old); _heap_nat = 1; aether_unwind_track_str_if(nat, _heap_nat); }
if (string_length(nat) > 0) {
                        {
#line 1343 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = tmp; tmp = aether_uniform_heap_str(nat, 0); if (_heap_tmp) aether_heap_str_free(_tmp_old); _heap_tmp = 1; aether_unwind_track_str_if(tmp, _heap_tmp); }
                        }
                    }
                }
            }
        }
    }
#line 1346 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = name; name = ({ char* _ad_5 = (char*)(({ char* _ad_6 = (char*)(string_from_int(os_getpid())); char* _ad_7 = (char*)(({ char* _ad_8 = (char*)(({ char* _ad_9 = (char*)(string_from_int(build__sh_hash(cmd))); const char* _ad_r = string_concat(_ad_9, ".sh"); aether_heap_str_free(_ad_9); _ad_r; })); const char* _ad_r = string_concat("_", _ad_8); aether_heap_str_free(_ad_8); _ad_r; })); const char* _ad_r = string_concat(_ad_6, _ad_7); aether_heap_str_free(_ad_6); aether_heap_str_free(_ad_7); _ad_r; })); const char* _ad_r = string_concat("_aeb_sh_", _ad_5); aether_heap_str_free(_ad_5); _ad_r; }); if (_heap_name) aether_heap_str_free(_tmp_old); _heap_name = 1; aether_unwind_track_str_if(name, _heap_name); }
#line 1348 "/home/paul/.local/share/aeb/lib/build/module.ae"
    const char* _builder_ret = aether_uniform_heap_str((const char*)(({ char* _ad_10 = (char*)(string_concat("/", name)); const char* _ad_r = string_concat(tmp, _ad_10); aether_heap_str_free(_ad_10); _ad_r; })), 1);
    /* deferred */ if (_heap_name) { aether_heap_str_free(name); name = NULL; _heap_name = 0; }
    /* deferred */ if (_heap_nat) { aether_heap_str_free(nat); nat = NULL; _heap_nat = 0; }
    /* deferred */ if (_heap_tmp) { aether_heap_str_free(tmp); tmp = NULL; _heap_tmp = 0; }
    return _builder_ret;
    /* deferred */ if (_heap_name) { aether_heap_str_free(name); name = NULL; _heap_name = 0; }
    /* deferred */ if (_heap_nat) { aether_heap_str_free(nat); nat = NULL; _heap_nat = 0; }
    /* deferred */ if (_heap_tmp) { aether_heap_str_free(tmp); tmp = NULL; _heap_tmp = 0; }
}

#line 1369 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED void build__sh_trace(const char* cmd) {
if (({ char* _ad_11 = (char*)(os_getenv(aether_string_data("AEB_SH_TRACE"))); int _ad_r = string_equals(_ad_11, "1"); aether_heap_str_free(_ad_11); _ad_r; }) == 1) {
        {
#line 1371 "/home/paul/.local/share/aeb/lib/build/module.ae"
printf("[aeb-sh trace] %s", _aether_safe_str(cmd)); putchar('\n');
        }
    }
}

#line 1410 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED _tuple_string_string build__sh_capture(const char* cmd) {
    int _heap_out = 0; (void)_heap_out;
    const char* out = NULL;
    int _heap_err = 0; (void)_heap_err;
    const char* err = NULL;
    int _heap_scriptf = 0; (void)_heap_scriptf;
    const char* scriptf = NULL;
    int _heap_werr = 0; (void)_heap_werr;
    const char* werr = NULL;
    int _heap__d = 0; (void)_heap__d;
    const char* _d = NULL;
#line 1411 "/home/paul/.local/share/aeb/lib/build/module.ae"
build__sh_trace(cmd);
if (build__is_windows() == 0) {
        {
#line 1413 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_string_string _tup12 = os_exec(cmd);
            { const char* _tmp_old = out; out = _tup12._0; if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
            { const char* _tmp_old = err; err = _tup12._1; if (_heap_err) aether_heap_str_free(_tmp_old); _heap_err = 0; }
#line 1414 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_string_string _builder_ret = (_tuple_string_string){aether_uniform_heap_str((const char*)(out), _heap_out), err};
            /* deferred */ if (_heap__d) { aether_heap_str_free(_d); _d = NULL; _heap__d = 0; }
            /* deferred */ if (_heap_werr) { aether_heap_str_free(werr); werr = NULL; _heap_werr = 0; }
            /* deferred */ if (_heap_scriptf) { aether_heap_str_free(scriptf); scriptf = NULL; _heap_scriptf = 0; }
            return _builder_ret;
        }
    }
#line 1416 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = scriptf; scriptf = build__sh_script_path(cmd); if (_heap_scriptf) aether_heap_str_free(_tmp_old); _heap_scriptf = 1; aether_unwind_track_str_if(scriptf, _heap_scriptf); }
#line 1417 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = werr; werr = io_write_file(scriptf, cmd); if (_heap_werr) aether_heap_str_free(_tmp_old); _heap_werr = 0; aether_unwind_track_str_if(werr, _heap_werr); }
if (string_length(werr) > 0) {
        {
#line 1423 "/home/paul/.local/share/aeb/lib/build/module.ae"
printf("aeb: WARNING cannot write temp script %s: %s", _aether_safe_str(scriptf), _aether_safe_str(werr)); putchar('\n');
#line 1424 "/home/paul/.local/share/aeb/lib/build/module.ae"
puts("aeb:   falling back to `sh -c` quoting; resolved flags may come back empty.");
#line 1425 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_string_string _tup13 = ({ char* _ad_12 = (char*)(build__sh_wrap(cmd)); _tuple_string_string _ad_r = os_exec(_ad_12); aether_heap_str_free(_ad_12); _ad_r; });
            { const char* _tmp_old = out; out = _tup13._0; if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
            { const char* _tmp_old = err; err = _tup13._1; if (_heap_err) aether_heap_str_free(_tmp_old); _heap_err = 0; }
#line 1426 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_string_string _builder_ret = (_tuple_string_string){aether_uniform_heap_str((const char*)(out), _heap_out), err};
            /* deferred */ if (_heap__d) { aether_heap_str_free(_d); _d = NULL; _heap__d = 0; }
            /* deferred */ if (_heap_werr) { aether_heap_str_free(werr); werr = NULL; _heap_werr = 0; }
            /* deferred */ if (_heap_scriptf) { aether_heap_str_free(scriptf); scriptf = NULL; _heap_scriptf = 0; }
            return _builder_ret;
        }
    }
#line 1428 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_string_string _tup14 = ({ char* _ad_13 = (char*)(string_concat("sh ", scriptf)); _tuple_string_string _ad_r = os_exec(_ad_13); aether_heap_str_free(_ad_13); _ad_r; });
    { const char* _tmp_old = out; out = _tup14._0; if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
    { const char* _tmp_old = err; err = _tup14._1; if (_heap_err) aether_heap_str_free(_tmp_old); _heap_err = 0; }
#line 1429 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = _d; _d = fs_delete(scriptf); if (_heap__d) aether_heap_str_free(_tmp_old); _heap__d = 0; aether_unwind_track_str_if(_d, _heap__d); }
#line 1430 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_string_string _builder_ret = (_tuple_string_string){aether_uniform_heap_str((const char*)(out), _heap_out), err};
    /* deferred */ if (_heap__d) { aether_heap_str_free(_d); _d = NULL; _heap__d = 0; }
    /* deferred */ if (_heap_werr) { aether_heap_str_free(werr); werr = NULL; _heap_werr = 0; }
    /* deferred */ if (_heap_scriptf) { aether_heap_str_free(scriptf); scriptf = NULL; _heap_scriptf = 0; }
    return _builder_ret;
    /* deferred */ if (_heap__d) { aether_heap_str_free(_d); _d = NULL; _heap__d = 0; }
    /* deferred */ if (_heap_werr) { aether_heap_str_free(werr); werr = NULL; _heap_werr = 0; }
    /* deferred */ if (_heap_scriptf) { aether_heap_str_free(scriptf); scriptf = NULL; _heap_scriptf = 0; }
}

#line 1452 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build__aether_dev_root(const char* root) {
if (string_length(root) == 0) {
        {
#line 1454 "/home/paul/.local/share/aeb/lib/build/module.ae"
            return "";
        }
    }
if (({ char* _ad_14 = (char*)(string_concat(root, "/build/libaether.a")); int _ad_r = fs_exists(_ad_14); aether_heap_str_free(_ad_14); _ad_r; }) == 1) {
        {
#line 1457 "/home/paul/.local/share/aeb/lib/build/module.ae"
            return root;
        }
    }
#line 1459 "/home/paul/.local/share/aeb/lib/build/module.ae"
    return "";
}

#line 1463 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build__resolve_aether_dir(void) {
    int _heap_ae = 0; (void)_heap_ae;
    const char* ae = NULL;
    int _heap_raw = 0; (void)_heap_raw;
    const char* raw = NULL;
    int _heap__eerr = 0; (void)_heap__eerr;
    const char* _eerr = NULL;
#line 1464 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = ae; ae = os_getenv(aether_string_data("AETHER")); if (_heap_ae) aether_heap_str_free(_tmp_old); _heap_ae = 1; aether_unwind_track_str_if(ae, _heap_ae); }
if (string_length(ae) == 0) {
        {
#line 1466 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = ae; ae = "ae"; if (_heap_ae) aether_heap_str_free(_tmp_old); _heap_ae = 0; aether_unwind_track_str_if(ae, _heap_ae); }
        }
    }
#line 1472 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_string_string _tup15 = build__sh_capture(_aether_interp("command -v %s", _aether_safe_str(ae)));
    { const char* _tmp_old = raw; raw = _tup15._0; if (_heap_raw) aether_heap_str_free(_tmp_old); _heap_raw = 1; aether_unwind_track_str_if(raw, _heap_raw); }
    { const char* _tmp_old = _eerr; _eerr = _tup15._1; if (_heap__eerr) aether_heap_str_free(_tmp_old); _heap__eerr = 0; aether_unwind_track_str_if(_eerr, _heap__eerr); }
#line 1473 "/home/paul/.local/share/aeb/lib/build/module.ae"
    const char* _builder_ret = aether_uniform_heap_str((const char*)(({ char* _ad_15 = (char*)(({ char* _ad_16 = (char*)(string_trim(raw)); const char* _ad_r = build__dirname(_ad_16); aether_heap_str_free(_ad_16); _ad_r; })); const char* _ad_r = build__to_native_path(_ad_15); if ((const char*)_ad_r != _ad_15) string_release(_ad_15); _ad_r; })), 1);
    /* deferred */ if (_heap__eerr) { aether_heap_str_free(_eerr); _eerr = NULL; _heap__eerr = 0; }
    /* deferred */ if (_heap_raw) { aether_heap_str_free(raw); raw = NULL; _heap_raw = 0; }
    /* deferred */ if (_heap_ae) { aether_heap_str_free(ae); ae = NULL; _heap_ae = 0; }
    return _builder_ret;
    /* deferred */ if (_heap__eerr) { aether_heap_str_free(_eerr); _eerr = NULL; _heap__eerr = 0; }
    /* deferred */ if (_heap_raw) { aether_heap_str_free(raw); raw = NULL; _heap_raw = 0; }
    /* deferred */ if (_heap_ae) { aether_heap_str_free(ae); ae = NULL; _heap_ae = 0; }
}

#line 1500 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build__to_native_path(const char* p) {
    int _heap_nat = 0; (void)_heap_nat;
    const char* nat = NULL;
    int _heap_nerr = 0; (void)_heap_nerr;
    const char* nerr = NULL;
    int _heap_t = 0; (void)_heap_t;
    const char* t = NULL;
if (build__is_windows() == 0) {
        {
#line 1501 "/home/paul/.local/share/aeb/lib/build/module.ae"
            const char* _builder_ret = aether_uniform_heap_str((const char*)(p), 0);
            if (_heap_t) { aether_heap_str_free(t); t = NULL; _heap_t = 0; }
            /* deferred */ if (_heap_nerr) { aether_heap_str_free(nerr); nerr = NULL; _heap_nerr = 0; }
            /* deferred */ if (_heap_nat) { aether_heap_str_free(nat); nat = NULL; _heap_nat = 0; }
            return _builder_ret;
        }
    }
if (string_length(p) == 0) {
        {
#line 1502 "/home/paul/.local/share/aeb/lib/build/module.ae"
            const char* _builder_ret = aether_uniform_heap_str((const char*)(p), 0);
            if (_heap_t) { aether_heap_str_free(t); t = NULL; _heap_t = 0; }
            /* deferred */ if (_heap_nerr) { aether_heap_str_free(nerr); nerr = NULL; _heap_nerr = 0; }
            /* deferred */ if (_heap_nat) { aether_heap_str_free(nat); nat = NULL; _heap_nat = 0; }
            return _builder_ret;
        }
    }
if (build__is_abs_native(p) == 1) {
        {
#line 1504 "/home/paul/.local/share/aeb/lib/build/module.ae"
            const char* _builder_ret = aether_uniform_heap_str((const char*)(p), 0);
            if (_heap_t) { aether_heap_str_free(t); t = NULL; _heap_t = 0; }
            /* deferred */ if (_heap_nerr) { aether_heap_str_free(nerr); nerr = NULL; _heap_nerr = 0; }
            /* deferred */ if (_heap_nat) { aether_heap_str_free(nat); nat = NULL; _heap_nat = 0; }
            return _builder_ret;
        }
    }
if (string_starts_with(p, "/") == 0) {
        {
#line 1505 "/home/paul/.local/share/aeb/lib/build/module.ae"
            const char* _builder_ret = aether_uniform_heap_str((const char*)(p), 0);
            if (_heap_t) { aether_heap_str_free(t); t = NULL; _heap_t = 0; }
            /* deferred */ if (_heap_nerr) { aether_heap_str_free(nerr); nerr = NULL; _heap_nerr = 0; }
            /* deferred */ if (_heap_nat) { aether_heap_str_free(nat); nat = NULL; _heap_nat = 0; }
            return _builder_ret;
        }
    }
#line 1506 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_string_string _tup16 = build__sh_capture(_aether_interp("cygpath -m '%s'", _aether_safe_str(p)));
    { const char* _tmp_old = nat; nat = _tup16._0; if (_heap_nat) aether_heap_str_free(_tmp_old); _heap_nat = 1; aether_unwind_track_str_if(nat, _heap_nat); }
    { const char* _tmp_old = nerr; nerr = _tup16._1; if (_heap_nerr) aether_heap_str_free(_tmp_old); _heap_nerr = 0; aether_unwind_track_str_if(nerr, _heap_nerr); }
if (string_length(nerr) > 0) {
        {
#line 1507 "/home/paul/.local/share/aeb/lib/build/module.ae"
            const char* _builder_ret = aether_uniform_heap_str((const char*)(p), 0);
            if (_heap_t) { aether_heap_str_free(t); t = NULL; _heap_t = 0; }
            /* deferred */ if (_heap_nerr) { aether_heap_str_free(nerr); nerr = NULL; _heap_nerr = 0; }
            /* deferred */ if (_heap_nat) { aether_heap_str_free(nat); nat = NULL; _heap_nat = 0; }
            return _builder_ret;
        }
    }
#line 1508 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = t; t = string_trim(nat); if (_heap_t) aether_heap_str_free(_tmp_old); _heap_t = 1; }
if (string_length(t) == 0) {
        {
#line 1509 "/home/paul/.local/share/aeb/lib/build/module.ae"
            const char* _builder_ret = aether_uniform_heap_str((const char*)(p), 0);
            if (_heap_t) { aether_heap_str_free(t); t = NULL; _heap_t = 0; }
            /* deferred */ if (_heap_nerr) { aether_heap_str_free(nerr); nerr = NULL; _heap_nerr = 0; }
            /* deferred */ if (_heap_nat) { aether_heap_str_free(nat); nat = NULL; _heap_nat = 0; }
            return _builder_ret;
        }
    }
#line 1510 "/home/paul/.local/share/aeb/lib/build/module.ae"
    const char* _builder_ret = aether_uniform_heap_str((const char*)(t), _heap_t);
    /* deferred */ if (_heap_nerr) { aether_heap_str_free(nerr); nerr = NULL; _heap_nerr = 0; }
    /* deferred */ if (_heap_nat) { aether_heap_str_free(nat); nat = NULL; _heap_nat = 0; }
    return _builder_ret;
    /* deferred */ if (_heap_nerr) { aether_heap_str_free(nerr); nerr = NULL; _heap_nerr = 0; }
    /* deferred */ if (_heap_nat) { aether_heap_str_free(nat); nat = NULL; _heap_nat = 0; }
}

#line 1515 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED int build__is_abs_native(const char* p) {
if (string_length(p) < 2) {
        {
#line 1516 "/home/paul/.local/share/aeb/lib/build/module.ae"
            return 0;
        }
    }
if (string_starts_with(p, "\\\\") == 1) {
        {
#line 1517 "/home/paul/.local/share/aeb/lib/build/module.ae"
            return 1;
        }
    }
if (({ char* _ad_17 = (char*)(string_substring(p, 1, 2)); int _ad_r = string_equals(_ad_17, ":"); aether_heap_str_free(_ad_17); _ad_r; }) == 1) {
        {
#line 1518 "/home/paul/.local/share/aeb/lib/build/module.ae"
            return 1;
        }
    }
#line 1519 "/home/paul/.local/share/aeb/lib/build/module.ae"
    return 0;
}

#line 1524 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build__aether_dev_bin_dir(const char* dev_root) {
    int _heap_dev = 0; (void)_heap_dev;
    const char* dev = NULL;
#line 1525 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = dev; dev = build__aether_dev_root(dev_root); if (_heap_dev) aether_heap_str_free(_tmp_old); _heap_dev = 0; aether_unwind_track_str_if(dev, _heap_dev); }
if (string_length(dev) == 0) {
        {
#line 1527 "/home/paul/.local/share/aeb/lib/build/module.ae"
            const char* _builder_ret = aether_uniform_heap_str((const char*)(""), 0);
            /* deferred */ if (_heap_dev) { aether_heap_str_free(dev); dev = NULL; _heap_dev = 0; }
            return _builder_ret;
        }
    }
#line 1529 "/home/paul/.local/share/aeb/lib/build/module.ae"
    const char* _builder_ret = aether_uniform_heap_str((const char*)(string_concat(dev, "/build")), 1);
    /* deferred */ if (_heap_dev) { aether_heap_str_free(dev); dev = NULL; _heap_dev = 0; }
    return _builder_ret;
    /* deferred */ if (_heap_dev) { aether_heap_str_free(dev); dev = NULL; _heap_dev = 0; }
}

#line 1535 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build__resolve_libaether_dir(const char* aether_dir) {
    int _heap__nat = 0; (void)_heap__nat;
    const char* _nat = NULL;
    int _heap__ne = 0; (void)_heap__ne;
    const char* _ne = NULL;
    int _heap_aether_dir = 0; (void)_heap_aether_dir;
    int _heap_cand1 = 0; (void)_heap_cand1;
    const char* cand1 = NULL;
    int _heap_cand2 = 0; (void)_heap_cand2;
    const char* cand2 = NULL;
    int _heap_cand3 = 0; (void)_heap_cand3;
    const char* cand3 = NULL;
if (build__is_windows() == 1) {
        {
#line 1537 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_string_string _tup17 = build__sh_capture(_aether_interp("cygpath -m %s", _aether_safe_str(aether_dir)));
            { const char* _tmp_old = _nat; _nat = _tup17._0; if (_heap__nat) aether_heap_str_free(_tmp_old); _heap__nat = 1; aether_unwind_track_str_if(_nat, _heap__nat); }
            { const char* _tmp_old = _ne; _ne = _tup17._1; if (_heap__ne) aether_heap_str_free(_tmp_old); _heap__ne = 0; aether_unwind_track_str_if(_ne, _heap__ne); }
#line 1538 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = _nat; _nat = string_trim(_nat); if (_heap__nat) aether_heap_str_free(_tmp_old); _heap__nat = 1; aether_unwind_track_str_if(_nat, _heap__nat); }
if (string_length(_nat) > 0) {
                {
#line 1539 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = aether_dir; aether_dir = aether_uniform_heap_str(_nat, 0); if (_heap_aether_dir) aether_heap_str_free(_tmp_old); _heap_aether_dir = 1; }
                }
            }
        }
    }
#line 1541 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = cand1; cand1 = string_concat(aether_dir, "/../lib/aether/libaether.a"); if (_heap_cand1) aether_heap_str_free(_tmp_old); _heap_cand1 = 1; aether_unwind_track_str_if(cand1, _heap_cand1); }
if (fs_exists(cand1) == 1) {
        {
#line 1543 "/home/paul/.local/share/aeb/lib/build/module.ae"
            const char* _builder_ret = aether_uniform_heap_str((const char*)(string_concat(aether_dir, "/../lib/aether")), 1);
            if (_heap_aether_dir) { aether_heap_str_free(aether_dir); aether_dir = NULL; _heap_aether_dir = 0; }
            /* deferred */ if (_heap_cand3) { aether_heap_str_free(cand3); cand3 = NULL; _heap_cand3 = 0; }
            /* deferred */ if (_heap_cand2) { aether_heap_str_free(cand2); cand2 = NULL; _heap_cand2 = 0; }
            /* deferred */ if (_heap_cand1) { aether_heap_str_free(cand1); cand1 = NULL; _heap_cand1 = 0; }
            /* deferred */ if (_heap__ne) { aether_heap_str_free(_ne); _ne = NULL; _heap__ne = 0; }
            /* deferred */ if (_heap__nat) { aether_heap_str_free(_nat); _nat = NULL; _heap__nat = 0; }
            return _builder_ret;
        }
    }
#line 1545 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = cand2; cand2 = string_concat(aether_dir, "/../lib/libaether.a"); if (_heap_cand2) aether_heap_str_free(_tmp_old); _heap_cand2 = 1; aether_unwind_track_str_if(cand2, _heap_cand2); }
if (fs_exists(cand2) == 1) {
        {
#line 1547 "/home/paul/.local/share/aeb/lib/build/module.ae"
            const char* _builder_ret = aether_uniform_heap_str((const char*)(string_concat(aether_dir, "/../lib")), 1);
            if (_heap_aether_dir) { aether_heap_str_free(aether_dir); aether_dir = NULL; _heap_aether_dir = 0; }
            /* deferred */ if (_heap_cand3) { aether_heap_str_free(cand3); cand3 = NULL; _heap_cand3 = 0; }
            /* deferred */ if (_heap_cand2) { aether_heap_str_free(cand2); cand2 = NULL; _heap_cand2 = 0; }
            /* deferred */ if (_heap_cand1) { aether_heap_str_free(cand1); cand1 = NULL; _heap_cand1 = 0; }
            /* deferred */ if (_heap__ne) { aether_heap_str_free(_ne); _ne = NULL; _heap__ne = 0; }
            /* deferred */ if (_heap__nat) { aether_heap_str_free(_nat); _nat = NULL; _heap__nat = 0; }
            return _builder_ret;
        }
    }
#line 1549 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = cand3; cand3 = string_concat(aether_dir, "/libaether.a"); if (_heap_cand3) aether_heap_str_free(_tmp_old); _heap_cand3 = 1; aether_unwind_track_str_if(cand3, _heap_cand3); }
if (fs_exists(cand3) == 1) {
        {
#line 1551 "/home/paul/.local/share/aeb/lib/build/module.ae"
            const char* _builder_ret = aether_uniform_heap_str((const char*)(aether_dir), _heap_aether_dir);
            /* deferred */ if (_heap_cand3) { aether_heap_str_free(cand3); cand3 = NULL; _heap_cand3 = 0; }
            /* deferred */ if (_heap_cand2) { aether_heap_str_free(cand2); cand2 = NULL; _heap_cand2 = 0; }
            /* deferred */ if (_heap_cand1) { aether_heap_str_free(cand1); cand1 = NULL; _heap_cand1 = 0; }
            /* deferred */ if (_heap__ne) { aether_heap_str_free(_ne); _ne = NULL; _heap__ne = 0; }
            /* deferred */ if (_heap__nat) { aether_heap_str_free(_nat); _nat = NULL; _heap__nat = 0; }
            return _builder_ret;
        }
    }
#line 1553 "/home/paul/.local/share/aeb/lib/build/module.ae"
    const char* _builder_ret = aether_uniform_heap_str((const char*)(""), 0);
    if (_heap_aether_dir) { aether_heap_str_free(aether_dir); aether_dir = NULL; _heap_aether_dir = 0; }
    /* deferred */ if (_heap_cand3) { aether_heap_str_free(cand3); cand3 = NULL; _heap_cand3 = 0; }
    /* deferred */ if (_heap_cand2) { aether_heap_str_free(cand2); cand2 = NULL; _heap_cand2 = 0; }
    /* deferred */ if (_heap_cand1) { aether_heap_str_free(cand1); cand1 = NULL; _heap_cand1 = 0; }
    /* deferred */ if (_heap__ne) { aether_heap_str_free(_ne); _ne = NULL; _heap__ne = 0; }
    /* deferred */ if (_heap__nat) { aether_heap_str_free(_nat); _nat = NULL; _heap__nat = 0; }
    return _builder_ret;
    /* deferred */ if (_heap_cand3) { aether_heap_str_free(cand3); cand3 = NULL; _heap_cand3 = 0; }
    /* deferred */ if (_heap_cand2) { aether_heap_str_free(cand2); cand2 = NULL; _heap_cand2 = 0; }
    /* deferred */ if (_heap_cand1) { aether_heap_str_free(cand1); cand1 = NULL; _heap_cand1 = 0; }
    /* deferred */ if (_heap__ne) { aether_heap_str_free(_ne); _ne = NULL; _heap__ne = 0; }
    /* deferred */ if (_heap__nat) { aether_heap_str_free(_nat); _nat = NULL; _heap__nat = 0; }
}

#line 1622 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED void build__mkdirs(const char* dir_path) {
    int _heap__m = 0; (void)_heap__m;
    const char* _m = NULL;
#line 1629 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = _m; _m = fs_mkdir_p(dir_path); if (_heap__m) aether_heap_str_free(_tmp_old); _heap__m = 0; aether_unwind_track_str_if(_m, _heap__m); }
    /* deferred */ if (_heap__m) { aether_heap_str_free(_m); _m = NULL; _heap__m = 0; }
}

#line 1632 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED void* build__get(void* ctx, const char* key) {
#line 1633 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_ptr_string _tup18 = map_get(ctx, key);
    void* v = _tup18._0;
#line 1634 "/home/paul/.local/share/aeb/lib/build/module.ae"
    return v;
}

#line 1655 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED void* build_target_dir(void* ctx) {
#line 1656 "/home/paul/.local/share/aeb/lib/build/module.ae"
    return build__get(ctx, "target_dir");
}

#line 1659 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED void* build_source_dir(void* ctx) {
#line 1660 "/home/paul/.local/share/aeb/lib/build/module.ae"
    return build__get(ctx, "source_dir");
}

#line 1663 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED void* build_root(void* ctx) {
#line 1664 "/home/paul/.local/share/aeb/lib/build/module.ae"
    return build__get(ctx, "root");
}

#line 1703 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build__dep_target_dir(const char* root, const char* dep_module) {
    int _heap_buildtype = 0; (void)_heap_buildtype;
    const char* buildtype = NULL;
    int _heap_dir = 0; (void)_heap_dir;
    const char* dir = NULL;
    int _heap_base = 0; (void)_heap_base;
    const char* base = NULL;
    int _heap_stem = 0; (void)_heap_stem;
    const char* stem = NULL;
#line 1704 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = buildtype; buildtype = "build"; if (_heap_buildtype) aether_heap_str_free(_tmp_old); _heap_buildtype = 0; aether_unwind_track_str_if(buildtype, _heap_buildtype); }
#line 1705 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = dir; dir = dep_module; if (_heap_dir) aether_heap_str_free(_tmp_old); _heap_dir = 0; aether_unwind_track_str_if(dir, _heap_dir); }
#line 1710 "/home/paul/.local/share/aeb/lib/build/module.ae"
int slash = build__last_slash(dep_module);
#line 1711 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = base; base = dep_module; if (_heap_base) aether_heap_str_free(_tmp_old); _heap_base = 0; aether_unwind_track_str_if(base, _heap_base); }
if (slash >= 0) {
        {
#line 1712 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = base; base = string_substring(dep_module, (slash + 1), string_length(dep_module)); if (_heap_base) aether_heap_str_free(_tmp_old); _heap_base = 1; aether_unwind_track_str_if(base, _heap_base); }
        }
    }
if (string_index_of(base, ".") == 0) {
        {
if (string_ends_with(base, ".ae") == 1) {
                {
#line 1715 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = stem; stem = string_substring(base, 1, (string_length(base) - 3)); if (_heap_stem) aether_heap_str_free(_tmp_old); _heap_stem = 1; aether_unwind_track_str_if(stem, _heap_stem); }
if (string_length(stem) > 0) {
                        {
#line 1717 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = buildtype; buildtype = aether_uniform_heap_str(stem, 0); if (_heap_buildtype) aether_heap_str_free(_tmp_old); _heap_buildtype = 1; aether_unwind_track_str_if(buildtype, _heap_buildtype); }
                        }
                    }
if (slash >= 0) {
                        {
#line 1719 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = dir; dir = string_substring(dep_module, 0, slash); if (_heap_dir) aether_heap_str_free(_tmp_old); _heap_dir = 1; aether_unwind_track_str_if(dir, _heap_dir); }
                        }
                    } else {
                        {
{ const char* _tmp_old = dir; dir = "."; if (_heap_dir) aether_heap_str_free(_tmp_old); _heap_dir = 0; aether_unwind_track_str_if(dir, _heap_dir); }
                        }
                    }
                }
            }
        }
    }
#line 1722 "/home/paul/.local/share/aeb/lib/build/module.ae"
    const char* _builder_ret = aether_uniform_heap_str((const char*)(({ char* _ad_18 = (char*)(({ char* _ad_19 = (char*)(path_join(aether_string_data(root), aether_string_data("target"))); const char* _ad_r = path_join(aether_string_data(_ad_19), aether_string_data(buildtype)); aether_heap_str_free(_ad_19); _ad_r; })); const char* _ad_r = path_join(aether_string_data(_ad_18), aether_string_data(dir)); aether_heap_str_free(_ad_18); _ad_r; })), 1);
    /* deferred */ if (_heap_stem) { aether_heap_str_free(stem); stem = NULL; _heap_stem = 0; }
    /* deferred */ if (_heap_base) { aether_heap_str_free(base); base = NULL; _heap_base = 0; }
    /* deferred */ if (_heap_dir) { aether_heap_str_free(dir); dir = NULL; _heap_dir = 0; }
    /* deferred */ if (_heap_buildtype) { aether_heap_str_free(buildtype); buildtype = NULL; _heap_buildtype = 0; }
    return _builder_ret;
    /* deferred */ if (_heap_stem) { aether_heap_str_free(stem); stem = NULL; _heap_stem = 0; }
    /* deferred */ if (_heap_base) { aether_heap_str_free(base); base = NULL; _heap_base = 0; }
    /* deferred */ if (_heap_dir) { aether_heap_str_free(dir); dir = NULL; _heap_dir = 0; }
    /* deferred */ if (_heap_buildtype) { aether_heap_str_free(buildtype); buildtype = NULL; _heap_buildtype = 0; }
}

#line 1726 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED int build__last_slash(const char* s) {
#line 1727 "/home/paul/.local/share/aeb/lib/build/module.ae"
int n = string_length(s);
#line 1728 "/home/paul/.local/share/aeb/lib/build/module.ae"
int found = (-(1));
#line 1729 "/home/paul/.local/share/aeb/lib/build/module.ae"
int i = 0;
while (i < n) {
        {
if (({ char* _ad_20 = (char*)(string_substring(s, i, (i + 1))); int _ad_r = string_equals(_ad_20, "/"); aether_heap_str_free(_ad_20); _ad_r; }) == 1) {
                {
#line 1731 "/home/paul/.local/share/aeb/lib/build/module.ae"
found = i;
                }
            }
#line 1732 "/home/paul/.local/share/aeb/lib/build/module.ae"
i = (i + 1);
        }
    }
#line 1734 "/home/paul/.local/share/aeb/lib/build/module.ae"
    return found;
}

#line 2000 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build__project_run_cmd(const char* absdir, void* env_pairs, void* steps) {
    int _heap_cmd = 0; (void)_heap_cmd;
    const char* cmd = NULL;
#line 2001 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = cmd; cmd = string_concat("cd \"", absdir); if (_heap_cmd) aether_heap_str_free(_tmp_old); _heap_cmd = 1; }
#line 2002 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = cmd; cmd = string_concat(cmd, "\""); if (_heap_cmd) aether_heap_str_free(_tmp_old); _heap_cmd = 1; }
#line 2003 "/home/paul/.local/share/aeb/lib/build/module.ae"
int ne = list_size(env_pairs);
#line 2004 "/home/paul/.local/share/aeb/lib/build/module.ae"
int i = 0;
while (i < ne) {
        {
#line 2006 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_ptr_string _tup19 = list_get(env_pairs, i);
            void* frag = _tup19._0;
#line 2007 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = cmd; cmd = string_concat(cmd, " && export "); if (_heap_cmd) aether_heap_str_free(_tmp_old); _heap_cmd = 1; }
#line 2008 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = cmd; cmd = string_concat(cmd, frag); if (_heap_cmd) aether_heap_str_free(_tmp_old); _heap_cmd = 1; }
#line 2009 "/home/paul/.local/share/aeb/lib/build/module.ae"
i = (i + 1);
        }
    }
#line 2011 "/home/paul/.local/share/aeb/lib/build/module.ae"
int ns = list_size(steps);
#line 2012 "/home/paul/.local/share/aeb/lib/build/module.ae"
int j = 0;
while (j < ns) {
        {
#line 2014 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_ptr_string _tup20 = list_get(steps, j);
            void* st = _tup20._0;
#line 2015 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = cmd; cmd = string_concat(cmd, " && "); if (_heap_cmd) aether_heap_str_free(_tmp_old); _heap_cmd = 1; }
#line 2016 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = cmd; cmd = string_concat(cmd, st); if (_heap_cmd) aether_heap_str_free(_tmp_old); _heap_cmd = 1; }
#line 2017 "/home/paul/.local/share/aeb/lib/build/module.ae"
j = (j + 1);
        }
    }
#line 2019 "/home/paul/.local/share/aeb/lib/build/module.ae"
    const char* _no_defer_ret = aether_uniform_heap_str((const char*)(cmd), _heap_cmd);
    return _no_defer_ret;
}

#line 2061 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build__run_project_cmd(const char* source_dir, const char* root, void* bmap, const char* default_step) {
    int _heap_absdir = 0; (void)_heap_absdir;
    const char* absdir = NULL;
    int _heap__d = 0; (void)_heap__d;
    const char* _d = NULL;
#line 2062 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = absdir; absdir = source_dir; if (_heap_absdir) aether_heap_str_free(_tmp_old); _heap_absdir = 0; aether_unwind_track_str_if(absdir, _heap_absdir); }
#line 2063 "/home/paul/.local/share/aeb/lib/build/module.ae"
void* env_pairs = list_new();
#line 2064 "/home/paul/.local/share/aeb/lib/build/module.ae"
void* steps = list_new();
if (bmap != NULL) {
        {
if (map_has(bmap, aether_string_data("proc_workdir")) == 1) {
                {
#line 2067 "/home/paul/.local/share/aeb/lib/build/module.ae"
                    _tuple_ptr_string _tup21 = map_get(bmap, "proc_workdir");
                    void* wd = _tup21._0;
#line 2068 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = absdir; absdir = path_join(aether_string_data(root), aether_string_data(wd)); if (_heap_absdir) aether_heap_str_free(_tmp_old); _heap_absdir = 1; aether_unwind_track_str_if(absdir, _heap_absdir); }
                }
            }
if (map_has(bmap, aether_string_data("proc_env")) == 1) {
                {
#line 2070 "/home/paul/.local/share/aeb/lib/build/module.ae"
                    _tuple_ptr_string _tup22 = map_get(bmap, "proc_env");
                    env_pairs = _tup22._0;
                }
            }
if (map_has(bmap, aether_string_data("proc_steps")) == 1) {
                {
#line 2071 "/home/paul/.local/share/aeb/lib/build/module.ae"
                    _tuple_ptr_string _tup23 = map_get(bmap, "proc_steps");
                    steps = _tup23._0;
                }
            }
        }
    }
if (list_size(steps) == 0) {
        {
#line 2073 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = _d; _d = list_add(steps, (void*)(default_step)); if (_heap__d) aether_heap_str_free(_tmp_old); _heap__d = 0; aether_unwind_track_str_if(_d, _heap__d); }
        }
    }
#line 2074 "/home/paul/.local/share/aeb/lib/build/module.ae"
    const char* _builder_ret = aether_uniform_heap_str((const char*)(build__project_run_cmd(absdir, env_pairs, steps)), 1);
    /* deferred */ if (_heap__d) { aether_heap_str_free(_d); _d = NULL; _heap__d = 0; }
    /* deferred */ if (_heap_absdir) { aether_heap_str_free(absdir); absdir = NULL; _heap_absdir = 0; }
    return _builder_ret;
    /* deferred */ if (_heap__d) { aether_heap_str_free(_d); _d = NULL; _heap__d = 0; }
    /* deferred */ if (_heap_absdir) { aether_heap_str_free(absdir); absdir = NULL; _heap_absdir = 0; }
}

#line 2134 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED void build__record_cache(void* ctx, const char* outcome) {
    int _heap_p = 0; (void)_heap_p;
    const char* p = NULL;
    int _heap__e = 0; (void)_heap__e;
    const char* _e = NULL;
#line 2135 "/home/paul/.local/share/aeb/lib/build/module.ae"
void* td = build__get(ctx, "target_dir");
#line 2136 "/home/paul/.local/share/aeb/lib/build/module.ae"
build__mkdirs(td);
#line 2137 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = p; p = path_join(aether_string_data(td), aether_string_data(".aeb_cache")); if (_heap_p) aether_heap_str_free(_tmp_old); _heap_p = 1; aether_unwind_track_str_if(p, _heap_p); }
#line 2138 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = _e; _e = fs_write_atomic(p, outcome, string_length(outcome)); if (_heap__e) aether_heap_str_free(_tmp_old); _heap__e = 0; aether_unwind_track_str_if(_e, _heap__e); }
    /* deferred */ if (_heap__e) { aether_heap_str_free(_e); _e = NULL; _heap__e = 0; }
    /* deferred */ if (_heap_p) { aether_heap_str_free(p); p = NULL; _heap_p = 0; }
}

#line 2143 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build__read_cache_outcome(const char* target_dir) {
    int _heap_p = 0; (void)_heap_p;
    const char* p = NULL;
    int _heap_content = 0; (void)_heap_content;
    const char* content = NULL;
    int _heap__err = 0; (void)_heap__err;
    const char* _err = NULL;
    int _heap_out = 0; (void)_heap_out;
    const char* out = NULL;
#line 2144 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = p; p = path_join(aether_string_data(target_dir), aether_string_data(".aeb_cache")); if (_heap_p) aether_heap_str_free(_tmp_old); _heap_p = 1; aether_unwind_track_str_if(p, _heap_p); }
if (fs_exists(p) == 0) {
        {
#line 2146 "/home/paul/.local/share/aeb/lib/build/module.ae"
            const char* _builder_ret = aether_uniform_heap_str((const char*)("n/a"), 0);
            if (_heap_out) { aether_heap_str_free(out); out = NULL; _heap_out = 0; }
            /* deferred */ if (_heap__err) { aether_heap_str_free(_err); _err = NULL; _heap__err = 0; }
            /* deferred */ if (_heap_content) { aether_heap_str_free(content); content = NULL; _heap_content = 0; }
            /* deferred */ if (_heap_p) { aether_heap_str_free(p); p = NULL; _heap_p = 0; }
            return _builder_ret;
        }
    }
#line 2148 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_string_string _tup24 = fs_read(p);
    { const char* _tmp_old = content; content = _tup24._0; if (_heap_content) aether_heap_str_free(_tmp_old); _heap_content = 1; aether_unwind_track_str_if(content, _heap_content); }
    { const char* _tmp_old = _err; _err = _tup24._1; if (_heap__err) aether_heap_str_free(_tmp_old); _heap__err = 0; aether_unwind_track_str_if(_err, _heap__err); }
#line 2149 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_trim(content); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
if (string_length(out) == 0) {
        {
#line 2150 "/home/paul/.local/share/aeb/lib/build/module.ae"
            const char* _builder_ret = aether_uniform_heap_str((const char*)("n/a"), 0);
            if (_heap_out) { aether_heap_str_free(out); out = NULL; _heap_out = 0; }
            /* deferred */ if (_heap__err) { aether_heap_str_free(_err); _err = NULL; _heap__err = 0; }
            /* deferred */ if (_heap_content) { aether_heap_str_free(content); content = NULL; _heap_content = 0; }
            /* deferred */ if (_heap_p) { aether_heap_str_free(p); p = NULL; _heap_p = 0; }
            return _builder_ret;
        }
    }
#line 2151 "/home/paul/.local/share/aeb/lib/build/module.ae"
    const char* _builder_ret = aether_uniform_heap_str((const char*)(out), _heap_out);
    /* deferred */ if (_heap__err) { aether_heap_str_free(_err); _err = NULL; _heap__err = 0; }
    /* deferred */ if (_heap_content) { aether_heap_str_free(content); content = NULL; _heap_content = 0; }
    /* deferred */ if (_heap_p) { aether_heap_str_free(p); p = NULL; _heap_p = 0; }
    return _builder_ret;
    /* deferred */ if (_heap__err) { aether_heap_str_free(_err); _err = NULL; _heap__err = 0; }
    /* deferred */ if (_heap_content) { aether_heap_str_free(content); content = NULL; _heap_content = 0; }
    /* deferred */ if (_heap_p) { aether_heap_str_free(p); p = NULL; _heap_p = 0; }
}

#line 2193 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED _tuple_string_string build__tar_dir(const char* src_dir) {
    int _heap_tmp_raw = 0; (void)_heap_tmp_raw;
    const char* tmp_raw = NULL;
    int _heap__err = 0; (void)_heap__err;
    const char* _err = NULL;
    int _heap_tmp = 0; (void)_heap_tmp;
    const char* tmp = NULL;
    int _heap_cmd = 0; (void)_heap_cmd;
    const char* cmd = NULL;
    int _heap_out = 0; (void)_heap_out;
    const char* out = NULL;
    int _heap_eerr = 0; (void)_heap_eerr;
    const char* eerr = NULL;
#line 2194 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_string_string _tup25 = build__sh_capture("mktemp");
    { const char* _tmp_old = tmp_raw; tmp_raw = _tup25._0; if (_heap_tmp_raw) aether_heap_str_free(_tmp_old); _heap_tmp_raw = 1; aether_unwind_track_str_if(tmp_raw, _heap_tmp_raw); }
    { const char* _tmp_old = _err; _err = _tup25._1; if (_heap__err) aether_heap_str_free(_tmp_old); _heap__err = 0; aether_unwind_track_str_if(_err, _heap__err); }
#line 2204 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = tmp; tmp = ({ char* _ad_21 = (char*)(string_trim(tmp_raw)); const char* _ad_r = build__to_native_path(_ad_21); if ((const char*)_ad_r != _ad_21) string_release(_ad_21); _ad_r; }); if (_heap_tmp) aether_heap_str_free(_tmp_old); _heap_tmp = 1; }
if (string_length(tmp) == 0) {
        {
#line 2206 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_string_string _builder_ret = (_tuple_string_string){aether_uniform_heap_str((const char*)(""), 0), aether_uniform_heap_str((const char*)("mktemp failed"), 0)};
            /* deferred */ if (_heap_eerr) { aether_heap_str_free(eerr); eerr = NULL; _heap_eerr = 0; }
            /* deferred */ if (_heap_out) { aether_heap_str_free(out); out = NULL; _heap_out = 0; }
            /* deferred */ if (_heap__err) { aether_heap_str_free(_err); _err = NULL; _heap__err = 0; }
            /* deferred */ if (_heap_tmp_raw) { aether_heap_str_free(tmp_raw); tmp_raw = NULL; _heap_tmp_raw = 0; }
            return _builder_ret;
        }
    }
#line 2213 "/home/paul/.local/share/aeb/lib/build/module.ae"
cmd = _aether_interp("tar %s-cf '%s' -C '%s' . 2>&1", _aether_safe_str(build__tar_local_flag()), _aether_safe_str(tmp), _aether_safe_str(src_dir));
#line 2214 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_string_string _tup26 = build__sh_capture(cmd);
    { const char* _tmp_old = out; out = _tup26._0; if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; aether_unwind_track_str_if(out, _heap_out); }
    { const char* _tmp_old = eerr; eerr = _tup26._1; if (_heap_eerr) aether_heap_str_free(_tmp_old); _heap_eerr = 0; aether_unwind_track_str_if(eerr, _heap_eerr); }
if (string_length(eerr) > 0) {
        {
#line 2216 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_string_string _builder_ret = (_tuple_string_string){aether_uniform_heap_str((const char*)(""), 0), aether_uniform_heap_str((const char*)(string_concat("tar failed: ", eerr)), 1)};
            /* deferred */ if (_heap_eerr) { aether_heap_str_free(eerr); eerr = NULL; _heap_eerr = 0; }
            /* deferred */ if (_heap_out) { aether_heap_str_free(out); out = NULL; _heap_out = 0; }
            /* deferred */ if (_heap__err) { aether_heap_str_free(_err); _err = NULL; _heap__err = 0; }
            /* deferred */ if (_heap_tmp_raw) { aether_heap_str_free(tmp_raw); tmp_raw = NULL; _heap_tmp_raw = 0; }
            return _builder_ret;
        }
    }
#line 2218 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_string_string _builder_ret = (_tuple_string_string){aether_uniform_heap_str((const char*)(tmp), _heap_tmp), aether_uniform_heap_str((const char*)(""), 0)};
    /* deferred */ if (_heap_eerr) { aether_heap_str_free(eerr); eerr = NULL; _heap_eerr = 0; }
    /* deferred */ if (_heap_out) { aether_heap_str_free(out); out = NULL; _heap_out = 0; }
    /* deferred */ if (_heap__err) { aether_heap_str_free(_err); _err = NULL; _heap__err = 0; }
    /* deferred */ if (_heap_tmp_raw) { aether_heap_str_free(tmp_raw); tmp_raw = NULL; _heap_tmp_raw = 0; }
    return _builder_ret;
    /* deferred */ if (_heap_eerr) { aether_heap_str_free(eerr); eerr = NULL; _heap_eerr = 0; }
    /* deferred */ if (_heap_out) { aether_heap_str_free(out); out = NULL; _heap_out = 0; }
    /* deferred */ if (_heap__err) { aether_heap_str_free(_err); _err = NULL; _heap__err = 0; }
    /* deferred */ if (_heap_tmp_raw) { aether_heap_str_free(tmp_raw); tmp_raw = NULL; _heap_tmp_raw = 0; }
}

#line 2223 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build__tar_local_flag(void) {
if (build__is_windows() == 1) {
        {
#line 2224 "/home/paul/.local/share/aeb/lib/build/module.ae"
            return "--force-local ";
        }
    }
#line 2225 "/home/paul/.local/share/aeb/lib/build/module.ae"
    return "";
}

#line 2274 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED void build__record_test_result(void* ctx, int passed, int failed) {
#line 2278 "/home/paul/.local/share/aeb/lib/build/module.ae"
build__record_test_result_r(ctx, passed, failed, 0, 1);
}

#line 2334 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED int build__int_key(void* bmap, const char* key) {
    int _heap__e = 0; (void)_heap__e;
    const char* _e = NULL;
if (bmap == NULL) {
        {
#line 2335 "/home/paul/.local/share/aeb/lib/build/module.ae"
            int _builder_ret = 0;
            /* deferred */ if (_heap__e) { aether_heap_str_free(_e); _e = NULL; _heap__e = 0; }
            return _builder_ret;
        }
    }
if (map_has(bmap, aether_string_data(key)) == 0) {
        {
#line 2336 "/home/paul/.local/share/aeb/lib/build/module.ae"
            int _builder_ret = 0;
            /* deferred */ if (_heap__e) { aether_heap_str_free(_e); _e = NULL; _heap__e = 0; }
            return _builder_ret;
        }
    }
#line 2337 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_ptr_string _tup27 = map_get(bmap, key);
    void* v = _tup27._0;
#line 2338 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_int_string _tup28 = ({ char* _ad_22 = (char*)(string_trim(v)); _tuple_int_string _ad_r = string_to_int(_ad_22); aether_heap_str_free(_ad_22); _ad_r; });
    int iv = _tup28._0;
    { const char* _tmp_old = _e; _e = _tup28._1; if (_heap__e) aether_heap_str_free(_tmp_old); _heap__e = 0; aether_unwind_track_str_if(_e, _heap__e); }
#line 2339 "/home/paul/.local/share/aeb/lib/build/module.ae"
    int _builder_ret = iv;
    /* deferred */ if (_heap__e) { aether_heap_str_free(_e); _e = NULL; _heap__e = 0; }
    return _builder_ret;
    /* deferred */ if (_heap__e) { aether_heap_str_free(_e); _e = NULL; _heap__e = 0; }
}

#line 2375 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build__str_key(void* bmap, const char* key) {
if (bmap == NULL) {
        {
#line 2376 "/home/paul/.local/share/aeb/lib/build/module.ae"
            return "";
        }
    }
if (map_has(bmap, aether_string_data(key)) == 0) {
        {
#line 2377 "/home/paul/.local/share/aeb/lib/build/module.ae"
            return "";
        }
    }
#line 2378 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_ptr_string _tup29 = map_get(bmap, key);
    void* v = _tup29._0;
#line 2379 "/home/paul/.local/share/aeb/lib/build/module.ae"
    return v;
}

#line 2548 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED void build__record_test_result_r(void* ctx, int passed, int failed, int skipped, int has_report) {
    int _heap_p = 0; (void)_heap_p;
    const char* p = NULL;
    int _heap_body = 0; (void)_heap_body;
    const char* body = NULL;
    int _heap__e = 0; (void)_heap__e;
    const char* _e = NULL;
#line 2549 "/home/paul/.local/share/aeb/lib/build/module.ae"
void* td = build__get(ctx, "target_dir");
#line 2550 "/home/paul/.local/share/aeb/lib/build/module.ae"
build__mkdirs(td);
#line 2551 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = p; p = path_join(aether_string_data(td), aether_string_data(".aeb_test_result")); if (_heap_p) aether_heap_str_free(_tmp_old); _heap_p = 1; aether_unwind_track_str_if(p, _heap_p); }
#line 2552 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = body; body = ({ char* _ad_23 = (char*)(string_from_int(passed)); const char* _ad_r = string_concat("passed=", _ad_23); aether_heap_str_free(_ad_23); _ad_r; }); if (_heap_body) aether_heap_str_free(_tmp_old); _heap_body = 1; aether_unwind_track_str_if(body, _heap_body); }
#line 2553 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = body; body = string_concat(body, "\nfailed="); if (_heap_body) aether_heap_str_free(_tmp_old); _heap_body = 1; aether_unwind_track_str_if(body, _heap_body); }
#line 2554 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = body; body = ({ char* _ad_24 = (char*)(string_from_int(failed)); const char* _ad_r = string_concat(body, _ad_24); aether_heap_str_free(_ad_24); _ad_r; }); if (_heap_body) aether_heap_str_free(_tmp_old); _heap_body = 1; aether_unwind_track_str_if(body, _heap_body); }
#line 2555 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = body; body = string_concat(body, "\nskipped="); if (_heap_body) aether_heap_str_free(_tmp_old); _heap_body = 1; aether_unwind_track_str_if(body, _heap_body); }
#line 2556 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = body; body = ({ char* _ad_25 = (char*)(string_from_int(skipped)); const char* _ad_r = string_concat(body, _ad_25); aether_heap_str_free(_ad_25); _ad_r; }); if (_heap_body) aether_heap_str_free(_tmp_old); _heap_body = 1; aether_unwind_track_str_if(body, _heap_body); }
#line 2557 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = body; body = string_concat(body, "\nreport="); if (_heap_body) aether_heap_str_free(_tmp_old); _heap_body = 1; aether_unwind_track_str_if(body, _heap_body); }
#line 2558 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = body; body = ({ char* _ad_26 = (char*)(string_from_int(has_report)); const char* _ad_r = string_concat(body, _ad_26); aether_heap_str_free(_ad_26); _ad_r; }); if (_heap_body) aether_heap_str_free(_tmp_old); _heap_body = 1; aether_unwind_track_str_if(body, _heap_body); }
#line 2559 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = body; body = string_concat(body, "\n"); if (_heap_body) aether_heap_str_free(_tmp_old); _heap_body = 1; aether_unwind_track_str_if(body, _heap_body); }
#line 2560 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = _e; _e = fs_write_atomic(p, body, string_length(body)); if (_heap__e) aether_heap_str_free(_tmp_old); _heap__e = 0; aether_unwind_track_str_if(_e, _heap__e); }
    /* deferred */ if (_heap__e) { aether_heap_str_free(_e); _e = NULL; _heap__e = 0; }
    /* deferred */ if (_heap_body) { aether_heap_str_free(body); body = NULL; _heap_body = 0; }
    /* deferred */ if (_heap_p) { aether_heap_str_free(p); p = NULL; _heap_p = 0; }
}

#line 2570 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED _tuple_int_int_int_int build__read_test_result(const char* target_dir) {
    int _heap_p = 0; (void)_heap_p;
    const char* p = NULL;
    int _heap_content = 0; (void)_heap_content;
    const char* content = NULL;
    int _heap__err = 0; (void)_heap__err;
    const char* _err = NULL;
    int _heap_rest = 0; (void)_heap_rest;
    const char* rest = NULL;
    int _heap_line = 0; (void)_heap_line;
    const char* line = NULL;
    int _heap_key = 0; (void)_heap_key;
    const char* key = NULL;
    int _heap_value_str = 0; (void)_heap_value_str;
    const char* value_str = NULL;
    int _heap__verr = 0; (void)_heap__verr;
    const char* _verr = NULL;
#line 2571 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = p; p = path_join(aether_string_data(target_dir), aether_string_data(".aeb_test_result")); if (_heap_p) aether_heap_str_free(_tmp_old); _heap_p = 1; aether_unwind_track_str_if(p, _heap_p); }
if (fs_exists(p) == 0) {
        {
#line 2573 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_int_int_int_int _builder_ret = (_tuple_int_int_int_int){0, 0, 0, 0};
            /* deferred */ if (_heap__verr) { aether_heap_str_free(_verr); _verr = NULL; _heap__verr = 0; }
            /* deferred */ if (_heap_value_str) { aether_heap_str_free(value_str); value_str = NULL; _heap_value_str = 0; }
            /* deferred */ if (_heap_key) { aether_heap_str_free(key); key = NULL; _heap_key = 0; }
            /* deferred */ if (_heap_line) { aether_heap_str_free(line); line = NULL; _heap_line = 0; }
            /* deferred */ if (_heap_rest) { aether_heap_str_free(rest); rest = NULL; _heap_rest = 0; }
            /* deferred */ if (_heap__err) { aether_heap_str_free(_err); _err = NULL; _heap__err = 0; }
            /* deferred */ if (_heap_content) { aether_heap_str_free(content); content = NULL; _heap_content = 0; }
            /* deferred */ if (_heap_p) { aether_heap_str_free(p); p = NULL; _heap_p = 0; }
            return _builder_ret;
        }
    }
#line 2575 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_string_string _tup30 = fs_read(p);
    { const char* _tmp_old = content; content = _tup30._0; if (_heap_content) aether_heap_str_free(_tmp_old); _heap_content = 1; aether_unwind_track_str_if(content, _heap_content); }
    { const char* _tmp_old = _err; _err = _tup30._1; if (_heap__err) aether_heap_str_free(_tmp_old); _heap__err = 0; aether_unwind_track_str_if(_err, _heap__err); }
if (string_length(content) == 0) {
        {
#line 2576 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_int_int_int_int _builder_ret = (_tuple_int_int_int_int){0, 0, 0, 0};
            /* deferred */ if (_heap__verr) { aether_heap_str_free(_verr); _verr = NULL; _heap__verr = 0; }
            /* deferred */ if (_heap_value_str) { aether_heap_str_free(value_str); value_str = NULL; _heap_value_str = 0; }
            /* deferred */ if (_heap_key) { aether_heap_str_free(key); key = NULL; _heap_key = 0; }
            /* deferred */ if (_heap_line) { aether_heap_str_free(line); line = NULL; _heap_line = 0; }
            /* deferred */ if (_heap_rest) { aether_heap_str_free(rest); rest = NULL; _heap_rest = 0; }
            /* deferred */ if (_heap__err) { aether_heap_str_free(_err); _err = NULL; _heap__err = 0; }
            /* deferred */ if (_heap_content) { aether_heap_str_free(content); content = NULL; _heap_content = 0; }
            /* deferred */ if (_heap_p) { aether_heap_str_free(p); p = NULL; _heap_p = 0; }
            return _builder_ret;
        }
    }
#line 2577 "/home/paul/.local/share/aeb/lib/build/module.ae"
int passed = 0;
#line 2578 "/home/paul/.local/share/aeb/lib/build/module.ae"
int failed = 0;
#line 2579 "/home/paul/.local/share/aeb/lib/build/module.ae"
int skipped = 0;
#line 2580 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = rest; rest = aether_uniform_heap_str(content, 0); if (_heap_rest) aether_heap_str_free(_tmp_old); _heap_rest = 1; aether_unwind_track_str_if(rest, _heap_rest); }
    int nl;
    int eq;
while (string_length(rest) > 0) {
        {
#line 2582 "/home/paul/.local/share/aeb/lib/build/module.ae"
nl = string_index_of(rest, "\n");
#line 2583 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = line; line = ""; if (_heap_line) aether_heap_str_free(_tmp_old); _heap_line = 0; aether_unwind_track_str_if(line, _heap_line); }
if (nl < 0) {
                {
#line 2585 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = line; line = aether_uniform_heap_str(rest, 0); if (_heap_line) aether_heap_str_free(_tmp_old); _heap_line = 1; aether_unwind_track_str_if(line, _heap_line); }
#line 2586 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = rest; rest = ""; if (_heap_rest) aether_heap_str_free(_tmp_old); _heap_rest = 0; aether_unwind_track_str_if(rest, _heap_rest); }
                }
            } else {
                {
#line 2588 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = line; line = string_substring(rest, 0, nl); if (_heap_line) aether_heap_str_free(_tmp_old); _heap_line = 1; aether_unwind_track_str_if(line, _heap_line); }
#line 2589 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = rest; rest = string_substring(rest, (nl + 1), string_length(rest)); if (_heap_rest) aether_heap_str_free(_tmp_old); _heap_rest = 1; aether_unwind_track_str_if(rest, _heap_rest); }
                }
            }
#line 2591 "/home/paul/.local/share/aeb/lib/build/module.ae"
eq = string_index_of(line, "=");
if (eq > 0) {
                {
#line 2593 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = key; key = string_substring(line, 0, eq); if (_heap_key) aether_heap_str_free(_tmp_old); _heap_key = 1; aether_unwind_track_str_if(key, _heap_key); }
#line 2594 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = value_str; value_str = string_substring(line, (eq + 1), string_length(line)); if (_heap_value_str) aether_heap_str_free(_tmp_old); _heap_value_str = 1; aether_unwind_track_str_if(value_str, _heap_value_str); }
#line 2595 "/home/paul/.local/share/aeb/lib/build/module.ae"
                    _tuple_int_string _tup31 = ({ char* _ad_27 = (char*)(string_trim(value_str)); _tuple_int_string _ad_r = string_to_int(_ad_27); aether_heap_str_free(_ad_27); _ad_r; });
                    int value = _tup31._0;
                    { const char* _tmp_old = _verr; _verr = _tup31._1; if (_heap__verr) aether_heap_str_free(_tmp_old); _heap__verr = 0; aether_unwind_track_str_if(_verr, _heap__verr); }
if (string_equals(key, "passed") == 1) {
                        {
#line 2596 "/home/paul/.local/share/aeb/lib/build/module.ae"
passed = value;
                        }
                    }
if (string_equals(key, "failed") == 1) {
                        {
#line 2597 "/home/paul/.local/share/aeb/lib/build/module.ae"
failed = value;
                        }
                    }
if (string_equals(key, "skipped") == 1) {
                        {
#line 2598 "/home/paul/.local/share/aeb/lib/build/module.ae"
skipped = value;
                        }
                    }
                }
            }
        }
    }
#line 2601 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_int_int_int_int _builder_ret = (_tuple_int_int_int_int){passed, failed, skipped, 1};
    /* deferred */ if (_heap__verr) { aether_heap_str_free(_verr); _verr = NULL; _heap__verr = 0; }
    /* deferred */ if (_heap_value_str) { aether_heap_str_free(value_str); value_str = NULL; _heap_value_str = 0; }
    /* deferred */ if (_heap_key) { aether_heap_str_free(key); key = NULL; _heap_key = 0; }
    /* deferred */ if (_heap_line) { aether_heap_str_free(line); line = NULL; _heap_line = 0; }
    /* deferred */ if (_heap_rest) { aether_heap_str_free(rest); rest = NULL; _heap_rest = 0; }
    /* deferred */ if (_heap__err) { aether_heap_str_free(_err); _err = NULL; _heap__err = 0; }
    /* deferred */ if (_heap_content) { aether_heap_str_free(content); content = NULL; _heap_content = 0; }
    /* deferred */ if (_heap_p) { aether_heap_str_free(p); p = NULL; _heap_p = 0; }
    return _builder_ret;
    /* deferred */ if (_heap__verr) { aether_heap_str_free(_verr); _verr = NULL; _heap__verr = 0; }
    /* deferred */ if (_heap_value_str) { aether_heap_str_free(value_str); value_str = NULL; _heap_value_str = 0; }
    /* deferred */ if (_heap_key) { aether_heap_str_free(key); key = NULL; _heap_key = 0; }
    /* deferred */ if (_heap_line) { aether_heap_str_free(line); line = NULL; _heap_line = 0; }
    /* deferred */ if (_heap_rest) { aether_heap_str_free(rest); rest = NULL; _heap_rest = 0; }
    /* deferred */ if (_heap__err) { aether_heap_str_free(_err); _err = NULL; _heap__err = 0; }
    /* deferred */ if (_heap_content) { aether_heap_str_free(content); content = NULL; _heap_content = 0; }
    /* deferred */ if (_heap_p) { aether_heap_str_free(p); p = NULL; _heap_p = 0; }
}

#line 2610 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED int build__read_test_report_flag(const char* target_dir) {
    int _heap_p = 0; (void)_heap_p;
    const char* p = NULL;
    int _heap_content = 0; (void)_heap_content;
    const char* content = NULL;
    int _heap__err = 0; (void)_heap__err;
    const char* _err = NULL;
    int _heap_rest = 0; (void)_heap_rest;
    const char* rest = NULL;
    int _heap_line = 0; (void)_heap_line;
    const char* line = NULL;
    int _heap_key = 0; (void)_heap_key;
    const char* key = NULL;
    int _heap_value_str = 0; (void)_heap_value_str;
    const char* value_str = NULL;
    int _heap__verr = 0; (void)_heap__verr;
    const char* _verr = NULL;
#line 2611 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = p; p = path_join(aether_string_data(target_dir), aether_string_data(".aeb_test_result")); if (_heap_p) aether_heap_str_free(_tmp_old); _heap_p = 1; aether_unwind_track_str_if(p, _heap_p); }
if (fs_exists(p) == 0) {
        {
#line 2612 "/home/paul/.local/share/aeb/lib/build/module.ae"
            int _builder_ret = 1;
            /* deferred */ if (_heap__verr) { aether_heap_str_free(_verr); _verr = NULL; _heap__verr = 0; }
            /* deferred */ if (_heap_value_str) { aether_heap_str_free(value_str); value_str = NULL; _heap_value_str = 0; }
            /* deferred */ if (_heap_key) { aether_heap_str_free(key); key = NULL; _heap_key = 0; }
            /* deferred */ if (_heap_line) { aether_heap_str_free(line); line = NULL; _heap_line = 0; }
            /* deferred */ if (_heap_rest) { aether_heap_str_free(rest); rest = NULL; _heap_rest = 0; }
            /* deferred */ if (_heap__err) { aether_heap_str_free(_err); _err = NULL; _heap__err = 0; }
            /* deferred */ if (_heap_content) { aether_heap_str_free(content); content = NULL; _heap_content = 0; }
            /* deferred */ if (_heap_p) { aether_heap_str_free(p); p = NULL; _heap_p = 0; }
            return _builder_ret;
        }
    }
#line 2613 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_string_string _tup32 = fs_read(p);
    { const char* _tmp_old = content; content = _tup32._0; if (_heap_content) aether_heap_str_free(_tmp_old); _heap_content = 1; aether_unwind_track_str_if(content, _heap_content); }
    { const char* _tmp_old = _err; _err = _tup32._1; if (_heap__err) aether_heap_str_free(_tmp_old); _heap__err = 0; aether_unwind_track_str_if(_err, _heap__err); }
if (string_length(content) == 0) {
        {
#line 2614 "/home/paul/.local/share/aeb/lib/build/module.ae"
            int _builder_ret = 1;
            /* deferred */ if (_heap__verr) { aether_heap_str_free(_verr); _verr = NULL; _heap__verr = 0; }
            /* deferred */ if (_heap_value_str) { aether_heap_str_free(value_str); value_str = NULL; _heap_value_str = 0; }
            /* deferred */ if (_heap_key) { aether_heap_str_free(key); key = NULL; _heap_key = 0; }
            /* deferred */ if (_heap_line) { aether_heap_str_free(line); line = NULL; _heap_line = 0; }
            /* deferred */ if (_heap_rest) { aether_heap_str_free(rest); rest = NULL; _heap_rest = 0; }
            /* deferred */ if (_heap__err) { aether_heap_str_free(_err); _err = NULL; _heap__err = 0; }
            /* deferred */ if (_heap_content) { aether_heap_str_free(content); content = NULL; _heap_content = 0; }
            /* deferred */ if (_heap_p) { aether_heap_str_free(p); p = NULL; _heap_p = 0; }
            return _builder_ret;
        }
    }
#line 2615 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = rest; rest = aether_uniform_heap_str(content, 0); if (_heap_rest) aether_heap_str_free(_tmp_old); _heap_rest = 1; aether_unwind_track_str_if(rest, _heap_rest); }
    int nl;
    int eq;
while (string_length(rest) > 0) {
        {
#line 2617 "/home/paul/.local/share/aeb/lib/build/module.ae"
nl = string_index_of(rest, "\n");
#line 2618 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = line; line = ""; if (_heap_line) aether_heap_str_free(_tmp_old); _heap_line = 0; aether_unwind_track_str_if(line, _heap_line); }
if (nl < 0) {
                {
#line 2620 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = line; line = aether_uniform_heap_str(rest, 0); if (_heap_line) aether_heap_str_free(_tmp_old); _heap_line = 1; aether_unwind_track_str_if(line, _heap_line); }
#line 2621 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = rest; rest = ""; if (_heap_rest) aether_heap_str_free(_tmp_old); _heap_rest = 0; aether_unwind_track_str_if(rest, _heap_rest); }
                }
            } else {
                {
#line 2623 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = line; line = string_substring(rest, 0, nl); if (_heap_line) aether_heap_str_free(_tmp_old); _heap_line = 1; aether_unwind_track_str_if(line, _heap_line); }
#line 2624 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = rest; rest = string_substring(rest, (nl + 1), string_length(rest)); if (_heap_rest) aether_heap_str_free(_tmp_old); _heap_rest = 1; aether_unwind_track_str_if(rest, _heap_rest); }
                }
            }
#line 2626 "/home/paul/.local/share/aeb/lib/build/module.ae"
eq = string_index_of(line, "=");
if (eq > 0) {
                {
#line 2628 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = key; key = string_substring(line, 0, eq); if (_heap_key) aether_heap_str_free(_tmp_old); _heap_key = 1; aether_unwind_track_str_if(key, _heap_key); }
if (string_equals(key, "report") == 1) {
                        {
#line 2630 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = value_str; value_str = string_substring(line, (eq + 1), string_length(line)); if (_heap_value_str) aether_heap_str_free(_tmp_old); _heap_value_str = 1; aether_unwind_track_str_if(value_str, _heap_value_str); }
#line 2631 "/home/paul/.local/share/aeb/lib/build/module.ae"
                            _tuple_int_string _tup33 = ({ char* _ad_28 = (char*)(string_trim(value_str)); _tuple_int_string _ad_r = string_to_int(_ad_28); aether_heap_str_free(_ad_28); _ad_r; });
                            int value = _tup33._0;
                            { const char* _tmp_old = _verr; _verr = _tup33._1; if (_heap__verr) aether_heap_str_free(_tmp_old); _heap__verr = 0; aether_unwind_track_str_if(_verr, _heap__verr); }
#line 2632 "/home/paul/.local/share/aeb/lib/build/module.ae"
                            int _builder_ret = value;
                            /* deferred */ if (_heap__verr) { aether_heap_str_free(_verr); _verr = NULL; _heap__verr = 0; }
                            /* deferred */ if (_heap_value_str) { aether_heap_str_free(value_str); value_str = NULL; _heap_value_str = 0; }
                            /* deferred */ if (_heap_key) { aether_heap_str_free(key); key = NULL; _heap_key = 0; }
                            /* deferred */ if (_heap_line) { aether_heap_str_free(line); line = NULL; _heap_line = 0; }
                            /* deferred */ if (_heap_rest) { aether_heap_str_free(rest); rest = NULL; _heap_rest = 0; }
                            /* deferred */ if (_heap__err) { aether_heap_str_free(_err); _err = NULL; _heap__err = 0; }
                            /* deferred */ if (_heap_content) { aether_heap_str_free(content); content = NULL; _heap_content = 0; }
                            /* deferred */ if (_heap_p) { aether_heap_str_free(p); p = NULL; _heap_p = 0; }
                            return _builder_ret;
                        }
                    }
                }
            }
        }
    }
#line 2636 "/home/paul/.local/share/aeb/lib/build/module.ae"
    int _builder_ret = 1;
    /* deferred */ if (_heap__verr) { aether_heap_str_free(_verr); _verr = NULL; _heap__verr = 0; }
    /* deferred */ if (_heap_value_str) { aether_heap_str_free(value_str); value_str = NULL; _heap_value_str = 0; }
    /* deferred */ if (_heap_key) { aether_heap_str_free(key); key = NULL; _heap_key = 0; }
    /* deferred */ if (_heap_line) { aether_heap_str_free(line); line = NULL; _heap_line = 0; }
    /* deferred */ if (_heap_rest) { aether_heap_str_free(rest); rest = NULL; _heap_rest = 0; }
    /* deferred */ if (_heap__err) { aether_heap_str_free(_err); _err = NULL; _heap__err = 0; }
    /* deferred */ if (_heap_content) { aether_heap_str_free(content); content = NULL; _heap_content = 0; }
    /* deferred */ if (_heap_p) { aether_heap_str_free(p); p = NULL; _heap_p = 0; }
    return _builder_ret;
    /* deferred */ if (_heap__verr) { aether_heap_str_free(_verr); _verr = NULL; _heap__verr = 0; }
    /* deferred */ if (_heap_value_str) { aether_heap_str_free(value_str); value_str = NULL; _heap_value_str = 0; }
    /* deferred */ if (_heap_key) { aether_heap_str_free(key); key = NULL; _heap_key = 0; }
    /* deferred */ if (_heap_line) { aether_heap_str_free(line); line = NULL; _heap_line = 0; }
    /* deferred */ if (_heap_rest) { aether_heap_str_free(rest); rest = NULL; _heap_rest = 0; }
    /* deferred */ if (_heap__err) { aether_heap_str_free(_err); _err = NULL; _heap__err = 0; }
    /* deferred */ if (_heap_content) { aether_heap_str_free(content); content = NULL; _heap_content = 0; }
    /* deferred */ if (_heap_p) { aether_heap_str_free(p); p = NULL; _heap_p = 0; }
}

#line 2672 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build__read_test_failures(const char* target_dir) {
    int _heap_p = 0; (void)_heap_p;
    const char* p = NULL;
    int _heap_content = 0; (void)_heap_content;
    const char* content = NULL;
    int _heap__err = 0; (void)_heap__err;
    const char* _err = NULL;
#line 2673 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = p; p = path_join(aether_string_data(target_dir), aether_string_data(".aeb_test_failures")); if (_heap_p) aether_heap_str_free(_tmp_old); _heap_p = 1; aether_unwind_track_str_if(p, _heap_p); }
if (fs_exists(p) == 0) {
        {
#line 2675 "/home/paul/.local/share/aeb/lib/build/module.ae"
            const char* _builder_ret = aether_uniform_heap_str((const char*)(""), 0);
            if (_heap_content) { aether_heap_str_free(content); content = NULL; _heap_content = 0; }
            /* deferred */ if (_heap__err) { aether_heap_str_free(_err); _err = NULL; _heap__err = 0; }
            /* deferred */ if (_heap_p) { aether_heap_str_free(p); p = NULL; _heap_p = 0; }
            return _builder_ret;
        }
    }
#line 2677 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_string_string _tup34 = fs_read(p);
    { const char* _tmp_old = content; content = _tup34._0; if (_heap_content) aether_heap_str_free(_tmp_old); _heap_content = 1; }
    { const char* _tmp_old = _err; _err = _tup34._1; if (_heap__err) aether_heap_str_free(_tmp_old); _heap__err = 0; aether_unwind_track_str_if(_err, _heap__err); }
#line 2678 "/home/paul/.local/share/aeb/lib/build/module.ae"
    const char* _builder_ret = aether_uniform_heap_str((const char*)(content), _heap_content);
    /* deferred */ if (_heap__err) { aether_heap_str_free(_err); _err = NULL; _heap__err = 0; }
    /* deferred */ if (_heap_p) { aether_heap_str_free(p); p = NULL; _heap_p = 0; }
    return _builder_ret;
    /* deferred */ if (_heap__err) { aether_heap_str_free(_err); _err = NULL; _heap__err = 0; }
    /* deferred */ if (_heap_p) { aether_heap_str_free(p); p = NULL; _heap_p = 0; }
}

#line 2982 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build__exec_chain_cmd(void* pre_cmds, const char* exec_cmd, void* post_cmds) {
    int _heap_body = 0; (void)_heap_body;
    const char* body = NULL;
if (build__exec_chain_is_passthrough(pre_cmds, post_cmds) == 1) {
        {
#line 2984 "/home/paul/.local/share/aeb/lib/build/module.ae"
            const char* _builder_ret = aether_uniform_heap_str((const char*)(exec_cmd), 0);
            /* deferred */ if (_heap_body) { aether_heap_str_free(body); body = NULL; _heap_body = 0; }
            return _builder_ret;
        }
    }
#line 2986 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = body; body = build__exec_chain_body(pre_cmds, exec_cmd, post_cmds); if (_heap_body) aether_heap_str_free(_tmp_old); _heap_body = 1; aether_unwind_track_str_if(body, _heap_body); }
#line 2987 "/home/paul/.local/share/aeb/lib/build/module.ae"
    const char* _builder_ret = aether_uniform_heap_str((const char*)(_aether_interp("bash -c '%s'", _aether_safe_str(body))), 1);
    /* deferred */ if (_heap_body) { aether_heap_str_free(body); body = NULL; _heap_body = 0; }
    return _builder_ret;
    /* deferred */ if (_heap_body) { aether_heap_str_free(body); body = NULL; _heap_body = 0; }
}

#line 2993 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED int build__exec_chain_is_passthrough(void* pre_cmds, void* post_cmds) {
#line 2994 "/home/paul/.local/share/aeb/lib/build/module.ae"
int pre_n = 0;
if (pre_cmds != NULL) {
        {
#line 2995 "/home/paul/.local/share/aeb/lib/build/module.ae"
pre_n = list_size(pre_cmds);
        }
    }
#line 2996 "/home/paul/.local/share/aeb/lib/build/module.ae"
int post_n = 0;
if (post_cmds != NULL) {
        {
#line 2997 "/home/paul/.local/share/aeb/lib/build/module.ae"
post_n = list_size(post_cmds);
        }
    }
if (pre_n == 0) {
        {
if (post_n == 0) {
                {
#line 3000 "/home/paul/.local/share/aeb/lib/build/module.ae"
                    return 1;
                }
            }
        }
    }
#line 3003 "/home/paul/.local/share/aeb/lib/build/module.ae"
    return 0;
}

#line 3013 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build__exec_chain_body(void* pre_cmds, const char* exec_cmd, void* post_cmds) {
    int _heap_dol_q = 0; (void)_heap_dol_q;
    const char* dol_q = NULL;
    int _heap_dol_rc = 0; (void)_heap_dol_rc;
    const char* dol_rc = NULL;
    int _heap_body = 0; (void)_heap_body;
    const char* body = NULL;
#line 3014 "/home/paul/.local/share/aeb/lib/build/module.ae"
int pre_n = 0;
if (pre_cmds != NULL) {
        {
#line 3015 "/home/paul/.local/share/aeb/lib/build/module.ae"
pre_n = list_size(pre_cmds);
        }
    }
#line 3016 "/home/paul/.local/share/aeb/lib/build/module.ae"
int post_n = 0;
if (post_cmds != NULL) {
        {
#line 3017 "/home/paul/.local/share/aeb/lib/build/module.ae"
post_n = list_size(post_cmds);
        }
    }
#line 3019 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = dol_q; dol_q = "$?"; if (_heap_dol_q) aether_heap_str_free(_tmp_old); _heap_dol_q = 0; aether_unwind_track_str_if(dol_q, _heap_dol_q); }
#line 3020 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = dol_rc; dol_rc = "$rc"; if (_heap_dol_rc) aether_heap_str_free(_tmp_old); _heap_dol_rc = 0; aether_unwind_track_str_if(dol_rc, _heap_dol_rc); }
#line 3022 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = body; body = ""; if (_heap_body) aether_heap_str_free(_tmp_old); _heap_body = 0; }
#line 3023 "/home/paul/.local/share/aeb/lib/build/module.ae"
int i = 0;
while (i < pre_n) {
        {
#line 3025 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_ptr_string _tup35 = list_get(pre_cmds, i);
            void* c = _tup35._0;
#line 3026 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = body; body = string_concat(body, c); if (_heap_body) aether_heap_str_free(_tmp_old); _heap_body = 1; }
#line 3027 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = body; body = string_concat(body, "; "); if (_heap_body) aether_heap_str_free(_tmp_old); _heap_body = 1; }
#line 3028 "/home/paul/.local/share/aeb/lib/build/module.ae"
i = (i + 1);
        }
    }
#line 3030 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = body; body = string_concat(body, exec_cmd); if (_heap_body) aether_heap_str_free(_tmp_old); _heap_body = 1; }
#line 3031 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = body; body = string_concat(body, "; rc="); if (_heap_body) aether_heap_str_free(_tmp_old); _heap_body = 1; }
#line 3032 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = body; body = string_concat(body, dol_q); if (_heap_body) aether_heap_str_free(_tmp_old); _heap_body = 1; }
#line 3033 "/home/paul/.local/share/aeb/lib/build/module.ae"
int j = 0;
while (j < post_n) {
        {
#line 3035 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_ptr_string _tup36 = list_get(post_cmds, j);
            void* pc = _tup36._0;
#line 3036 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = body; body = string_concat(body, "; "); if (_heap_body) aether_heap_str_free(_tmp_old); _heap_body = 1; }
#line 3037 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = body; body = string_concat(body, pc); if (_heap_body) aether_heap_str_free(_tmp_old); _heap_body = 1; }
#line 3038 "/home/paul/.local/share/aeb/lib/build/module.ae"
j = (j + 1);
        }
    }
#line 3040 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = body; body = string_concat(body, "; exit "); if (_heap_body) aether_heap_str_free(_tmp_old); _heap_body = 1; }
#line 3041 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = body; body = string_concat(body, dol_rc); if (_heap_body) aether_heap_str_free(_tmp_old); _heap_body = 1; }
#line 3042 "/home/paul/.local/share/aeb/lib/build/module.ae"
    const char* _builder_ret = aether_uniform_heap_str((const char*)(body), _heap_body);
    /* deferred */ if (_heap_dol_rc) { aether_heap_str_free(dol_rc); dol_rc = NULL; _heap_dol_rc = 0; }
    /* deferred */ if (_heap_dol_q) { aether_heap_str_free(dol_q); dol_q = NULL; _heap_dol_q = 0; }
    return _builder_ret;
    /* deferred */ if (_heap_dol_rc) { aether_heap_str_free(dol_rc); dol_rc = NULL; _heap_dol_rc = 0; }
    /* deferred */ if (_heap_dol_q) { aether_heap_str_free(dol_q); dol_q = NULL; _heap_dol_q = 0; }
}

#line 3318 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build__label_to_target_dir(const char* root, const char* module_dir) {
    int _heap_target_base = 0; (void)_heap_target_base;
    const char* target_base = NULL;
#line 3322 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = target_base; target_base = ({ char* _ad_29 = (char*)(path_join(aether_string_data(root), aether_string_data("target"))); char* _ad_30 = (char*)(build__label_buildtype(module_dir)); const char* _ad_r = path_join(aether_string_data(_ad_29), aether_string_data(_ad_30)); aether_heap_str_free(_ad_29); aether_heap_str_free(_ad_30); _ad_r; }); if (_heap_target_base) aether_heap_str_free(_tmp_old); _heap_target_base = 1; aether_unwind_track_str_if(target_base, _heap_target_base); }
#line 3323 "/home/paul/.local/share/aeb/lib/build/module.ae"
    const char* _builder_ret = aether_uniform_heap_str((const char*)(({ char* _ad_31 = (char*)(build__label_dir(module_dir)); const char* _ad_r = path_join(aether_string_data(target_base), aether_string_data(_ad_31)); aether_heap_str_free(_ad_31); _ad_r; })), 1);
    /* deferred */ if (_heap_target_base) { aether_heap_str_free(target_base); target_base = NULL; _heap_target_base = 0; }
    return _builder_ret;
    /* deferred */ if (_heap_target_base) { aether_heap_str_free(target_base); target_base = NULL; _heap_target_base = 0; }
}

#line 3359 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build__label_display(const char* label) {
#line 3360 "/home/paul/.local/share/aeb/lib/build/module.ae"
    return aether_uniform_heap_str((const char*)(build__label_dir(label)), 1);
}

#line 3371 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED int build__status_is_failed(const char* status) {
if (string_equals(status, "failed") == 1) {
        {
#line 3372 "/home/paul/.local/share/aeb/lib/build/module.ae"
            return 1;
        }
    }
if (string_equals(status, "fail") == 1) {
        {
#line 3373 "/home/paul/.local/share/aeb/lib/build/module.ae"
            return 1;
        }
    }
#line 3374 "/home/paul/.local/share/aeb/lib/build/module.ae"
    return 0;
}

#line 3377 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build__format_telemetry_line(const char* label, const char* type_word, int wall_ms, const char* cache, int test_passed, int test_failed, int has_test_result, const char* status) {
    int _heap_label_col = 0; (void)_heap_label_col;
    const char* label_col = NULL;
    int _heap_type_col = 0; (void)_heap_type_col;
    const char* type_col = NULL;
    int _heap_cs_str = 0; (void)_heap_cs_str;
    const char* cs_str = NULL;
    int _heap_wall_str = 0; (void)_heap_wall_str;
    const char* wall_str = NULL;
    int _heap_base = 0; (void)_heap_base;
    const char* base = NULL;
    int _heap_verdict = 0; (void)_heap_verdict;
    const char* verdict = NULL;
    int _heap_trailer = 0; (void)_heap_trailer;
    const char* trailer = NULL;
#line 3380 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = label_col; label_col = label; if (_heap_label_col) aether_heap_str_free(_tmp_old); _heap_label_col = 0; aether_unwind_track_str_if(label_col, _heap_label_col); }
#line 3381 "/home/paul/.local/share/aeb/lib/build/module.ae"
int pad_to = 32;
#line 3382 "/home/paul/.local/share/aeb/lib/build/module.ae"
int cur = string_length(label_col);
if (cur < pad_to) {
        {
#line 3384 "/home/paul/.local/share/aeb/lib/build/module.ae"
int i = cur;
while (i < pad_to) {
                {
#line 3386 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = label_col; label_col = string_concat(label_col, " "); if (_heap_label_col) aether_heap_str_free(_tmp_old); _heap_label_col = 1; aether_unwind_track_str_if(label_col, _heap_label_col); }
#line 3387 "/home/paul/.local/share/aeb/lib/build/module.ae"
i = (i + 1);
                }
            }
        }
    }
#line 3391 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = type_col; type_col = string_concat(type_word, ":"); if (_heap_type_col) aether_heap_str_free(_tmp_old); _heap_type_col = 1; aether_unwind_track_str_if(type_col, _heap_type_col); }
#line 3392 "/home/paul/.local/share/aeb/lib/build/module.ae"
int cur2 = string_length(type_col);
if (cur2 < 8) {
        {
#line 3394 "/home/paul/.local/share/aeb/lib/build/module.ae"
int j = cur2;
while (j < 8) {
                {
#line 3396 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = type_col; type_col = string_concat(type_col, " "); if (_heap_type_col) aether_heap_str_free(_tmp_old); _heap_type_col = 1; aether_unwind_track_str_if(type_col, _heap_type_col); }
#line 3397 "/home/paul/.local/share/aeb/lib/build/module.ae"
j = (j + 1);
                }
            }
        }
    }
#line 3401 "/home/paul/.local/share/aeb/lib/build/module.ae"
int secs = (wall_ms / 1000);
#line 3402 "/home/paul/.local/share/aeb/lib/build/module.ae"
int rem = (wall_ms - (secs * 1000));
#line 3404 "/home/paul/.local/share/aeb/lib/build/module.ae"
int cs = ((rem + 5) / 10);
if (cs >= 100) {
        {
#line 3406 "/home/paul/.local/share/aeb/lib/build/module.ae"
secs = (secs + 1);
#line 3407 "/home/paul/.local/share/aeb/lib/build/module.ae"
cs = 0;
        }
    }
#line 3409 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = cs_str; cs_str = string_from_int(cs); if (_heap_cs_str) aether_heap_str_free(_tmp_old); _heap_cs_str = 1; aether_unwind_track_str_if(cs_str, _heap_cs_str); }
if (cs < 10) {
        {
#line 3410 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = cs_str; cs_str = string_concat("0", cs_str); if (_heap_cs_str) aether_heap_str_free(_tmp_old); _heap_cs_str = 1; aether_unwind_track_str_if(cs_str, _heap_cs_str); }
        }
    }
#line 3411 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = wall_str; wall_str = ({ char* _ad_32 = (char*)(({ char* _ad_34 = (char*)(string_from_int(secs)); const char* _ad_r = string_concat(_ad_34, "."); aether_heap_str_free(_ad_34); _ad_r; })); char* _ad_33 = (char*)(string_concat(cs_str, "s")); const char* _ad_r = string_concat(_ad_32, _ad_33); aether_heap_str_free(_ad_32); aether_heap_str_free(_ad_33); _ad_r; }); if (_heap_wall_str) aether_heap_str_free(_tmp_old); _heap_wall_str = 1; aether_unwind_track_str_if(wall_str, _heap_wall_str); }
#line 3413 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = base; base = ({ char* _ad_35 = (char*)(({ char* _ad_37 = (char*)(({ char* _ad_39 = (char*)(string_concat("  ", type_col)); const char* _ad_r = string_concat(_ad_39, " "); aether_heap_str_free(_ad_39); _ad_r; })); char* _ad_38 = (char*)(string_concat(label_col, " ")); const char* _ad_r = string_concat(_ad_37, _ad_38); aether_heap_str_free(_ad_37); aether_heap_str_free(_ad_38); _ad_r; })); char* _ad_36 = (char*)(({ char* _ad_40 = (char*)(string_concat(wall_str, " [")); char* _ad_41 = (char*)(string_concat(cache, "]")); const char* _ad_r = string_concat(_ad_40, _ad_41); aether_heap_str_free(_ad_40); aether_heap_str_free(_ad_41); _ad_r; })); const char* _ad_r = string_concat(_ad_35, _ad_36); aether_heap_str_free(_ad_35); aether_heap_str_free(_ad_36); _ad_r; }); if (_heap_base) aether_heap_str_free(_tmp_old); _heap_base = 1; }
if (has_test_result == 0) {
        {
if (build__status_is_failed(status) == 1) {
                {
#line 3419 "/home/paul/.local/share/aeb/lib/build/module.ae"
                    const char* _builder_ret = aether_uniform_heap_str((const char*)(string_concat(base, " FAILED")), 1);
                    if (_heap_base) { aether_heap_str_free(base); base = NULL; _heap_base = 0; }
                    /* deferred */ if (_heap_trailer) { aether_heap_str_free(trailer); trailer = NULL; _heap_trailer = 0; }
                    /* deferred */ if (_heap_verdict) { aether_heap_str_free(verdict); verdict = NULL; _heap_verdict = 0; }
                    /* deferred */ if (_heap_wall_str) { aether_heap_str_free(wall_str); wall_str = NULL; _heap_wall_str = 0; }
                    /* deferred */ if (_heap_cs_str) { aether_heap_str_free(cs_str); cs_str = NULL; _heap_cs_str = 0; }
                    /* deferred */ if (_heap_type_col) { aether_heap_str_free(type_col); type_col = NULL; _heap_type_col = 0; }
                    /* deferred */ if (_heap_label_col) { aether_heap_str_free(label_col); label_col = NULL; _heap_label_col = 0; }
                    return _builder_ret;
                }
            }
#line 3421 "/home/paul/.local/share/aeb/lib/build/module.ae"
            const char* _builder_ret = aether_uniform_heap_str((const char*)(base), _heap_base);
            /* deferred */ if (_heap_trailer) { aether_heap_str_free(trailer); trailer = NULL; _heap_trailer = 0; }
            /* deferred */ if (_heap_verdict) { aether_heap_str_free(verdict); verdict = NULL; _heap_verdict = 0; }
            /* deferred */ if (_heap_wall_str) { aether_heap_str_free(wall_str); wall_str = NULL; _heap_wall_str = 0; }
            /* deferred */ if (_heap_cs_str) { aether_heap_str_free(cs_str); cs_str = NULL; _heap_cs_str = 0; }
            /* deferred */ if (_heap_type_col) { aether_heap_str_free(type_col); type_col = NULL; _heap_type_col = 0; }
            /* deferred */ if (_heap_label_col) { aether_heap_str_free(label_col); label_col = NULL; _heap_label_col = 0; }
            return _builder_ret;
        }
    }
#line 3423 "/home/paul/.local/share/aeb/lib/build/module.ae"
int total = (test_passed + test_failed);
#line 3424 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = verdict; verdict = "PASS"; if (_heap_verdict) aether_heap_str_free(_tmp_old); _heap_verdict = 0; aether_unwind_track_str_if(verdict, _heap_verdict); }
if (test_failed > 0) {
        {
#line 3425 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = verdict; verdict = "FAIL"; if (_heap_verdict) aether_heap_str_free(_tmp_old); _heap_verdict = 0; aether_unwind_track_str_if(verdict, _heap_verdict); }
        }
    }
if (build__status_is_failed(status) == 1) {
        {
#line 3430 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = verdict; verdict = "FAIL"; if (_heap_verdict) aether_heap_str_free(_tmp_old); _heap_verdict = 0; aether_unwind_track_str_if(verdict, _heap_verdict); }
        }
    }
#line 3431 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = trailer; trailer = ({ char* _ad_42 = (char*)(({ char* _ad_44 = (char*)(string_from_int(test_passed)); const char* _ad_r = string_concat(" ", _ad_44); aether_heap_str_free(_ad_44); _ad_r; })); char* _ad_43 = (char*)(({ char* _ad_45 = (char*)(string_from_int(total)); const char* _ad_r = string_concat("/", _ad_45); aether_heap_str_free(_ad_45); _ad_r; })); const char* _ad_r = string_concat(_ad_42, _ad_43); aether_heap_str_free(_ad_42); aether_heap_str_free(_ad_43); _ad_r; }); if (_heap_trailer) aether_heap_str_free(_tmp_old); _heap_trailer = 1; aether_unwind_track_str_if(trailer, _heap_trailer); }
#line 3432 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = trailer; trailer = string_concat(trailer, " "); if (_heap_trailer) aether_heap_str_free(_tmp_old); _heap_trailer = 1; aether_unwind_track_str_if(trailer, _heap_trailer); }
#line 3433 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = trailer; trailer = string_concat(trailer, verdict); if (_heap_trailer) aether_heap_str_free(_tmp_old); _heap_trailer = 1; aether_unwind_track_str_if(trailer, _heap_trailer); }
#line 3434 "/home/paul/.local/share/aeb/lib/build/module.ae"
    const char* _builder_ret = aether_uniform_heap_str((const char*)(string_concat(base, trailer)), 1);
    if (_heap_base) { aether_heap_str_free(base); base = NULL; _heap_base = 0; }
    /* deferred */ if (_heap_trailer) { aether_heap_str_free(trailer); trailer = NULL; _heap_trailer = 0; }
    /* deferred */ if (_heap_verdict) { aether_heap_str_free(verdict); verdict = NULL; _heap_verdict = 0; }
    /* deferred */ if (_heap_wall_str) { aether_heap_str_free(wall_str); wall_str = NULL; _heap_wall_str = 0; }
    /* deferred */ if (_heap_cs_str) { aether_heap_str_free(cs_str); cs_str = NULL; _heap_cs_str = 0; }
    /* deferred */ if (_heap_type_col) { aether_heap_str_free(type_col); type_col = NULL; _heap_type_col = 0; }
    /* deferred */ if (_heap_label_col) { aether_heap_str_free(label_col); label_col = NULL; _heap_label_col = 0; }
    return _builder_ret;
    /* deferred */ if (_heap_trailer) { aether_heap_str_free(trailer); trailer = NULL; _heap_trailer = 0; }
    /* deferred */ if (_heap_verdict) { aether_heap_str_free(verdict); verdict = NULL; _heap_verdict = 0; }
    /* deferred */ if (_heap_wall_str) { aether_heap_str_free(wall_str); wall_str = NULL; _heap_wall_str = 0; }
    /* deferred */ if (_heap_cs_str) { aether_heap_str_free(cs_str); cs_str = NULL; _heap_cs_str = 0; }
    /* deferred */ if (_heap_type_col) { aether_heap_str_free(type_col); type_col = NULL; _heap_type_col = 0; }
    /* deferred */ if (_heap_label_col) { aether_heap_str_free(label_col); label_col = NULL; _heap_label_col = 0; }
}

#line 3458 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build_render_telemetry(void* records, int total_ms) {
    int _heap_out = 0; (void)_heap_out;
    const char* out = NULL;
    int _heap_failed_labels = 0; (void)_heap_failed_labels;
    const char* failed_labels = NULL;
    int _heap__werr = 0; (void)_heap__werr;
    const char* _werr = NULL;
    int _heap_status = 0; (void)_heap_status;
    const char* status = NULL;
    int _heap_line = 0; (void)_heap_line;
    const char* line = NULL;
    int _heap_entry = 0; (void)_heap_entry;
    const char* entry = NULL;
    int _heap_rest = 0; (void)_heap_rest;
    const char* rest = NULL;
    int _heap_cs_str = 0; (void)_heap_cs_str;
    const char* cs_str = NULL;
#line 3459 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = "[telemetry]\n"; if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 0; }
#line 3463 "/home/paul/.local/share/aeb/lib/build/module.ae"
int n_failed = 0;
#line 3464 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = failed_labels; failed_labels = ""; if (_heap_failed_labels) aether_heap_str_free(_tmp_old); _heap_failed_labels = 0; aether_unwind_track_str_if(failed_labels, _heap_failed_labels); }
#line 3465 "/home/paul/.local/share/aeb/lib/build/module.ae"
int n = list_size(records);
#line 3466 "/home/paul/.local/share/aeb/lib/build/module.ae"
int i = 0;
    int passed;
    int failed;
    int has_test_result;
    int nl;
while (i < n) {
        {
#line 3468 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_ptr_string _tup37 = list_get(records, i);
            void* rec = _tup37._0;
#line 3469 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_ptr_string _tup38 = map_get(rec, "label");
            void* label = _tup38._0;
#line 3470 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_ptr_string _tup39 = map_get(rec, "type");
            void* type_word = _tup39._0;
#line 3471 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_ptr_string _tup40 = map_get(rec, "wall_ms");
            void* wm_s = _tup40._0;
#line 3472 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_ptr_string _tup41 = map_get(rec, "cache");
            void* cache = _tup41._0;
#line 3473 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_int_string _tup42 = string_to_int(wm_s);
            int wall_ms = _tup42._0;
            { const char* _tmp_old = _werr; _werr = _tup42._1; if (_heap__werr) aether_heap_str_free(_tmp_old); _heap__werr = 0; aether_unwind_track_str_if(_werr, _heap__werr); }
#line 3476 "/home/paul/.local/share/aeb/lib/build/module.ae"
passed = 0;
#line 3477 "/home/paul/.local/share/aeb/lib/build/module.ae"
failed = 0;
#line 3478 "/home/paul/.local/share/aeb/lib/build/module.ae"
has_test_result = 0;
if (map_has(rec, aether_string_data("test_passed")) == 1) {
                {
#line 3480 "/home/paul/.local/share/aeb/lib/build/module.ae"
                    _tuple_ptr_string _tup43 = map_get(rec, "test_passed");
                    void* tp_s = _tup43._0;
#line 3481 "/home/paul/.local/share/aeb/lib/build/module.ae"
                    _tuple_int_string _tup44 = string_to_int(tp_s);
                    passed = _tup44._0;
#line 3482 "/home/paul/.local/share/aeb/lib/build/module.ae"
                    _tuple_ptr_string _tup45 = map_get(rec, "test_failed");
                    void* tf_s = _tup45._0;
#line 3483 "/home/paul/.local/share/aeb/lib/build/module.ae"
                    _tuple_int_string _tup46 = string_to_int(tf_s);
                    failed = _tup46._0;
#line 3484 "/home/paul/.local/share/aeb/lib/build/module.ae"
has_test_result = 1;
                }
            }
#line 3488 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = status; status = ""; if (_heap_status) aether_heap_str_free(_tmp_old); _heap_status = 0; aether_unwind_track_str_if(status, _heap_status); }
if (map_has(rec, aether_string_data("status")) == 1) {
                {
#line 3490 "/home/paul/.local/share/aeb/lib/build/module.ae"
                    _tuple_ptr_string _tup47 = map_get(rec, "status");
                    { const char* _tmp_old = status; status = _tup47._0; if (_heap_status) aether_heap_str_free(_tmp_old); _heap_status = 0; aether_unwind_track_str_if(status, _heap_status); }
                }
            }
#line 3492 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = line; line = build__format_telemetry_line(build__label_display(label), type_word, wall_ms, cache, passed, failed, has_test_result, status); if (_heap_line) aether_heap_str_free(_tmp_old); _heap_line = 1; aether_unwind_track_str_if(line, _heap_line); }
#line 3493 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, line); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3494 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, "\n"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
if (build__status_is_failed(status) == 1) {
                {
#line 3496 "/home/paul/.local/share/aeb/lib/build/module.ae"
n_failed = (n_failed + 1);
#line 3497 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = failed_labels; failed_labels = string_concat(failed_labels, "\n  "); if (_heap_failed_labels) aether_heap_str_free(_tmp_old); _heap_failed_labels = 1; aether_unwind_track_str_if(failed_labels, _heap_failed_labels); }
#line 3498 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = failed_labels; failed_labels = string_concat(failed_labels, type_word); if (_heap_failed_labels) aether_heap_str_free(_tmp_old); _heap_failed_labels = 1; aether_unwind_track_str_if(failed_labels, _heap_failed_labels); }
#line 3499 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = failed_labels; failed_labels = string_concat(failed_labels, ": "); if (_heap_failed_labels) aether_heap_str_free(_tmp_old); _heap_failed_labels = 1; aether_unwind_track_str_if(failed_labels, _heap_failed_labels); }
#line 3500 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = failed_labels; failed_labels = ({ char* _ad_46 = (char*)(build__label_display(label)); const char* _ad_r = string_concat(failed_labels, _ad_46); aether_heap_str_free(_ad_46); _ad_r; }); if (_heap_failed_labels) aether_heap_str_free(_tmp_old); _heap_failed_labels = 1; aether_unwind_track_str_if(failed_labels, _heap_failed_labels); }
                }
            }
if (failed > 0) {
                {
if (map_has(rec, aether_string_data("test_failed_names")) == 1) {
                        {
#line 3506 "/home/paul/.local/share/aeb/lib/build/module.ae"
                            _tuple_ptr_string _tup48 = map_get(rec, "test_failed_names");
                            void* tfn = _tup48._0;
if (string_length(tfn) > 0) {
                                {
#line 3508 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = rest; rest = tfn; if (_heap_rest) aether_heap_str_free(_tmp_old); _heap_rest = 0; aether_unwind_track_str_if(rest, _heap_rest); }
while (string_length(rest) > 0) {
                                        {
#line 3510 "/home/paul/.local/share/aeb/lib/build/module.ae"
nl = string_index_of(rest, "\n");
#line 3511 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = entry; entry = ""; if (_heap_entry) aether_heap_str_free(_tmp_old); _heap_entry = 0; aether_unwind_track_str_if(entry, _heap_entry); }
if (nl < 0) {
                                                {
#line 3513 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = entry; entry = aether_uniform_heap_str(rest, 0); if (_heap_entry) aether_heap_str_free(_tmp_old); _heap_entry = 1; aether_unwind_track_str_if(entry, _heap_entry); }
#line 3514 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = rest; rest = ""; if (_heap_rest) aether_heap_str_free(_tmp_old); _heap_rest = 0; aether_unwind_track_str_if(rest, _heap_rest); }
                                                }
                                            } else {
                                                {
#line 3516 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = entry; entry = string_substring(rest, 0, nl); if (_heap_entry) aether_heap_str_free(_tmp_old); _heap_entry = 1; aether_unwind_track_str_if(entry, _heap_entry); }
#line 3517 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = rest; rest = string_substring(rest, (nl + 1), string_length(rest)); if (_heap_rest) aether_heap_str_free(_tmp_old); _heap_rest = 1; aether_unwind_track_str_if(rest, _heap_rest); }
                                                }
                                            }
if (string_length(entry) > 0) {
                                                {
#line 3520 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, "          - "); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3521 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, entry); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3522 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, "\n"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
#line 3528 "/home/paul/.local/share/aeb/lib/build/module.ae"
i = (i + 1);
        }
    }
#line 3530 "/home/paul/.local/share/aeb/lib/build/module.ae"
int secs = (total_ms / 1000);
#line 3531 "/home/paul/.local/share/aeb/lib/build/module.ae"
int rem = (total_ms - (secs * 1000));
#line 3532 "/home/paul/.local/share/aeb/lib/build/module.ae"
int cs = ((rem + 5) / 10);
if (cs >= 100) {
        {
#line 3534 "/home/paul/.local/share/aeb/lib/build/module.ae"
secs = (secs + 1);
#line 3535 "/home/paul/.local/share/aeb/lib/build/module.ae"
cs = 0;
        }
    }
#line 3537 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = cs_str; cs_str = string_from_int(cs); if (_heap_cs_str) aether_heap_str_free(_tmp_old); _heap_cs_str = 1; aether_unwind_track_str_if(cs_str, _heap_cs_str); }
if (cs < 10) {
        {
#line 3538 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = cs_str; cs_str = string_concat("0", cs_str); if (_heap_cs_str) aether_heap_str_free(_tmp_old); _heap_cs_str = 1; aether_unwind_track_str_if(cs_str, _heap_cs_str); }
        }
    }
#line 3539 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = ({ char* _ad_47 = (char*)(({ char* _ad_48 = (char*)(({ char* _ad_50 = (char*)(string_from_int(secs)); const char* _ad_r = string_concat("total: ", _ad_50); aether_heap_str_free(_ad_50); _ad_r; })); char* _ad_49 = (char*)(({ char* _ad_51 = (char*)(string_concat(".", cs_str)); const char* _ad_r = string_concat(_ad_51, "s wall"); aether_heap_str_free(_ad_51); _ad_r; })); const char* _ad_r = string_concat(_ad_48, _ad_49); aether_heap_str_free(_ad_48); aether_heap_str_free(_ad_49); _ad_r; })); const char* _ad_r = string_concat(out, _ad_47); aether_heap_str_free(_ad_47); _ad_r; }); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
if (n_failed > 0) {
        {
#line 3544 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, "\nFAILED: "); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3545 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = ({ char* _ad_52 = (char*)(string_from_int(n_failed)); const char* _ad_r = string_concat(out, _ad_52); aether_heap_str_free(_ad_52); _ad_r; }); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
if (n_failed == 1) {
                {
#line 3547 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, " target"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
                }
            } else {
                {
#line 3549 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, " targets"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
                }
            }
#line 3551 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, failed_labels); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
        }
    }
#line 3553 "/home/paul/.local/share/aeb/lib/build/module.ae"
    const char* _builder_ret = aether_uniform_heap_str((const char*)(out), _heap_out);
    /* deferred */ if (_heap_cs_str) { aether_heap_str_free(cs_str); cs_str = NULL; _heap_cs_str = 0; }
    /* deferred */ if (_heap_rest) { aether_heap_str_free(rest); rest = NULL; _heap_rest = 0; }
    /* deferred */ if (_heap_entry) { aether_heap_str_free(entry); entry = NULL; _heap_entry = 0; }
    /* deferred */ if (_heap_line) { aether_heap_str_free(line); line = NULL; _heap_line = 0; }
    /* deferred */ if (_heap_status) { aether_heap_str_free(status); status = NULL; _heap_status = 0; }
    /* deferred */ if (_heap__werr) { aether_heap_str_free(_werr); _werr = NULL; _heap__werr = 0; }
    /* deferred */ if (_heap_failed_labels) { aether_heap_str_free(failed_labels); failed_labels = NULL; _heap_failed_labels = 0; }
    return _builder_ret;
    /* deferred */ if (_heap_cs_str) { aether_heap_str_free(cs_str); cs_str = NULL; _heap_cs_str = 0; }
    /* deferred */ if (_heap_rest) { aether_heap_str_free(rest); rest = NULL; _heap_rest = 0; }
    /* deferred */ if (_heap_entry) { aether_heap_str_free(entry); entry = NULL; _heap_entry = 0; }
    /* deferred */ if (_heap_line) { aether_heap_str_free(line); line = NULL; _heap_line = 0; }
    /* deferred */ if (_heap_status) { aether_heap_str_free(status); status = NULL; _heap_status = 0; }
    /* deferred */ if (_heap__werr) { aether_heap_str_free(_werr); _werr = NULL; _heap__werr = 0; }
    /* deferred */ if (_heap_failed_labels) { aether_heap_str_free(failed_labels); failed_labels = NULL; _heap_failed_labels = 0; }
}

#line 3556 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build__json_escape(const char* s) {
    int _heap_out = 0; (void)_heap_out;
    const char* out = NULL;
    int _heap_ch = 0; (void)_heap_ch;
    const char* ch = NULL;
#line 3557 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = ""; if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 0; }
#line 3558 "/home/paul/.local/share/aeb/lib/build/module.ae"
int n = string_length(s);
#line 3559 "/home/paul/.local/share/aeb/lib/build/module.ae"
int i = 0;
while (i < n) {
        {
#line 3561 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = ch; ch = string_substring(s, i, (i + 1)); if (_heap_ch) aether_heap_str_free(_tmp_old); _heap_ch = 1; aether_unwind_track_str_if(ch, _heap_ch); }
if (string_equals(ch, "\\") == 1) {
                {
#line 3563 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, "\\\\"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
                }
            } else {
                {
if (string_equals(ch, "\"") == 1) {
                        {
#line 3566 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, "\\\""); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
                        }
                    } else {
                        {
if (string_equals(ch, "\n") == 1) {
                                {
#line 3569 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, "\\n"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
                                }
                            } else {
                                {
if (string_equals(ch, "\t") == 1) {
                                        {
#line 3572 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, "\\t"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
                                        }
                                    } else {
                                        {
if (string_equals(ch, "\r") == 1) {
                                                {
#line 3575 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, "\\r"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
                                                }
                                            } else {
                                                {
#line 3577 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, ch); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
#line 3583 "/home/paul/.local/share/aeb/lib/build/module.ae"
i = (i + 1);
        }
    }
#line 3585 "/home/paul/.local/share/aeb/lib/build/module.ae"
    const char* _builder_ret = aether_uniform_heap_str((const char*)(out), _heap_out);
    /* deferred */ if (_heap_ch) { aether_heap_str_free(ch); ch = NULL; _heap_ch = 0; }
    return _builder_ret;
    /* deferred */ if (_heap_ch) { aether_heap_str_free(ch); ch = NULL; _heap_ch = 0; }
}

#line 3588 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build__json_str(const char* s) {
#line 3589 "/home/paul/.local/share/aeb/lib/build/module.ae"
    return aether_uniform_heap_str((const char*)(({ char* _ad_53 = (char*)(({ char* _ad_54 = (char*)(build__json_escape(s)); const char* _ad_r = string_concat("\"", _ad_54); aether_heap_str_free(_ad_54); _ad_r; })); const char* _ad_r = string_concat(_ad_53, "\""); aether_heap_str_free(_ad_53); _ad_r; })), 1);
}

#line 3592 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build__record_json(void* rec) {
    int _heap_status = 0; (void)_heap_status;
    const char* status = NULL;
    int _heap_rc = 0; (void)_heap_rc;
    const char* rc = NULL;
    int _heap_out = 0; (void)_heap_out;
    const char* out = NULL;
    int _heap_tsk = 0; (void)_heap_tsk;
    const char* tsk = NULL;
#line 3593 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_ptr_string _tup49 = map_get(rec, "label");
    void* label = _tup49._0;
#line 3594 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_ptr_string _tup50 = map_get(rec, "type");
    void* type_word = _tup50._0;
#line 3595 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_ptr_string _tup51 = map_get(rec, "wall_ms");
    void* wm_s = _tup51._0;
#line 3596 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_ptr_string _tup52 = map_get(rec, "cache");
    void* cache = _tup52._0;
#line 3597 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = status; status = build__telemetry_status(rec); if (_heap_status) aether_heap_str_free(_tmp_old); _heap_status = 0; aether_unwind_track_str_if(status, _heap_status); }
#line 3598 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = rc; rc = "0"; if (_heap_rc) aether_heap_str_free(_tmp_old); _heap_rc = 0; aether_unwind_track_str_if(rc, _heap_rc); }
if (map_has(rec, aether_string_data("rc")) == 1) {
        {
#line 3600 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_ptr_string _tup53 = map_get(rec, "rc");
            { const char* _tmp_old = rc; rc = _tup53._0; if (_heap_rc) aether_heap_str_free(_tmp_old); _heap_rc = 0; aether_unwind_track_str_if(rc, _heap_rc); }
        }
    }
#line 3602 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = "{"; if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 0; }
#line 3603 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, "\"label\":"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3604 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = ({ char* _ad_55 = (char*)(({ char* _ad_56 = (char*)(build__label_display(label)); const char* _ad_r = build__json_str(_ad_56); aether_heap_str_free(_ad_56); _ad_r; })); const char* _ad_r = string_concat(out, _ad_55); aether_heap_str_free(_ad_55); _ad_r; }); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3605 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, ",\"type\":"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3606 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = ({ char* _ad_57 = (char*)(build__json_str(type_word)); const char* _ad_r = string_concat(out, _ad_57); aether_heap_str_free(_ad_57); _ad_r; }); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3607 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, ",\"status\":"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3608 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = ({ char* _ad_58 = (char*)(build__json_str(status)); const char* _ad_r = string_concat(out, _ad_58); aether_heap_str_free(_ad_58); _ad_r; }); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3609 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, ",\"duration_ms\":"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3610 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, wm_s); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3611 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, ",\"cache\":"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3612 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = ({ char* _ad_59 = (char*)(build__json_str(cache)); const char* _ad_r = string_concat(out, _ad_59); aether_heap_str_free(_ad_59); _ad_r; }); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3613 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, ",\"rc\":"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3614 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, rc); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3620 "/home/paul/.local/share/aeb/lib/build/module.ae"
int has_report = 1;
if (map_has(rec, aether_string_data("test_has_report")) == 1) {
        {
#line 3622 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_ptr_string _tup54 = map_get(rec, "test_has_report");
            void* thr_s = _tup54._0;
if (string_equals(thr_s, "0") == 1) {
                {
#line 3623 "/home/paul/.local/share/aeb/lib/build/module.ae"
has_report = 0;
                }
            }
        }
    }
if (map_has(rec, aether_string_data("test_passed")) == 1) {
        {
if (has_report == 1) {
                {
#line 3627 "/home/paul/.local/share/aeb/lib/build/module.ae"
                    _tuple_ptr_string _tup55 = map_get(rec, "test_passed");
                    void* tp = _tup55._0;
#line 3628 "/home/paul/.local/share/aeb/lib/build/module.ae"
                    _tuple_ptr_string _tup56 = map_get(rec, "test_failed");
                    void* tf = _tup56._0;
#line 3629 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = tsk; tsk = "0"; if (_heap_tsk) aether_heap_str_free(_tmp_old); _heap_tsk = 0; aether_unwind_track_str_if(tsk, _heap_tsk); }
if (map_has(rec, aether_string_data("test_skipped")) == 1) {
                        {
#line 3630 "/home/paul/.local/share/aeb/lib/build/module.ae"
                            _tuple_ptr_string _tup57 = map_get(rec, "test_skipped");
                            { const char* _tmp_old = tsk; tsk = _tup57._0; if (_heap_tsk) aether_heap_str_free(_tmp_old); _heap_tsk = 0; aether_unwind_track_str_if(tsk, _heap_tsk); }
                        }
                    }
#line 3631 "/home/paul/.local/share/aeb/lib/build/module.ae"
                    _tuple_int_string _tup58 = string_to_int(tp);
                    int total_i = _tup58._0;
#line 3632 "/home/paul/.local/share/aeb/lib/build/module.ae"
                    _tuple_int_string _tup59 = string_to_int(tf);
                    int failed_i = _tup59._0;
#line 3633 "/home/paul/.local/share/aeb/lib/build/module.ae"
total_i = (total_i + failed_i);
#line 3636 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, ",\"tests\":{\"total\":"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3637 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = ({ char* _ad_60 = (char*)(string_from_int(total_i)); const char* _ad_r = string_concat(out, _ad_60); aether_heap_str_free(_ad_60); _ad_r; }); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3638 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, ",\"passed\":"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3639 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, tp); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3640 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, ",\"failed\":"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3641 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, tf); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3642 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, ",\"skipped\":"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3643 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, tsk); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3644 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, ",\"errored\":0}"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
                }
            } else {
                {
#line 3646 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, ",\"tests\":null"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
                }
            }
        }
    } else {
        {
#line 3649 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, ",\"tests\":null"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
        }
    }
#line 3651 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, "}"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3652 "/home/paul/.local/share/aeb/lib/build/module.ae"
    const char* _builder_ret = aether_uniform_heap_str((const char*)(out), _heap_out);
    /* deferred */ if (_heap_tsk) { aether_heap_str_free(tsk); tsk = NULL; _heap_tsk = 0; }
    /* deferred */ if (_heap_rc) { aether_heap_str_free(rc); rc = NULL; _heap_rc = 0; }
    /* deferred */ if (_heap_status) { aether_heap_str_free(status); status = NULL; _heap_status = 0; }
    return _builder_ret;
    /* deferred */ if (_heap_tsk) { aether_heap_str_free(tsk); tsk = NULL; _heap_tsk = 0; }
    /* deferred */ if (_heap_rc) { aether_heap_str_free(rc); rc = NULL; _heap_rc = 0; }
    /* deferred */ if (_heap_status) { aether_heap_str_free(status); status = NULL; _heap_status = 0; }
}

#line 3655 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build__telemetry_status(void* rec) {
    int _heap_rc = 0; (void)_heap_rc;
    const char* rc = NULL;
if (map_has(rec, aether_string_data("status")) == 1) {
        {
#line 3657 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_ptr_string _tup60 = map_get(rec, "status");
            void* st = _tup60._0;
#line 3658 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_ptr_string _tup61 = map_get(rec, "cache");
            void* cache0 = _tup61._0;
if (string_equals(st, "passed") == 1) {
                {
if (string_equals(cache0, "hit") == 1) {
                        {
#line 3660 "/home/paul/.local/share/aeb/lib/build/module.ae"
                            const char* _builder_ret = "cache-hit";
                            /* deferred */ if (_heap_rc) { aether_heap_str_free(rc); rc = NULL; _heap_rc = 0; }
                            return _builder_ret;
                        }
                    }
#line 3661 "/home/paul/.local/share/aeb/lib/build/module.ae"
                    const char* _builder_ret = "pass";
                    /* deferred */ if (_heap_rc) { aether_heap_str_free(rc); rc = NULL; _heap_rc = 0; }
                    return _builder_ret;
                }
            }
if (string_equals(st, "failed") == 1) {
                {
#line 3663 "/home/paul/.local/share/aeb/lib/build/module.ae"
                    const char* _builder_ret = "fail";
                    /* deferred */ if (_heap_rc) { aether_heap_str_free(rc); rc = NULL; _heap_rc = 0; }
                    return _builder_ret;
                }
            }
if (string_equals(st, "pass") == 1) {
                {
if (string_equals(cache0, "hit") == 1) {
                        {
#line 3665 "/home/paul/.local/share/aeb/lib/build/module.ae"
                            const char* _builder_ret = "cache-hit";
                            /* deferred */ if (_heap_rc) { aether_heap_str_free(rc); rc = NULL; _heap_rc = 0; }
                            return _builder_ret;
                        }
                    }
#line 3666 "/home/paul/.local/share/aeb/lib/build/module.ae"
                    const char* _builder_ret = "pass";
                    /* deferred */ if (_heap_rc) { aether_heap_str_free(rc); rc = NULL; _heap_rc = 0; }
                    return _builder_ret;
                }
            }
if (string_length(st) > 0) {
                {
#line 3668 "/home/paul/.local/share/aeb/lib/build/module.ae"
                    const char* _builder_ret = st;
                    /* deferred */ if (_heap_rc) { aether_heap_str_free(rc); rc = NULL; _heap_rc = 0; }
                    return _builder_ret;
                }
            }
        }
    }
#line 3670 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_ptr_string _tup62 = map_get(rec, "cache");
    void* cache = _tup62._0;
if (string_equals(cache, "hit") == 1) {
        {
#line 3671 "/home/paul/.local/share/aeb/lib/build/module.ae"
            const char* _builder_ret = "cache-hit";
            /* deferred */ if (_heap_rc) { aether_heap_str_free(rc); rc = NULL; _heap_rc = 0; }
            return _builder_ret;
        }
    }
#line 3672 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = rc; rc = "0"; if (_heap_rc) aether_heap_str_free(_tmp_old); _heap_rc = 0; aether_unwind_track_str_if(rc, _heap_rc); }
if (map_has(rec, aether_string_data("rc")) == 1) {
        {
#line 3673 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_ptr_string _tup63 = map_get(rec, "rc");
            { const char* _tmp_old = rc; rc = _tup63._0; if (_heap_rc) aether_heap_str_free(_tmp_old); _heap_rc = 0; aether_unwind_track_str_if(rc, _heap_rc); }
        }
    }
if (string_equals(rc, "0") == 0) {
        {
#line 3674 "/home/paul/.local/share/aeb/lib/build/module.ae"
            const char* _builder_ret = "fail";
            /* deferred */ if (_heap_rc) { aether_heap_str_free(rc); rc = NULL; _heap_rc = 0; }
            return _builder_ret;
        }
    }
if (map_has(rec, aether_string_data("test_failed")) == 1) {
        {
#line 3676 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_ptr_string _tup64 = map_get(rec, "test_failed");
            void* tf = _tup64._0;
#line 3677 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_int_string _tup65 = string_to_int(tf);
            int tfi = _tup65._0;
if (tfi > 0) {
                {
#line 3678 "/home/paul/.local/share/aeb/lib/build/module.ae"
                    const char* _builder_ret = "fail";
                    /* deferred */ if (_heap_rc) { aether_heap_str_free(rc); rc = NULL; _heap_rc = 0; }
                    return _builder_ret;
                }
            }
        }
    }
#line 3680 "/home/paul/.local/share/aeb/lib/build/module.ae"
    const char* _builder_ret = "pass";
    /* deferred */ if (_heap_rc) { aether_heap_str_free(rc); rc = NULL; _heap_rc = 0; }
    return _builder_ret;
    /* deferred */ if (_heap_rc) { aether_heap_str_free(rc); rc = NULL; _heap_rc = 0; }
}

#line 3683 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build_render_telemetry_json(void* records, int total_ms) {
    int _heap_aeb_version = 0; (void)_heap_aeb_version;
    const char* aeb_version = NULL;
    int _heap_since_ref = 0; (void)_heap_since_ref;
    const char* since_ref = NULL;
    int _heap_out = 0; (void)_heap_out;
    const char* out = NULL;
    int _heap_st = 0; (void)_heap_st;
    const char* st = NULL;
#line 3684 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = aeb_version; aeb_version = os_getenv(aether_string_data("AEB_VERSION")); if (_heap_aeb_version) aether_heap_str_free(_tmp_old); _heap_aeb_version = 1; aether_unwind_track_str_if(aeb_version, _heap_aeb_version); }
#line 3685 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = since_ref; since_ref = os_getenv(aether_string_data("AEB_SINCE_REF")); if (_heap_since_ref) aether_heap_str_free(_tmp_old); _heap_since_ref = 1; aether_unwind_track_str_if(since_ref, _heap_since_ref); }
#line 3686 "/home/paul/.local/share/aeb/lib/build/module.ae"
int built = 0;
#line 3687 "/home/paul/.local/share/aeb/lib/build/module.ae"
int failed_count = 0;
#line 3688 "/home/paul/.local/share/aeb/lib/build/module.ae"
int skipped_count = 0;
#line 3689 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = "{"; if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 0; }
#line 3690 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, "\"version\":1"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3691 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, ",\"aeb_version\":"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3692 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = ({ char* _ad_61 = (char*)(build__json_str(aeb_version)); const char* _ad_r = string_concat(out, _ad_61); aether_heap_str_free(_ad_61); _ad_r; }); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3693 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, ",\"since_ref\":"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
if (string_length(since_ref) > 0) {
        {
#line 3695 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = ({ char* _ad_62 = (char*)(build__json_str(since_ref)); const char* _ad_r = string_concat(out, _ad_62); aether_heap_str_free(_ad_62); _ad_r; }); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
        }
    } else {
        {
#line 3697 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, "null"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
        }
    }
#line 3699 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, ",\"targets\":["); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3700 "/home/paul/.local/share/aeb/lib/build/module.ae"
int n = list_size(records);
#line 3701 "/home/paul/.local/share/aeb/lib/build/module.ae"
int i = 0;
while (i < n) {
        {
#line 3703 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_ptr_string _tup66 = list_get(records, i);
            void* rec = _tup66._0;
if (i > 0) {
                {
#line 3704 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, ","); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
                }
            }
#line 3705 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = st; st = build__telemetry_status(rec); if (_heap_st) aether_heap_str_free(_tmp_old); _heap_st = 0; aether_unwind_track_str_if(st, _heap_st); }
if (string_equals(st, "skipped") == 1) {
                {
#line 3707 "/home/paul/.local/share/aeb/lib/build/module.ae"
skipped_count = (skipped_count + 1);
                }
            } else {
                {
#line 3709 "/home/paul/.local/share/aeb/lib/build/module.ae"
built = (built + 1);
                }
            }
if (string_equals(st, "fail") == 1) {
                {
#line 3711 "/home/paul/.local/share/aeb/lib/build/module.ae"
failed_count = (failed_count + 1);
                }
            }
#line 3712 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = ({ char* _ad_63 = (char*)(build__record_json(rec)); const char* _ad_r = string_concat(out, _ad_63); aether_heap_str_free(_ad_63); _ad_r; }); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3713 "/home/paul/.local/share/aeb/lib/build/module.ae"
i = (i + 1);
        }
    }
#line 3715 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, "],\"summary\":{\"built\":"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3716 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = ({ char* _ad_64 = (char*)(string_from_int(built)); const char* _ad_r = string_concat(out, _ad_64); aether_heap_str_free(_ad_64); _ad_r; }); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3717 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, ",\"failed\":"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3718 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = ({ char* _ad_65 = (char*)(string_from_int(failed_count)); const char* _ad_r = string_concat(out, _ad_65); aether_heap_str_free(_ad_65); _ad_r; }); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3719 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, ",\"skipped\":"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3720 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = ({ char* _ad_66 = (char*)(string_from_int(skipped_count)); const char* _ad_r = string_concat(out, _ad_66); aether_heap_str_free(_ad_66); _ad_r; }); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3721 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, ",\"duration_ms\":"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3722 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = ({ char* _ad_67 = (char*)(string_from_int(total_ms)); const char* _ad_r = string_concat(out, _ad_67); aether_heap_str_free(_ad_67); _ad_r; }); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3723 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, "}}"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3724 "/home/paul/.local/share/aeb/lib/build/module.ae"
    const char* _builder_ret = aether_uniform_heap_str((const char*)(out), _heap_out);
    /* deferred */ if (_heap_st) { aether_heap_str_free(st); st = NULL; _heap_st = 0; }
    /* deferred */ if (_heap_since_ref) { aether_heap_str_free(since_ref); since_ref = NULL; _heap_since_ref = 0; }
    /* deferred */ if (_heap_aeb_version) { aether_heap_str_free(aeb_version); aeb_version = NULL; _heap_aeb_version = 0; }
    return _builder_ret;
    /* deferred */ if (_heap_st) { aether_heap_str_free(st); st = NULL; _heap_st = 0; }
    /* deferred */ if (_heap_since_ref) { aether_heap_str_free(since_ref); since_ref = NULL; _heap_since_ref = 0; }
    /* deferred */ if (_heap_aeb_version) { aether_heap_str_free(aeb_version); aeb_version = NULL; _heap_aeb_version = 0; }
}

#line 3727 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build_render_tests_json(void* records) {
    int _heap_out = 0; (void)_heap_out;
    const char* out = NULL;
    int _heap_passed = 0; (void)_heap_passed;
    const char* passed = NULL;
    int _heap_failed = 0; (void)_heap_failed;
    const char* failed = NULL;
    int _heap_has_results = 0; (void)_heap_has_results;
    const char* has_results = NULL;
    int _heap_verdict = 0; (void)_heap_verdict;
    const char* verdict = NULL;
    int _heap_skipped_s = 0; (void)_heap_skipped_s;
    const char* skipped_s = NULL;
#line 3728 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = "{\"tests\":["; if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 0; }
#line 3729 "/home/paul/.local/share/aeb/lib/build/module.ae"
int wrote = 0;
#line 3730 "/home/paul/.local/share/aeb/lib/build/module.ae"
int n = list_size(records);
#line 3731 "/home/paul/.local/share/aeb/lib/build/module.ae"
int i = 0;
while (i < n) {
        {
#line 3733 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_ptr_string _tup67 = list_get(records, i);
            void* rec = _tup67._0;
#line 3734 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_ptr_string _tup68 = map_get(rec, "type");
            void* type_word = _tup68._0;
if (map_has(rec, aether_string_data("test_passed")) == 1) {
                {
#line 3739 "/home/paul/.local/share/aeb/lib/build/module.ae"
                    _tuple_ptr_string _tup69 = map_get(rec, "label");
                    void* label = _tup69._0;
#line 3740 "/home/paul/.local/share/aeb/lib/build/module.ae"
                    _tuple_ptr_string _tup70 = map_get(rec, "wall_ms");
                    void* wm_s = _tup70._0;
#line 3741 "/home/paul/.local/share/aeb/lib/build/module.ae"
                    _tuple_ptr_string _tup71 = map_get(rec, "cache");
                    void* cache = _tup71._0;
#line 3742 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = passed; passed = "0"; if (_heap_passed) aether_heap_str_free(_tmp_old); _heap_passed = 0; aether_unwind_track_str_if(passed, _heap_passed); }
#line 3743 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = failed; failed = "0"; if (_heap_failed) aether_heap_str_free(_tmp_old); _heap_failed = 0; aether_unwind_track_str_if(failed, _heap_failed); }
#line 3744 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = has_results; has_results = "false"; if (_heap_has_results) aether_heap_str_free(_tmp_old); _heap_has_results = 0; aether_unwind_track_str_if(has_results, _heap_has_results); }
#line 3745 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = verdict; verdict = "UNKNOWN"; if (_heap_verdict) aether_heap_str_free(_tmp_old); _heap_verdict = 0; aether_unwind_track_str_if(verdict, _heap_verdict); }
if (map_has(rec, aether_string_data("test_passed")) == 1) {
                        {
#line 3747 "/home/paul/.local/share/aeb/lib/build/module.ae"
                            _tuple_ptr_string _tup72 = map_get(rec, "test_passed");
                            { const char* _tmp_old = passed; passed = _tup72._0; if (_heap_passed) aether_heap_str_free(_tmp_old); _heap_passed = 0; aether_unwind_track_str_if(passed, _heap_passed); }
#line 3748 "/home/paul/.local/share/aeb/lib/build/module.ae"
                            _tuple_ptr_string _tup73 = map_get(rec, "test_failed");
                            { const char* _tmp_old = failed; failed = _tup73._0; if (_heap_failed) aether_heap_str_free(_tmp_old); _heap_failed = 0; aether_unwind_track_str_if(failed, _heap_failed); }
#line 3749 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = has_results; has_results = "true"; if (_heap_has_results) aether_heap_str_free(_tmp_old); _heap_has_results = 0; aether_unwind_track_str_if(has_results, _heap_has_results); }
#line 3750 "/home/paul/.local/share/aeb/lib/build/module.ae"
                            _tuple_int_string _tup74 = string_to_int(failed);
                            int failed_i = _tup74._0;
#line 3751 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = verdict; verdict = "PASS"; if (_heap_verdict) aether_heap_str_free(_tmp_old); _heap_verdict = 0; aether_unwind_track_str_if(verdict, _heap_verdict); }
if (failed_i > 0) {
                                {
#line 3752 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = verdict; verdict = "FAIL"; if (_heap_verdict) aether_heap_str_free(_tmp_old); _heap_verdict = 0; aether_unwind_track_str_if(verdict, _heap_verdict); }
                                }
                            }
                        }
                    }
if (wrote > 0) {
                        {
#line 3754 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, ","); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
                        }
                    }
#line 3755 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, "{"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3756 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, "\"label\":"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3757 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = ({ char* _ad_68 = (char*)(build__json_str(label)); const char* _ad_r = string_concat(out, _ad_68); aether_heap_str_free(_ad_68); _ad_r; }); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3758 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, ",\"wall_ms\":"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3759 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, wm_s); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3760 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, ",\"cache\":"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3761 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = ({ char* _ad_69 = (char*)(build__json_str(cache)); const char* _ad_r = string_concat(out, _ad_69); aether_heap_str_free(_ad_69); _ad_r; }); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3762 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, ",\"has_results\":"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3763 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, has_results); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3764 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, ",\"passed\":"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3765 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, passed); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3766 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, ",\"failed\":"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3767 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, failed); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3768 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = skipped_s; skipped_s = "0"; if (_heap_skipped_s) aether_heap_str_free(_tmp_old); _heap_skipped_s = 0; aether_unwind_track_str_if(skipped_s, _heap_skipped_s); }
if (map_has(rec, aether_string_data("test_skipped")) == 1) {
                        {
#line 3769 "/home/paul/.local/share/aeb/lib/build/module.ae"
                            _tuple_ptr_string _tup75 = map_get(rec, "test_skipped");
                            { const char* _tmp_old = skipped_s; skipped_s = _tup75._0; if (_heap_skipped_s) aether_heap_str_free(_tmp_old); _heap_skipped_s = 0; aether_unwind_track_str_if(skipped_s, _heap_skipped_s); }
                        }
                    }
#line 3770 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, ",\"skipped\":"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3771 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, skipped_s); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3772 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, ",\"verdict\":"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3773 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = ({ char* _ad_70 = (char*)(build__json_str(verdict)); const char* _ad_r = string_concat(out, _ad_70); aether_heap_str_free(_ad_70); _ad_r; }); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
if (map_has(rec, aether_string_data("test_failed_names")) == 1) {
                        {
#line 3775 "/home/paul/.local/share/aeb/lib/build/module.ae"
                            _tuple_ptr_string _tup76 = map_get(rec, "test_failed_names");
                            void* tfn = _tup76._0;
#line 3776 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, ",\"failed_names\":"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3777 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = ({ char* _ad_71 = (char*)(build__json_str(tfn)); const char* _ad_r = string_concat(out, _ad_71); aether_heap_str_free(_ad_71); _ad_r; }); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
                        }
                    }
#line 3779 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, "}"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3780 "/home/paul/.local/share/aeb/lib/build/module.ae"
wrote = (wrote + 1);
                }
            }
#line 3782 "/home/paul/.local/share/aeb/lib/build/module.ae"
i = (i + 1);
        }
    }
#line 3784 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, "]}"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3785 "/home/paul/.local/share/aeb/lib/build/module.ae"
    const char* _builder_ret = aether_uniform_heap_str((const char*)(out), _heap_out);
    /* deferred */ if (_heap_skipped_s) { aether_heap_str_free(skipped_s); skipped_s = NULL; _heap_skipped_s = 0; }
    /* deferred */ if (_heap_verdict) { aether_heap_str_free(verdict); verdict = NULL; _heap_verdict = 0; }
    /* deferred */ if (_heap_has_results) { aether_heap_str_free(has_results); has_results = NULL; _heap_has_results = 0; }
    /* deferred */ if (_heap_failed) { aether_heap_str_free(failed); failed = NULL; _heap_failed = 0; }
    /* deferred */ if (_heap_passed) { aether_heap_str_free(passed); passed = NULL; _heap_passed = 0; }
    return _builder_ret;
    /* deferred */ if (_heap_skipped_s) { aether_heap_str_free(skipped_s); skipped_s = NULL; _heap_skipped_s = 0; }
    /* deferred */ if (_heap_verdict) { aether_heap_str_free(verdict); verdict = NULL; _heap_verdict = 0; }
    /* deferred */ if (_heap_has_results) { aether_heap_str_free(has_results); has_results = NULL; _heap_has_results = 0; }
    /* deferred */ if (_heap_failed) { aether_heap_str_free(failed); failed = NULL; _heap_failed = 0; }
    /* deferred */ if (_heap_passed) { aether_heap_str_free(passed); passed = NULL; _heap_passed = 0; }
}

#line 3788 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build_render_artifacts_json(const char* root, void* records) {
    int _heap_out = 0; (void)_heap_out;
    const char* out = NULL;
    int _heap_td = 0; (void)_heap_td;
    const char* td = NULL;
    int _heap_pat = 0; (void)_heap_pat;
    const char* pat = NULL;
    int _heap__gerr = 0; (void)_heap__gerr;
    const char* _gerr = NULL;
    int _heap_f = 0; (void)_heap_f;
    const char* f = NULL;
    int _heap_name = 0; (void)_heap_name;
    const char* name = NULL;
#line 3789 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = "{\"artifacts\":["; if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 0; }
#line 3790 "/home/paul/.local/share/aeb/lib/build/module.ae"
int wrote = 0;
#line 3791 "/home/paul/.local/share/aeb/lib/build/module.ae"
int n = list_size(records);
#line 3792 "/home/paul/.local/share/aeb/lib/build/module.ae"
int i = 0;
    int count;
    int j;
    int is_internal;
while (i < n) {
        {
#line 3794 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_ptr_string _tup77 = list_get(records, i);
            void* rec = _tup77._0;
#line 3795 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_ptr_string _tup78 = map_get(rec, "label");
            void* label = _tup78._0;
#line 3796 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_ptr_string _tup79 = map_get(rec, "type");
            void* type_word = _tup79._0;
#line 3797 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = td; td = build__label_to_target_dir(root, label); if (_heap_td) aether_heap_str_free(_tmp_old); _heap_td = 1; aether_unwind_track_str_if(td, _heap_td); }
#line 3798 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = pat; pat = path_join(aether_string_data(td), aether_string_data("*")); if (_heap_pat) aether_heap_str_free(_tmp_old); _heap_pat = 1; aether_unwind_track_str_if(pat, _heap_pat); }
#line 3799 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_ptr_string _tup80 = fs_glob(pat);
            void* files = _tup80._0;
            { const char* _tmp_old = _gerr; _gerr = _tup80._1; if (_heap__gerr) aether_heap_str_free(_tmp_old); _heap__gerr = 0; aether_unwind_track_str_if(_gerr, _heap__gerr); }
#line 3800 "/home/paul/.local/share/aeb/lib/build/module.ae"
count = dir_list_count(files);
#line 3801 "/home/paul/.local/share/aeb/lib/build/module.ae"
j = 0;
while (j < count) {
                {
#line 3803 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = f; f = dir_list_get(files, j); if (_heap_f) aether_heap_str_free(_tmp_old); _heap_f = 0; aether_unwind_track_str_if(f, _heap_f); }
#line 3804 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = name; name = path_basename(aether_string_data(f)); if (_heap_name) aether_heap_str_free(_tmp_old); _heap_name = 1; aether_unwind_track_str_if(name, _heap_name); }
if (string_starts_with(name, ".") == 0) {
                        {
#line 3806 "/home/paul/.local/share/aeb/lib/build/module.ae"
is_internal = 0;
if (string_equals(name, "_aeb") == 1) {
                                {
#line 3807 "/home/paul/.local/share/aeb/lib/build/module.ae"
is_internal = 1;
                                }
                            }
if (string_equals(name, "_ae_build_all") == 1) {
                                {
#line 3808 "/home/paul/.local/share/aeb/lib/build/module.ae"
is_internal = 1;
                                }
                            }
if (is_internal == 0) {
                                {
if (wrote > 0) {
                                        {
#line 3810 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, ","); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
                                        }
                                    }
#line 3811 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, "{"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3812 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, "\"label\":"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3813 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = ({ char* _ad_72 = (char*)(build__json_str(label)); const char* _ad_r = string_concat(out, _ad_72); aether_heap_str_free(_ad_72); _ad_r; }); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3814 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, ",\"type\":"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3815 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = ({ char* _ad_73 = (char*)(build__json_str(type_word)); const char* _ad_r = string_concat(out, _ad_73); aether_heap_str_free(_ad_73); _ad_r; }); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3816 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, ",\"target_dir\":"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3817 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = ({ char* _ad_74 = (char*)(build__json_str(td)); const char* _ad_r = string_concat(out, _ad_74); aether_heap_str_free(_ad_74); _ad_r; }); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3818 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, ",\"name\":"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3819 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = ({ char* _ad_75 = (char*)(build__json_str(name)); const char* _ad_r = string_concat(out, _ad_75); aether_heap_str_free(_ad_75); _ad_r; }); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3820 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, ",\"path\":"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3821 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = ({ char* _ad_76 = (char*)(build__json_str(f)); const char* _ad_r = string_concat(out, _ad_76); aether_heap_str_free(_ad_76); _ad_r; }); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3822 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, "}"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3823 "/home/paul/.local/share/aeb/lib/build/module.ae"
wrote = (wrote + 1);
                                }
                            }
                        }
                    }
#line 3826 "/home/paul/.local/share/aeb/lib/build/module.ae"
j = (j + 1);
                }
            }
#line 3828 "/home/paul/.local/share/aeb/lib/build/module.ae"
dir_list_free(files);
#line 3829 "/home/paul/.local/share/aeb/lib/build/module.ae"
i = (i + 1);
        }
    }
#line 3831 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, "]}"); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 3832 "/home/paul/.local/share/aeb/lib/build/module.ae"
    const char* _builder_ret = aether_uniform_heap_str((const char*)(out), _heap_out);
    /* deferred */ if (_heap_name) { aether_heap_str_free(name); name = NULL; _heap_name = 0; }
    /* deferred */ if (_heap_f) { aether_heap_str_free(f); f = NULL; _heap_f = 0; }
    /* deferred */ if (_heap__gerr) { aether_heap_str_free(_gerr); _gerr = NULL; _heap__gerr = 0; }
    /* deferred */ if (_heap_pat) { aether_heap_str_free(pat); pat = NULL; _heap_pat = 0; }
    /* deferred */ if (_heap_td) { aether_heap_str_free(td); td = NULL; _heap_td = 0; }
    return _builder_ret;
    /* deferred */ if (_heap_name) { aether_heap_str_free(name); name = NULL; _heap_name = 0; }
    /* deferred */ if (_heap_f) { aether_heap_str_free(f); f = NULL; _heap_f = 0; }
    /* deferred */ if (_heap__gerr) { aether_heap_str_free(_gerr); _gerr = NULL; _heap__gerr = 0; }
    /* deferred */ if (_heap_pat) { aether_heap_str_free(pat); pat = NULL; _heap_pat = 0; }
    /* deferred */ if (_heap_td) { aether_heap_str_free(td); td = NULL; _heap_td = 0; }
}

#line 3864 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build__collect_file_list(const char* pattern) {
    int _heap__gerr = 0; (void)_heap__gerr;
    const char* _gerr = NULL;
    int _heap_result = 0; (void)_heap_result;
    const char* result = NULL;
    int _heap_f = 0; (void)_heap_f;
    const char* f = NULL;
    int _heap_sp = 0; (void)_heap_sp;
    const char* sp = NULL;
#line 3865 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_ptr_string _tup81 = fs_glob(pattern);
    void* files = _tup81._0;
    { const char* _tmp_old = _gerr; _gerr = _tup81._1; if (_heap__gerr) aether_heap_str_free(_tmp_old); _heap__gerr = 0; aether_unwind_track_str_if(_gerr, _heap__gerr); }
#line 3866 "/home/paul/.local/share/aeb/lib/build/module.ae"
int count = dir_list_count(files);
#line 3867 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = result; result = ""; if (_heap_result) aether_heap_str_free(_tmp_old); _heap_result = 0; }
#line 3868 "/home/paul/.local/share/aeb/lib/build/module.ae"
int i = 0;
while (i < count) {
        {
#line 3870 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = f; f = dir_list_get(files, i); if (_heap_f) aether_heap_str_free(_tmp_old); _heap_f = 0; aether_unwind_track_str_if(f, _heap_f); }
if (i == 0) {
                {
#line 3872 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = result; result = string_concat(f, ""); if (_heap_result) aether_heap_str_free(_tmp_old); _heap_result = 1; }
                }
            } else {
                {
#line 3874 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = sp; sp = string_concat(result, " "); if (_heap_sp) aether_heap_str_free(_tmp_old); _heap_sp = 1; aether_unwind_track_str_if(sp, _heap_sp); }
#line 3875 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = result; result = string_concat(sp, f); if (_heap_result) aether_heap_str_free(_tmp_old); _heap_result = 1; }
                }
            }
#line 3877 "/home/paul/.local/share/aeb/lib/build/module.ae"
i = (i + 1);
        }
    }
#line 3879 "/home/paul/.local/share/aeb/lib/build/module.ae"
dir_list_free(files);
#line 3880 "/home/paul/.local/share/aeb/lib/build/module.ae"
    const char* _builder_ret = aether_uniform_heap_str((const char*)(result), _heap_result);
    /* deferred */ if (_heap_sp) { aether_heap_str_free(sp); sp = NULL; _heap_sp = 0; }
    /* deferred */ if (_heap_f) { aether_heap_str_free(f); f = NULL; _heap_f = 0; }
    /* deferred */ if (_heap__gerr) { aether_heap_str_free(_gerr); _gerr = NULL; _heap__gerr = 0; }
    return _builder_ret;
    /* deferred */ if (_heap_sp) { aether_heap_str_free(sp); sp = NULL; _heap_sp = 0; }
    /* deferred */ if (_heap_f) { aether_heap_str_free(f); f = NULL; _heap_f = 0; }
    /* deferred */ if (_heap__gerr) { aether_heap_str_free(_gerr); _gerr = NULL; _heap__gerr = 0; }
}

#line 384 "/home/paul/.local/bin/../share/aether/std/string/module.ae"
static AETHER_MAYBE_UNUSED _tuple_int_string string_to_int(const char* s) {
#line 385 "/home/paul/.local/bin/../share/aether/std/string/module.ae"
int ok = string_try_int(s);
if (ok == 0) {
        {
#line 387 "/home/paul/.local/bin/../share/aether/std/string/module.ae"
            return (_tuple_int_string){0, "invalid integer"};
        }
    }
#line 389 "/home/paul/.local/bin/../share/aether/std/string/module.ae"
    return (_tuple_int_string){string_get_int(s), ""};
}

#line 473 "/home/paul/.local/bin/../share/aether/std/string/module.ae"
static AETHER_MAYBE_UNUSED const char* string_copy(const char* s) {
#line 474 "/home/paul/.local/bin/../share/aether/std/string/module.ae"
    return aether_uniform_heap_str((const char*)(string_concat(s, "")), 1);
}

#line 90 "/home/paul/.local/bin/../share/aether/std/io/module.ae"
static AETHER_MAYBE_UNUSED _tuple_string_string io_read_file(const char* path) {
    int _heap_content = 0; (void)_heap_content;
    const char* content = NULL;
    int _heap_content_copy = 0; (void)_heap_content_copy;
    const char* content_copy = NULL;
#line 91 "/home/paul/.local/bin/../share/aether/std/io/module.ae"
{ const char* _tmp_old = content; content = io_read_file_raw(aether_string_data(path)); if (_heap_content) aether_heap_str_free(_tmp_old); _heap_content = 1; aether_unwind_track_str_if(content, _heap_content); }
if (strcmp(_aether_safe_str(content), _aether_safe_str(NULL)) == 0) {
        {
#line 93 "/home/paul/.local/bin/../share/aether/std/io/module.ae"
            _tuple_string_string _builder_ret = (_tuple_string_string){aether_uniform_heap_str((const char*)(""), 0), "cannot read file"};
            /* deferred */ if (_heap_content) { aether_heap_str_free(content); content = NULL; _heap_content = 0; }
            return _builder_ret;
        }
    }
#line 95 "/home/paul/.local/bin/../share/aether/std/io/module.ae"
{ const char* _tmp_old = content_copy; content_copy = string_concat(content, ""); if (_heap_content_copy) aether_heap_str_free(_tmp_old); _heap_content_copy = 1; }
#line 96 "/home/paul/.local/bin/../share/aether/std/io/module.ae"
    _tuple_string_string _builder_ret = (_tuple_string_string){aether_uniform_heap_str((const char*)(content_copy), _heap_content_copy), ""};
    /* deferred */ if (_heap_content) { aether_heap_str_free(content); content = NULL; _heap_content = 0; }
    return _builder_ret;
    /* deferred */ if (_heap_content) { aether_heap_str_free(content); content = NULL; _heap_content = 0; }
}

#line 101 "/home/paul/.local/bin/../share/aether/std/io/module.ae"
static AETHER_MAYBE_UNUSED const char* io_write_file(const char* path, const char* content) {
#line 102 "/home/paul/.local/bin/../share/aether/std/io/module.ae"
int ok = io_write_file_raw(aether_string_data(path), aether_string_data(content));
if (ok == 0) {
        {
#line 104 "/home/paul/.local/bin/../share/aether/std/io/module.ae"
            return "cannot write file";
        }
    }
#line 106 "/home/paul/.local/bin/../share/aether/std/io/module.ae"
    return "";
}

#line 111 "/home/paul/.local/bin/../share/aether/std/io/module.ae"
static AETHER_MAYBE_UNUSED const char* io_append_file(const char* path, const char* content) {
#line 112 "/home/paul/.local/bin/../share/aether/std/io/module.ae"
int ok = io_append_file_raw(aether_string_data(path), aether_string_data(content));
if (ok == 0) {
        {
#line 114 "/home/paul/.local/bin/../share/aether/std/io/module.ae"
            return "cannot append to file";
        }
    }
#line 116 "/home/paul/.local/bin/../share/aether/std/io/module.ae"
    return "";
}

#line 120 "/home/paul/.local/bin/../share/aether/std/io/module.ae"
static AETHER_MAYBE_UNUSED const char* io_delete_file(const char* path) {
#line 121 "/home/paul/.local/bin/../share/aether/std/io/module.ae"
int ok = io_delete_file_raw(aether_string_data(path));
if (ok == 0) {
        {
#line 123 "/home/paul/.local/bin/../share/aether/std/io/module.ae"
            return "cannot delete file";
        }
    }
#line 125 "/home/paul/.local/bin/../share/aether/std/io/module.ae"
    return "";
}

#line 249 "/home/paul/.local/bin/../share/aether/std/io/module.ae"
static AETHER_MAYBE_UNUSED _tuple_string_int_string io_fd_read_n(int fd, int n) {
#line 250 "/home/paul/.local/bin/../share/aether/std/io/module.ae"
    return io_fd_read_n_tuple(fd, n);
}

#line 293 "/home/paul/.local/bin/../share/aether/std/io/module.ae"
static AETHER_MAYBE_UNUSED _tuple_string_string io_fd_read_line(int fd) {
#line 294 "/home/paul/.local/bin/../share/aether/std/io/module.ae"
    return io_fd_read_line_tuple(fd);
}

#line 243 "/home/paul/.local/bin/../share/aether/std/os/module.ae"
static AETHER_MAYBE_UNUSED int os_args_count(void) {
#line 244 "/home/paul/.local/bin/../share/aether/std/os/module.ae"
    return aether_args_count();
}

#line 272 "/home/paul/.local/bin/../share/aether/std/os/module.ae"
static AETHER_MAYBE_UNUSED _tuple_string_string os_exec(const char* cmd) {
    int _heap_output = 0; (void)_heap_output;
    const char* output = NULL;
    int _heap_output_copy = 0; (void)_heap_output_copy;
    const char* output_copy = NULL;
#line 273 "/home/paul/.local/bin/../share/aether/std/os/module.ae"
{ const char* _tmp_old = output; output = os_exec_raw(aether_string_data(cmd)); if (_heap_output) aether_heap_str_free(_tmp_old); _heap_output = 1; aether_unwind_track_str_if(output, _heap_output); }
if (strcmp(_aether_safe_str(output), _aether_safe_str(NULL)) == 0) {
        {
#line 275 "/home/paul/.local/bin/../share/aether/std/os/module.ae"
            _tuple_string_string _builder_ret = (_tuple_string_string){aether_uniform_heap_str((const char*)(""), 0), "command failed"};
            /* deferred */ if (_heap_output) { aether_heap_str_free(output); output = NULL; _heap_output = 0; }
            return _builder_ret;
        }
    }
#line 277 "/home/paul/.local/bin/../share/aether/std/os/module.ae"
{ const char* _tmp_old = output_copy; output_copy = string_concat(output, ""); if (_heap_output_copy) aether_heap_str_free(_tmp_old); _heap_output_copy = 1; }
#line 278 "/home/paul/.local/bin/../share/aether/std/os/module.ae"
    _tuple_string_string _builder_ret = (_tuple_string_string){aether_uniform_heap_str((const char*)(output_copy), _heap_output_copy), ""};
    /* deferred */ if (_heap_output) { aether_heap_str_free(output); output = NULL; _heap_output = 0; }
    return _builder_ret;
    /* deferred */ if (_heap_output) { aether_heap_str_free(output); output = NULL; _heap_output = 0; }
}

#line 636 "/home/paul/.local/bin/../share/aether/std/os/module.ae"
static AETHER_MAYBE_UNUSED const char* os_platform(void) {
    int _heap_s = 0; (void)_heap_s;
    const char* s = NULL;
#line 637 "/home/paul/.local/bin/../share/aether/std/os/module.ae"
{ const char* _tmp_old = s; s = os_platform_raw(); if (_heap_s) aether_heap_str_free(_tmp_old); _heap_s = 1; aether_unwind_track_str_if(s, _heap_s); }
if (strcmp(_aether_safe_str(s), _aether_safe_str(NULL)) == 0) {
        {
#line 639 "/home/paul/.local/bin/../share/aether/std/os/module.ae"
            const char* _builder_ret = aether_uniform_heap_str((const char*)("unknown"), 0);
            /* deferred */ if (_heap_s) { aether_heap_str_free(s); s = NULL; _heap_s = 0; }
            return _builder_ret;
        }
    }
#line 641 "/home/paul/.local/bin/../share/aether/std/os/module.ae"
    const char* _builder_ret = aether_uniform_heap_str((const char*)(string_concat(s, "")), 1);
    /* deferred */ if (_heap_s) { aether_heap_str_free(s); s = NULL; _heap_s = 0; }
    return _builder_ret;
    /* deferred */ if (_heap_s) { aether_heap_str_free(s); s = NULL; _heap_s = 0; }
}

#line 655 "/home/paul/.local/bin/../share/aether/std/os/module.ae"
static AETHER_MAYBE_UNUSED const char* os_temp_dir(void) {
    int _heap_s = 0; (void)_heap_s;
    const char* s = NULL;
#line 656 "/home/paul/.local/bin/../share/aether/std/os/module.ae"
{ const char* _tmp_old = s; s = os_temp_dir_raw(); if (_heap_s) aether_heap_str_free(_tmp_old); _heap_s = 0; aether_unwind_track_str_if(s, _heap_s); }
if (strcmp(_aether_safe_str(s), _aether_safe_str(NULL)) == 0) {
        {
#line 658 "/home/paul/.local/bin/../share/aether/std/os/module.ae"
            const char* _builder_ret = aether_uniform_heap_str((const char*)("/tmp"), 0);
            /* deferred */ if (_heap_s) { aether_heap_str_free(s); s = NULL; _heap_s = 0; }
            return _builder_ret;
        }
    }
#line 660 "/home/paul/.local/bin/../share/aether/std/os/module.ae"
    const char* _builder_ret = aether_uniform_heap_str((const char*)(string_concat(s, "")), 1);
    /* deferred */ if (_heap_s) { aether_heap_str_free(s); s = NULL; _heap_s = 0; }
    return _builder_ret;
    /* deferred */ if (_heap_s) { aether_heap_str_free(s); s = NULL; _heap_s = 0; }
}

#line 674 "/home/paul/.local/bin/../share/aether/std/os/module.ae"
static AETHER_MAYBE_UNUSED int os_getpid(void) {
#line 675 "/home/paul/.local/bin/../share/aether/std/os/module.ae"
    return os_getpid_raw();
}

#line 734 "/home/paul/.local/bin/../share/aether/std/os/module.ae"
static AETHER_MAYBE_UNUSED int64_t os_now_monotonic_ns(void) {
#line 735 "/home/paul/.local/bin/../share/aether/std/os/module.ae"
    return os_now_monotonic_ns_raw();
}

#line 108 "/home/paul/.local/bin/../share/aether/std/file/module.ae"
static AETHER_MAYBE_UNUSED int file_fd(void* handle) {
#line 109 "/home/paul/.local/bin/../share/aether/std/file/module.ae"
    return file_fd_raw(handle);
}

#line 388 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
static AETHER_MAYBE_UNUSED _tuple_string_string fs_read(const char* path) {
    int _heap_content = 0; (void)_heap_content;
    const char* content = NULL;
    int _heap_content_copy = 0; (void)_heap_content_copy;
    const char* content_copy = NULL;
#line 389 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
void* handle = file_open_raw(aether_string_data(path), aether_string_data("r"));
if ((intptr_t)handle == 0) {
        {
#line 394 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
            _tuple_string_string _builder_ret = (_tuple_string_string){aether_uniform_heap_str((const char*)(""), 0), fs_error_message(aether_string_data(path), aether_string_data("cannot open file"))};
            /* deferred */ if (_heap_content) { aether_heap_str_free(content); content = NULL; _heap_content = 0; }
            return _builder_ret;
        }
    }
#line 396 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
{ const char* _tmp_old = content; content = file_read_all_raw(handle); if (_heap_content) aether_heap_str_free(_tmp_old); _heap_content = 1; aether_unwind_track_str_if(content, _heap_content); }
if (content == 0) {
        {
#line 398 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
file_close(handle);
#line 399 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
            _tuple_string_string _builder_ret = (_tuple_string_string){aether_uniform_heap_str((const char*)(""), 0), fs_error_message(aether_string_data(path), aether_string_data("cannot read file"))};
            /* deferred */ if (_heap_content) { aether_heap_str_free(content); content = NULL; _heap_content = 0; }
            return _builder_ret;
        }
    }
#line 401 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
{ const char* _tmp_old = content_copy; content_copy = string_concat(content, ""); if (_heap_content_copy) aether_heap_str_free(_tmp_old); _heap_content_copy = 1; }
#line 402 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
file_close(handle);
#line 403 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
    _tuple_string_string _builder_ret = (_tuple_string_string){aether_uniform_heap_str((const char*)(content_copy), _heap_content_copy), ""};
    /* deferred */ if (_heap_content) { aether_heap_str_free(content); content = NULL; _heap_content = 0; }
    return _builder_ret;
    /* deferred */ if (_heap_content) { aether_heap_str_free(content); content = NULL; _heap_content = 0; }
}

#line 423 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
static AETHER_MAYBE_UNUSED const char* fs_delete(const char* path) {
#line 424 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
int ok = file_delete_raw(aether_string_data(path));
if (ok == 0) {
        {
#line 426 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
            return "cannot delete file";
        }
    }
#line 428 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
    return "";
}

#line 466 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
static AETHER_MAYBE_UNUSED int fs_exists(const char* path) {
#line 467 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
    return fs_path_exists(aether_string_data(path));
}

#line 471 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
static AETHER_MAYBE_UNUSED const char* fs_create_dir(const char* path) {
#line 472 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
int ok = dir_create_raw(aether_string_data(path));
if (ok == 0) {
        {
#line 474 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
            return "cannot create directory";
        }
    }
#line 476 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
    return "";
}

#line 494 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
static AETHER_MAYBE_UNUSED const char* fs_delete_dir(const char* path) {
#line 495 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
int ok = dir_delete_raw(aether_string_data(path));
if (ok == 0) {
        {
#line 497 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
            return "cannot delete directory";
        }
    }
#line 499 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
    return "";
}

#line 505 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
static AETHER_MAYBE_UNUSED const char* fs_mkdir_p(const char* path) {
#line 506 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
int ok = fs_mkdir_p_raw(aether_string_data(path));
if (ok == 0) {
        {
#line 508 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
            return "cannot mkdir -p";
        }
    }
#line 510 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
    return "";
}

#line 548 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
static AETHER_MAYBE_UNUSED _tuple_ptr_string fs_list_dir(const char* path) {
#line 549 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
void* list = dir_list_raw(aether_string_data(path));
if (list == NULL) {
        {
#line 551 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
            return (_tuple_ptr_string){NULL, "cannot list directory"};
        }
    }
#line 553 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
    return (_tuple_ptr_string){list, ""};
}

#line 558 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
static AETHER_MAYBE_UNUSED _tuple_ptr_string fs_glob(const char* pattern) {
#line 559 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
void* list = fs_glob_raw(aether_string_data(pattern));
if (list == NULL) {
        {
#line 561 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
            return (_tuple_ptr_string){NULL, "glob failed"};
        }
    }
#line 563 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
    return (_tuple_ptr_string){list, ""};
}

#line 671 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
static AETHER_MAYBE_UNUSED const char* fs_write_atomic(const char* path, const char* data, int length) {
#line 672 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
int ok = fs_write_atomic_raw(aether_string_data(path), aether_string_data(data), length);
if (ok == 0) {
        {
#line 674 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
            return "atomic write failed";
        }
    }
#line 676 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
    return "";
}

#line 954 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
static AETHER_MAYBE_UNUSED int fs_is_within_base(const char* base, const char* target) {
#line 955 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
    return path_is_within_base(aether_string_data(base), aether_string_data(target));
}

#line 1054 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
static AETHER_MAYBE_UNUSED int fs_fd(void* file) {
#line 1055 "/home/paul/.local/bin/../share/aether/std/fs/module.ae"
    return file_fd_raw(file);
}

#line 35 "/home/paul/.local/bin/../share/aether/std/list/module.ae"
static AETHER_MAYBE_UNUSED const char* list_add(void* list, void* item) {
#line 36 "/home/paul/.local/bin/../share/aether/std/list/module.ae"
int ok = list_add_raw(list, item);
if (ok == 0) {
        {
#line 38 "/home/paul/.local/bin/../share/aether/std/list/module.ae"
            return "list.add failed";
        }
    }
#line 40 "/home/paul/.local/bin/../share/aether/std/list/module.ae"
    return "";
}

#line 47 "/home/paul/.local/bin/../share/aether/std/list/module.ae"
static AETHER_MAYBE_UNUSED _tuple_ptr_string list_get(void* list, int index) {
if (list == NULL) {
        {
#line 49 "/home/paul/.local/bin/../share/aether/std/list/module.ae"
            return (_tuple_ptr_string){NULL, "null list"};
        }
    }
#line 51 "/home/paul/.local/bin/../share/aether/std/list/module.ae"
void* item = list_get_raw(list, index);
#line 52 "/home/paul/.local/bin/../share/aether/std/list/module.ae"
    return (_tuple_ptr_string){item, ""};
}

#line 39 "/home/paul/.local/bin/../share/aether/std/map/module.ae"
static AETHER_MAYBE_UNUSED const char* map_put(void* map, const char* key, void* value) {
#line 40 "/home/paul/.local/bin/../share/aether/std/map/module.ae"
int ok = map_put_raw(map, aether_string_data(key), value);
if (ok == 0) {
        {
#line 42 "/home/paul/.local/bin/../share/aether/std/map/module.ae"
            return "map.put failed";
        }
    }
#line 44 "/home/paul/.local/bin/../share/aether/std/map/module.ae"
    return "";
}

#line 51 "/home/paul/.local/bin/../share/aether/std/map/module.ae"
static AETHER_MAYBE_UNUSED _tuple_ptr_string map_get(void* map, const char* key) {
if (map == NULL) {
        {
#line 53 "/home/paul/.local/bin/../share/aether/std/map/module.ae"
            return (_tuple_ptr_string){NULL, "null map"};
        }
    }
#line 55 "/home/paul/.local/bin/../share/aether/std/map/module.ae"
void* v = map_get_raw(map, aether_string_data(key));
#line 56 "/home/paul/.local/bin/../share/aether/std/map/module.ae"
    return (_tuple_ptr_string){v, ""};
}

#line 41 "/home/paul/.local/bin/../share/aether/std/dir/module.ae"
static AETHER_MAYBE_UNUSED _tuple_ptr_string dir_list(const char* path) {
#line 42 "/home/paul/.local/bin/../share/aether/std/dir/module.ae"
void* result = dir_list_raw(aether_string_data(path));
if (result == NULL) {
        {
#line 44 "/home/paul/.local/bin/../share/aether/std/dir/module.ae"
            return (_tuple_ptr_string){NULL, "cannot list directory"};
        }
    }
#line 46 "/home/paul/.local/bin/../share/aether/std/dir/module.ae"
    return (_tuple_ptr_string){result, ""};
}

int main(int argc, char** argv) {
    #ifdef _WIN32
    SetConsoleOutputCP(65001);  // CP_UTF8
    SetConsoleCP(65001);
    _setmode(_fileno(stdout), _O_BINARY);
    _setmode(_fileno(stderr), _O_BINARY);
    #endif
    aether_args_init(argc, argv);
    aether_capsicum_autosandbox();
    
    int _heap__root = 0; (void)_heap__root;
    const char* _root = NULL;
    int _heap__sel = 0; (void)_heap__sel;
    const char* _sel = NULL;
    int _heap__st = 0; (void)_heap__st;
    const char* _st = NULL;
    int _heap__rc = 0; (void)_heap__rc;
    const char* _rc = NULL;
    int _heap__td = 0; (void)_heap__td;
    const char* _td = NULL;
    int _heap__tfn = 0; (void)_heap__tfn;
    const char* _tfn = NULL;
    int _heap__telemetry_json = 0; (void)_heap__telemetry_json;
    const char* _telemetry_json = NULL;
    int _heap__tj_dir = 0; (void)_heap__tj_dir;
    const char* _tj_dir = NULL;
    int _heap__tj_body = 0; (void)_heap__tj_body;
    const char* _tj_body = NULL;
    int _heap__tj_err = 0; (void)_heap__tj_err;
    const char* _tj_err = NULL;
    int _heap__tests_json = 0; (void)_heap__tests_json;
    const char* _tests_json = NULL;
    int _heap__testj_dir = 0; (void)_heap__testj_dir;
    const char* _testj_dir = NULL;
    int _heap__testj_body = 0; (void)_heap__testj_body;
    const char* _testj_body = NULL;
    int _heap__testj_err = 0; (void)_heap__testj_err;
    const char* _testj_err = NULL;
    int _heap__artifacts_json = 0; (void)_heap__artifacts_json;
    const char* _artifacts_json = NULL;
    int _heap__artj_dir = 0; (void)_heap__artj_dir;
    const char* _artj_dir = NULL;
    int _heap__artj_body = 0; (void)_heap__artj_body;
    const char* _artj_body = NULL;
    int _heap__artj_err = 0; (void)_heap__artj_err;
    const char* _artj_err = NULL;
    {
#line 17 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
void* s = build_session(aether_args_get(1));
#line 18 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
{ const char* _tmp_old = _root; _root = aether_args_get(1); if (_heap__root) aether_heap_str_free(_tmp_old); _heap__root = 0; aether_unwind_track_str_if(_root, _heap__root); }
#line 19 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
{ const char* _tmp_old = _sel; _sel = ""; if (_heap__sel) aether_heap_str_free(_tmp_old); _heap__sel = 0; aether_unwind_track_str_if(_sel, _heap__sel); }
if (aether_args_count() > 2) {
            {
#line 20 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
{ const char* _tmp_old = _sel; _sel = aether_args_get(2); if (_heap__sel) aether_heap_str_free(_tmp_old); _heap__sel = 0; aether_unwind_track_str_if(_sel, _heap__sel); }
            }
        }
#line 21 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
void* _records = list_new();
#line 22 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
int64_t _session_start = _aether_clock_ns();
#line 23 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
int _run = 0;
if (string_length(_sel) == 0) {
            {
#line 24 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
_run = 1;
            }
        }
if (string_equals(_sel, "tests:.") == 1) {
            {
#line 25 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
_run = 1;
            }
        }
if (_run == 1) {
            {
#line 27 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
int64_t _start = _aether_clock_ns();
#line 28 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
ae_D_tests_D_ae(s);
#line 29 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
build_done(s, "tests:.");
#line 30 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
int64_t _end = _aether_clock_ns();
#line 31 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
void* _rec = map_new();
#line 32 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
map_put(_rec, "label", "tests:.");
#line 33 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
map_put(_rec, "type", "tests");
#line 34 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
_aether_map_put_adopted(_rec, aether_string_data((const void*)"wall_ms"), (void*)string_from_int(((_end - _start) / (int64_t)1000000)));
#line 35 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
_st = build_status_of(s, "tests:.");
if (string_length(_st) == 0) {
                    {
#line 36 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
_st = "passed";
                    }
                }
#line 37 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
map_put(_rec, "status", (void*)(_st));
#line 38 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
_rc = "0";
if (string_equals(_st, "failed") == 1) {
                    {
#line 39 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
_rc = "1";
                    }
                }
#line 40 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
map_put(_rec, "rc", (void*)(_rc));
#line 41 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
{ const char* _tmp_old = _td; _td = build__label_to_target_dir(_root, "tests:."); if (_heap__td) aether_heap_str_free(_tmp_old); _heap__td = 1; aether_unwind_track_str_if(_td, _heap__td); }
#line 42 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
_aether_map_put_adopted(_rec, aether_string_data((const void*)"cache"), (void*)build__read_cache_outcome(_td));
#line 43 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
                _tuple_int_int_int_int _tup82 = build__read_test_result(_td);
                int _tp = _tup82._0;
                int _tf = _tup82._1;
                int _tsk = _tup82._2;
                int _thr = _tup82._3;
if (_thr == 1) {
                    {
#line 45 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
_aether_map_put_adopted(_rec, aether_string_data((const void*)"test_passed"), (void*)string_from_int(_tp));
#line 46 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
_aether_map_put_adopted(_rec, aether_string_data((const void*)"test_failed"), (void*)string_from_int(_tf));
#line 47 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
_aether_map_put_adopted(_rec, aether_string_data((const void*)"test_skipped"), (void*)string_from_int(_tsk));
#line 48 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
_aether_map_put_adopted(_rec, aether_string_data((const void*)"test_has_report"), (void*)string_from_int(build__read_test_report_flag(_td)));
                    }
                }
#line 50 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
_tfn = build__read_test_failures(_td);
if (string_length(_tfn) > 0) {
                    {
#line 52 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
_aether_map_put_adopted(_rec, aether_string_data((const void*)"test_failed_names"), (void*)_tfn);
                    }
                }
#line 54 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
list_add(_records, _rec);
            }
        }
#line 56 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
int64_t _session_end = _aether_clock_ns();
#line 57 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
int64_t _total_ms = ((_session_end - _session_start) / (int64_t)1000000);
if (string_length(_sel) == 0) {
            {
#line 59 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
{ const char* _tmp_old = _telemetry_json; _telemetry_json = os_getenv(aether_string_data("AEB_TELEMETRY_JSON")); if (_heap__telemetry_json) aether_heap_str_free(_tmp_old); _heap__telemetry_json = 1; aether_unwind_track_str_if(_telemetry_json, _heap__telemetry_json); }
if (string_length(_telemetry_json) > 0) {
                    {
#line 61 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
{ const char* _tmp_old = _tj_dir; _tj_dir = path_dirname(aether_string_data(_telemetry_json)); if (_heap__tj_dir) aether_heap_str_free(_tmp_old); _heap__tj_dir = 1; aether_unwind_track_str_if(_tj_dir, _heap__tj_dir); }
if (string_length(_tj_dir) > 0) {
                            {
#line 62 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
build__mkdirs(_tj_dir);
                            }
                        }
#line 63 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
{ const char* _tmp_old = _tj_body; _tj_body = build_render_telemetry_json(_records, _total_ms); if (_heap__tj_body) aether_heap_str_free(_tmp_old); _heap__tj_body = 1; aether_unwind_track_str_if(_tj_body, _heap__tj_body); }
#line 64 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
{ const char* _tmp_old = _tj_err; _tj_err = fs_write_atomic(_telemetry_json, _tj_body, string_length(_tj_body)); if (_heap__tj_err) aether_heap_str_free(_tmp_old); _heap__tj_err = 0; aether_unwind_track_str_if(_tj_err, _heap__tj_err); }
                    }
                }
#line 66 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
{ const char* _tmp_old = _tests_json; _tests_json = os_getenv(aether_string_data("AEB_TESTS_JSON")); if (_heap__tests_json) aether_heap_str_free(_tmp_old); _heap__tests_json = 1; aether_unwind_track_str_if(_tests_json, _heap__tests_json); }
if (string_length(_tests_json) > 0) {
                    {
#line 68 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
{ const char* _tmp_old = _testj_dir; _testj_dir = path_dirname(aether_string_data(_tests_json)); if (_heap__testj_dir) aether_heap_str_free(_tmp_old); _heap__testj_dir = 1; aether_unwind_track_str_if(_testj_dir, _heap__testj_dir); }
if (string_length(_testj_dir) > 0) {
                            {
#line 69 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
build__mkdirs(_testj_dir);
                            }
                        }
#line 70 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
{ const char* _tmp_old = _testj_body; _testj_body = build_render_tests_json(_records); if (_heap__testj_body) aether_heap_str_free(_tmp_old); _heap__testj_body = 1; aether_unwind_track_str_if(_testj_body, _heap__testj_body); }
#line 71 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
{ const char* _tmp_old = _testj_err; _testj_err = fs_write_atomic(_tests_json, _testj_body, string_length(_testj_body)); if (_heap__testj_err) aether_heap_str_free(_tmp_old); _heap__testj_err = 0; aether_unwind_track_str_if(_testj_err, _heap__testj_err); }
                    }
                }
#line 73 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
{ const char* _tmp_old = _artifacts_json; _artifacts_json = os_getenv(aether_string_data("AEB_ARTIFACTS_JSON")); if (_heap__artifacts_json) aether_heap_str_free(_tmp_old); _heap__artifacts_json = 1; aether_unwind_track_str_if(_artifacts_json, _heap__artifacts_json); }
if (string_length(_artifacts_json) > 0) {
                    {
#line 75 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
{ const char* _tmp_old = _artj_dir; _artj_dir = path_dirname(aether_string_data(_artifacts_json)); if (_heap__artj_dir) aether_heap_str_free(_tmp_old); _heap__artj_dir = 1; aether_unwind_track_str_if(_artj_dir, _heap__artj_dir); }
if (string_length(_artj_dir) > 0) {
                            {
#line 76 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
build__mkdirs(_artj_dir);
                            }
                        }
#line 77 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
{ const char* _tmp_old = _artj_body; _artj_body = build_render_artifacts_json(_root, _records); if (_heap__artj_body) aether_heap_str_free(_tmp_old); _heap__artj_body = 1; aether_unwind_track_str_if(_artj_body, _heap__artj_body); }
#line 78 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
{ const char* _tmp_old = _artj_err; _artj_err = fs_write_atomic(_artifacts_json, _artj_body, string_length(_artj_body)); if (_heap__artj_err) aether_heap_str_free(_tmp_old); _heap__artj_err = 0; aether_unwind_track_str_if(_artj_err, _heap__artj_err); }
                    }
                }
#line 80 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
_aether_println_owned(build_render_telemetry(_records, _total_ms));
            }
        }
if (build_any_failed(s) == 1) {
            {
#line 82 "/home/paul/scm/selenium/rb/target/_aeb/_orchestrator.ae"
                /* deferred */ if (_heap__artj_err) { aether_heap_str_free(_artj_err); _artj_err = NULL; _heap__artj_err = 0; }
                /* deferred */ if (_heap__artj_body) { aether_heap_str_free(_artj_body); _artj_body = NULL; _heap__artj_body = 0; }
                /* deferred */ if (_heap__artj_dir) { aether_heap_str_free(_artj_dir); _artj_dir = NULL; _heap__artj_dir = 0; }
                /* deferred */ if (_heap__artifacts_json) { aether_heap_str_free(_artifacts_json); _artifacts_json = NULL; _heap__artifacts_json = 0; }
                /* deferred */ if (_heap__testj_err) { aether_heap_str_free(_testj_err); _testj_err = NULL; _heap__testj_err = 0; }
                /* deferred */ if (_heap__testj_body) { aether_heap_str_free(_testj_body); _testj_body = NULL; _heap__testj_body = 0; }
                /* deferred */ if (_heap__testj_dir) { aether_heap_str_free(_testj_dir); _testj_dir = NULL; _heap__testj_dir = 0; }
                /* deferred */ if (_heap__tests_json) { aether_heap_str_free(_tests_json); _tests_json = NULL; _heap__tests_json = 0; }
                /* deferred */ if (_heap__tj_err) { aether_heap_str_free(_tj_err); _tj_err = NULL; _heap__tj_err = 0; }
                /* deferred */ if (_heap__tj_body) { aether_heap_str_free(_tj_body); _tj_body = NULL; _heap__tj_body = 0; }
                /* deferred */ if (_heap__tj_dir) { aether_heap_str_free(_tj_dir); _tj_dir = NULL; _heap__tj_dir = 0; }
                /* deferred */ if (_heap__telemetry_json) { aether_heap_str_free(_telemetry_json); _telemetry_json = NULL; _heap__telemetry_json = 0; }
                /* deferred */ if (_heap__td) { aether_heap_str_free(_td); _td = NULL; _heap__td = 0; }
                /* deferred */ if (_heap__sel) { aether_heap_str_free(_sel); _sel = NULL; _heap__sel = 0; }
                /* deferred */ if (_heap__root) { aether_heap_str_free(_root); _root = NULL; _heap__root = 0; }
exit(1);
            }
        }
    }
    /* deferred */ if (_heap__artj_err) { aether_heap_str_free(_artj_err); _artj_err = NULL; _heap__artj_err = 0; }
    /* deferred */ if (_heap__artj_body) { aether_heap_str_free(_artj_body); _artj_body = NULL; _heap__artj_body = 0; }
    /* deferred */ if (_heap__artj_dir) { aether_heap_str_free(_artj_dir); _artj_dir = NULL; _heap__artj_dir = 0; }
    /* deferred */ if (_heap__artifacts_json) { aether_heap_str_free(_artifacts_json); _artifacts_json = NULL; _heap__artifacts_json = 0; }
    /* deferred */ if (_heap__testj_err) { aether_heap_str_free(_testj_err); _testj_err = NULL; _heap__testj_err = 0; }
    /* deferred */ if (_heap__testj_body) { aether_heap_str_free(_testj_body); _testj_body = NULL; _heap__testj_body = 0; }
    /* deferred */ if (_heap__testj_dir) { aether_heap_str_free(_testj_dir); _testj_dir = NULL; _heap__testj_dir = 0; }
    /* deferred */ if (_heap__tests_json) { aether_heap_str_free(_tests_json); _tests_json = NULL; _heap__tests_json = 0; }
    /* deferred */ if (_heap__tj_err) { aether_heap_str_free(_tj_err); _tj_err = NULL; _heap__tj_err = 0; }
    /* deferred */ if (_heap__tj_body) { aether_heap_str_free(_tj_body); _tj_body = NULL; _heap__tj_body = 0; }
    /* deferred */ if (_heap__tj_dir) { aether_heap_str_free(_tj_dir); _tj_dir = NULL; _heap__tj_dir = 0; }
    /* deferred */ if (_heap__telemetry_json) { aether_heap_str_free(_telemetry_json); _telemetry_json = NULL; _heap__telemetry_json = 0; }
    /* deferred */ if (_heap__td) { aether_heap_str_free(_td); _td = NULL; _heap__td = 0; }
    /* deferred */ if (_heap__sel) { aether_heap_str_free(_sel); _sel = NULL; _heap__sel = 0; }
    /* deferred */ if (_heap__root) { aether_heap_str_free(_root); _root = NULL; _heap__root = 0; }
    return 0;
}
