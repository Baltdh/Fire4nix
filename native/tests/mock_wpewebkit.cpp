// Small mock WPE WebKit 2.0 GObject ABI for *CI smoke tests only*.
// Do NOT ship this fake library inside the R36H release ZIP.
#include <glib.h>
#include <glib-object.h>
typedef struct { GObject parent; } FakeSettings;
typedef struct { GObjectClass parent_class; } FakeSettingsClass;
G_DEFINE_TYPE(FakeSettings, fake_settings, G_TYPE_OBJECT)
static void fake_settings_class_init(FakeSettingsClass*) {}
static void fake_settings_init(FakeSettings*) {}
extern "C" GType webkit_settings_get_type(void) { return fake_settings_get_type(); }
static void fake_view_set_property(GObject* obj, guint prop, const GValue* val, GParamSpec* spec)
{
    (void)obj;
    if (prop == 1 && g_value_get_object(val))
        g_printerr("[MOCK-WPE] settings supplied during webview creation\n");
    else G_OBJECT_WARN_INVALID_PROPERTY_ID(obj, prop, spec);
}
typedef struct { GObject parent; } FakeView;
typedef struct { GObjectClass parent_class; } FakeViewClass;
G_DEFINE_TYPE(FakeView, fake_view, G_TYPE_OBJECT)
static guint changed;
static guint terminated;
static guint displayDisconnected;
static guint closed;
static guint keyboardEventSignal;
struct FakeKeyEvent { int type; unsigned modifiers; unsigned keyval; };
static gboolean fullscreenEnabled = FALSE;
static void fake_view_class_init(FakeViewClass* klass) {
    auto* objectClass = G_OBJECT_CLASS(klass);
    objectClass->set_property = fake_view_set_property;
    g_object_class_install_property(objectClass, 1,
        g_param_spec_object("settings", "Settings", "Construct-only WebKit settings",
                            fake_settings_get_type(), static_cast<GParamFlags>(G_PARAM_WRITABLE | G_PARAM_CONSTRUCT_ONLY)));
    closed = g_signal_new("closed", fake_view_get_type(), G_SIGNAL_RUN_LAST,
                           0, nullptr, nullptr, nullptr, G_TYPE_NONE, 0);
    keyboardEventSignal = g_signal_new("event", fake_view_get_type(), G_SIGNAL_RUN_LAST,
                           0, g_signal_accumulator_true_handled, nullptr, nullptr,
                           G_TYPE_BOOLEAN, 1, G_TYPE_POINTER);
    displayDisconnected = g_signal_new("disconnected", fake_view_get_type(),
                          G_SIGNAL_RUN_LAST, 0, nullptr, nullptr, nullptr,
                          G_TYPE_NONE, 1, G_TYPE_ERROR);
    terminated = g_signal_new("web-process-terminated", fake_view_get_type(),
                             G_SIGNAL_RUN_LAST, 0, nullptr, nullptr, nullptr,
                             G_TYPE_NONE, 1, G_TYPE_INT);
    changed = g_signal_new("load-changed", fake_view_get_type(),
                           G_SIGNAL_RUN_LAST, 0, nullptr, nullptr, nullptr,
                           G_TYPE_NONE, 1, G_TYPE_INT);
}
static void fake_view_init(FakeView*) {}
extern "C" GType webkit_web_view_get_type(void) { return fake_view_get_type(); }
#ifndef MOCK_NO_PLATFORM
extern "C" gpointer webkit_web_view_get_wpe_view(gpointer view) { return view; }
#endif
extern "C" gpointer wpe_view_get_toplevel(gpointer view) { return view; }
extern "C" gpointer wpe_view_get_display(gpointer view) { return view; }
extern "C" gboolean wpe_toplevel_fullscreen(gpointer) {
    fullscreenEnabled = TRUE;
    g_printerr("[MOCK-WPE] fullscreen requested\n");
    return TRUE;
}
extern "C" unsigned wpe_toplevel_get_state(gpointer) { return fullscreenEnabled ? 1u : 0u; }
extern "C" gboolean wpe_toplevel_unfullscreen(gpointer) {
    fullscreenEnabled = FALSE;
    g_printerr("[MOCK-WPE] window mode requested\n");
    return TRUE;
}
extern "C" int wpe_event_get_event_type(gpointer event) { return static_cast<FakeKeyEvent*>(event)->type; }
extern "C" unsigned wpe_event_get_modifiers(gpointer event) { return static_cast<FakeKeyEvent*>(event)->modifiers; }
extern "C" unsigned wpe_event_keyboard_get_keyval(gpointer event) { return static_cast<FakeKeyEvent*>(event)->keyval; }
extern "C" void webkit_web_view_reload(gpointer) { g_printerr("[MOCK-WPE] reload performed\n"); }
extern "C" gboolean webkit_web_view_can_go_back(gpointer) { return TRUE; }
extern "C" gboolean webkit_web_view_can_go_forward(gpointer) { return TRUE; }
extern "C" void webkit_web_view_go_back(gpointer) { g_printerr("[MOCK-WPE] back performed\n"); }
extern "C" void webkit_web_view_go_forward(gpointer) { g_printerr("[MOCK-WPE] forward performed\n"); }
extern "C" void wpe_toplevel_set_title(gpointer, const char*) {}
extern "C" const char* webkit_web_view_get_uri(gpointer) { return "about:blank"; }
static gboolean finished(gpointer v) {
    // Simulated compositor events follow official WPEEvent/keysym values.
    const FakeKeyEvent shortcuts[] = {
        {7, 1u, 0x68},       // Ctrl+H
        {7, 1u, 0x72},       // Ctrl+R
        {7, 1u << 2, 0xff51}, // Alt+Left
        {7, 1u << 2, 0xff53}, // Alt+Right
        {7, 0, 0xffc8},     // F11
    };
    for (const auto& shortcut : shortcuts) {
        gboolean handled = FALSE;
        g_signal_emit(v, keyboardEventSignal, 0, &shortcut, &handled);
        if (!handled) g_printerr("[MOCK-WPE] shortcut not handled\n");
    }
    if (g_getenv("FIRE4NIX_MOCK_QUIT")) {
        const FakeKeyEvent quit = {7, 1u, 0x71}; // Ctrl+Q
        gboolean handled = FALSE;
        g_signal_emit(v, keyboardEventSignal, 0, &quit, &handled);
    }
    if (g_getenv("FIRE4NIX_MOCK_TERMINATE")) {
        g_signal_emit(v, terminated, 0, 1);
        g_printerr("[MOCK-WPE] web process terminated before load finish\n");
    }
    if (g_getenv("FIRE4NIX_MOCK_DISPLAY_DISCONNECT")) {
        g_signal_emit(v, displayDisconnected, 0, nullptr);
        g_printerr("[MOCK-WPE] display disconnected\n");
    }
    g_signal_emit(v,changed,0,3);
    (void)closed;
    g_object_unref(v);
    return G_SOURCE_REMOVE;
}
extern "C" void webkit_web_view_load_uri(gpointer v, const char* uri) {
    static unsigned requestCount = 0;
    ++requestCount;
    g_printerr("[MOCK-WPE] load_uri request=%s\n", uri ? uri : "(null)");
    // A synthetic home shortcut must not recursively schedule endless fixture events.
    if (requestCount == 1)
        g_idle_add(finished, g_object_ref(v));
}
