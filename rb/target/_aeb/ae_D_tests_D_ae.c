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
typedef struct { void* _0; const char* _1; } _tuple_ptr_string;
typedef struct { int _0; int _1; int _2; int _3; } _tuple_int_int_int_int;
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
int ae_D_tests_D_ae(void*);
static AETHER_MAYBE_UNUSED _tuple_int_string string_to_int(const char*);
static AETHER_MAYBE_UNUSED const char* string_copy(const char*);
static AETHER_MAYBE_UNUSED _tuple_string_string io_read_file(const char*);
static AETHER_MAYBE_UNUSED const char* io_write_file(const char*, const char*);
static AETHER_MAYBE_UNUSED const char* io_append_file(const char*, const char*);
static AETHER_MAYBE_UNUSED const char* io_delete_file(const char*);
static AETHER_MAYBE_UNUSED _tuple_string_int_string io_fd_read_n(int, int);
static AETHER_MAYBE_UNUSED _tuple_string_string io_fd_read_line(int);
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
static AETHER_MAYBE_UNUSED const char* build__label_buildtype(const char*);
static AETHER_MAYBE_UNUSED const char* build__label_dir(const char*);
static AETHER_MAYBE_UNUSED void* build_begin(void*, const char*);
static AETHER_MAYBE_UNUSED void build__mark_failed(void*, const char*, const char*);
static AETHER_MAYBE_UNUSED int build_fail(void*, const char*);
static AETHER_MAYBE_UNUSED int build_record_status(void*, const char*, int);
static AETHER_MAYBE_UNUSED void* build_session_handle(void*);
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
static AETHER_MAYBE_UNUSED int build__sh(const char*);
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
static AETHER_MAYBE_UNUSED const char* build__env_export_prefix(void*);
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
static AETHER_MAYBE_UNUSED const char* build__exec_chain_cmd(void*, const char*, void*);
static AETHER_MAYBE_UNUSED int build__exec_chain_is_passthrough(void*, void*);
static AETHER_MAYBE_UNUSED const char* build__exec_chain_body(void*, const char*, void*);
static AETHER_MAYBE_UNUSED const char* build__label_to_target_dir(const char*, const char*);
static AETHER_MAYBE_UNUSED int build__status_is_failed(const char*);
static AETHER_MAYBE_UNUSED const char* build__format_telemetry_line(const char*, const char*, int, const char*, int, int, int, const char*);
static AETHER_MAYBE_UNUSED const char* build__telemetry_status(void*);
static AETHER_MAYBE_UNUSED const char* build__collect_file_list(const char*);
static AETHER_MAYBE_UNUSED void ruby_bundle_path(void*, const char*);
static AETHER_MAYBE_UNUSED void ruby_rspec_arg(void*, const char*);
static AETHER_MAYBE_UNUSED const char* ruby_bundle_install_cmd(const char*, const char*, const char*);
static AETHER_MAYBE_UNUSED const char* ruby_bundle_exec_cmd(const char*, const char*, const char*);
static AETHER_MAYBE_UNUSED const char* ruby_rspec_cmd(const char*, const char*, const char*);
static AETHER_MAYBE_UNUSED const char* ruby_rubocop_cmd(const char*, const char*, const char*);
static AETHER_MAYBE_UNUSED const char* ruby_gem_build_cmd(const char*, const char*, const char*, const char*);
static AETHER_MAYBE_UNUSED const char* ruby__resolve_bundle_path(void*, const char*);
static AETHER_MAYBE_UNUSED const char* ruby__resolve_bundle_bin(void);
static AETHER_MAYBE_UNUSED const char* ruby__resolve_gem_bin(void);
static AETHER_MAYBE_UNUSED const char* ruby__rspec_args_str(void*);
static AETHER_MAYBE_UNUSED int ruby_rspec(void*, void*);
static AETHER_MAYBE_UNUSED int os_args_count(void);
static AETHER_MAYBE_UNUSED _tuple_string_string os_exec(const char*);
static AETHER_MAYBE_UNUSED const char* os_platform(void);
static AETHER_MAYBE_UNUSED const char* os_temp_dir(void);
static AETHER_MAYBE_UNUSED int os_getpid(void);
static AETHER_MAYBE_UNUSED int64_t os_now_monotonic_ns(void);

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


// Import: std.string
// Import: std.io
// Import: std.file
// Import: std.fs
// Import: std.list
// Import: std.map
// Import: std.path
// Import: std.dir
// Import: build
// Import: ruby
// Import: ruby as rspec_arg
// Import: std.os
#line 28 "/home/paul/scm/selenium/rb/target/_aeb/ae_D_tests_D_ae.ae"
int ae_D_tests_D_ae(void* s) {
#line 29 "/home/paul/scm/selenium/rb/target/_aeb/ae_D_tests_D_ae.ae"
void* b = build_begin(s, "tests:.");
if ((intptr_t)b == 0) {
        {
#line 30 "/home/paul/scm/selenium/rb/target/_aeb/ae_D_tests_D_ae.ae"
            return 0;
        }
    }
#line 31 "/home/paul/scm/selenium/rb/target/_aeb/ae_D_tests_D_ae.ae"
void* root = build__get(b, "root");
#line 32 "/home/paul/scm/selenium/rb/target/_aeb/ae_D_tests_D_ae.ae"
int s1 = ({ char* _ad_0 = (char*)(_aether_interp("cp %s/../LICENSE %s/../NOTICE %s/", _aether_safe_str(root), _aether_safe_str(root), _aether_safe_str(root))); int _ad_r = os_system(aether_string_data(_ad_0)); aether_heap_str_free(_ad_0); _ad_r; });
if (s1 != 0) {
        {
#line 33 "/home/paul/scm/selenium/rb/target/_aeb/ae_D_tests_D_ae.ae"
puts("rb tests: staging LICENSE/NOTICE failed");
            return 1;
        }
    }
#line 34 "/home/paul/scm/selenium/rb/target/_aeb/ae_D_tests_D_ae.ae"
int s2 = ({ char* _ad_1 = (char*)(_aether_interp("cd %s && bundle config set --local with development >/dev/null 2>&1; bundle install >/dev/null 2>&1", _aether_safe_str(root))); int _ad_r = os_system(aether_string_data(_ad_1)); aether_heap_str_free(_ad_1); _ad_r; });
if (s2 != 0) {
        {
#line 35 "/home/paul/scm/selenium/rb/target/_aeb/ae_D_tests_D_ae.ae"
puts("rb tests: bundle install failed");
            return 1;
        }
    }
#line 36 "/home/paul/scm/selenium/rb/target/_aeb/ae_D_tests_D_ae.ae"
int s3 = ({ char* _ad_2 = (char*)(_aether_interp("cd %s && bash generate-devtools.sh", _aether_safe_str(root))); int _ad_r = os_system(aether_string_data(_ad_2)); aether_heap_str_free(_ad_2); _ad_r; });
if (s3 != 0) {
        {
#line 37 "/home/paul/scm/selenium/rb/target/_aeb/ae_D_tests_D_ae.ae"
puts("rb tests: devtools codegen failed");
            return 1;
        }
    }
#line 38 "/home/paul/scm/selenium/rb/target/_aeb/ae_D_tests_D_ae.ae"
    {
        void* _bcfg = (void*)(intptr_t)map_new();
        _aether_ctx_push(_bcfg);
        {
#line 39 "/home/paul/scm/selenium/rb/target/_aeb/ae_D_tests_D_ae.ae"
ruby_rspec_arg(_aether_ctx_get(), "spec/unit/");
        }
        _aether_ctx_pop();
        ruby_rspec(b, _bcfg);
    }
#line 41 "/home/paul/scm/selenium/rb/target/_aeb/ae_D_tests_D_ae.ae"
    return 0;
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

#line 65 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED void* build_begin(void* s, const char* module_dir) {
    int _heap__e1 = 0; (void)_heap__e1;
    const char* _e1 = NULL;
    int _heap__e2 = 0; (void)_heap__e2;
    const char* _e2 = NULL;
    int _heap__es = 0; (void)_heap__es;
    const char* _es = NULL;
    int _heap_buildtype = 0; (void)_heap_buildtype;
    const char* buildtype = NULL;
    int _heap_fs_dir = 0; (void)_heap_fs_dir;
    const char* fs_dir = NULL;
    int _heap_mod_name = 0; (void)_heap_mod_name;
    const char* mod_name = NULL;
    int _heap__e3 = 0; (void)_heap__e3;
    const char* _e3 = NULL;
    int _heap_source_dir = 0; (void)_heap_source_dir;
    const char* source_dir = NULL;
    int _heap__e4 = 0; (void)_heap__e4;
    const char* _e4 = NULL;
    int _heap_target_base = 0; (void)_heap_target_base;
    const char* target_base = NULL;
    int _heap_tgt_dir = 0; (void)_heap_tgt_dir;
    const char* tgt_dir = NULL;
    int _heap__e5 = 0; (void)_heap__e5;
    const char* _e5 = NULL;
    int _heap__e6 = 0; (void)_heap__e6;
    const char* _e6 = NULL;
    int _heap__e7 = 0; (void)_heap__e7;
    const char* _e7 = NULL;
    int _heap__e8 = 0; (void)_heap__e8;
    const char* _e8 = NULL;
    int _heap__e9 = 0; (void)_heap__e9;
    const char* _e9 = NULL;
    int _heap__e10 = 0; (void)_heap__e10;
    const char* _e10 = NULL;
    int _heap__e10b = 0; (void)_heap__e10b;
    const char* _e10b = NULL;
    int _heap__e11 = 0; (void)_heap__e11;
    const char* _e11 = NULL;
    int _heap__e12 = 0; (void)_heap__e12;
    const char* _e12 = NULL;
#line 66 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_ptr_string _tup0 = map_get(s, "visited");
    void* visited = _tup0._0;
if (map_has(visited, aether_string_data(module_dir)) == 1) {
        {
#line 68 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_ptr_string _tup1 = map_get(s, "_null_");
            void* _null = _tup1._0;
#line 69 "/home/paul/.local/share/aeb/lib/build/module.ae"
            void* _builder_ret = _null;
            /* deferred */ if (_heap__e12) { aether_heap_str_free(_e12); _e12 = NULL; _heap__e12 = 0; }
            /* deferred */ if (_heap__e11) { aether_heap_str_free(_e11); _e11 = NULL; _heap__e11 = 0; }
            /* deferred */ if (_heap__e10b) { aether_heap_str_free(_e10b); _e10b = NULL; _heap__e10b = 0; }
            /* deferred */ if (_heap__e10) { aether_heap_str_free(_e10); _e10 = NULL; _heap__e10 = 0; }
            /* deferred */ if (_heap__e9) { aether_heap_str_free(_e9); _e9 = NULL; _heap__e9 = 0; }
            /* deferred */ if (_heap__e8) { aether_heap_str_free(_e8); _e8 = NULL; _heap__e8 = 0; }
            /* deferred */ if (_heap__e7) { aether_heap_str_free(_e7); _e7 = NULL; _heap__e7 = 0; }
            /* deferred */ if (_heap__e6) { aether_heap_str_free(_e6); _e6 = NULL; _heap__e6 = 0; }
            /* deferred */ if (_heap__e5) { aether_heap_str_free(_e5); _e5 = NULL; _heap__e5 = 0; }
            /* deferred */ if (_heap_target_base) { aether_heap_str_free(target_base); target_base = NULL; _heap_target_base = 0; }
            /* deferred */ if (_heap__e4) { aether_heap_str_free(_e4); _e4 = NULL; _heap__e4 = 0; }
            /* deferred */ if (_heap__e3) { aether_heap_str_free(_e3); _e3 = NULL; _heap__e3 = 0; }
            /* deferred */ if (_heap_fs_dir) { aether_heap_str_free(fs_dir); fs_dir = NULL; _heap_fs_dir = 0; }
            /* deferred */ if (_heap_buildtype) { aether_heap_str_free(buildtype); buildtype = NULL; _heap_buildtype = 0; }
            /* deferred */ if (_heap__es) { aether_heap_str_free(_es); _es = NULL; _heap__es = 0; }
            /* deferred */ if (_heap__e2) { aether_heap_str_free(_e2); _e2 = NULL; _heap__e2 = 0; }
            /* deferred */ if (_heap__e1) { aether_heap_str_free(_e1); _e1 = NULL; _heap__e1 = 0; }
            return _builder_ret;
        }
    }
#line 72 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_ptr_string _tup2 = map_get(s, "root");
    void* root = _tup2._0;
#line 73 "/home/paul/.local/share/aeb/lib/build/module.ae"
void* ctx = map_new();
#line 74 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = _e1; _e1 = map_put(ctx, "root", root); if (_heap__e1) aether_heap_str_free(_tmp_old); _heap__e1 = 0; aether_unwind_track_str_if(_e1, _heap__e1); }
#line 75 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = _e2; _e2 = map_put(ctx, "module_dir", (void*)(module_dir)); if (_heap__e2) aether_heap_str_free(_tmp_old); _heap__e2 = 0; aether_unwind_track_str_if(_e2, _heap__e2); }
#line 81 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = _es; _es = map_put(ctx, "_session", s); if (_heap__es) aether_heap_str_free(_tmp_old); _heap__es = 0; aether_unwind_track_str_if(_es, _heap__es); }
#line 86 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = buildtype; buildtype = build__label_buildtype(module_dir); if (_heap_buildtype) aether_heap_str_free(_tmp_old); _heap_buildtype = 1; aether_unwind_track_str_if(buildtype, _heap_buildtype); }
#line 87 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = fs_dir; fs_dir = build__label_dir(module_dir); if (_heap_fs_dir) aether_heap_str_free(_tmp_old); _heap_fs_dir = 1; aether_unwind_track_str_if(fs_dir, _heap_fs_dir); }
#line 89 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ mod_name = fs_dir; _heap_mod_name = _heap_fs_dir; _heap_fs_dir = 0; }
#line 90 "/home/paul/.local/share/aeb/lib/build/module.ae"
int slash = string_index_of(fs_dir, "/");
if (slash >= 0) {
        {
#line 92 "/home/paul/.local/share/aeb/lib/build/module.ae"
mod_name = string_substring(fs_dir, (slash + 1), string_length(fs_dir));
        }
    }
#line 94 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = _e3; _e3 = _aether_map_put_adopted(ctx, aether_string_data((const void*)"module"), (void*)mod_name); if (_heap__e3) aether_heap_str_free(_tmp_old); _heap__e3 = 0; aether_unwind_track_str_if(_e3, _heap__e3); }
#line 96 "/home/paul/.local/share/aeb/lib/build/module.ae"
source_dir = path_join(aether_string_data(root), aether_string_data(fs_dir));
#line 97 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = _e4; _e4 = _aether_map_put_adopted(ctx, aether_string_data((const void*)"source_dir"), (void*)source_dir); if (_heap__e4) aether_heap_str_free(_tmp_old); _heap__e4 = 0; aether_unwind_track_str_if(_e4, _heap__e4); }
#line 105 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = target_base; target_base = ({ char* _ad_3 = (char*)(path_join(aether_string_data(root), aether_string_data("target"))); const char* _ad_r = path_join(aether_string_data(_ad_3), aether_string_data(buildtype)); aether_heap_str_free(_ad_3); _ad_r; }); if (_heap_target_base) aether_heap_str_free(_tmp_old); _heap_target_base = 1; aether_unwind_track_str_if(target_base, _heap_target_base); }
#line 108 "/home/paul/.local/share/aeb/lib/build/module.ae"
tgt_dir = path_join(aether_string_data(target_base), aether_string_data(fs_dir));
#line 109 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = _e5; _e5 = _aether_map_put_adopted(ctx, aether_string_data((const void*)"target_dir"), (void*)tgt_dir); if (_heap__e5) aether_heap_str_free(_tmp_old); _heap__e5 = 0; aether_unwind_track_str_if(_e5, _heap__e5); }
#line 111 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = _e6; _e6 = map_put(ctx, "deps", list_new()); if (_heap__e6) aether_heap_str_free(_tmp_old); _heap__e6 = 0; aether_unwind_track_str_if(_e6, _heap__e6); }
#line 112 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = _e7; _e7 = map_put(ctx, "libs", list_new()); if (_heap__e7) aether_heap_str_free(_tmp_old); _heap__e7 = 0; aether_unwind_track_str_if(_e7, _heap__e7); }
#line 113 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = _e8; _e8 = map_put(ctx, "cargo_deps", list_new()); if (_heap__e8) aether_heap_str_free(_tmp_old); _heap__e8 = 0; aether_unwind_track_str_if(_e8, _heap__e8); }
#line 114 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = _e9; _e9 = map_put(ctx, "npm_deps", list_new()); if (_heap__e9) aether_heap_str_free(_tmp_old); _heap__e9 = 0; aether_unwind_track_str_if(_e9, _heap__e9); }
#line 115 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = _e10; _e10 = map_put(ctx, "maven_deps", list_new()); if (_heap__e10) aether_heap_str_free(_tmp_old); _heap__e10 = 0; aether_unwind_track_str_if(_e10, _heap__e10); }
#line 116 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = _e10b; _e10b = map_put(ctx, "prereqs", list_new()); if (_heap__e10b) aether_heap_str_free(_tmp_old); _heap__e10b = 0; aether_unwind_track_str_if(_e10b, _heap__e10b); }
#line 117 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = _e11; _e11 = map_put(ctx, "boms", list_new()); if (_heap__e11) aether_heap_str_free(_tmp_old); _heap__e11 = 0; aether_unwind_track_str_if(_e11, _heap__e11); }
#line 118 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = _e12; _e12 = map_put(ctx, "repos", list_new()); if (_heap__e12) aether_heap_str_free(_tmp_old); _heap__e12 = 0; aether_unwind_track_str_if(_e12, _heap__e12); }
#line 120 "/home/paul/.local/share/aeb/lib/build/module.ae"
    void* _builder_ret = ctx;
    /* deferred */ if (_heap__e12) { aether_heap_str_free(_e12); _e12 = NULL; _heap__e12 = 0; }
    /* deferred */ if (_heap__e11) { aether_heap_str_free(_e11); _e11 = NULL; _heap__e11 = 0; }
    /* deferred */ if (_heap__e10b) { aether_heap_str_free(_e10b); _e10b = NULL; _heap__e10b = 0; }
    /* deferred */ if (_heap__e10) { aether_heap_str_free(_e10); _e10 = NULL; _heap__e10 = 0; }
    /* deferred */ if (_heap__e9) { aether_heap_str_free(_e9); _e9 = NULL; _heap__e9 = 0; }
    /* deferred */ if (_heap__e8) { aether_heap_str_free(_e8); _e8 = NULL; _heap__e8 = 0; }
    /* deferred */ if (_heap__e7) { aether_heap_str_free(_e7); _e7 = NULL; _heap__e7 = 0; }
    /* deferred */ if (_heap__e6) { aether_heap_str_free(_e6); _e6 = NULL; _heap__e6 = 0; }
    /* deferred */ if (_heap__e5) { aether_heap_str_free(_e5); _e5 = NULL; _heap__e5 = 0; }
    /* deferred */ if (_heap_target_base) { aether_heap_str_free(target_base); target_base = NULL; _heap_target_base = 0; }
    /* deferred */ if (_heap__e4) { aether_heap_str_free(_e4); _e4 = NULL; _heap__e4 = 0; }
    /* deferred */ if (_heap__e3) { aether_heap_str_free(_e3); _e3 = NULL; _heap__e3 = 0; }
    /* deferred */ if (_heap_fs_dir) { aether_heap_str_free(fs_dir); fs_dir = NULL; _heap_fs_dir = 0; }
    /* deferred */ if (_heap_buildtype) { aether_heap_str_free(buildtype); buildtype = NULL; _heap_buildtype = 0; }
    /* deferred */ if (_heap__es) { aether_heap_str_free(_es); _es = NULL; _heap__es = 0; }
    /* deferred */ if (_heap__e2) { aether_heap_str_free(_e2); _e2 = NULL; _heap__e2 = 0; }
    /* deferred */ if (_heap__e1) { aether_heap_str_free(_e1); _e1 = NULL; _heap__e1 = 0; }
    return _builder_ret;
    /* deferred */ if (_heap__e12) { aether_heap_str_free(_e12); _e12 = NULL; _heap__e12 = 0; }
    /* deferred */ if (_heap__e11) { aether_heap_str_free(_e11); _e11 = NULL; _heap__e11 = 0; }
    /* deferred */ if (_heap__e10b) { aether_heap_str_free(_e10b); _e10b = NULL; _heap__e10b = 0; }
    /* deferred */ if (_heap__e10) { aether_heap_str_free(_e10); _e10 = NULL; _heap__e10 = 0; }
    /* deferred */ if (_heap__e9) { aether_heap_str_free(_e9); _e9 = NULL; _heap__e9 = 0; }
    /* deferred */ if (_heap__e8) { aether_heap_str_free(_e8); _e8 = NULL; _heap__e8 = 0; }
    /* deferred */ if (_heap__e7) { aether_heap_str_free(_e7); _e7 = NULL; _heap__e7 = 0; }
    /* deferred */ if (_heap__e6) { aether_heap_str_free(_e6); _e6 = NULL; _heap__e6 = 0; }
    /* deferred */ if (_heap__e5) { aether_heap_str_free(_e5); _e5 = NULL; _heap__e5 = 0; }
    /* deferred */ if (_heap_target_base) { aether_heap_str_free(target_base); target_base = NULL; _heap_target_base = 0; }
    /* deferred */ if (_heap__e4) { aether_heap_str_free(_e4); _e4 = NULL; _heap__e4 = 0; }
    /* deferred */ if (_heap__e3) { aether_heap_str_free(_e3); _e3 = NULL; _heap__e3 = 0; }
    /* deferred */ if (_heap_fs_dir) { aether_heap_str_free(fs_dir); fs_dir = NULL; _heap_fs_dir = 0; }
    /* deferred */ if (_heap_buildtype) { aether_heap_str_free(buildtype); buildtype = NULL; _heap_buildtype = 0; }
    /* deferred */ if (_heap__es) { aether_heap_str_free(_es); _es = NULL; _heap__es = 0; }
    /* deferred */ if (_heap__e2) { aether_heap_str_free(_e2); _e2 = NULL; _heap__e2 = 0; }
    /* deferred */ if (_heap__e1) { aether_heap_str_free(_e1); _e1 = NULL; _heap__e1 = 0; }
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
    _tuple_ptr_string _tup3 = map_get(s, "status");
    void* st = _tup3._0;
#line 150 "/home/paul/.local/share/aeb/lib/build/module.ae"
int already = 0;
if (map_has(st, aether_string_data(label)) == 1) {
        {
#line 152 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_ptr_string _tup4 = map_get(st, label);
            void* cur = _tup4._0;
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
            _tuple_ptr_string _tup5 = map_get(s, "reason");
            void* rm = _tup5._0;
#line 158 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = _e2; _e2 = map_put(rm, label, (void*)(reason)); if (_heap__e2) aether_heap_str_free(_tmp_old); _heap__e2 = 0; aether_unwind_track_str_if(_e2, _heap__e2); }
        }
    }
if (already == 0) {
        {
#line 161 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_ptr_string _tup6 = map_get(s, "failed");
            void* failed = _tup6._0;
#line 162 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = _e3; _e3 = _aether_list_add_adopted(failed, (void*)string_copy(label)); if (_heap__e3) aether_heap_str_free(_tmp_old); _heap__e3 = 0; aether_unwind_track_str_if(_e3, _heap__e3); }
        }
    }
    /* deferred */ if (_heap__e3) { aether_heap_str_free(_e3); _e3 = NULL; _heap__e3 = 0; }
    /* deferred */ if (_heap__e2) { aether_heap_str_free(_e2); _e2 = NULL; _heap__e2 = 0; }
    /* deferred */ if (_heap__e1) { aether_heap_str_free(_e1); _e1 = NULL; _heap__e1 = 0; }
}

#line 170 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED int build_fail(void* ctx, const char* reason) {
if (map_has(ctx, aether_string_data("_session")) == 0) {
        {
#line 171 "/home/paul/.local/share/aeb/lib/build/module.ae"
            return 0;
        }
    }
#line 172 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_ptr_string _tup7 = map_get(ctx, "_session");
    void* s = _tup7._0;
if (s == NULL) {
        {
#line 173 "/home/paul/.local/share/aeb/lib/build/module.ae"
            return 0;
        }
    }
#line 174 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_ptr_string _tup8 = map_get(ctx, "module_dir");
    void* label = _tup8._0;
#line 175 "/home/paul/.local/share/aeb/lib/build/module.ae"
printf("%s: FAILED — %s", _aether_safe_str(label), _aether_safe_str(reason)); putchar('\n');
#line 176 "/home/paul/.local/share/aeb/lib/build/module.ae"
build__mark_failed(s, label, reason);
#line 177 "/home/paul/.local/share/aeb/lib/build/module.ae"
    return 0;
}

#line 184 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED int build_record_status(void* s, const char* label, int rc) {
    int _heap__e = 0; (void)_heap__e;
    const char* _e = NULL;
#line 185 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_ptr_string _tup9 = map_get(s, "status");
    void* st = _tup9._0;
if (map_has(st, aether_string_data(label)) == 1) {
        {
#line 187 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_ptr_string _tup10 = map_get(st, label);
            void* cur = _tup10._0;
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
build__mark_failed(s, label, ({ char* _ad_4 = (char*)(string_from_int(rc)); const char* _ad_r = string_concat("builder returned exit ", _ad_4); aether_heap_str_free(_ad_4); _ad_r; }));
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
    _tuple_ptr_string _tup11 = map_get(ctx, "_session");
    void* s = _tup11._0;
#line 203 "/home/paul/.local/share/aeb/lib/build/module.ae"
    return s;
}

#line 216 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED int build_any_failed(void* s) {
#line 217 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_ptr_string _tup12 = map_get(s, "failed");
    void* failed = _tup12._0;
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
if (({ char* _ad_5 = (char*)(string_substring(s, 1, 2)); int _ad_r = string_equals(_ad_5, ":"); aether_heap_str_free(_ad_5); _ad_r; }) == 0) {
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
    const char* _builder_ret = aether_uniform_heap_str((const char*)(({ char* _ad_6 = (char*)(string_concat(abase, "/")); const char* _ad_r = string_concat(_ad_6, b); aether_heap_str_free(_ad_6); _ad_r; })), 1);
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
            return aether_uniform_heap_str((const char*)(({ char* _ad_7 = (char*)(build__cmd_caret_escape(build__sh_quote(cmd))); const char* _ad_r = string_concat("sh -c ", _ad_7); aether_heap_str_free(_ad_7); _ad_r; })), 1);
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
    _tuple_string_string _tup13 = ({ char* _ad_8 = (char*)(_aether_interp("sh -c \"cygpath -m '%s'\"", _aether_safe_str(posix))); _tuple_string_string _ad_r = os_exec(_ad_8); aether_heap_str_free(_ad_8); _ad_r; });
    { const char* _tmp_old = out; out = _tup13._0; if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; aether_unwind_track_str_if(out, _heap_out); }
    { const char* _tmp_old = err; err = _tup13._1; if (_heap_err) aether_heap_str_free(_tmp_old); _heap_err = 0; aether_unwind_track_str_if(err, _heap_err); }
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
{ const char* _tmp_old = name; name = ({ char* _ad_9 = (char*)(({ char* _ad_10 = (char*)(string_from_int(os_getpid())); char* _ad_11 = (char*)(({ char* _ad_12 = (char*)(({ char* _ad_13 = (char*)(string_from_int(build__sh_hash(cmd))); const char* _ad_r = string_concat(_ad_13, ".sh"); aether_heap_str_free(_ad_13); _ad_r; })); const char* _ad_r = string_concat("_", _ad_12); aether_heap_str_free(_ad_12); _ad_r; })); const char* _ad_r = string_concat(_ad_10, _ad_11); aether_heap_str_free(_ad_10); aether_heap_str_free(_ad_11); _ad_r; })); const char* _ad_r = string_concat("_aeb_sh_", _ad_9); aether_heap_str_free(_ad_9); _ad_r; }); if (_heap_name) aether_heap_str_free(_tmp_old); _heap_name = 1; aether_unwind_track_str_if(name, _heap_name); }
#line 1348 "/home/paul/.local/share/aeb/lib/build/module.ae"
    const char* _builder_ret = aether_uniform_heap_str((const char*)(({ char* _ad_14 = (char*)(string_concat("/", name)); const char* _ad_r = string_concat(tmp, _ad_14); aether_heap_str_free(_ad_14); _ad_r; })), 1);
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
if (({ char* _ad_15 = (char*)(os_getenv(aether_string_data("AEB_SH_TRACE"))); int _ad_r = string_equals(_ad_15, "1"); aether_heap_str_free(_ad_15); _ad_r; }) == 1) {
        {
#line 1371 "/home/paul/.local/share/aeb/lib/build/module.ae"
printf("[aeb-sh trace] %s", _aether_safe_str(cmd)); putchar('\n');
        }
    }
}

#line 1375 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED int build__sh(const char* cmd) {
    int _heap_scriptf = 0; (void)_heap_scriptf;
    const char* scriptf = NULL;
    int _heap_werr = 0; (void)_heap_werr;
    const char* werr = NULL;
    int _heap__d = 0; (void)_heap__d;
    const char* _d = NULL;
#line 1376 "/home/paul/.local/share/aeb/lib/build/module.ae"
build__sh_trace(cmd);
if (build__is_windows() == 0) {
        {
#line 1378 "/home/paul/.local/share/aeb/lib/build/module.ae"
            int _builder_ret = os_system(aether_string_data(cmd));
            /* deferred */ if (_heap__d) { aether_heap_str_free(_d); _d = NULL; _heap__d = 0; }
            /* deferred */ if (_heap_werr) { aether_heap_str_free(werr); werr = NULL; _heap_werr = 0; }
            /* deferred */ if (_heap_scriptf) { aether_heap_str_free(scriptf); scriptf = NULL; _heap_scriptf = 0; }
            return _builder_ret;
        }
    }
#line 1380 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = scriptf; scriptf = build__sh_script_path(cmd); if (_heap_scriptf) aether_heap_str_free(_tmp_old); _heap_scriptf = 1; aether_unwind_track_str_if(scriptf, _heap_scriptf); }
#line 1381 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = werr; werr = io_write_file(scriptf, cmd); if (_heap_werr) aether_heap_str_free(_tmp_old); _heap_werr = 0; aether_unwind_track_str_if(werr, _heap_werr); }
if (string_length(werr) > 0) {
        {
#line 1394 "/home/paul/.local/share/aeb/lib/build/module.ae"
printf("aeb: WARNING cannot write temp script %s: %s", _aether_safe_str(scriptf), _aether_safe_str(werr)); putchar('\n');
#line 1395 "/home/paul/.local/share/aeb/lib/build/module.ae"
puts("aeb:   falling back to `sh -c` quoting, which mangles nested quotes on Windows.");
#line 1396 "/home/paul/.local/share/aeb/lib/build/module.ae"
puts("aeb:   set TMP or TEMP to a writable directory to restore the reliable path.");
#line 1397 "/home/paul/.local/share/aeb/lib/build/module.ae"
            int _builder_ret = ({ char* _ad_16 = (char*)(build__sh_wrap(cmd)); int _ad_r = os_system(aether_string_data(_ad_16)); aether_heap_str_free(_ad_16); _ad_r; });
            /* deferred */ if (_heap__d) { aether_heap_str_free(_d); _d = NULL; _heap__d = 0; }
            /* deferred */ if (_heap_werr) { aether_heap_str_free(werr); werr = NULL; _heap_werr = 0; }
            /* deferred */ if (_heap_scriptf) { aether_heap_str_free(scriptf); scriptf = NULL; _heap_scriptf = 0; }
            return _builder_ret;
        }
    }
#line 1399 "/home/paul/.local/share/aeb/lib/build/module.ae"
int rc = ({ char* _ad_17 = (char*)(string_concat("sh ", scriptf)); int _ad_r = os_system(aether_string_data(_ad_17)); aether_heap_str_free(_ad_17); _ad_r; });
if (({ char* _ad_18 = (char*)(os_getenv(aether_string_data("AEB_SH_KEEP"))); int _ad_r = string_equals(_ad_18, "1"); aether_heap_str_free(_ad_18); _ad_r; }) == 1) {
        {
#line 1401 "/home/paul/.local/share/aeb/lib/build/module.ae"
printf("[aeb-sh kept] %s", _aether_safe_str(scriptf)); putchar('\n');
#line 1402 "/home/paul/.local/share/aeb/lib/build/module.ae"
            int _builder_ret = rc;
            /* deferred */ if (_heap__d) { aether_heap_str_free(_d); _d = NULL; _heap__d = 0; }
            /* deferred */ if (_heap_werr) { aether_heap_str_free(werr); werr = NULL; _heap_werr = 0; }
            /* deferred */ if (_heap_scriptf) { aether_heap_str_free(scriptf); scriptf = NULL; _heap_scriptf = 0; }
            return _builder_ret;
        }
    }
#line 1404 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = _d; _d = fs_delete(scriptf); if (_heap__d) aether_heap_str_free(_tmp_old); _heap__d = 0; aether_unwind_track_str_if(_d, _heap__d); }
#line 1405 "/home/paul/.local/share/aeb/lib/build/module.ae"
    int _builder_ret = rc;
    /* deferred */ if (_heap__d) { aether_heap_str_free(_d); _d = NULL; _heap__d = 0; }
    /* deferred */ if (_heap_werr) { aether_heap_str_free(werr); werr = NULL; _heap_werr = 0; }
    /* deferred */ if (_heap_scriptf) { aether_heap_str_free(scriptf); scriptf = NULL; _heap_scriptf = 0; }
    return _builder_ret;
    /* deferred */ if (_heap__d) { aether_heap_str_free(_d); _d = NULL; _heap__d = 0; }
    /* deferred */ if (_heap_werr) { aether_heap_str_free(werr); werr = NULL; _heap_werr = 0; }
    /* deferred */ if (_heap_scriptf) { aether_heap_str_free(scriptf); scriptf = NULL; _heap_scriptf = 0; }
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
            _tuple_string_string _tup14 = os_exec(cmd);
            { const char* _tmp_old = out; out = _tup14._0; if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
            { const char* _tmp_old = err; err = _tup14._1; if (_heap_err) aether_heap_str_free(_tmp_old); _heap_err = 0; }
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
            _tuple_string_string _tup15 = ({ char* _ad_19 = (char*)(build__sh_wrap(cmd)); _tuple_string_string _ad_r = os_exec(_ad_19); aether_heap_str_free(_ad_19); _ad_r; });
            { const char* _tmp_old = out; out = _tup15._0; if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
            { const char* _tmp_old = err; err = _tup15._1; if (_heap_err) aether_heap_str_free(_tmp_old); _heap_err = 0; }
#line 1426 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_string_string _builder_ret = (_tuple_string_string){aether_uniform_heap_str((const char*)(out), _heap_out), err};
            /* deferred */ if (_heap__d) { aether_heap_str_free(_d); _d = NULL; _heap__d = 0; }
            /* deferred */ if (_heap_werr) { aether_heap_str_free(werr); werr = NULL; _heap_werr = 0; }
            /* deferred */ if (_heap_scriptf) { aether_heap_str_free(scriptf); scriptf = NULL; _heap_scriptf = 0; }
            return _builder_ret;
        }
    }
#line 1428 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_string_string _tup16 = ({ char* _ad_20 = (char*)(string_concat("sh ", scriptf)); _tuple_string_string _ad_r = os_exec(_ad_20); aether_heap_str_free(_ad_20); _ad_r; });
    { const char* _tmp_old = out; out = _tup16._0; if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
    { const char* _tmp_old = err; err = _tup16._1; if (_heap_err) aether_heap_str_free(_tmp_old); _heap_err = 0; }
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
if (({ char* _ad_21 = (char*)(string_concat(root, "/build/libaether.a")); int _ad_r = fs_exists(_ad_21); aether_heap_str_free(_ad_21); _ad_r; }) == 1) {
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
    _tuple_string_string _tup17 = build__sh_capture(_aether_interp("command -v %s", _aether_safe_str(ae)));
    { const char* _tmp_old = raw; raw = _tup17._0; if (_heap_raw) aether_heap_str_free(_tmp_old); _heap_raw = 1; aether_unwind_track_str_if(raw, _heap_raw); }
    { const char* _tmp_old = _eerr; _eerr = _tup17._1; if (_heap__eerr) aether_heap_str_free(_tmp_old); _heap__eerr = 0; aether_unwind_track_str_if(_eerr, _heap__eerr); }
#line 1473 "/home/paul/.local/share/aeb/lib/build/module.ae"
    const char* _builder_ret = aether_uniform_heap_str((const char*)(({ char* _ad_22 = (char*)(({ char* _ad_23 = (char*)(string_trim(raw)); const char* _ad_r = build__dirname(_ad_23); aether_heap_str_free(_ad_23); _ad_r; })); const char* _ad_r = build__to_native_path(_ad_22); if ((const char*)_ad_r != _ad_22) string_release(_ad_22); _ad_r; })), 1);
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
    _tuple_string_string _tup18 = build__sh_capture(_aether_interp("cygpath -m '%s'", _aether_safe_str(p)));
    { const char* _tmp_old = nat; nat = _tup18._0; if (_heap_nat) aether_heap_str_free(_tmp_old); _heap_nat = 1; aether_unwind_track_str_if(nat, _heap_nat); }
    { const char* _tmp_old = nerr; nerr = _tup18._1; if (_heap_nerr) aether_heap_str_free(_tmp_old); _heap_nerr = 0; aether_unwind_track_str_if(nerr, _heap_nerr); }
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
if (({ char* _ad_24 = (char*)(string_substring(p, 1, 2)); int _ad_r = string_equals(_ad_24, ":"); aether_heap_str_free(_ad_24); _ad_r; }) == 1) {
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
            _tuple_string_string _tup19 = build__sh_capture(_aether_interp("cygpath -m %s", _aether_safe_str(aether_dir)));
            { const char* _tmp_old = _nat; _nat = _tup19._0; if (_heap__nat) aether_heap_str_free(_tmp_old); _heap__nat = 1; aether_unwind_track_str_if(_nat, _heap__nat); }
            { const char* _tmp_old = _ne; _ne = _tup19._1; if (_heap__ne) aether_heap_str_free(_tmp_old); _heap__ne = 0; aether_unwind_track_str_if(_ne, _heap__ne); }
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
    _tuple_ptr_string _tup20 = map_get(ctx, key);
    void* v = _tup20._0;
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
    const char* _builder_ret = aether_uniform_heap_str((const char*)(({ char* _ad_25 = (char*)(({ char* _ad_26 = (char*)(path_join(aether_string_data(root), aether_string_data("target"))); const char* _ad_r = path_join(aether_string_data(_ad_26), aether_string_data(buildtype)); aether_heap_str_free(_ad_26); _ad_r; })); const char* _ad_r = path_join(aether_string_data(_ad_25), aether_string_data(dir)); aether_heap_str_free(_ad_25); _ad_r; })), 1);
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
if (({ char* _ad_27 = (char*)(string_substring(s, i, (i + 1))); int _ad_r = string_equals(_ad_27, "/"); aether_heap_str_free(_ad_27); _ad_r; }) == 1) {
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
            _tuple_ptr_string _tup21 = list_get(env_pairs, i);
            void* frag = _tup21._0;
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
            _tuple_ptr_string _tup22 = list_get(steps, j);
            void* st = _tup22._0;
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

#line 2029 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build__env_export_prefix(void* bmap) {
    int _heap_out = 0; (void)_heap_out;
    const char* out = NULL;
if (bmap == NULL) {
        {
#line 2030 "/home/paul/.local/share/aeb/lib/build/module.ae"
            const char* _no_defer_ret = aether_uniform_heap_str((const char*)(""), 0);
            if (_heap_out) { aether_heap_str_free(out); out = NULL; _heap_out = 0; }
            return _no_defer_ret;
        }
    }
if (map_has(bmap, aether_string_data("proc_env")) == 0) {
        {
#line 2031 "/home/paul/.local/share/aeb/lib/build/module.ae"
            const char* _no_defer_ret = aether_uniform_heap_str((const char*)(""), 0);
            if (_heap_out) { aether_heap_str_free(out); out = NULL; _heap_out = 0; }
            return _no_defer_ret;
        }
    }
#line 2032 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_ptr_string _tup23 = map_get(bmap, "proc_env");
    void* pairs = _tup23._0;
#line 2033 "/home/paul/.local/share/aeb/lib/build/module.ae"
int n = list_size(pairs);
if (n == 0) {
        {
#line 2034 "/home/paul/.local/share/aeb/lib/build/module.ae"
            const char* _no_defer_ret = aether_uniform_heap_str((const char*)(""), 0);
            if (_heap_out) { aether_heap_str_free(out); out = NULL; _heap_out = 0; }
            return _no_defer_ret;
        }
    }
#line 2035 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = ""; if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 0; }
#line 2036 "/home/paul/.local/share/aeb/lib/build/module.ae"
int i = 0;
while (i < n) {
        {
#line 2038 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_ptr_string _tup24 = list_get(pairs, i);
            void* frag = _tup24._0;
#line 2039 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, "export "); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 2040 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, frag); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 2041 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, " && "); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 2042 "/home/paul/.local/share/aeb/lib/build/module.ae"
i = (i + 1);
        }
    }
#line 2044 "/home/paul/.local/share/aeb/lib/build/module.ae"
    const char* _no_defer_ret = aether_uniform_heap_str((const char*)(out), _heap_out);
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
                    _tuple_ptr_string _tup25 = map_get(bmap, "proc_workdir");
                    void* wd = _tup25._0;
#line 2068 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = absdir; absdir = path_join(aether_string_data(root), aether_string_data(wd)); if (_heap_absdir) aether_heap_str_free(_tmp_old); _heap_absdir = 1; aether_unwind_track_str_if(absdir, _heap_absdir); }
                }
            }
if (map_has(bmap, aether_string_data("proc_env")) == 1) {
                {
#line 2070 "/home/paul/.local/share/aeb/lib/build/module.ae"
                    _tuple_ptr_string _tup26 = map_get(bmap, "proc_env");
                    env_pairs = _tup26._0;
                }
            }
if (map_has(bmap, aether_string_data("proc_steps")) == 1) {
                {
#line 2071 "/home/paul/.local/share/aeb/lib/build/module.ae"
                    _tuple_ptr_string _tup27 = map_get(bmap, "proc_steps");
                    steps = _tup27._0;
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
    _tuple_string_string _tup28 = fs_read(p);
    { const char* _tmp_old = content; content = _tup28._0; if (_heap_content) aether_heap_str_free(_tmp_old); _heap_content = 1; aether_unwind_track_str_if(content, _heap_content); }
    { const char* _tmp_old = _err; _err = _tup28._1; if (_heap__err) aether_heap_str_free(_tmp_old); _heap__err = 0; aether_unwind_track_str_if(_err, _heap__err); }
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
    _tuple_string_string _tup29 = build__sh_capture("mktemp");
    { const char* _tmp_old = tmp_raw; tmp_raw = _tup29._0; if (_heap_tmp_raw) aether_heap_str_free(_tmp_old); _heap_tmp_raw = 1; aether_unwind_track_str_if(tmp_raw, _heap_tmp_raw); }
    { const char* _tmp_old = _err; _err = _tup29._1; if (_heap__err) aether_heap_str_free(_tmp_old); _heap__err = 0; aether_unwind_track_str_if(_err, _heap__err); }
#line 2204 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = tmp; tmp = ({ char* _ad_28 = (char*)(string_trim(tmp_raw)); const char* _ad_r = build__to_native_path(_ad_28); if ((const char*)_ad_r != _ad_28) string_release(_ad_28); _ad_r; }); if (_heap_tmp) aether_heap_str_free(_tmp_old); _heap_tmp = 1; }
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
    _tuple_string_string _tup30 = build__sh_capture(cmd);
    { const char* _tmp_old = out; out = _tup30._0; if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; aether_unwind_track_str_if(out, _heap_out); }
    { const char* _tmp_old = eerr; eerr = _tup30._1; if (_heap_eerr) aether_heap_str_free(_tmp_old); _heap_eerr = 0; aether_unwind_track_str_if(eerr, _heap_eerr); }
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
    _tuple_ptr_string _tup31 = map_get(bmap, key);
    void* v = _tup31._0;
#line 2338 "/home/paul/.local/share/aeb/lib/build/module.ae"
    _tuple_int_string _tup32 = ({ char* _ad_29 = (char*)(string_trim(v)); _tuple_int_string _ad_r = string_to_int(_ad_29); aether_heap_str_free(_ad_29); _ad_r; });
    int iv = _tup32._0;
    { const char* _tmp_old = _e; _e = _tup32._1; if (_heap__e) aether_heap_str_free(_tmp_old); _heap__e = 0; aether_unwind_track_str_if(_e, _heap__e); }
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
    _tuple_ptr_string _tup33 = map_get(bmap, key);
    void* v = _tup33._0;
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
{ const char* _tmp_old = body; body = ({ char* _ad_30 = (char*)(string_from_int(passed)); const char* _ad_r = string_concat("passed=", _ad_30); aether_heap_str_free(_ad_30); _ad_r; }); if (_heap_body) aether_heap_str_free(_tmp_old); _heap_body = 1; aether_unwind_track_str_if(body, _heap_body); }
#line 2553 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = body; body = string_concat(body, "\nfailed="); if (_heap_body) aether_heap_str_free(_tmp_old); _heap_body = 1; aether_unwind_track_str_if(body, _heap_body); }
#line 2554 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = body; body = ({ char* _ad_31 = (char*)(string_from_int(failed)); const char* _ad_r = string_concat(body, _ad_31); aether_heap_str_free(_ad_31); _ad_r; }); if (_heap_body) aether_heap_str_free(_tmp_old); _heap_body = 1; aether_unwind_track_str_if(body, _heap_body); }
#line 2555 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = body; body = string_concat(body, "\nskipped="); if (_heap_body) aether_heap_str_free(_tmp_old); _heap_body = 1; aether_unwind_track_str_if(body, _heap_body); }
#line 2556 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = body; body = ({ char* _ad_32 = (char*)(string_from_int(skipped)); const char* _ad_r = string_concat(body, _ad_32); aether_heap_str_free(_ad_32); _ad_r; }); if (_heap_body) aether_heap_str_free(_tmp_old); _heap_body = 1; aether_unwind_track_str_if(body, _heap_body); }
#line 2557 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = body; body = string_concat(body, "\nreport="); if (_heap_body) aether_heap_str_free(_tmp_old); _heap_body = 1; aether_unwind_track_str_if(body, _heap_body); }
#line 2558 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = body; body = ({ char* _ad_33 = (char*)(string_from_int(has_report)); const char* _ad_r = string_concat(body, _ad_33); aether_heap_str_free(_ad_33); _ad_r; }); if (_heap_body) aether_heap_str_free(_tmp_old); _heap_body = 1; aether_unwind_track_str_if(body, _heap_body); }
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
    _tuple_string_string _tup34 = fs_read(p);
    { const char* _tmp_old = content; content = _tup34._0; if (_heap_content) aether_heap_str_free(_tmp_old); _heap_content = 1; aether_unwind_track_str_if(content, _heap_content); }
    { const char* _tmp_old = _err; _err = _tup34._1; if (_heap__err) aether_heap_str_free(_tmp_old); _heap__err = 0; aether_unwind_track_str_if(_err, _heap__err); }
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
                    _tuple_int_string _tup35 = ({ char* _ad_34 = (char*)(string_trim(value_str)); _tuple_int_string _ad_r = string_to_int(_ad_34); aether_heap_str_free(_ad_34); _ad_r; });
                    int value = _tup35._0;
                    { const char* _tmp_old = _verr; _verr = _tup35._1; if (_heap__verr) aether_heap_str_free(_tmp_old); _heap__verr = 0; aether_unwind_track_str_if(_verr, _heap__verr); }
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
            _tuple_ptr_string _tup36 = list_get(pre_cmds, i);
            void* c = _tup36._0;
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
            _tuple_ptr_string _tup37 = list_get(post_cmds, j);
            void* pc = _tup37._0;
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
{ const char* _tmp_old = target_base; target_base = ({ char* _ad_35 = (char*)(path_join(aether_string_data(root), aether_string_data("target"))); char* _ad_36 = (char*)(build__label_buildtype(module_dir)); const char* _ad_r = path_join(aether_string_data(_ad_35), aether_string_data(_ad_36)); aether_heap_str_free(_ad_35); aether_heap_str_free(_ad_36); _ad_r; }); if (_heap_target_base) aether_heap_str_free(_tmp_old); _heap_target_base = 1; aether_unwind_track_str_if(target_base, _heap_target_base); }
#line 3323 "/home/paul/.local/share/aeb/lib/build/module.ae"
    const char* _builder_ret = aether_uniform_heap_str((const char*)(({ char* _ad_37 = (char*)(build__label_dir(module_dir)); const char* _ad_r = path_join(aether_string_data(target_base), aether_string_data(_ad_37)); aether_heap_str_free(_ad_37); _ad_r; })), 1);
    /* deferred */ if (_heap_target_base) { aether_heap_str_free(target_base); target_base = NULL; _heap_target_base = 0; }
    return _builder_ret;
    /* deferred */ if (_heap_target_base) { aether_heap_str_free(target_base); target_base = NULL; _heap_target_base = 0; }
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
{ const char* _tmp_old = wall_str; wall_str = ({ char* _ad_38 = (char*)(({ char* _ad_40 = (char*)(string_from_int(secs)); const char* _ad_r = string_concat(_ad_40, "."); aether_heap_str_free(_ad_40); _ad_r; })); char* _ad_39 = (char*)(string_concat(cs_str, "s")); const char* _ad_r = string_concat(_ad_38, _ad_39); aether_heap_str_free(_ad_38); aether_heap_str_free(_ad_39); _ad_r; }); if (_heap_wall_str) aether_heap_str_free(_tmp_old); _heap_wall_str = 1; aether_unwind_track_str_if(wall_str, _heap_wall_str); }
#line 3413 "/home/paul/.local/share/aeb/lib/build/module.ae"
{ const char* _tmp_old = base; base = ({ char* _ad_41 = (char*)(({ char* _ad_43 = (char*)(({ char* _ad_45 = (char*)(string_concat("  ", type_col)); const char* _ad_r = string_concat(_ad_45, " "); aether_heap_str_free(_ad_45); _ad_r; })); char* _ad_44 = (char*)(string_concat(label_col, " ")); const char* _ad_r = string_concat(_ad_43, _ad_44); aether_heap_str_free(_ad_43); aether_heap_str_free(_ad_44); _ad_r; })); char* _ad_42 = (char*)(({ char* _ad_46 = (char*)(string_concat(wall_str, " [")); char* _ad_47 = (char*)(string_concat(cache, "]")); const char* _ad_r = string_concat(_ad_46, _ad_47); aether_heap_str_free(_ad_46); aether_heap_str_free(_ad_47); _ad_r; })); const char* _ad_r = string_concat(_ad_41, _ad_42); aether_heap_str_free(_ad_41); aether_heap_str_free(_ad_42); _ad_r; }); if (_heap_base) aether_heap_str_free(_tmp_old); _heap_base = 1; }
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
{ const char* _tmp_old = trailer; trailer = ({ char* _ad_48 = (char*)(({ char* _ad_50 = (char*)(string_from_int(test_passed)); const char* _ad_r = string_concat(" ", _ad_50); aether_heap_str_free(_ad_50); _ad_r; })); char* _ad_49 = (char*)(({ char* _ad_51 = (char*)(string_from_int(total)); const char* _ad_r = string_concat("/", _ad_51); aether_heap_str_free(_ad_51); _ad_r; })); const char* _ad_r = string_concat(_ad_48, _ad_49); aether_heap_str_free(_ad_48); aether_heap_str_free(_ad_49); _ad_r; }); if (_heap_trailer) aether_heap_str_free(_tmp_old); _heap_trailer = 1; aether_unwind_track_str_if(trailer, _heap_trailer); }
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

#line 3655 "/home/paul/.local/share/aeb/lib/build/module.ae"
static AETHER_MAYBE_UNUSED const char* build__telemetry_status(void* rec) {
    int _heap_rc = 0; (void)_heap_rc;
    const char* rc = NULL;
if (map_has(rec, aether_string_data("status")) == 1) {
        {
#line 3657 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_ptr_string _tup38 = map_get(rec, "status");
            void* st = _tup38._0;
#line 3658 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_ptr_string _tup39 = map_get(rec, "cache");
            void* cache0 = _tup39._0;
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
    _tuple_ptr_string _tup40 = map_get(rec, "cache");
    void* cache = _tup40._0;
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
            _tuple_ptr_string _tup41 = map_get(rec, "rc");
            { const char* _tmp_old = rc; rc = _tup41._0; if (_heap_rc) aether_heap_str_free(_tmp_old); _heap_rc = 0; aether_unwind_track_str_if(rc, _heap_rc); }
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
            _tuple_ptr_string _tup42 = map_get(rec, "test_failed");
            void* tf = _tup42._0;
#line 3677 "/home/paul/.local/share/aeb/lib/build/module.ae"
            _tuple_int_string _tup43 = string_to_int(tf);
            int tfi = _tup43._0;
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
    _tuple_ptr_string _tup44 = fs_glob(pattern);
    void* files = _tup44._0;
    { const char* _tmp_old = _gerr; _gerr = _tup44._1; if (_heap__gerr) aether_heap_str_free(_tmp_old); _heap__gerr = 0; aether_unwind_track_str_if(_gerr, _heap__gerr); }
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

#line 82 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
static AETHER_MAYBE_UNUSED void ruby_bundle_path(void* _ctx, const char* dir) {
    int _heap__e = 0; (void)_heap__e;
    const char* _e = NULL;
#line 83 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
{ const char* _tmp_old = _e; _e = map_put(_ctx, "ruby_bundle_path", (void*)(dir)); if (_heap__e) aether_heap_str_free(_tmp_old); _heap__e = 0; aether_unwind_track_str_if(_e, _heap__e); }
    /* deferred */ if (_heap__e) { aether_heap_str_free(_e); _e = NULL; _heap__e = 0; }
}

#line 88 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
static AETHER_MAYBE_UNUSED void ruby_rspec_arg(void* _ctx, const char* arg) {
    int _heap__e1 = 0; (void)_heap__e1;
    const char* _e1 = NULL;
    int _heap__e2 = 0; (void)_heap__e2;
    const char* _e2 = NULL;
if (map_has(_ctx, aether_string_data("ruby_rspec_args")) == 0) {
        {
#line 90 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
{ const char* _tmp_old = _e1; _e1 = map_put(_ctx, "ruby_rspec_args", list_new()); if (_heap__e1) aether_heap_str_free(_tmp_old); _heap__e1 = 0; aether_unwind_track_str_if(_e1, _heap__e1); }
        }
    }
#line 92 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
    _tuple_ptr_string _tup45 = map_get(_ctx, "ruby_rspec_args");
    void* args = _tup45._0;
#line 93 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
{ const char* _tmp_old = _e2; _e2 = list_add(args, (void*)(arg)); if (_heap__e2) aether_heap_str_free(_tmp_old); _heap__e2 = 0; aether_unwind_track_str_if(_e2, _heap__e2); }
    /* deferred */ if (_heap__e2) { aether_heap_str_free(_e2); _e2 = NULL; _heap__e2 = 0; }
    /* deferred */ if (_heap__e1) { aether_heap_str_free(_e1); _e1 = NULL; _heap__e1 = 0; }
}

#line 124 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
static AETHER_MAYBE_UNUSED const char* ruby_bundle_install_cmd(const char* bundle_bin, const char* source_dir, const char* bundle_path) {
#line 125 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
    return aether_uniform_heap_str((const char*)(_aether_interp("cd '%s' && '%s' config set --local path '%s' && '%s' install", _aether_safe_str(source_dir), _aether_safe_str(bundle_bin), _aether_safe_str(bundle_path), _aether_safe_str(bundle_bin))), 1);
}

#line 131 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
static AETHER_MAYBE_UNUSED const char* ruby_bundle_exec_cmd(const char* bundle_bin, const char* source_dir, const char* argv_str) {
#line 132 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
    return aether_uniform_heap_str((const char*)(_aether_interp("cd '%s' && '%s' exec %s", _aether_safe_str(source_dir), _aether_safe_str(bundle_bin), _aether_safe_str(argv_str))), 1);
}

#line 138 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
static AETHER_MAYBE_UNUSED const char* ruby_rspec_cmd(const char* bundle_bin, const char* source_dir, const char* args) {
if (string_length(args) == 0) {
        {
#line 140 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
            return aether_uniform_heap_str((const char*)(_aether_interp("cd '%s' && '%s' exec rspec", _aether_safe_str(source_dir), _aether_safe_str(bundle_bin))), 1);
        }
    }
#line 142 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
    return aether_uniform_heap_str((const char*)(_aether_interp("cd '%s' && '%s' exec rspec %s", _aether_safe_str(source_dir), _aether_safe_str(bundle_bin), _aether_safe_str(args))), 1);
}

#line 147 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
static AETHER_MAYBE_UNUSED const char* ruby_rubocop_cmd(const char* bundle_bin, const char* source_dir, const char* config_path) {
if (string_length(config_path) == 0) {
        {
#line 149 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
            return aether_uniform_heap_str((const char*)(_aether_interp("cd '%s' && '%s' exec rubocop", _aether_safe_str(source_dir), _aether_safe_str(bundle_bin))), 1);
        }
    }
#line 151 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
    return aether_uniform_heap_str((const char*)(_aether_interp("cd '%s' && '%s' exec rubocop --config '%s'", _aether_safe_str(source_dir), _aether_safe_str(bundle_bin), _aether_safe_str(config_path))), 1);
}

#line 167 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
static AETHER_MAYBE_UNUSED const char* ruby_gem_build_cmd(const char* gem_bin, const char* source_dir, const char* gemspec_basename, const char* dist_dir) {
#line 168 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
    return aether_uniform_heap_str((const char*)(_aether_interp("cd '%s' && '%s' build '%s' && mv -f *.gem '%s/'", _aether_safe_str(source_dir), _aether_safe_str(gem_bin), _aether_safe_str(gemspec_basename), _aether_safe_str(dist_dir))), 1);
}

#line 176 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
static AETHER_MAYBE_UNUSED const char* ruby__resolve_bundle_path(void* builder_map, const char* root) {
if (builder_map != NULL) {
        {
if (map_has(builder_map, aether_string_data("ruby_bundle_path")) == 1) {
                {
#line 179 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
                    _tuple_ptr_string _tup46 = map_get(builder_map, "ruby_bundle_path");
                    void* p = _tup46._0;
if (string_length(p) > 0) {
                        {
if (build__is_abs_path(p) == 1) {
                                {
#line 181 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
                                    return aether_uniform_heap_str((const char*)(p), 0);
                                }
                            }
#line 182 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
                            return aether_uniform_heap_str((const char*)(path_join(aether_string_data(root), aether_string_data(p))), 1);
                        }
                    }
                }
            }
        }
    }
#line 186 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
    return aether_uniform_heap_str((const char*)(path_join(aether_string_data(root), aether_string_data(".aeb/bundle"))), 1);
}

#line 192 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
static AETHER_MAYBE_UNUSED const char* ruby__resolve_bundle_bin(void) {
#line 193 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
    return "bundle";
}

#line 196 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
static AETHER_MAYBE_UNUSED const char* ruby__resolve_gem_bin(void) {
#line 197 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
    return "gem";
}

#line 201 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
static AETHER_MAYBE_UNUSED const char* ruby__rspec_args_str(void* builder_map) {
    int _heap_out = 0; (void)_heap_out;
    const char* out = NULL;
if (builder_map == NULL) {
        {
#line 202 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
            const char* _no_defer_ret = aether_uniform_heap_str((const char*)(""), 0);
            if (_heap_out) { aether_heap_str_free(out); out = NULL; _heap_out = 0; }
            return _no_defer_ret;
        }
    }
if (map_has(builder_map, aether_string_data("ruby_rspec_args")) == 0) {
        {
#line 203 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
            const char* _no_defer_ret = aether_uniform_heap_str((const char*)(""), 0);
            if (_heap_out) { aether_heap_str_free(out); out = NULL; _heap_out = 0; }
            return _no_defer_ret;
        }
    }
#line 204 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
    _tuple_ptr_string _tup47 = map_get(builder_map, "ruby_rspec_args");
    void* args = _tup47._0;
#line 205 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
int n = list_size(args);
if (n == 0) {
        {
#line 206 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
            const char* _no_defer_ret = aether_uniform_heap_str((const char*)(""), 0);
            if (_heap_out) { aether_heap_str_free(out); out = NULL; _heap_out = 0; }
            return _no_defer_ret;
        }
    }
#line 207 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
{ const char* _tmp_old = out; out = ""; if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 0; }
#line 208 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
int i = 0;
while (i < n) {
        {
#line 210 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
            _tuple_ptr_string _tup48 = list_get(args, i);
            void* a = _tup48._0;
if (i > 0) {
                {
#line 211 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, " "); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
                }
            }
#line 212 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
{ const char* _tmp_old = out; out = string_concat(out, a); if (_heap_out) aether_heap_str_free(_tmp_old); _heap_out = 1; }
#line 213 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
i = (i + 1);
        }
    }
#line 215 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
    const char* _no_defer_ret = aether_uniform_heap_str((const char*)(out), _heap_out);
    return _no_defer_ret;
}

#line 249 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
static AETHER_MAYBE_UNUSED int ruby_rspec(void* ctx, void* _builder) {
    int _heap_bundle = 0; (void)_heap_bundle;
    const char* bundle = NULL;
    int _heap_args_str = 0; (void)_heap_args_str;
    const char* args_str = NULL;
    int _heap_cmd = 0; (void)_heap_cmd;
    const char* cmd = NULL;
    int _heap__ew = 0; (void)_heap__ew;
    const char* _ew = NULL;
#line 250 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
void* target_dir = build__get(ctx, "target_dir");
#line 251 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
void* mod_dir = build__get(ctx, "module_dir");
#line 252 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
void* source_dir = build__get(ctx, "source_dir");
#line 254 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
build__mkdirs(target_dir);
#line 255 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
printf("%s: running tests (rspec)", _aether_safe_str(mod_dir)); putchar('\n');
#line 257 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
{ const char* _tmp_old = bundle; bundle = ruby__resolve_bundle_bin(); if (_heap_bundle) aether_heap_str_free(_tmp_old); _heap_bundle = 0; aether_unwind_track_str_if(bundle, _heap_bundle); }
#line 258 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
{ const char* _tmp_old = args_str; args_str = ruby__rspec_args_str(_builder); if (_heap_args_str) aether_heap_str_free(_tmp_old); _heap_args_str = 1; aether_unwind_track_str_if(args_str, _heap_args_str); }
#line 259 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
cmd = ({ char* _ad_52 = (char*)(build__env_export_prefix(_builder)); char* _ad_53 = (char*)(ruby_rspec_cmd(bundle, source_dir, args_str)); const char* _ad_r = string_concat(_ad_52, _ad_53); aether_heap_str_free(_ad_52); aether_heap_str_free(_ad_53); _ad_r; });
#line 260 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
int rc = build__sh(cmd);
if (rc != 0) {
        {
#line 265 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
build__record_test_result(ctx, 0, 1);
#line 266 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
printf("%s: tests FAILED", _aether_safe_str(mod_dir)); putchar('\n');
#line 267 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
build_fail(ctx, "tests FAILED");
#line 268 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
            int _builder_ret = rc;
            /* deferred */ if (_heap__ew) { aether_heap_str_free(_ew); _ew = NULL; _heap__ew = 0; }
            /* deferred */ if (_heap_args_str) { aether_heap_str_free(args_str); args_str = NULL; _heap_args_str = 0; }
            /* deferred */ if (_heap_bundle) { aether_heap_str_free(bundle); bundle = NULL; _heap_bundle = 0; }
            return _builder_ret;
        }
    }
#line 270 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
build__record_test_result(ctx, 1, 0);
#line 271 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
printf("%s: tests PASSED", _aether_safe_str(mod_dir)); putchar('\n');
#line 272 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
{ const char* _tmp_old = _ew; _ew = ({ char* _ad_54 = (char*)(path_join(aether_string_data(target_dir), aether_string_data(".timestamp"))); const char* _ad_r = io_write_file(_ad_54, ""); aether_heap_str_free(_ad_54); _ad_r; }); if (_heap__ew) aether_heap_str_free(_tmp_old); _heap__ew = 0; aether_unwind_track_str_if(_ew, _heap__ew); }
#line 273 "/home/paul/.local/share/aeb/lib/ruby/module.ae"
    int _builder_ret = 0;
    /* deferred */ if (_heap__ew) { aether_heap_str_free(_ew); _ew = NULL; _heap__ew = 0; }
    /* deferred */ if (_heap_args_str) { aether_heap_str_free(args_str); args_str = NULL; _heap_args_str = 0; }
    /* deferred */ if (_heap_bundle) { aether_heap_str_free(bundle); bundle = NULL; _heap_bundle = 0; }
    return _builder_ret;
    /* deferred */ if (_heap__ew) { aether_heap_str_free(_ew); _ew = NULL; _heap__ew = 0; }
    /* deferred */ if (_heap_args_str) { aether_heap_str_free(args_str); args_str = NULL; _heap_args_str = 0; }
    /* deferred */ if (_heap_bundle) { aether_heap_str_free(bundle); bundle = NULL; _heap_bundle = 0; }
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

