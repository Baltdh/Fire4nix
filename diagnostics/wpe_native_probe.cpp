// Fire4Nix R36H: separate ARM64 WPE WebKit diagnostic executable.
// Intentional dlopen: avoids linking to a mismatched WebKit on the GitHub runner.
// This program is NOT a replacement for the main Fire4Nix browser.
#include <glib.h>
#include <glib-object.h>
#include <dlfcn.h>
#include <execinfo.h>
#include <signal.h>
#include <unistd.h>
#include <cstdio>
#include <cstring>
#include <cstdlib>

static volatile sig_atomic_t stage = 0;
static void onFatal(int signum) {
    const char* prefix = "\nFire4Nix WPE probe: fatal signal, backtrace follows\n";
    const ssize_t written = write(STDERR_FILENO, prefix, strlen(prefix));
    (void)written;
    void* stack[48];
    int n = backtrace(stack, 48);
    backtrace_symbols_fd(stack, n, STDERR_FILENO);
    _exit(128 + signum);
}
static void onAlarm(int) {
    const char* line = "Fire4Nix WPE probe: 30s timeout without exit (not proof of rendering)\n";
    const ssize_t written = write(STDERR_FILENO, line, strlen(line));
    (void)written;
    _exit(124);
}
static void stageLog(int n, const char* s) {
    stage = n;
    fprintf(stderr, "[WPE-PROBE] stage=%d %s\n", n, s);
    fflush(stderr);
}
static void onLoadChanged(GObject*, int event, gpointer) {
    fprintf(stderr, "[WPE-PROBE] load-changed event=%d\n", event);
    fflush(stderr);
}
int main(int argc, char** argv) {
    if (argc > 1 && (!strcmp(argv[1], "--help") || !strcmp(argv[1], "-h"))) {
        puts("Fire4Nix WPE ARM64 probe: --selftest | --check-library | --check-view | --load [URL]");
        return 0;
    }
    if (argc > 1 && !strcmp(argv[1], "--selftest")) {
        printf("arch=%s glib=%u.%u.%u\n",
#ifdef __aarch64__
               "aarch64",
#else
               "NOT-AARCH64",
#endif
               glib_major_version, glib_minor_version, glib_micro_version);
        return 0;
    }
    struct sigaction sa{};
    sa.sa_handler = onFatal;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_RESETHAND;
    sigaction(SIGSEGV, &sa, nullptr);
    sigaction(SIGABRT, &sa, nullptr);
    signal(SIGALRM, onAlarm);
    alarm(30);

    stageLog(1, "before dlopen");
    void* lib = dlopen("libWPEWebKit-2.0.so.1", RTLD_NOW | RTLD_GLOBAL);
    if (!lib) {
        fprintf(stderr, "[WPE-PROBE] dlopen error: %s\n", dlerror());
        return 127;
    }
    stageLog(2, "after dlopen: WPE shared library loaded");
    if (argc > 1 && !strcmp(argv[1], "--check-library")) return 0;

    using GetType = GType (*)();
    using LoadUri = void (*)(gpointer, const char*);
    auto getType = reinterpret_cast<GetType>(dlsym(lib, "webkit_web_view_get_type"));
    auto loadUri = reinterpret_cast<LoadUri>(dlsym(lib, "webkit_web_view_load_uri"));
    if (!getType || !loadUri) {
        fprintf(stderr, "[WPE-PROBE] WebKit symbols missing: getType=%p loadUri=%p\n",
                reinterpret_cast<void*>(getType), reinterpret_cast<void*>(loadUri));
        return 127;
    }
    stageLog(3, "before WebKitWebView type registration");
    GType type = getType();
    if (!type) {
        fprintf(stderr, "[WPE-PROBE] WebKitWebView GType unavailable\n");
        return 3;
    }
    stageLog(4, "before WebKitWebView construction / platform selection");
    GObject* view = static_cast<GObject*>(g_object_new(type, nullptr));
    if (!view) {
        fprintf(stderr, "[WPE-PROBE] WebKitWebView construction returned NULL\n");
        return 3;
    }
    stageLog(5, "after WebKitWebView construction");
    if (argc > 1 && !strcmp(argv[1], "--check-view")) {
        g_object_unref(view);
        return 0;
    }

    const char* uri = "about:blank";
    if (argc > 2 && !strcmp(argv[1], "--load")) uri=argv[2];
    else if (argc > 1 && strncmp(argv[1], "--", 2)) uri=argv[1];
    fprintf(stderr, "[WPE-PROBE] url=%s\n", uri);
    g_signal_connect(view, "load-changed", G_CALLBACK(onLoadChanged), nullptr);
    stageLog(6, "before load_uri");
    loadUri(view, uri);
    stageLog(7, "after load_uri, entering GLib event loop");
    GMainLoop* loop = g_main_loop_new(nullptr, FALSE);
    g_main_loop_run(loop);
    stageLog(8, "GLib loop exited");
    g_main_loop_unref(loop);
    g_object_unref(view);
    return 0;
}
