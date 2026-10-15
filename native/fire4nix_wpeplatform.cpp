// Fire4Nix R36H v0.86 - optional native WPEPlatform launcher, not a replacement.
// Build on AArch64 Linux against GLib/GObject; load the *user-installed* WPE2.0
// runtime with dlopen. Never pull GTK/Qt libraries into the launcher.
#include <glib.h>
#include <glib-object.h>
#include <glib-unix.h>
#include <dlfcn.h>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace {
using LoadUri = void (*)(gpointer, const char*);
using GetType = GType (*)();
using SetSettings = void (*)(gpointer, gpointer);
using GetUri = const char* (*)(gpointer);

struct App {
    GMainLoop* loop = nullptr;
    GObject* view = nullptr;
    void* webkit = nullptr;
    LoadUri loadUri = nullptr;
    GetUri getUri = nullptr;
    bool smoke = false;
    bool loaded = false;
    bool failed = false;
    int exitCode = 0;
    const char* initialUrl = nullptr;
};

static bool setting(GObject* obj, const char* name, gboolean enabled) {
    if (!obj) return false;
    GParamSpec* spec = g_object_class_find_property(G_OBJECT_GET_CLASS(obj), name);
    if (!spec || !G_IS_PARAM_SPEC_BOOLEAN(spec) || !(spec->flags & G_PARAM_WRITABLE)) return false;
    g_object_set(obj, name, enabled, nullptr);
    return true;
}
static bool lowMemory() {
    const char* v = g_getenv("FIRE4NIX_LOW_MEMORY");
    return !v || (strcmp(v, "0") && g_ascii_strcasecmp(v, "false") && g_ascii_strcasecmp(v, "off"));
}
static void stage(const char* name) {
    g_printerr("[FIRE4NIX-NATIVE] %s\n", name);
}
static gboolean timeoutQuit(gpointer data) {
    App* app = static_cast<App*>(data);
    stage("smoke timeout; no confirmed page load");
    app->exitCode = 124;
    if (app->loop) g_main_loop_quit(app->loop);
    return G_SOURCE_REMOVE;
}
static gboolean signalQuit(gpointer data) {
    App* app = static_cast<App*>(data);
    stage("received SIGINT/SIGTERM, closing cleanly");
    if (app->loop) g_main_loop_quit(app->loop);
    return G_SOURCE_REMOVE;
}
static gboolean smokeQuit(gpointer data) {
    App* app = static_cast<App*>(data);
    if (app->loop) g_main_loop_quit(app->loop);
    return G_SOURCE_REMOVE;
}
static void loadChanged(GObject*, int event, gpointer data) {
    App* app = static_cast<App*>(data);
    const char* url = app->getUri ? app->getUri(app->view) : nullptr;
    g_printerr("[FIRE4NIX-NATIVE] load-event=%d url=%s\n", event, url ? url : "(pending)");
    // WebKitLoadEvent: STARTED=0, REDIRECTED=1, COMMITTED=2, FINISHED=3.
    if (event == 3) {
        app->loaded = true;
        if (app->smoke) {
            app->exitCode = app->failed ? 3 : 0;
            g_idle_add(smokeQuit, app);
        }
    }
}
static gboolean loadFailed(GObject*, int, const char* url, GError* error, gpointer data) {
    App* app = static_cast<App*>(data);
    app->failed = true;
    g_printerr("[FIRE4NIX-NATIVE] load-failed url=%s error=%s\n",
               url ? url : "(unknown)", error ? error->message : "unknown");
    if (app->smoke) { app->exitCode = 3; g_idle_add(smokeQuit, app); }
    return FALSE;  // normal WebKit error handling; do not silently ignore TLS failures
}
static void childTerminated(GObject*, int reason, gpointer data) {
    App* app = static_cast<App*>(data);
    app->failed = true;
    g_printerr("[FIRE4NIX-NATIVE] web-process-terminated reason=%d\n", reason);
    if (app->smoke) { app->exitCode = 139; g_idle_add(smokeQuit, app); }
}
static gboolean closeView(GObject*, gpointer data) {
    App* app = static_cast<App*>(data);
    if (app->loop) g_main_loop_quit(app->loop);
    return TRUE;
}
static void titleChanged(GObject* object, GParamSpec*, gpointer) {
    gchar* title = nullptr;
    g_object_get(object, "title", &title, nullptr);
    if (title) { g_printerr("[FIRE4NIX-NATIVE] title=%s\n", title); g_free(title); }
}
template <typename T> T symbol(void* library, const char* name) {
    dlerror();
    void* pointer = dlsym(library, name);
    const char* error = dlerror();
    if (error) g_printerr("[FIRE4NIX-NATIVE] missing symbol %s: %s\n", name, error);
    return reinterpret_cast<T>(pointer);
}
}

int main(int argc, char** argv) {
    if (argc > 1 && (!strcmp(argv[1], "--help") || !strcmp(argv[1], "-h"))) {
        puts("Fire4Nix native WPEPlatform 0.86: [--selftest|--check-library|--smoke] [URL]");
        return 0;
    }
    if (argc > 1 && !strcmp(argv[1], "--selftest")) {
#if defined(__aarch64__)
        puts("fire4nix-native AArch64 selftest OK");
#else
        puts("fire4nix-native NON-AARCH64 selftest OK");
#endif
        return 0;
    }
    const bool onlyLibrary = argc > 1 && !strcmp(argv[1], "--check-library");
    const bool smoke = argc > 1 && !strcmp(argv[1], "--smoke");
    const char* url = "about:blank";
    for (int i=1; i<argc; ++i) {
        if (strcmp(argv[i],"--check-library") && strcmp(argv[i],"--smoke") &&
            argv[i][0] != '-') { url=argv[i]; break; }
    }
    stage("dlopen libWPEWebKit-2.0.so.1");
    App app;
    app.smoke = smoke;
    app.initialUrl = url;
    app.webkit = dlopen("libWPEWebKit-2.0.so.1", RTLD_NOW | RTLD_GLOBAL);
    if (!app.webkit) {
        g_printerr("[FIRE4NIX-NATIVE] loader error: %s\n", dlerror());
        return 127;
    }
    stage("dlopen success");
    if (onlyLibrary) return 0;
    auto webViewType = symbol<GetType>(app.webkit, "webkit_web_view_get_type");
    app.loadUri = symbol<LoadUri>(app.webkit, "webkit_web_view_load_uri");
    app.getUri = symbol<GetUri>(app.webkit, "webkit_web_view_get_uri");
    auto settingsType = symbol<GetType>(app.webkit, "webkit_settings_get_type");
    auto assignSettings = symbol<SetSettings>(app.webkit, "webkit_web_view_set_settings");
    if (!webViewType || !app.loadUri) return 127;

    app.loop = g_main_loop_new(nullptr, FALSE);
    stage("creating WebKitWebView via GObject/WPEPlatform");
    // WPE 2.52 WPEPlatform: the GObject constructor initializes display.
    // The old webkit_web_view_new_with_context() is a legacy backend API.
    app.view = static_cast<GObject*>(g_object_new(webViewType(), nullptr));
    if (!app.view) { stage("WebKitWebView creation failed"); return 3; }
    stage("WebKitWebView created");
    if (settingsType && assignSettings) {
        GObject* settings = static_cast<GObject*>(g_object_new(settingsType(), nullptr));
        if (settings) {
            if (lowMemory()) {
                setting(settings, "enable-webgl", FALSE);
                setting(settings, "enable-webrtc", FALSE);
                setting(settings, "enable-media-stream", FALSE);
                setting(settings, "enable-mediasource", FALSE);
                setting(settings, "enable-encrypted-media", FALSE);
                setting(settings, "enable-developer-extras", FALSE);
            }
            assignSettings(app.view, settings);
            g_object_unref(settings);
        }
    }
    if (g_signal_lookup("load-changed", G_OBJECT_TYPE(app.view)))
        g_signal_connect(app.view, "load-changed", G_CALLBACK(loadChanged), &app);
    if (g_signal_lookup("load-failed", G_OBJECT_TYPE(app.view)))
        g_signal_connect(app.view, "load-failed", G_CALLBACK(loadFailed), &app);
    if (g_signal_lookup("web-process-terminated", G_OBJECT_TYPE(app.view)))
        g_signal_connect(app.view, "web-process-terminated", G_CALLBACK(childTerminated), &app);
    if (g_signal_lookup("close", G_OBJECT_TYPE(app.view)))
        g_signal_connect(app.view, "close", G_CALLBACK(closeView), &app);
    g_signal_connect(app.view, "notify::title", G_CALLBACK(titleChanged), nullptr);

    g_unix_signal_add(SIGINT, signalQuit, &app);
    g_unix_signal_add(SIGTERM, signalQuit, &app);
    if (app.smoke) g_timeout_add_seconds(15, timeoutQuit, &app);
    g_printerr("[FIRE4NIX-NATIVE] mode=%s low_memory=%d url=%s platform=%s\n",
               app.smoke ? "smoke" : "interactive", lowMemory() ? 1 : 0, url,
               g_getenv("WPE_PLATFORM") ? g_getenv("WPE_PLATFORM") : "default");
    app.loadUri(app.view, url);
    stage("entering GLib main loop");
    g_main_loop_run(app.loop);
    stage("GLib main loop exited");
    g_object_unref(app.view);
    g_main_loop_unref(app.loop);
    dlclose(app.webkit);
    return app.exitCode;
}
