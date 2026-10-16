// Fire4Nix R36H v0.94 - resilient native WPEPlatform launcher.
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
using GetWPEView = gpointer (*)(gpointer);
using GetToplevel = gpointer (*)(gpointer);
using ToplevelFullscreen = gboolean (*)(gpointer);
using ToplevelSetTitle = void (*)(gpointer, const char*);
using GetEventType = int (*)(gpointer);
using GetEventModifiers = unsigned (*)(gpointer);
using GetEventKeyval = unsigned (*)(gpointer);
using NavigateAction = void (*)(gpointer);
using CanNavigate = gboolean (*)(gpointer);
using ToplevelGetState = unsigned (*)(gpointer);

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
    guint smokeTimeoutSource = 0;
    gpointer toplevel = nullptr;
    GObject* display = nullptr;
    gulong displayDisconnectedHandler = 0;
    ToplevelSetTitle setTitle = nullptr;
    GetEventType getEventType = nullptr;
    GetEventModifiers getEventModifiers = nullptr;
    GetEventKeyval getEventKeyval = nullptr;
    NavigateAction reload = nullptr;
    NavigateAction goBack = nullptr;
    NavigateAction goForward = nullptr;
    CanNavigate canGoBack = nullptr;
    CanNavigate canGoForward = nullptr;
    ToplevelGetState getToplevelState = nullptr;
    ToplevelFullscreen fullscreen = nullptr;
    ToplevelFullscreen unfullscreen = nullptr;
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
    if (app->loaded || app->failed) return G_SOURCE_REMOVE;
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
            if (!app->failed) app->exitCode = 0;
            else if (!app->exitCode) app->exitCode = 3;
            g_idle_add(smokeQuit, app);
        }
    }
}
static gboolean loadFailed(GObject*, int, const char* url, GError* error, gpointer data) {
    App* app = static_cast<App*>(data);
    app->failed = true;
    g_printerr("[FIRE4NIX-NATIVE] load-failed url=%s error=%s\n",
               url ? url : "(unknown)", error ? error->message : "unknown");
    if (!app->exitCode) app->exitCode = 3;
    if (app->smoke) g_idle_add(smokeQuit, app);
    return FALSE;  // normal WebKit error handling; do not silently ignore TLS failures
}
static void childTerminated(GObject*, int reason, gpointer data) {
    App* app = static_cast<App*>(data);
    app->failed = true;
    g_printerr("[FIRE4NIX-NATIVE] web-process-terminated reason=%d\n", reason);
    app->exitCode = 70;
    // An unexpected renderer exit in interactive mode otherwise leaves a dead page.
    g_idle_add(smokeQuit, app);
}
// WPEEventType and WPEModifiers follow the WPEPlatform public ABI.
static constexpr int keyboardDown = 7; // WPE_EVENT_KEYBOARD_KEY_DOWN
static constexpr unsigned controlModifier = 1u << 0;
static constexpr unsigned altModifier = 1u << 2;
static constexpr unsigned keyLeft = 0xff51;
static constexpr unsigned keyRight = 0xff53;
static constexpr unsigned keyF11 = 0xffc8;
static constexpr unsigned fullscreenState = 1u << 0;

static gboolean onPlatformEvent(GObject*, gpointer event, gpointer data) {
    auto* app = static_cast<App*>(data);
    if (!app || !app->getEventType || !app->getEventKeyval ||
        !app->getEventModifiers || app->getEventType(event) != keyboardDown)
        return FALSE;
    const unsigned modifiers = app->getEventModifiers(event);
    const unsigned keyval = app->getEventKeyval(event);
    if ((modifiers & controlModifier) && (keyval == 'q' || keyval == 'Q')) {
        stage("shortcut Ctrl+Q: close browser");
        if (app->loop) g_main_loop_quit(app->loop);
        return TRUE;
    }
    if ((modifiers & controlModifier) && (keyval == 'h' || keyval == 'H') && app->loadUri) {
        const char* home = g_getenv("FIRE4NIX_HOME_URL");
        if (home && *home) {
            stage("shortcut Ctrl+H: home");
            app->loadUri(app->view, home);
            return TRUE;
        }
    }
    if ((modifiers & controlModifier) && (keyval == 'r' || keyval == 'R') && app->reload) {
        stage("shortcut Ctrl+R: reload");
        app->reload(app->view);
        return TRUE;
    }
    if (modifiers & altModifier) {
        if (keyval == keyLeft && app->goBack && app->canGoBack && app->canGoBack(app->view)) {
            stage("shortcut Alt+Left: back");
            app->goBack(app->view);
            return TRUE;
        }
        if (keyval == keyRight && app->goForward && app->canGoForward && app->canGoForward(app->view)) {
            stage("shortcut Alt+Right: forward");
            app->goForward(app->view);
            return TRUE;
        }
    }
    if (keyval == keyF11 && app->toplevel && app->getToplevelState) {
        if ((app->getToplevelState(app->toplevel) & fullscreenState) && app->unfullscreen) {
            stage("shortcut F11: window mode");
            app->unfullscreen(app->toplevel);
            return TRUE;
        }
        if (app->fullscreen) {
            stage("shortcut F11: fullscreen");
            app->fullscreen(app->toplevel);
            return TRUE;
        }
    }
    return FALSE; // Other keys go to the website (forms/text inputs).
}

static void platformDisplayDisconnected(GObject*, GError* error, gpointer data) {
    App* app = static_cast<App*>(data);
    if (error)
        g_printerr("[FIRE4NIX-NATIVE] WPE display disconnected: %s\n", error->message);
    else
        stage("WPE display disconnected");
    // Do not leave an invisible but still-running browser in Ports.
    app->failed = true;
    app->exitCode = 71;
    if (app->loop) g_main_loop_quit(app->loop);
}
static void platformViewClosed(GObject*, gpointer data) {
    App* app = static_cast<App*>(data);
    stage("WPEView closed by compositor");
    if (app->loop) g_main_loop_quit(app->loop);
}
static gboolean closeView(GObject*, gpointer data) {
    App* app = static_cast<App*>(data);
    if (app->loop) g_main_loop_quit(app->loop);
    return TRUE;
}
static void titleChanged(GObject* object, GParamSpec*, gpointer data) {
    auto* app = static_cast<App*>(data);
    gchar* title = nullptr;
    g_object_get(object, "title", &title, nullptr);
    if (title) {
        g_printerr("[FIRE4NIX-NATIVE] title=%s\n", title);
        if (app && app->toplevel && app->setTitle)
            app->setTitle(app->toplevel, title);
        g_free(title);
    }
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
        puts("Fire4Nix native WPEPlatform 0.94: [--selftest|--check-library|--check-platform|--smoke] [URL]");
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
    const bool onlyPlatform = argc > 1 && !strcmp(argv[1], "--check-platform");
    const bool smoke = argc > 1 && !strcmp(argv[1], "--smoke");
    const char* url = "about:blank";
    for (int i=1; i<argc; ++i) {
        if (strcmp(argv[i],"--check-library") && strcmp(argv[i],"--check-platform") && strcmp(argv[i],"--smoke") &&
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
    if (onlyLibrary) {
        dlclose(app.webkit);
        return 0;
    }
    auto webViewType = symbol<GetType>(app.webkit, "webkit_web_view_get_type");
    auto getWPEView = symbol<GetWPEView>(app.webkit, "webkit_web_view_get_wpe_view");
    app.loadUri = symbol<LoadUri>(app.webkit, "webkit_web_view_load_uri");
    app.getUri = symbol<GetUri>(app.webkit, "webkit_web_view_get_uri");
    auto settingsType = symbol<GetType>(app.webkit, "webkit_settings_get_type");
    auto assignSettings = symbol<SetSettings>(app.webkit, "webkit_web_view_set_settings");
    if (!webViewType || !app.loadUri) {
        stage("WebKit core ABI missing; incompatible or damaged library");
        dlclose(app.webkit);
        return 127;
    }
    // The library might expose only the older libwpe backend, even when dlopen worked.
    if (!getWPEView) {
        stage("INCOMPATIBLE WPE: WPEPlatform API absent; legacy backend required");
        dlclose(app.webkit);
        return 78;
    }
    if (onlyPlatform) {
        stage("WPEPlatform symbol found (actual Wayland display still untested)");
        Dl_info providerInfo {};
        if (dladdr(reinterpret_cast<void*>(getWPEView), &providerInfo) && providerInfo.dli_fname)
            g_printerr("[FIRE4NIX-ABI] webkit_library=%s\n", providerInfo.dli_fname);
        const char* symbols[] = {
            "wpe_view_get_toplevel",
            "wpe_toplevel_fullscreen",
            "wpe_toplevel_set_title",
            "wpe_event_get_event_type",
            "wpe_event_get_modifiers",
            "wpe_event_keyboard_get_keyval",
            "webkit_web_view_reload",
            "webkit_web_view_can_go_back",
            "webkit_web_view_go_back"
        };
        for (const char* name : symbols) {
            void* found = dlsym(RTLD_DEFAULT, name);
            if (!found) found = dlsym(app.webkit, name);
            g_printerr("[FIRE4NIX-ABI] %s=%s\n", name, found ? "present" : "absent");
        }
        stage("ABI availability above is NOT a GPU/Wayland rendering test");
        dlclose(app.webkit);
        return 0;
    }

    // The upstream WPE MiniBrowser sets WebKitSettings in g_object_new().
    // Supplying settings at construction ensures low-memory flags take effect
    // before WebKit starts allocating page and media resources.
    GObject* settings = settingsType ?
        static_cast<GObject*>(g_object_new(settingsType(), nullptr)) : nullptr;
    if (settings && lowMemory()) {
        setting(settings, "enable-webgl", FALSE);
        setting(settings, "enable-webrtc", FALSE);
        setting(settings, "enable-media-stream", FALSE);
        setting(settings, "enable-mediasource", FALSE);
        setting(settings, "enable-page-cache", FALSE);
        setting(settings, "enable-webaudio", FALSE);
        setting(settings, "media-playback-requires-user-gesture", TRUE);
        setting(settings, "enable-encrypted-media", FALSE);
        setting(settings, "enable-developer-extras", FALSE);
    }
    bool settingsAtConstruction = false;
    if (settings) {
        GObjectClass* klass = static_cast<GObjectClass*>(g_type_class_ref(webViewType()));
        const GParamSpec* prop = g_object_class_find_property(klass, "settings");
        settingsAtConstruction = prop && (prop->flags & G_PARAM_WRITABLE);
        g_type_class_unref(klass);
    }
    app.loop = g_main_loop_new(nullptr, FALSE);
    stage("creating WebKitWebView via GObject/WPEPlatform");
    // WPEPlatform: the GObject constructor initializes the selected display.
    // The old webkit_web_view_new_with_context() is a legacy backend API.
    app.view = static_cast<GObject*>(settingsAtConstruction ?
        g_object_new(webViewType(), "settings", settings, nullptr) :
        g_object_new(webViewType(), nullptr));
    if (!app.view) {
        stage("WebKitWebView creation failed");
        if (settings) g_object_unref(settings);
        g_main_loop_unref(app.loop);
        dlclose(app.webkit);
        return 3;
    }
    if (settings) {
        if (!settingsAtConstruction && assignSettings)
            assignSettings(app.view, settings);
        if (!settingsAtConstruction && !assignSettings)
            stage("WebKitSettings unavailable for this WebKit ABI");
        g_object_unref(settings);
    }
    stage("WebKitWebView created");
    gpointer nativeView = getWPEView(app.view);
    if (!nativeView || !G_IS_OBJECT(nativeView)) {
        stage("WPEPlatform WPEView unavailable");
        g_object_unref(app.view);
        g_main_loop_unref(app.loop);
        return 78;
    }
    // The display/window closes via WPEView::closed (not WebKitWebView::close).
    if (g_signal_lookup("closed", G_OBJECT_TYPE(nativeView)))
        g_signal_connect(nativeView, "closed", G_CALLBACK(platformViewClosed), &app);
    stage("WPEPlatform WPEView available");
    // Match the official WPE MiniBrowser: watch the actual display, not just
    // the Wayland socket, which can remain present after a disconnect.
    using GetDisplay = gpointer (*)(gpointer);
    auto getDisplay = reinterpret_cast<GetDisplay>(dlsym(RTLD_DEFAULT, "wpe_view_get_display"));
    if (getDisplay) {
        gpointer display = getDisplay(nativeView);
        if (display && G_IS_OBJECT(display)) {
            app.display = G_OBJECT(display);
            if (g_signal_lookup("disconnected", G_OBJECT_TYPE(app.display))) {
                app.displayDisconnectedHandler = g_signal_connect(
                    app.display, "disconnected", G_CALLBACK(platformDisplayDisconnected), &app);
                stage("WPEPlatform display disconnect monitoring active");
            } else stage("WPEPlatform display lacks disconnected signal");
        } else stage("WPEPlatform display not available from WPEView");
    } else stage("WPEPlatform wpe_view_get_display unavailable");
    // The normal ROCKNIX Sway session has a single 640x480 handheld display.
    // Request compositor-managed fullscreen instead of merely opening a tile.
    auto getToplevel = reinterpret_cast<GetToplevel>(dlsym(RTLD_DEFAULT, "wpe_view_get_toplevel"));
    auto fullscreen = reinterpret_cast<ToplevelFullscreen>(dlsym(RTLD_DEFAULT, "wpe_toplevel_fullscreen"));
    app.fullscreen = fullscreen;
    app.unfullscreen = reinterpret_cast<ToplevelFullscreen>(dlsym(RTLD_DEFAULT, "wpe_toplevel_unfullscreen"));
    app.getToplevelState = reinterpret_cast<ToplevelGetState>(dlsym(RTLD_DEFAULT, "wpe_toplevel_get_state"));
    app.getEventType = reinterpret_cast<GetEventType>(dlsym(RTLD_DEFAULT, "wpe_event_get_event_type"));
    app.getEventModifiers = reinterpret_cast<GetEventModifiers>(dlsym(RTLD_DEFAULT, "wpe_event_get_modifiers"));
    app.getEventKeyval = reinterpret_cast<GetEventKeyval>(dlsym(RTLD_DEFAULT, "wpe_event_keyboard_get_keyval"));
    app.reload = symbol<NavigateAction>(app.webkit, "webkit_web_view_reload");
    app.goBack = symbol<NavigateAction>(app.webkit, "webkit_web_view_go_back");
    app.goForward = symbol<NavigateAction>(app.webkit, "webkit_web_view_go_forward");
    app.canGoBack = symbol<CanNavigate>(app.webkit, "webkit_web_view_can_go_back");
    app.canGoForward = symbol<CanNavigate>(app.webkit, "webkit_web_view_can_go_forward");
    if (g_signal_lookup("event", G_OBJECT_TYPE(nativeView)) &&
        app.getEventType && app.getEventModifiers && app.getEventKeyval)
        g_signal_connect(nativeView, "event", G_CALLBACK(onPlatformEvent), &app);
    app.setTitle = reinterpret_cast<ToplevelSetTitle>(dlsym(RTLD_DEFAULT, "wpe_toplevel_set_title"));
    if (getToplevel) {
        app.toplevel = getToplevel(nativeView);
        if (app.toplevel) {
            if (app.setTitle) app.setTitle(app.toplevel, "Fire4Nix - ROCKNIX");
            const char* fullscreenSetting = g_getenv("FIRE4NIX_FULLSCREEN");
            if (fullscreen && (!fullscreenSetting || strcmp(fullscreenSetting, "0"))) {
                fullscreen(app.toplevel);
                stage("requested WPEPlatform fullscreen");
            }
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
    g_signal_connect(app.view, "notify::title", G_CALLBACK(titleChanged), &app);

    g_unix_signal_add(SIGINT, signalQuit, &app);
    g_unix_signal_add(SIGTERM, signalQuit, &app);
    if (app.smoke) app.smokeTimeoutSource = g_timeout_add_seconds(30, timeoutQuit, &app);
    g_printerr("[FIRE4NIX-NATIVE] mode=%s low_memory=%d url=%s platform=%s\n",
               app.smoke ? "smoke" : "interactive", lowMemory() ? 1 : 0, url,
               g_getenv("WPE_PLATFORM") ? g_getenv("WPE_PLATFORM") : "default");
    app.loadUri(app.view, url);
    stage("entering GLib main loop");
    g_main_loop_run(app.loop);
    stage("GLib main loop exited");
    // Never leave callbacks referring to the stack App after the loop returns.
    if (app.smokeTimeoutSource &&
        g_main_context_find_source_by_id(nullptr, app.smokeTimeoutSource))
        g_source_remove(app.smokeTimeoutSource);
    if (app.display && app.displayDisconnectedHandler) {
        g_signal_handler_disconnect(app.display, app.displayDisconnectedHandler);
        app.displayDisconnectedHandler = 0;
    }
    g_object_unref(app.view);
    g_main_loop_unref(app.loop);
    dlclose(app.webkit);
    return app.exitCode;
}
