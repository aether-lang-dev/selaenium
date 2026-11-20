/* proctree.c: run a driver (chromedriver, geckodriver, appium) so that its
 * whole process tree ends when it is stopped, and when the program that
 * started it dies.
 *
 * Why this is C and not std.os: see module.ae beside this file and
 * docs/Selenium-Manager-Port.md ("Driver and browser lifetime"). In short,
 * std.os.spawn_proc_to puts the driver in a process group of its own and
 * os.kill signals that group, which is enough while the client lives and calls
 * stop. Nothing in the stdlib ends the driver when the client dies (a test
 * killed by a timeout, a crash, a process that exits without stop), and a
 * group kill misses anything that left the group with setsid.
 *
 * POSIX shape. The client forks a short-lived intermediate, which forks the
 * SUPERVISOR and exits at once (so the client never has to reap the
 * supervisor, and a released driver leaves no zombie behind). The supervisor:
 *   - becomes a child subreaper (Linux PR_SET_CHILD_SUBREAPER, FreeBSD
 *     procctl PROC_REAP_ACQUIRE), so every descendant whose parent dies is
 *     re-parented to it rather than to init, wherever its process group;
 *   - forks the driver into a process group of its own (pgid == driver pid),
 *     with clean signal dispositions and mask, stdin /dev/null, stdout and
 *     stderr to the log file, then execs it;
 *   - watches the CLIENT's pid: a pidfd on Linux, kqueue EVFILT_PROC/NOTE_EXIT
 *     on macOS and FreeBSD, both registered while the client is provably alive
 *     (it is blocked reading our status pipe), so pid reuse cannot fool it;
 *   - tears the tree down when the client dies, when it is asked to (SIGTERM
 *     to the supervisor), or when the driver exits on its own: SIGTERM to the
 *     driver's group, a grace period, SIGKILL to the group, then (Linux,
 *     FreeBSD) SIGKILL to every remaining descendant until none is left.
 * Nothing depends on a signal reaching the CLIENT, so a host that blocks or
 * ignores signals (the BEAM, the JVM, Julia) gets the same guarantee.
 *
 * The supervisor is a fork of the client WITHOUT an exec (there is no
 * supervisor binary to ship with 30 bindings). The client may be
 * multithreaded, so after fork only async-signal-safe calls are made: no
 * malloc, no stdio, no locks. Everything that allocates happens before the
 * first fork.
 *
 * Windows shape: CreateProcess, suspended, into a Job Object with
 * JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE, then resumed. The client holds the only
 * handle to the job, so when the client process ends, however it ends, the
 * kernel closes the handle and kills every process in the job. The job is
 * named after the driver pid so reap(pid) can find it with no handle.
 */

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct SelProcTree {
    int driver_pid;   /* the driver; on POSIX also its process group id */
    int sup_pid;      /* POSIX: the supervisor; 0 on Windows */
    int status_fd;    /* POSIX: read end of the supervisor's status pipe; EOF = supervisor gone */
    void* job;        /* Windows: the Job Object handle */
    void* proc;       /* Windows: the driver's process handle */
} SelProcTree;

/* Split "a\nb\nc" into a NULL-terminated argv after argv0. Returns NULL on OOM. */
static char** split_args(const char* prog, const char* args_nl) {
    size_t n = 2;
    for (const char* p = args_nl; p && *p; p++) if (*p == '\n') n++;
    char** argv = (char**)calloc(n + 1, sizeof(char*));
    if (!argv) return NULL;
    size_t i = 0;
    argv[i++] = strdup(prog);
    if (args_nl && *args_nl) {
        const char* s = args_nl;
        for (;;) {
            const char* e = strchr(s, '\n');
            size_t len = e ? (size_t)(e - s) : strlen(s);
            char* a = (char*)malloc(len + 1);
            if (!a) break;
            memcpy(a, s, len);
            a[len] = 0;
            argv[i++] = a;
            if (!e) break;
            s = e + 1;
        }
    }
    argv[i] = NULL;
    return argv;
}

static void free_args(char** argv) {
    if (!argv) return;
    for (size_t i = 0; argv[i]; i++) free(argv[i]);
    free(argv);
}

#if defined(_WIN32)

#include <windows.h>
#include <stdio.h>

/* Quote one argument the way CommandLineToArgvW reads it back. */
static size_t win_quote(char* out, const char* a) {
    size_t o = 0;
    int needs = (*a == 0) || strpbrk(a, " \t\"") != NULL;
    if (!needs) {
        size_t n = strlen(a);
        if (out) memcpy(out, a, n);
        return n;
    }
    if (out) out[o] = '"';
    o++;
    for (const char* p = a;; p++) {
        size_t bs = 0;
        while (*p == '\\') { bs++; p++; }
        if (*p == 0) {
            for (size_t k = 0; k < bs * 2; k++) { if (out) out[o] = '\\'; o++; }
            break;
        }
        if (*p == '"') {
            for (size_t k = 0; k < bs * 2 + 1; k++) { if (out) out[o] = '\\'; o++; }
        } else {
            for (size_t k = 0; k < bs; k++) { if (out) out[o] = '\\'; o++; }
        }
        if (out) out[o] = *p;
        o++;
    }
    if (out) out[o] = '"';
    o++;
    return o;
}

static void job_name(char* buf, size_t n, int pid) {
    snprintf(buf, n, "Local\\selaenium-driver-%d", pid);
}

void* sel_proctree_spawn(const char* prog, const char* args_nl, const char* log_path, int grace_ms) {
    (void)grace_ms;
    if (!prog || !*prog || !log_path) return NULL;
    char** argv = split_args(prog, args_nl);
    if (!argv) return NULL;
    size_t len = 1;
    for (size_t i = 0; argv[i]; i++) len += win_quote(NULL, argv[i]) + 1;
    char* cmd = (char*)malloc(len);
    if (!cmd) { free_args(argv); return NULL; }
    size_t o = 0;
    for (size_t i = 0; argv[i]; i++) {
        if (i) cmd[o++] = ' ';
        o += win_quote(cmd + o, argv[i]);
    }
    cmd[o] = 0;
    free_args(argv);

    SECURITY_ATTRIBUTES sa;
    memset(&sa, 0, sizeof sa);
    sa.nLength = sizeof sa;
    sa.bInheritHandle = TRUE;
    HANDLE logh = CreateFileA(log_path, GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                              &sa, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    HANDLE nul = CreateFileA("NUL", GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, &sa, OPEN_EXISTING, 0, NULL);
    if (logh == INVALID_HANDLE_VALUE) { free(cmd); if (nul != INVALID_HANDLE_VALUE) CloseHandle(nul); return NULL; }

    STARTUPINFOA si;
    memset(&si, 0, sizeof si);
    si.cb = sizeof si;
    si.dwFlags = STARTF_USESTDHANDLES;
    si.hStdInput = nul;
    si.hStdOutput = logh;
    si.hStdError = logh;
    PROCESS_INFORMATION pi;
    memset(&pi, 0, sizeof pi);
    /* A bare name is left to CreateProcess's own search of the command line. */
    const char* app = (strchr(prog, '\\') || strchr(prog, '/')) ? prog : NULL;
    BOOL ok = CreateProcessA(app, cmd, NULL, NULL, TRUE, CREATE_SUSPENDED | CREATE_NO_WINDOW,
                             NULL, NULL, &si, &pi);
    free(cmd);
    CloseHandle(logh);
    if (nul != INVALID_HANDLE_VALUE) CloseHandle(nul);
    if (!ok) return NULL;

    char name[64];
    job_name(name, sizeof name, (int)pi.dwProcessId);
    HANDLE job = CreateJobObjectA(NULL, name);
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION li;
    memset(&li, 0, sizeof li);
    li.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
                                        | JOB_OBJECT_LIMIT_DIE_ON_UNHANDLED_EXCEPTION;
    if (!job || !SetInformationJobObject(job, JobObjectExtendedLimitInformation, &li, sizeof li)
             || !AssignProcessToJobObject(job, pi.hProcess)) {
        /* No job, no guarantee: refuse rather than run a driver that can outlive us. */
        TerminateProcess(pi.hProcess, 1);
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
        if (job) CloseHandle(job);
        return NULL;
    }
    ResumeThread(pi.hThread);
    CloseHandle(pi.hThread);

    SelProcTree* t = (SelProcTree*)calloc(1, sizeof *t);
    if (!t) { TerminateJobObject(job, 1); CloseHandle(job); CloseHandle(pi.hProcess); return NULL; }
    t->driver_pid = (int)pi.dwProcessId;
    t->status_fd = -1;
    t->job = job;
    t->proc = pi.hProcess;
    return t;
}

int sel_proctree_pid(void* h) { return h ? ((SelProcTree*)h)->driver_pid : -1; }

int sel_proctree_alive(void* h) {
    if (!h) return 0;
    return WaitForSingleObject((HANDLE)((SelProcTree*)h)->proc, 0) == WAIT_TIMEOUT;
}

/* Windows has no SIGTERM to offer a driver first; ending the job is the stop. */
void sel_proctree_stop(void* h) {
    if (!h) return;
    SelProcTree* t = (SelProcTree*)h;
    TerminateJobObject((HANDLE)t->job, 1);
    WaitForSingleObject((HANDLE)t->proc, 10000);
    CloseHandle((HANDLE)t->proc);
    CloseHandle((HANDLE)t->job);
    free(t);
}

/* release(): keep the job handle open on purpose. It is what keeps the tree
 * alive for the rest of this process's life, and what kills it when the
 * process ends. reap(pid) ends it earlier by name. */
void sel_proctree_forget(void* h) {
    if (!h) return;
    SelProcTree* t = (SelProcTree*)h;
    CloseHandle((HANDLE)t->proc);
    free(t);
}

void sel_proctree_reap(int pid, int grace_ms) {
    (void)grace_ms;
    if (pid <= 0) return;
    char name[64];
    job_name(name, sizeof name, pid);
    HANDLE job = OpenJobObjectA(JOB_OBJECT_TERMINATE, FALSE, name);
    if (job) {
        TerminateJobObject(job, 1);
        CloseHandle(job);
        return;
    }
    HANDLE p = OpenProcess(PROCESS_TERMINATE | SYNCHRONIZE, FALSE, (DWORD)pid);
    if (p) {
        TerminateProcess(p, 1);
        WaitForSingleObject(p, 10000);
        CloseHandle(p);
    }
}

/* What this platform guarantees, for the doc and the tests. */
const char* sel_proctree_guarantee(void) {
    return "job-object: stop ends the whole job; the job is killed when the client process ends";
}

#else /* POSIX */

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#if defined(__linux__)
#include <sys/prctl.h>
#include <sys/syscall.h>
#ifndef SYS_pidfd_open
#define SYS_pidfd_open 434
#endif
#endif
#if defined(__APPLE__) || defined(__FreeBSD__) || defined(__NetBSD__) || defined(__OpenBSD__) || defined(__DragonFly__)
#define SEL_HAVE_KQUEUE 1
#include <sys/event.h>
#endif
#if defined(__FreeBSD__)
#include <sys/procctl.h>
#endif

extern char** environ;

/* Status record the supervisor writes once the driver has exec'd (or failed). */
typedef struct {
    int32_t err;        /* 0, or the errno of the failed exec/fork */
    int32_t driver_pid;
    int32_t sup_pid;
} SupStatus;

/* Set by the supervisor's SIGTERM handler. A signal handler can only reach a
 * static, and this one only ever means anything inside a supervisor process
 * (a fork): the client's copy is never written or read. */
static volatile sig_atomic_t g_sup_term = 0;

static void sup_on_term(int sig) { (void)sig; g_sup_term = 1; }

static int64_t now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static void nap_ms(int ms) {
    struct timespec ts = { ms / 1000, (long)(ms % 1000) * 1000000L };
    while (nanosleep(&ts, &ts) < 0 && errno == EINTR) {}
}

static void reset_signals(void) {
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = SIG_DFL;
    sigemptyset(&sa.sa_mask);
    for (int s = 1; s < 65; s++) {
        if (s == SIGKILL || s == SIGSTOP) continue;
        sigaction(s, &sa, NULL);
    }
    sigset_t none;
    sigemptyset(&none);
    sigprocmask(SIG_SETMASK, &none, NULL);
}

static int write_all(int fd, const void* buf, size_t n) {
    const char* p = (const char*)buf;
    while (n > 0) {
        ssize_t w = write(fd, p, n);
        if (w < 0) { if (errno == EINTR) continue; return -1; }
        p += w;
        n -= (size_t)w;
    }
    return 0;
}

static void close_from(int lo, int keep_a, int keep_b) {
#if defined(__linux__)
    /* close_range (Linux 5.9) also reaches descriptors above the 65536 cap the
     * loop below uses, which a JVM with a raised RLIMIT_NOFILE can hold. */
    {
        int a = keep_a < keep_b ? keep_a : keep_b;
        int b = keep_a < keep_b ? keep_b : keep_a;
        unsigned int from = (unsigned int)lo;
        int ok = 1;
        int keeps[2] = { a, b };
        for (int k = 0; k < 2 && ok; k++) {
            if (keeps[k] < lo) continue;
            if ((unsigned int)keeps[k] > from &&
                syscall(436 /* SYS_close_range */, from, (unsigned int)keeps[k] - 1, 0) != 0) ok = 0;
            from = (unsigned int)keeps[k] + 1;
        }
        if (ok && syscall(436, from, ~0U, 0) == 0) return;
    }
#endif
    int hi = (int)sysconf(_SC_OPEN_MAX);
    if (hi <= 0 || hi > 65536) hi = 65536;
    for (int fd = lo; fd < hi; fd++) {
        if (fd == keep_a || fd == keep_b) continue;
        close(fd);
    }
}

/* Reap every child that has exited. Returns 1 if `driver` was among them. */
static int reap_children(pid_t driver) {
    int got_driver = 0;
    for (;;) {
        int st;
        pid_t r = waitpid(-1, &st, WNOHANG);
        if (r <= 0) break;
        if (r == driver) got_driver = 1;
    }
    return got_driver;
}

static int group_alive(pid_t pg) {
    return kill(-pg, 0) == 0 || errno == EPERM;
}

#if defined(__linux__)
/* Parse /proc/self/task/<pid>/children (a space-separated pid list) and send
 * `sig` to each. Async-signal-safe: open/read/close and hand-rolled parsing.
 * Returns how many pids were signalled. */
static int signal_children(int sig) {
    char path[64] = "/proc/self/task/";
    char num[16];
    int n = 0;
    pid_t me = getpid();
    do { num[n++] = (char)('0' + me % 10); me /= 10; } while (me > 0);
    size_t o = strlen(path);
    while (n > 0) path[o++] = num[--n];
    memcpy(path + o, "/children", 10);
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return 0;
    char buf[4096];
    int count = 0;
    long cur = -1;
    for (;;) {
        ssize_t r = read(fd, buf, sizeof buf);
        if (r < 0) { if (errno == EINTR) continue; break; }
        if (r == 0) break;
        for (ssize_t i = 0; i < r; i++) {
            char c = buf[i];
            if (c >= '0' && c <= '9') {
                cur = (cur < 0 ? 0 : cur) * 10 + (c - '0');
            } else if (cur > 0) {
                kill((pid_t)cur, sig);
                count++;
                cur = -1;
            }
        }
    }
    if (cur > 0) { kill((pid_t)cur, sig); count++; }
    close(fd);
    return count;
}
#endif

/* Take the driver's whole tree down: SIGTERM to its group, up to grace_ms for
 * the group to empty, SIGKILL to the group, then every descendant that left
 * the group (re-parented to us as subreaper) until we have no children. */
static void teardown(pid_t driver, int grace_ms) {
    kill(-driver, SIGTERM);
    int64_t deadline = now_ms() + grace_ms;
    while (now_ms() < deadline) {
        reap_children(driver);
        if (!group_alive(driver)) break;
        nap_ms(20);
    }
    kill(-driver, SIGKILL);
#if defined(__FreeBSD__)
    {
        struct procctl_reaper_kill rk;
        memset(&rk, 0, sizeof rk);
        rk.rk_sig = SIGKILL;
        procctl(P_PID, getpid(), PROC_REAP_KILL, &rk);
    }
#endif
    /* Linux/FreeBSD: our children now are the driver (if not yet reaped) and
     * any descendant whose parent died. Kill and reap until there are none.
     * Bounded, so a process stuck in uninterruptible sleep cannot hang us. */
    int64_t until = now_ms() + 10000;
    while (now_ms() < until) {
#if defined(__linux__)
        signal_children(SIGKILL);
#endif
        int st;
        pid_t r = waitpid(-1, &st, WNOHANG);
        if (r < 0 && errno == ECHILD) break;
        if (r == 0) nap_ms(10);
    }
}

/* The supervisor's life. Never returns. */
static void supervise(pid_t client, char** argv, int log_fd, int status_fd, int grace_ms) {
    reset_signals();
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = sup_on_term;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGTERM, &sa, NULL);
    sa.sa_handler = SIG_IGN;
    sigaction(SIGPIPE, &sa, NULL);
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGHUP, &sa, NULL);
    setpgid(0, 0);

    int nul = open("/dev/null", O_RDWR);
    if (nul >= 0) { dup2(nul, 0); dup2(nul, 1); dup2(nul, 2); if (nul > 2) close(nul); }
    close_from(3, log_fd, status_fd);

#if defined(__linux__)
    prctl(PR_SET_CHILD_SUBREAPER, 1, 0, 0, 0);
#elif defined(__FreeBSD__)
    procctl(P_PID, getpid(), PROC_REAP_ACQUIRE, NULL);
#endif

    /* Watch the client. It is alive right now: it is blocked reading status_fd. */
    int watch_fd = -1;
#if defined(__linux__)
    watch_fd = (int)syscall(SYS_pidfd_open, (int)client, 0);
#elif defined(SEL_HAVE_KQUEUE)
    watch_fd = kqueue();
    if (watch_fd >= 0) {
        struct kevent kev;
        EV_SET(&kev, (uintptr_t)client, EVFILT_PROC, EV_ADD | EV_ONESHOT, NOTE_EXIT, 0, NULL);
        if (kevent(watch_fd, &kev, 1, NULL, 0, NULL) < 0) {
            close(watch_fd);
            watch_fd = -1;
        }
    }
#endif

    int exec_pipe[2];
    SupStatus st = { 0, 0, (int32_t)getpid() };
    if (pipe(exec_pipe) != 0) {
        st.err = errno;
        write_all(status_fd, &st, sizeof st);
        _exit(1);
    }
    fcntl(exec_pipe[1], F_SETFD, FD_CLOEXEC);
    pid_t driver = fork();
    if (driver < 0) {
        st.err = errno;
        write_all(status_fd, &st, sizeof st);
        _exit(1);
    }
    if (driver == 0) {
        reset_signals();
        setpgid(0, 0);
        close(exec_pipe[0]);
        close(status_fd);
        if (watch_fd >= 0) close(watch_fd);
        if (log_fd >= 0) { dup2(log_fd, 1); dup2(log_fd, 2); if (log_fd > 2) close(log_fd); }
        execve(argv[0], argv, environ);
        int e = errno;
        write_all(exec_pipe[1], &e, sizeof e);
        _exit(127);
    }
    setpgid(driver, driver);
    close(exec_pipe[1]);
    if (log_fd >= 0) close(log_fd);
    int exec_err = 0;
    for (;;) {
        ssize_t r = read(exec_pipe[0], &exec_err, sizeof exec_err);
        if (r < 0 && errno == EINTR) continue;
        if (r <= 0) exec_err = 0;
        break;
    }
    close(exec_pipe[0]);
    st.err = exec_err;
    st.driver_pid = (int32_t)driver;
    write_all(status_fd, &st, sizeof st);
    if (exec_err) {
        int s;
        waitpid(driver, &s, 0);
        _exit(1);
    }

    /* Wait for one of: the client died, a stop request, the driver exited. */
    for (;;) {
        if (g_sup_term) break;
        if (reap_children(driver)) break;
        int client_gone = 0;
        if (watch_fd >= 0) {
            struct pollfd p = { watch_fd, POLLIN, 0 };
            int r = poll(&p, 1, 250);
            if (r > 0) client_gone = 1;
        } else {
            nap_ms(250);
            if (kill(client, 0) < 0 && errno == ESRCH) client_gone = 1;
        }
        if (client_gone) break;
    }
    teardown(driver, grace_ms);
    /* status_fd closes with us: EOF tells a waiting stop() the tree is gone. */
    _exit(0);
}

/* A bare program name resolved on PATH, before any fork (it allocates).
 * Returns a malloc'd path, or NULL when nothing executable is found. */
static char* resolve_on_path(const char* prog) {
    if (strchr(prog, '/')) return strdup(prog);
    const char* path = getenv("PATH");
    if (!path) path = "/usr/bin:/bin";
    size_t plen = strlen(prog);
    for (const char* s = path;;) {
        const char* e = strchr(s, ':');
        size_t dlen = e ? (size_t)(e - s) : strlen(s);
        char* cand = (char*)malloc(dlen + plen + 2);
        if (!cand) return NULL;
        if (dlen == 0) { cand[0] = '.'; dlen = 1; } else memcpy(cand, s, dlen);
        cand[dlen] = '/';
        memcpy(cand + dlen + 1, prog, plen + 1);
        if (access(cand, X_OK) == 0) return cand;
        free(cand);
        if (!e) break;
        s = e + 1;
    }
    return NULL;
}

void* sel_proctree_spawn(const char* prog, const char* args_nl, const char* log_path, int grace_ms) {
    if (!prog || !*prog || !log_path) return NULL;
    if (grace_ms < 0) grace_ms = 0;
    char* exe = resolve_on_path(prog);
    if (!exe) return NULL;
    char** argv = split_args(exe, args_nl);
    free(exe);
    if (!argv) return NULL;
    SelProcTree* t = (SelProcTree*)calloc(1, sizeof *t);
    if (!t) { free_args(argv); return NULL; }
    int log_fd = open(log_path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
    if (log_fd < 0) { free(t); free_args(argv); return NULL; }
    int sp[2];
    if (pipe(sp) != 0) { close(log_fd); free(t); free_args(argv); return NULL; }
    fcntl(sp[0], F_SETFD, FD_CLOEXEC);
    fcntl(sp[1], F_SETFD, FD_CLOEXEC);
    pid_t client = getpid();

    pid_t mid = fork();
    if (mid < 0) { close(sp[0]); close(sp[1]); close(log_fd); free(t); free_args(argv); return NULL; }
    if (mid == 0) {
        close(sp[0]);
        pid_t sup = fork();
        if (sup == 0) supervise(client, argv, log_fd, sp[1], grace_ms);
        if (sup < 0) {
            SupStatus st = { errno ? errno : EAGAIN, 0, 0 };
            write_all(sp[1], &st, sizeof st);
        }
        _exit(0);
    }
    close(sp[1]);
    close(log_fd);
    free_args(argv);
    {
        int s;
        while (waitpid(mid, &s, 0) < 0 && errno == EINTR) {}
        /* ECHILD here means the host ignores SIGCHLD (the BEAM): already reaped. */
    }
    SupStatus st;
    memset(&st, 0, sizeof st);
    size_t got = 0;
    while (got < sizeof st) {
        ssize_t r = read(sp[0], (char*)&st + got, sizeof st - got);
        if (r < 0 && errno == EINTR) continue;
        if (r <= 0) break;
        got += (size_t)r;
    }
    if (got < sizeof st || st.err != 0 || st.driver_pid <= 0) {
        close(sp[0]);
        free(t);
        return NULL;
    }
    t->driver_pid = st.driver_pid;
    t->sup_pid = st.sup_pid;
    t->status_fd = sp[0];
    return t;
}

int sel_proctree_pid(void* h) { return h ? ((SelProcTree*)h)->driver_pid : -1; }

int sel_proctree_alive(void* h) {
    if (!h) return 0;
    return group_alive((pid_t)((SelProcTree*)h)->driver_pid);
}

/* Wait until fd reads EOF (the supervisor exited), at most ms. 1 = EOF seen. */
static int wait_eof(int fd, int ms) {
    int64_t deadline = now_ms() + ms;
    for (;;) {
        int64_t left = deadline - now_ms();
        if (left < 0) return 0;
        struct pollfd p = { fd, POLLIN, 0 };
        int r = poll(&p, 1, (int)left);
        if (r < 0) { if (errno == EINTR) continue; return 0; }
        if (r == 0) return 0;
        char b[64];
        ssize_t n = read(fd, b, sizeof b);
        if (n == 0) return 1;
        if (n < 0 && errno != EINTR && errno != EAGAIN) return 1;
    }
}

/* Ask the supervisor to take the tree down, and wait until it has. If the
 * supervisor itself is gone or stuck, do the group kill from here. */
void sel_proctree_stop(void* h, int grace_ms) {
    if (!h) return;
    SelProcTree* t = (SelProcTree*)h;
    if (grace_ms < 0) grace_ms = 0;
    /* EOF already means the supervisor is gone (the driver exited and it
     * cleaned up): do not signal a pid that may since have been reused. */
    if (wait_eof(t->status_fd, 0)) {
        close(t->status_fd);
        free(t);
        return;
    }
    kill((pid_t)t->sup_pid, SIGTERM);
    if (!wait_eof(t->status_fd, grace_ms + 12000)) {
        kill(-(pid_t)t->driver_pid, SIGKILL);
        kill((pid_t)t->sup_pid, SIGKILL);
    }
    close(t->status_fd);
    free(t);
}

/* release(): free the handle; the tree keeps running until reap(pid), until the
 * driver exits, or until this process dies, whichever is first. */
void sel_proctree_forget(void* h) {
    if (!h) return;
    SelProcTree* t = (SelProcTree*)h;
    close(t->status_fd);
    free(t);
}

/* reap(pid) for a released driver: SIGTERM its group; the supervisor sees the
 * driver exit and finishes the tree. Escalate to SIGKILL after grace_ms, and
 * return once the group is empty (or after a bound). */
void sel_proctree_reap(int pid, int grace_ms) {
    if (pid <= 0) return;
    if (grace_ms < 0) grace_ms = 0;
    kill(-(pid_t)pid, SIGTERM);
    int64_t deadline = now_ms() + grace_ms;
    while (now_ms() < deadline && group_alive((pid_t)pid)) nap_ms(20);
    if (group_alive((pid_t)pid)) kill(-(pid_t)pid, SIGKILL);
    int64_t until = now_ms() + 5000;
    while (now_ms() < until && group_alive((pid_t)pid)) nap_ms(20);
}

const char* sel_proctree_guarantee(void) {
#if defined(__linux__)
    return "linux: process group + child subreaper + pidfd client watch";
#elif defined(__FreeBSD__)
    return "freebsd: process group + procctl reaper (PROC_REAP_KILL) + kqueue client watch";
#elif defined(SEL_HAVE_KQUEUE)
    return "kqueue: process group + kqueue client watch; descendants that leave the group are not covered";
#else
    return "posix: process group + polled client watch; descendants that leave the group are not covered";
#endif
}

#endif
