// Fire4Nix v1.02 - WPEPlatform launcher with an executable headless DOM/CSS/JS gate.
// Build on AArch64 Linux against GLib/GObject; load the *user-installed* WPE2.0
// runtime with dlopen. Never pull GTK/Qt libraries into the launcher.
#include <glib.h>
#include <glib-object.h>
#include <glib-unix.h>
#include <gio/gio.h>
#include <dlfcn.h>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace {
using LoadUri = void (*)(gpointer, const char*);
using LoadHtml = void (*)(gpointer, const char*, const char*);
using GetType = GType (*)();
using GetVersionPart = unsigned (*)();
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
using EvaluateJavaScript = void (*)(gpointer, const char*, gssize, const char*, const char*, GCancellable*, GAsyncReadyCallback, gpointer);
using EvaluateJavaScriptFinish = gpointer (*)(gpointer, GAsyncResult*, GError**);
using JSCValueToString = gchar* (*)(gpointer);
using JSCValueUnref = void (*)(gpointer);

struct App {
    GMainLoop* loop = nullptr;
    GObject* view = nullptr;
    void* webkit = nullptr;
    LoadUri loadUri = nullptr;
    LoadHtml loadHtml = nullptr;
    GetUri getUri = nullptr;
    bool smoke = false;
    bool verifyOffline = false;
    bool verifyNavigation = false;
    unsigned navigationPhase = 0;
    unsigned navigationReloads = 0;
    bool verifyForm = false;
    unsigned formPhase = 0;
    bool verifyStorage = false;
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
    EvaluateJavaScript evaluateJavaScript = nullptr;
    EvaluateJavaScriptFinish evaluateJavaScriptFinish = nullptr;
    JSCValueToString jscValueToString = nullptr;
    JSCValueUnref jscValueUnref = nullptr;
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
static void offlineEvaluationFinished(GObject* object, GAsyncResult* result, gpointer data) {
    App* app = static_cast<App*>(data);
    GError* error = nullptr;
    gpointer value = app->evaluateJavaScriptFinish ?
        app->evaluateJavaScriptFinish(object, result, &error) : nullptr;
    if (error) {
        g_printerr("[FIRE4NIX-VERIFY] JavaScript evaluation failed: %s\n", error->message);
        g_error_free(error);
        app->exitCode = 4;
        app->failed = true;
    } else {
        gchar* report = value && app->jscValueToString ?
            app->jscValueToString(value) : nullptr;
        if (!report) {
            stage("offline verifier returned no diagnostic string");
            app->exitCode = 4;
            app->failed = true;
        } else {
            g_printerr("[FIRE4NIX-VERIFY] detail=%s\n", report);
            const bool titleOK = strstr(report, "title=PASS") != nullptr;
            const bool scriptOK = strstr(report, "inline_js=PASS") != nullptr;
            const bool domOK = strstr(report, "swatches=3") != nullptr;
            const bool cssOK = strstr(report, "background=rgb(16, 24, 39)") != nullptr;
            const bool clickOK = strstr(report, "click_count=Cliques: 1") != nullptr;
            if (titleOK && scriptOK && domOK && cssOK && clickOK) {
                stage("offline DOM, JavaScript, click and computed CSS verification passed");
                g_printerr("[FIRE4NIX-VERIFY] offline_dom=PASS\n");
                g_printerr("[FIRE4NIX-VERIFY] inline_javascript=PASS\n");
                g_printerr("[FIRE4NIX-VERIFY] computed_css=PASS\n");
                g_printerr("[FIRE4NIX-VERIFY] button_event=PASS\n");
                app->exitCode = 0;
            } else {
                stage("offline DOM/CSS/JavaScript verification failed; see detail fields");
                g_printerr("[FIRE4NIX-VERIFY] title=%s inline_javascript=%s dom=%s css=%s button=%s\n",
                    titleOK ? "PASS" : "FAIL", scriptOK ? "PASS" : "FAIL",
                    domOK ? "PASS" : "FAIL", cssOK ? "PASS" : "FAIL",
                    clickOK ? "PASS" : "FAIL");
                app->exitCode = 4;
                app->failed = true;
            }
            g_free(report);
        }
    }
    if (value && app->jscValueUnref) app->jscValueUnref(value);
    if (app->loop) g_main_loop_quit(app->loop);
}

static void navigationEvaluationFinished(GObject* object, GAsyncResult* result, gpointer data) {
    App* app = static_cast<App*>(data);
    GError* error = nullptr;
    gpointer value = app->evaluateJavaScriptFinish ?
        app->evaluateJavaScriptFinish(object, result, &error) : nullptr;
    gchar* report = (!error && value && app->jscValueToString) ?
        app->jscValueToString(value) : nullptr;
    if (error || !report) {
        g_printerr("[FIRE4NIX-NAV] phase=%u evaluation_error=%s\n",
                   app->navigationPhase, error ? error->message : "empty result");
        if (error) g_error_free(error);
        app->exitCode = 4;
        app->failed = true;
    } else {
        const char* expected = nullptr;
        if (app->navigationPhase == 0 || app->navigationPhase == 2)
            expected = "Fire4Nix Nav Start|START_JS_OK|true";
        else
            expected = "Fire4Nix Nav Target|TARGET_JS_OK|true";
        const bool passed = strcmp(report, expected) == 0;
        g_printerr("[FIRE4NIX-NAV] phase=%u result=%s status=%s\n",
                   app->navigationPhase, report, passed ? "PASS" : "FAIL");
        if (!passed) {
            app->exitCode = 4;
            app->failed = true;
        } else if (app->navigationPhase == 0) {
            const char* target = g_getenv("FIRE4NIX_NAV_TARGET_URL");
            if (!target || !*target || !app->loadUri) {
                stage("navigation target URL missing");
                app->exitCode = 4;
                app->failed = true;
            } else {
                app->navigationPhase = 1;
                app->loaded = false;
                stage("navigation: loading second page");
                app->loadUri(app->view, target);
            }
        } else if (app->navigationPhase == 1) {
            if (!app->goBack || !app->canGoBack || !app->canGoBack(app->view)) {
                stage("navigation history back unavailable");
                app->exitCode = 4;
                app->failed = true;
            } else {
                app->navigationPhase = 2;
                app->loaded = false;
                stage("navigation: invoking browser back");
                app->goBack(app->view);
            }
        } else if (app->navigationPhase == 2) {
            if (!app->goForward || !app->canGoForward || !app->canGoForward(app->view)) {
                stage("navigation history forward unavailable");
                app->exitCode = 4;
                app->failed = true;
            } else {
                app->navigationPhase = 3;
                app->loaded = false;
                stage("navigation: invoking browser forward");
                app->goForward(app->view);
            }
        } else if (app->navigationPhase == 3) {
            if (!app->reload) {
                stage("browser reload API unavailable");
                app->exitCode = 78;
                app->failed = true;
            } else {
                app->navigationPhase = 4;
                app->navigationReloads = 1;
                app->loaded = false;
                stage("navigation: reload page cycle 1");
                app->reload(app->view);
            }
        } else if (app->navigationPhase == 4) {
            if (!app->reload) {
                stage("browser reload API unavailable");
                app->exitCode = 78;
                app->failed = true;
            } else if (app->navigationReloads < 2) {
                app->navigationReloads++;
                app->loaded = false;
                stage("navigation: reload page cycle 2");
                app->reload(app->view);
            } else {
                stage("navigation, back, forward and two reload cycles passed");
                g_printerr("[FIRE4NIX-NAV] navigation=PASS\n");
                g_printerr("[FIRE4NIX-NAV] history_back=PASS\n");
                g_printerr("[FIRE4NIX-NAV] history_forward=PASS\n");
                g_printerr("[FIRE4NIX-NAV] page_reload=PASS\n");
                g_printerr("[FIRE4NIX-NAV] reload_cycles=2\n");
                app->navigationPhase = 5;
                app->exitCode = 0;
            }
        }
    }
    g_free(report);
    if (value && app->jscValueUnref) app->jscValueUnref(value);
    if (app->failed || app->exitCode || app->navigationPhase == 5) {
        if (app->loop) g_main_loop_quit(app->loop);
    }
}

static void startNavigationEvaluation(App* app) {
    if (!app->evaluateJavaScript || !app->evaluateJavaScriptFinish ||
        !app->jscValueToString || !app->jscValueUnref) {
        stage("navigation verification API unavailable");
        app->exitCode = 78;
        app->failed = true;
        if (app->loop) g_main_loop_quit(app->loop);
        return;
    }
    static const char startScript[] =
        "(() => { const s=document.querySelector('#nav-state');"
        " const a=document.querySelector('#nav-next');"
        " return document.title+'|'+(s?s.textContent:'MISSING')+'|'+(!!a); })()";
    static const char targetScript[] =
        "(() => { const s=document.querySelector('#nav-state');"
        " const a=document.querySelector('#nav-back');"
        " return document.title+'|'+(s?s.textContent:'MISSING')+'|'+(!!a); })()";
    const char* script = (app->navigationPhase == 0 || app->navigationPhase == 2) ?
        startScript : targetScript;
    stage("evaluating browser navigation and history state");
    app->evaluateJavaScript(app->view, script, -1, nullptr, nullptr,
                            nullptr, navigationEvaluationFinished, app);
}

static void formResultEvaluationFinished(GObject* object, GAsyncResult* result, gpointer data) {
    App* app = static_cast<App*>(data);
    GError* error = nullptr;
    gpointer value = app->evaluateJavaScriptFinish ?
        app->evaluateJavaScriptFinish(object, result, &error) : nullptr;
    gchar* report = (!error && value && app->jscValueToString) ?
        app->jscValueToString(value) : nullptr;
    const char* expected =
        "Fire4Nix Form Result|FORM_POST_OK|FORM_RESULT_JS_OK|LOCAL_OK|SESSION_OK";
    if (error || !report || strcmp(report, expected) != 0) {
        g_printerr("[FIRE4NIX-FORM] phase=%u result=%s error=%s status=FAIL\n",
                   app->formPhase, report ? report : "(null)",
                   error ? error->message : "none");
        if (error) g_error_free(error);
        app->exitCode = 4;
        app->failed = true;
    } else if (app->formPhase == 2) {
        g_printerr("[FIRE4NIX-FORM] form_post=PASS\n");
        g_printerr("[FIRE4NIX-FORM] local_storage=PASS\n");
        g_printerr("[FIRE4NIX-FORM] session_storage=PASS\n");
        app->formPhase = 3;
        app->loaded = false;
        if (!app->reload) {
            stage("form verification could not find WebKit reload API");
            app->exitCode = 78;
            app->failed = true;
        } else {
            stage("form verification: reloading POST result to verify storage");
            app->reload(app->view);
        }
    } else if (app->formPhase == 3) {
        g_printerr("[FIRE4NIX-FORM] storage_after_reload=PASS\n");
        g_printerr("[FIRE4NIX-FORM] form_and_storage=PASS\n");
        app->formPhase = 4;
        app->exitCode = 0;
    } else {
        g_printerr("[FIRE4NIX-FORM] unexpected phase=%u\n", app->formPhase);
        app->exitCode = 4;
        app->failed = true;
    }
    g_free(report);
    if (value && app->jscValueUnref) app->jscValueUnref(value);
    if (app->failed || app->formPhase == 4) {
        if (app->loop) g_main_loop_quit(app->loop);
    }
}

static void startFormResultEvaluation(App* app) {
    static const char script[] =
        "(() => { const result=document.querySelector('#server-result');"
        " const state=document.querySelector('#js-state');"
        " return [document.title,"
        " result?result.textContent.trim():'MISSING',"
        " state?state.textContent.trim():'MISSING',"
        " localStorage.getItem('fire4nix-form-local')||'MISSING',"
        " sessionStorage.getItem('fire4nix-form-session')||'MISSING'].join('|'); })()";
    if (!app->evaluateJavaScript || !app->evaluateJavaScriptFinish ||
        !app->jscValueToString || !app->jscValueUnref) {
        stage("form result verification API unavailable");
        app->exitCode = 78;
        app->failed = true;
        if (app->loop) g_main_loop_quit(app->loop);
        return;
    }
    stage("evaluating submitted form result and browser storage");
    app->evaluateJavaScript(app->view, script, -1, nullptr, nullptr,
                            nullptr, formResultEvaluationFinished, app);
}

static void formSubmitEvaluationFinished(GObject* object, GAsyncResult* result, gpointer data) {
    App* app = static_cast<App*>(data);
    GError* error = nullptr;
    gpointer value = app->evaluateJavaScriptFinish ?
        app->evaluateJavaScriptFinish(object, result, &error) : nullptr;
    gchar* report = (!error && value && app->jscValueToString) ?
        app->jscValueToString(value) : nullptr;
    if (error || !report || strcmp(report, "FORM_SUBMIT_STARTED") != 0) {
        g_printerr("[FIRE4NIX-FORM] submit_result=%s error=%s status=FAIL\n",
                   report ? report : "(null)", error ? error->message : "none");
        if (error) g_error_free(error);
        app->exitCode = 4;
        app->failed = true;
    } else {
        g_printerr("[FIRE4NIX-FORM] submission=STARTED\n");
    }
    g_free(report);
    if (value && app->jscValueUnref) app->jscValueUnref(value);
    if (app->failed && app->loop) g_main_loop_quit(app->loop);
}

static void startFormSubmission(App* app) {
    static const char script[] =
        "(() => { const form=document.querySelector('#post-form');"
        " const field=document.querySelector('#payload');"
        " if (!form || !field) return 'FORM_MISSING';"
        " localStorage.setItem('fire4nix-form-local','LOCAL_OK');"
        " sessionStorage.setItem('fire4nix-form-session','SESSION_OK');"
        " field.value='FIRE4NIX_FIELD';"
        " form.requestSubmit();"
        " return 'FORM_SUBMIT_STARTED'; })()";
    if (!app->evaluateJavaScript || !app->evaluateJavaScriptFinish ||
        !app->jscValueToString || !app->jscValueUnref) {
        stage("form submission API unavailable");
        app->exitCode = 78;
        app->failed = true;
        if (app->loop) g_main_loop_quit(app->loop);
        return;
    }
    // Set the phase before requesting submission because load-changed may be
    // emitted as soon as WebKit begins committing the POST response.
    app->formPhase = 2;
    app->loaded = false;
    stage("submitting a real HTML form with application/x-www-form-urlencoded POST");
    app->evaluateJavaScript(app->view, script, -1, nullptr, nullptr,
                            nullptr, formSubmitEvaluationFinished, app);
}

static void formSetupEvaluationFinished(GObject* object, GAsyncResult* result, gpointer data) {
    App* app = static_cast<App*>(data);
    GError* error = nullptr;
    gpointer value = app->evaluateJavaScriptFinish ?
        app->evaluateJavaScriptFinish(object, result, &error) : nullptr;
    gchar* report = (!error && value && app->jscValueToString) ?
        app->jscValueToString(value) : nullptr;
    if (error || !report || strcmp(report, "Fire4Nix Form Page|FORM_PAGE_JS_OK|true|true") != 0) {
        g_printerr("[FIRE4NIX-FORM] setup_result=%s error=%s status=FAIL\n",
                   report ? report : "(null)", error ? error->message : "none");
        if (error) g_error_free(error);
        app->exitCode = 4;
        app->failed = true;
    } else {
        g_printerr("[FIRE4NIX-FORM] form_page=PASS\n");
        startFormSubmission(app);
    }
    g_free(report);
    if (value && app->jscValueUnref) app->jscValueUnref(value);
    if (app->failed && app->loop) g_main_loop_quit(app->loop);
}

static void startFormSetupEvaluation(App* app) {
    static const char script[] =
        "(() => { const form=document.querySelector('#post-form');"
        " const field=document.querySelector('#payload');"
        " const status=document.querySelector('#form-state');"
        " return [document.title,"
        " status?status.textContent.trim():'MISSING',"
        " !!form,!!field].join('|'); })()";
    if (!app->evaluateJavaScript || !app->evaluateJavaScriptFinish ||
        !app->jscValueToString || !app->jscValueUnref) {
        stage("form setup verification API unavailable");
        app->exitCode = 78;
        app->failed = true;
        if (app->loop) g_main_loop_quit(app->loop);
        return;
    }
    stage("checking real HTML form before submission");
    app->evaluateJavaScript(app->view, script, -1, nullptr, nullptr,
                            nullptr, formSetupEvaluationFinished, app);
}

static void persistentStorageEvaluationFinished(GObject* object, GAsyncResult* result, gpointer data) {
    App* app = static_cast<App*>(data);
    GError* error = nullptr;
    gpointer value = app->evaluateJavaScriptFinish ?
        app->evaluateJavaScriptFinish(object, result, &error) : nullptr;
    gchar* report = (!error && value && app->jscValueToString) ?
        app->jscValueToString(value) : nullptr;
    if (error || !report || strcmp(report, "LOCAL_OK|EMPTY") != 0) {
        g_printerr("[FIRE4NIX-STORAGE] process_restart_result=%s error=%s status=FAIL\n",
                   report ? report : "(null)", error ? error->message : "none");
        if (error) g_error_free(error);
        app->exitCode = 4;
        app->failed = true;
    } else {
        g_printerr("[FIRE4NIX-STORAGE] local_storage_after_process_restart=PASS\n");
        g_printerr("[FIRE4NIX-STORAGE] session_storage_new_context=EMPTY_AS_EXPECTED\n");
        g_printerr("[FIRE4NIX-STORAGE] persistent_profile=PASS\n");
        app->exitCode = 0;
    }
    g_free(report);
    if (value && app->jscValueUnref) app->jscValueUnref(value);
    if (app->loop) g_main_loop_quit(app->loop);
}

static void startPersistentStorageEvaluation(App* app) {
    static const char script[] =
        "(() => { const local=localStorage.getItem('fire4nix-form-local')||'MISSING';"
        " const session=sessionStorage.getItem('fire4nix-form-session')||'EMPTY';"
        " return local+'|'+session; })()";
    if (!app->evaluateJavaScript || !app->evaluateJavaScriptFinish ||
        !app->jscValueToString || !app->jscValueUnref) {
        stage("persistent storage verification API unavailable");
        app->exitCode = 78;
        app->failed = true;
        if (app->loop) g_main_loop_quit(app->loop);
        return;
    }
    stage("checking persistent localStorage and isolated sessionStorage in a new process");
    app->evaluateJavaScript(app->view, script, -1, nullptr, nullptr,
                            nullptr, persistentStorageEvaluationFinished, app);
}

static void loadChanged(GObject*, int event, gpointer data) {
    App* app = static_cast<App*>(data);
    const char* url = app->getUri ? app->getUri(app->view) : nullptr;
    g_printerr("[FIRE4NIX-NATIVE] load-event=%d url=%s\n", event, url ? url : "(pending)");
    // WebKitLoadEvent: STARTED=0, REDIRECTED=1, COMMITTED=2, FINISHED=3.
    if (event == 3) {
        app->loaded = true;
        if (app->verifyStorage) {
            startPersistentStorageEvaluation(app);
            return;
        }
        if (app->verifyForm) {
            if (app->formPhase == 0)
                startFormSetupEvaluation(app);
            else if (app->formPhase == 2 || app->formPhase == 3)
                startFormResultEvaluation(app);
            return;
        }
        if (app->verifyNavigation) {
            startNavigationEvaluation(app);
            return;
        }
        if (app->verifyOffline) {
            if (!app->evaluateJavaScript || !app->evaluateJavaScriptFinish ||
                !app->jscValueToString || !app->jscValueUnref) {
                stage("offline verification API unavailable in this WPE runtime");
                app->exitCode = 78;
                app->failed = true;
                g_idle_add(smokeQuit, app);
                return;
            }
            // Verify the actual WPE page DOM, inline JS result and computed CSS.
            // This is a real browser-engine integration test, not a GPU/frame test.
            static const char script[] =
                "(() => { const s = document.querySelector('#js-state');"
                " const css = getComputedStyle(document.body);"
                " const button = document.querySelector('#test-button');"
                " const count = document.querySelector('#click-count');"
                " if (button) button.click();"
                " const checks = [];"
                " checks.push('location=' + location.href);"
                " checks.push('ready_state=' + document.readyState);"
                " checks.push('html_length=' + (document.documentElement ? document.documentElement.outerHTML.length : 0));"
                " checks.push('body_text=' + (document.body ? document.body.innerText.slice(0, 120).replace(/\\s+/g, ' ') : 'NO_BODY'));"
                " checks.push('title_value=' + document.title);"
                " checks.push('title=' + (document.title === 'Fire4Nix | Primeiro teste offline' ? 'PASS' : 'FAIL'));"
                " checks.push('inline_js=' + (!!s && s.textContent.trim() === 'JS OK' ? 'PASS' : 'FAIL'));"
                " checks.push('swatches=' + document.querySelectorAll('.swatch').length);"
                " checks.push('background=' + css.backgroundColor);"
                " checks.push('click_count=' + (count ? count.textContent.trim() : 'MISSING'));"
                " return checks.join(';'); })()";
            stage("evaluating offline DOM, JavaScript and computed CSS");
            app->evaluateJavaScript(app->view, script, -1, nullptr, nullptr,
                                    nullptr, offlineEvaluationFinished, app);
            return;
        }
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
        puts("Fire4Nix native WPEPlatform 1.05: [--selftest|--check-library|--check-platform|--smoke|--verify-offline|--verify-navigation|--verify-form|--verify-storage] [URL]");
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
    const bool verifyOffline = argc > 1 && !strcmp(argv[1], "--verify-offline");
    const bool verifyNavigation = argc > 1 && !strcmp(argv[1], "--verify-navigation");
    const bool verifyForm = argc > 1 && !strcmp(argv[1], "--verify-form");
    const bool verifyStorage = argc > 1 && !strcmp(argv[1], "--verify-storage");
    const char* url = "about:blank";
    for (int i=1; i<argc; ++i) {
        if (strcmp(argv[i],"--check-library") && strcmp(argv[i],"--check-platform") &&
            strcmp(argv[i],"--smoke") && strcmp(argv[i],"--verify-offline") &&
            strcmp(argv[i],"--verify-navigation") && strcmp(argv[i],"--verify-form") &&
            strcmp(argv[i],"--verify-storage") && argv[i][0] != '-') { url=argv[i]; break; }
    }
    stage("dlopen libWPEWebKit-2.0.so.1");
    App app;
    app.smoke = smoke || verifyOffline || verifyNavigation || verifyForm || verifyStorage;
    app.verifyOffline = verifyOffline;
    app.verifyNavigation = verifyNavigation;
    app.verifyForm = verifyForm;
    app.verifyStorage = verifyStorage;
    app.initialUrl = url;
    app.webkit = dlopen("libWPEWebKit-2.0.so.1", RTLD_NOW | RTLD_GLOBAL);
    if (!app.webkit) {
        g_printerr("[FIRE4NIX-NATIVE] loader error: %s\n", dlerror());
        return 127;
    }
    stage("dlopen success");
    stage("wpe version dlsym begin");
    // Get the version from the *loaded runtime*, not the launcher's build.
    // WPEPlatform became stable in 2.54; availability still depends on the
    // options used when compiling this particular library.
    auto majorVersion = reinterpret_cast<GetVersionPart>(dlsym(app.webkit, "webkit_get_major_version"));
    auto minorVersion = reinterpret_cast<GetVersionPart>(dlsym(app.webkit, "webkit_get_minor_version"));
    auto microVersion = reinterpret_cast<GetVersionPart>(dlsym(app.webkit, "webkit_get_micro_version"));
    stage("wpe version dlsym done");
    if (majorVersion && minorVersion && microVersion) {
        stage("wpe version getters begin");
        const unsigned major = majorVersion(), minor = minorVersion(), micro = microVersion();
        stage("wpe version getters done");
        g_printerr("[FIRE4NIX-ABI] wpe_version=%u.%u.%u\n", major, minor, micro);
        if (major < 2 || (major == 2 && minor < 54))
            stage("WPE version older than 2.54: WPEPlatform may be missing or experimental");
        if (major == 2 && minor == 54 && micro == 0)
            stage("WPE 2.54.0 detected: prefer WPE 2.54.1+ for Wayland 1.25+ build support");
    } else {
        stage("WPE version API unavailable; report as unknown, never guess from filename");
        g_printerr("[FIRE4NIX-ABI] wpe_version=unknown\n");
    }
    if (onlyLibrary) {
        dlclose(app.webkit);
        return 0;
    }
    app.evaluateJavaScript = symbol<EvaluateJavaScript>(app.webkit, "webkit_web_view_evaluate_javascript");
    app.evaluateJavaScriptFinish = symbol<EvaluateJavaScriptFinish>(app.webkit, "webkit_web_view_evaluate_javascript_finish");
    app.jscValueToString = symbol<JSCValueToString>(RTLD_DEFAULT, "jsc_value_to_string");
    if (!app.jscValueToString)
        app.jscValueToString = symbol<JSCValueToString>(app.webkit, "jsc_value_to_string");
    // JSCValue derives from GObject. Its transfer-full result must be
    // released with g_object_unref(); there is no jsc_value_unref() API.
    app.jscValueUnref = &g_object_unref;
    stage("WPE core symbol probes begin");
    auto webViewType = symbol<GetType>(app.webkit, "webkit_web_view_get_type");
    auto getWPEView = symbol<GetWPEView>(app.webkit, "webkit_web_view_get_wpe_view");
    app.loadUri = symbol<LoadUri>(app.webkit, "webkit_web_view_load_uri");
    app.loadHtml = symbol<LoadHtml>(app.webkit, "webkit_web_view_load_html");
    app.getUri = symbol<GetUri>(app.webkit, "webkit_web_view_get_uri");
    auto settingsType = symbol<GetType>(app.webkit, "webkit_settings_get_type");
    auto assignSettings = symbol<SetSettings>(app.webkit, "webkit_web_view_set_settings");
    stage("WPE core symbol probes done");
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
            "wpe_view_get_display",
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
               app.verifyOffline ? "verify-offline" : (app.smoke ? "smoke" : "interactive"),
               lowMemory() ? 1 : 0, url,
               g_getenv("WPE_PLATFORM") ? g_getenv("WPE_PLATFORM") : "default");
    bool loadedLocalHtml = false;
    const bool localHtmlUrl = g_str_has_prefix(url, "file://") &&
        (g_str_has_suffix(url, ".html") || g_str_has_suffix(url, ".htm"));
    if (localHtmlUrl && app.loadHtml) {
        // Minimal ROCKNIX images may omit shared-mime-info text/html mapping.
        // load_html() avoids treating a local .html file as plain text while
        // preserving the original file URI as base for relative resources.
        gchar* hostname = nullptr;
        GError* fileError = nullptr;
        gchar* localPath = g_filename_from_uri(url, &hostname, &fileError);
        if (localPath && (!hostname || !*hostname)) {
            gchar* html = nullptr;
            gsize htmlLength = 0;
            if (g_file_get_contents(localPath, &html, &htmlLength, &fileError)) {
                stage("loading local HTML explicitly with webkit_web_view_load_html (MIME-independent)");
                app.loadHtml(app.view, html, url);
                loadedLocalHtml = true;
                g_free(html);
            }
        }
        if (fileError) {
            g_printerr("[FIRE4NIX-NATIVE] local HTML read failed: %s\n", fileError->message);
            g_error_free(fileError);
        }
        g_free(localPath);
        g_free(hostname);
    }
    if (!loadedLocalHtml) {
        if (localHtmlUrl && !app.loadHtml)
            stage("webkit_web_view_load_html unavailable; falling back to URI MIME detection");
        app.loadUri(app.view, url);
    }
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
