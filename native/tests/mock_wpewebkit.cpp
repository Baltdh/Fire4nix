// Small mock WPE WebKit 2.0 GObject ABI for *CI smoke tests only*.
// Do NOT ship this fake library inside the R36H release ZIP.
#include <glib.h>
#include <glib-object.h>
typedef struct { GObject parent; } FakeView;
typedef struct { GObjectClass parent_class; } FakeViewClass;
G_DEFINE_TYPE(FakeView, fake_view, G_TYPE_OBJECT)
static guint changed;
static void fake_view_class_init(FakeViewClass*) {
    changed = g_signal_new("load-changed", fake_view_get_type(),
                           G_SIGNAL_RUN_LAST, 0, nullptr, nullptr, nullptr,
                           G_TYPE_NONE, 1, G_TYPE_INT);
}
static void fake_view_init(FakeView*) {}
extern "C" GType webkit_web_view_get_type(void) { return fake_view_get_type(); }
extern "C" const char* webkit_web_view_get_uri(gpointer) { return "about:blank"; }
static gboolean finished(gpointer v) {
    g_signal_emit(v,changed,0,3);
    g_object_unref(v);
    return G_SOURCE_REMOVE;
}
extern "C" void webkit_web_view_load_uri(gpointer v, const char*) {
    g_idle_add(finished, g_object_ref(v));
}
