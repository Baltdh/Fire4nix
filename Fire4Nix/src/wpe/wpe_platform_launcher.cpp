// Fire4Nix native WPE launcher.
// This launcher keeps the first-test path small, but it now mirrors the
// official WPE MiniBrowser behavior more closely: the web context is built
// with a proper website data manager, cookies/proxy/TLS settings are honored,
// content filters are loaded when provided, and the initial page uses the
// project defaults for ROCKNIX / RK3326.

#include <glib.h>
#include <glib-unix.h>
#include <wpe/webkit.h>

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <filesystem>
#include <string>
#include <vector>

namespace {

struct LaunchOptions {
    std::string url;
    std::string timeZone;
    std::string cookiesFile;
    std::string cookiesPolicy;
    std::string proxy;
    std::vector<std::string> ignoreHosts;
    std::string contentFilter;
    std::string backgroundColor;
    bool privateMode { false };
    bool automationMode { false };
    bool ignoreTlsErrors { false };
    bool enableItp { false };
    bool headlessMode { false };
    bool maximize { false };
    bool fullscreen { false };
};

struct FilterSaveData {
    GMainLoop* mainLoop { nullptr };
    WebKitUserContentFilter* filter { nullptr };
    GError* error { nullptr };
};

static void filterSavedCallback(WebKitUserContentFilterStore* store, GAsyncResult* result, FilterSaveData* data)
{
    data->filter = webkit_user_content_filter_store_save_finish(store, result, &data->error);
    g_main_loop_quit(data->mainLoop);
}

std::string trimCopy(const std::string& text)
{
    const auto begin = text.find_first_not_of(" \t\r\n");
    if (begin == std::string::npos) {
        return {};
    }
    const auto end = text.find_last_not_of(" \t\r\n");
    return text.substr(begin, end - begin + 1);
}

bool envEnabled(const char* name, bool fallback = false)
{
    if (const char* value = g_getenv(name); value != nullptr && *value != '\0') {
        const std::string lower = trimCopy(value);
        if (lower == "1" || lower == "true" || lower == "yes" || lower == "on")
            return true;
        if (lower == "0" || lower == "false" || lower == "no" || lower == "off")
            return false;
    }
    return fallback;
}

std::string envOr(const char* name, const std::string& fallback)
{
    if (const char* value = g_getenv(name); value != nullptr && *value != '\0')
        return trimCopy(value);
    return fallback;
}

std::string defaultStartUrl()
{
    return envOr("FIRE4NIX_START_PAGE",
                 envOr("FIRE4NIX_HOME_URL",
                        envOr("FIRE4NIX_DEFAULT_HOME_URL", "https://lite.duckduckgo.com/lite/")));
}

std::vector<std::string> splitList(const std::string& text)
{
    std::vector<std::string> items;
    std::string current;
    for (char ch : text) {
        if (ch == ',' || ch == ';' || ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r') {
            if (!current.empty()) {
                items.push_back(trimCopy(current));
                current.clear();
            }
            continue;
        }
        current.push_back(ch);
    }
    if (!current.empty())
        items.push_back(trimCopy(current));
    return items;
}

const char* maybeCString(const std::string& value)
{
    return value.empty() ? nullptr : value.c_str();
}

void appendHostList(std::vector<std::string>& dst, const std::string& text)
{
    for (const auto& item : splitList(text)) {
        if (!item.empty())
            dst.push_back(item);
    }
}

LaunchOptions parseOptions(int argc, char** argv)
{
    LaunchOptions options;
    options.url = defaultStartUrl();
    options.privateMode = envEnabled("FIRE4NIX_PRIVATE_MODE", false);
    options.automationMode = envEnabled("FIRE4NIX_AUTOMATION_MODE", false);
    options.ignoreTlsErrors = envEnabled("FIRE4NIX_IGNORE_TLS_ERRORS", false);
    options.enableItp = envEnabled("FIRE4NIX_ENABLE_ITP", false);
    options.headlessMode = envEnabled("FIRE4NIX_HEADLESS_MODE", false);
    options.maximize = envEnabled("FIRE4NIX_MAXIMIZE", true);
    options.fullscreen = envEnabled("FIRE4NIX_FULLSCREEN", true);
    options.backgroundColor = envOr("FIRE4NIX_BG_COLOR", envOr("FIRE4NIX_WPE_BG_COLOR", "white"));
    options.timeZone = envOr("FIRE4NIX_TIME_ZONE", envOr("FIRE4NIX_WPE_TIME_ZONE", ""));
    options.cookiesFile = envOr("FIRE4NIX_COOKIES_FILE", envOr("FIRE4NIX_WPE_COOKIES_FILE", ""));
    options.cookiesPolicy = envOr("FIRE4NIX_COOKIES_POLICY", envOr("FIRE4NIX_WPE_COOKIES_POLICY", ""));
    options.proxy = envOr("FIRE4NIX_PROXY", envOr("FIRE4NIX_WPE_PROXY", ""));
    options.contentFilter = envOr("FIRE4NIX_CONTENT_FILTER", envOr("FIRE4NIX_WPE_CONTENT_FILTER", ""));
    if (const char* ignoreHosts = g_getenv("FIRE4NIX_IGNORE_HOSTS"); ignoreHosts != nullptr && *ignoreHosts != '\0')
        appendHostList(options.ignoreHosts, ignoreHosts);
    if (const char* ignoreHosts = g_getenv("FIRE4NIX_WPE_IGNORE_HOSTS"); ignoreHosts != nullptr && *ignoreHosts != '\0')
        appendHostList(options.ignoreHosts, ignoreHosts);

    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i] != nullptr ? trimCopy(argv[i]) : std::string();
        if (arg.empty())
            continue;

        if (arg == "--help" || arg == "-h") {
            g_print("Fire4Nix WPE launcher\n");
            g_print("Usage: %s [URL] [options]\n", argv[0] != nullptr ? argv[0] : "fire4nix-wpe-platform");
            g_print("Options: --private --automation --ignore-tls-errors --enable-itp --headless\n");
            g_print("         --cookies-file=PATH --cookies-policy=always|never|no-third-party\n");
            g_print("         --proxy=URL --ignore-host=HOST[,HOST...] --content-filter=PATH\n");
            g_print("         --time-zone=ZONE --bg-color=COLOR --fullscreen --maximized\n");
            std::exit(EXIT_SUCCESS);
        }

        if (arg == "--version" || arg == "-v") {
            g_print("Fire4Nix WPE launcher\n");
            std::exit(EXIT_SUCCESS);
        }

        if (arg == "--private" || arg == "--private-mode") {
            options.privateMode = true;
            continue;
        }
        if (arg == "--automation") {
            options.automationMode = true;
            continue;
        }
        if (arg == "--ignore-tls-errors") {
            options.ignoreTlsErrors = true;
            continue;
        }
        if (arg == "--enable-itp") {
            options.enableItp = true;
            continue;
        }
        if (arg == "--headless") {
            options.headlessMode = true;
            continue;
        }
        if (arg == "--fullscreen") {
            options.fullscreen = true;
            continue;
        }
        if (arg == "--maximized") {
            options.maximize = true;
            continue;
        }

        auto consumeValue = [&](const char* prefix, std::string& target) -> bool {
            const std::string key(prefix);
            if (arg == key) {
                if (i + 1 < argc && argv[i + 1] != nullptr) {
                    target = trimCopy(argv[++i]);
                    return true;
                }
                g_printerr("Missing value for %s\n", prefix);
                std::exit(EXIT_FAILURE);
            }
            if (arg.rfind(key + "=", 0) == 0) {
                target = trimCopy(arg.substr(key.size() + 1));
                return true;
            }
            return false;
        };

        if (consumeValue("--cookies-file", options.cookiesFile)) continue;
        if (consumeValue("--cookies-policy", options.cookiesPolicy)) continue;
        if (consumeValue("--proxy", options.proxy)) continue;
        if (consumeValue("--content-filter", options.contentFilter)) continue;
        if (consumeValue("--time-zone", options.timeZone)) continue;
        if (consumeValue("--bg-color", options.backgroundColor)) continue;

        if (arg.rfind("--ignore-host", 0) == 0) {
            std::string value;
            if (arg == "--ignore-host") {
                if (i + 1 < argc && argv[i + 1] != nullptr) {
                    value = trimCopy(argv[++i]);
                } else {
                    g_printerr("Missing value for --ignore-host\n");
                    std::exit(EXIT_FAILURE);
                }
            } else if (arg.rfind("--ignore-host=", 0) == 0) {
                value = trimCopy(arg.substr(std::strlen("--ignore-host=")));
            }
            if (!value.empty())
                appendHostList(options.ignoreHosts, value);
            continue;
        }

        if (arg == "--size" || arg.rfind("--size=", 0) == 0) {
            // The launcher accepts the option for parity with the official WPE
            // MiniBrowser, but the native platform decides the actual surface
            // size. Keep the argument so the beta first-test flow remains simple.
            continue;
        }

        // First positional argument becomes the initial URL.
        if (options.url == defaultStartUrl() || options.url.empty()) {
            options.url = arg;
            continue;
        }
    }

    if (options.url.empty())
        options.url = defaultStartUrl();

    return options;
}

void loadContentFilterIfRequested(WebKitWebView* view, const LaunchOptions& options)
{
    if (options.contentFilter.empty())
        return;

    g_autoptr(GFile) contentFilterFile = g_file_new_for_commandline_arg(options.contentFilter.c_str());
    if (contentFilterFile == nullptr)
        return;

    FilterSaveData saveData { nullptr, nullptr, nullptr };
    g_autofree char* filtersPath = g_build_filename(g_get_user_cache_dir(), g_get_prgname(), "filters", nullptr);
    WebKitUserContentFilterStore* store = webkit_user_content_filter_store_new(filtersPath);

    saveData.mainLoop = g_main_loop_new(nullptr, FALSE);
    webkit_user_content_filter_store_save_from_file(store, "Fire4NixFilter", contentFilterFile, nullptr,
        G_CALLBACK(filterSavedCallback),
        &saveData);
    g_main_loop_run(saveData.mainLoop);

    if (saveData.filter != nullptr) {
        WebKitUserContentManager* manager = webkit_web_view_get_user_content_manager(view);
        if (manager != nullptr)
            webkit_user_content_manager_add_filter(manager, saveData.filter);
    } else {
        g_printerr("Cannot load filter '%s': %s\n",
                   options.contentFilter.c_str(),
                   saveData.error != nullptr && saveData.error->message != nullptr ? saveData.error->message : "unknown error");
    }

    g_clear_pointer(&saveData.error, g_error_free);
    g_clear_pointer(&saveData.filter, webkit_user_content_filter_unref);
    g_main_loop_unref(saveData.mainLoop);
    if (store != nullptr)
        g_object_unref(store);
}

WebKitWebsiteDataManager* createWebsiteDataManager(const LaunchOptions& options)
{
    WebKitWebsiteDataManager* manager = (options.privateMode || options.automationMode)
        ? webkit_website_data_manager_new_ephemeral()
        : webkit_website_data_manager_new(nullptr);

    if (options.enableItp)
        webkit_website_data_manager_set_itp_enabled(manager, TRUE);

    if (!options.proxy.empty()) {
        std::vector<const gchar*> ignoreHosts;
        ignoreHosts.reserve(options.ignoreHosts.size() + 1);
        for (const auto& host : options.ignoreHosts)
            ignoreHosts.push_back(host.c_str());
        ignoreHosts.push_back(nullptr);

        WebKitNetworkProxySettings* proxySettings = webkit_network_proxy_settings_new(options.proxy.c_str(), ignoreHosts.data());
        if (proxySettings != nullptr) {
            webkit_website_data_manager_set_network_proxy_settings(manager, WEBKIT_NETWORK_PROXY_MODE_CUSTOM, proxySettings);
            webkit_network_proxy_settings_free(proxySettings);
        }
    }

    if (options.ignoreTlsErrors)
        webkit_website_data_manager_set_tls_errors_policy(manager, WEBKIT_TLS_ERRORS_POLICY_IGNORE);

    return manager;
}

WebKitWebContext* createWebContext(const LaunchOptions& options)
{
    WebKitWebsiteDataManager* manager = createWebsiteDataManager(options);
    if (manager == nullptr)
        return nullptr;

    WebKitWebContext* webContext = nullptr;
    if (!options.timeZone.empty()) {
        webContext = WEBKIT_WEB_CONTEXT(g_object_new(WEBKIT_TYPE_WEB_CONTEXT,
                                         "website-data-manager", manager,
                                         "time-zone-override", options.timeZone.c_str(),
                                         nullptr));
    } else {
        webContext = WEBKIT_WEB_CONTEXT(g_object_new(WEBKIT_TYPE_WEB_CONTEXT,
                                         "website-data-manager", manager,
                                         nullptr));
    }

    g_object_unref(manager);
    return webContext;
}

void applyCookieSettings(WebKitWebContext* webContext, const LaunchOptions& options)
{
    if (webContext == nullptr)
        return;

    if (!options.cookiesPolicy.empty()) {
        auto* enumClass = static_cast<GEnumClass*>(g_type_class_ref(WEBKIT_TYPE_COOKIE_ACCEPT_POLICY));
        const GEnumValue* enumValue = g_enum_get_value_by_nick(enumClass, options.cookiesPolicy.c_str());
        if (enumValue != nullptr) {
            auto* cookieManager = webkit_web_context_get_cookie_manager(webContext);
            webkit_cookie_manager_set_accept_policy(cookieManager, static_cast<WebKitCookieAcceptPolicy>(enumValue->value));
        }
        g_type_class_unref(enumClass);
    }

    if (!options.cookiesFile.empty() && !webkit_web_context_is_ephemeral(webContext)) {
        auto* cookieManager = webkit_web_context_get_cookie_manager(webContext);
        const gboolean isText = g_str_has_suffix(options.cookiesFile.c_str(), ".txt");
        const auto storageType = isText ? WEBKIT_COOKIE_PERSISTENT_STORAGE_TEXT : WEBKIT_COOKIE_PERSISTENT_STORAGE_SQLITE;
        webkit_cookie_manager_set_persistent_storage(cookieManager, options.cookiesFile.c_str(), storageType);
    }
}

void applyBrowserDefaults(WebKitWebView* view, const LaunchOptions& options)
{
    WebKitSettings* settings = webkit_settings_new_with_settings(
        "enable-javascript", TRUE,
        "enable-developer-extras", TRUE,
        "enable-write-console-messages-to-stdout", TRUE,
        "enable-media-stream", TRUE,
        "enable-mediasource", TRUE,
        "enable-webgl", TRUE,
        "enable-webrtc", TRUE,
        "enable-encrypted-media", TRUE,
        "enable-back-forward-navigation-gestures", TRUE,
        nullptr);

    webkit_web_view_set_settings(view, settings);
    g_object_unref(settings);

    if (!options.backgroundColor.empty()) {
        WebKitColor color;
        if (webkit_color_parse(&color, options.backgroundColor.c_str()))
            webkit_web_view_set_background_color(view, &color);
    }
}

void logLoadState(WebKitWebView* view, WebKitLoadEvent loadEvent)
{
    const char* uri = webkit_web_view_get_uri(view);
    switch (loadEvent) {
    case WEBKIT_LOAD_STARTED:
        g_message("Fire4Nix WPE loading: %s", uri != nullptr ? uri : "(pending)");
        break;
    case WEBKIT_LOAD_COMMITTED:
        g_message("Fire4Nix WPE committed: %s", uri != nullptr ? uri : "(pending)");
        break;
    case WEBKIT_LOAD_FINISHED:
        g_message("Fire4Nix WPE finished: %s", uri != nullptr ? uri : "(pending)");
        break;
    default:
        break;
    }
}

gboolean onUnixSignal(gpointer userData)
{
    auto* loop = static_cast<GMainLoop*>(userData);
    if (loop != nullptr)
        g_main_loop_quit(loop);
    return G_SOURCE_REMOVE;
}

void onLoadChanged(WebKitWebView* view, WebKitLoadEvent loadEvent, gpointer)
{
    logLoadState(view, loadEvent);
}

gboolean onLoadFailed(WebKitWebView* view, WebKitLoadEvent, const gchar* failingUri, GError* error, gpointer)
{
    g_warning("Fire4Nix WPE load failed for %s: %s",
              failingUri != nullptr ? failingUri : "(unknown)",
              error != nullptr && error->message != nullptr ? error->message : "unknown error");
    (void)view;
    return FALSE;
}

gboolean onLoadFailedWithTlsErrors(WebKitWebView* view, gchar* failingUri, GTlsCertificate*, GTlsCertificateFlags errors, gpointer)
{
    g_warning("Fire4Nix WPE TLS error for %s (flags=0x%x)",
              failingUri != nullptr ? failingUri : "(unknown)",
              static_cast<unsigned>(errors));
    (void)view;
    return FALSE;
}

gboolean onWebProcessTerminated(WebKitWebView* view, WebKitWebProcessTerminationReason reason, gpointer)
{
    const char* reasonText = "unknown";
    switch (reason) {
    case WEBKIT_WEB_PROCESS_CRASHED:
        reasonText = "crashed";
        break;
    case WEBKIT_WEB_PROCESS_EXCEEDED_MEMORY_LIMIT:
        reasonText = "memory-limit";
        break;
    default:
        break;
    }

    g_warning("Fire4Nix WPE web process terminated (%s)", reasonText);
    if (view != nullptr)
        webkit_web_view_reload(view);
    return TRUE;
}

std::filesystem::path commandFilePath()
{
    if (const char* explicitPath = g_getenv("FIRE4NIX_BROWSER_COMMAND_FILE"); explicitPath && *explicitPath)
        return explicitPath;
    if (const char* runtime = g_getenv("FIRE4NIX_RUNTIME_DIR"); runtime && *runtime)
        return std::filesystem::path(runtime) / "browser.cmd";
    return std::filesystem::path(".fire4nix") / "runtime" / "browser.cmd";
}

struct CommandConsumer {
    WebKitWebView* view { nullptr };
    std::filesystem::path path;
    std::streamoff offset { 0 };
};

bool applyBrowserCommand(WebKitWebView* view, const std::string& command)
{
    if (!view || command.empty() || command.size() > 8192)
        return false;
    if (command.rfind("load:", 0) == 0) {
        const auto uri = command.substr(5);
        if (uri.rfind("https://", 0) != 0 && uri.rfind("http://", 0) != 0 &&
            uri != "about:home" && uri != "about:blank")
            return false;
        webkit_web_view_load_uri(view, uri.c_str());
        return true;
    }
    if (command == "back") {
        if (webkit_web_view_can_go_back(view))
            webkit_web_view_go_back(view);
        return true;
    }
    if (command == "key:alt+Right") {
        if (webkit_web_view_can_go_forward(view))
            webkit_web_view_go_forward(view);
        return true;
    }
    if (command == "key:ctrl+r") {
        webkit_web_view_reload(view);
        return true;
    }
    return false;
}

gboolean pollBrowserCommands(gpointer userData)
{
    auto* consumer = static_cast<CommandConsumer*>(userData);
    if (!consumer || !consumer->view)
        return G_SOURCE_REMOVE;

    std::error_code ec;
    const auto size = std::filesystem::file_size(consumer->path, ec);
    if (ec)
        return G_SOURCE_CONTINUE;
    if (static_cast<std::uintmax_t>(consumer->offset) > size)
        consumer->offset = 0;

    std::ifstream input(consumer->path);
    if (!input.is_open())
        return G_SOURCE_CONTINUE;
    input.seekg(consumer->offset);

    std::string command;
    while (std::getline(input, command)) {
        if (!command.empty() && command.back() == '\r')
            command.pop_back();
        if (!applyBrowserCommand(consumer->view, command))
            g_warning("Fire4Nix WPE rejected IPC command: %s", command.c_str());
    }
    const auto pos = input.tellg();
    consumer->offset = pos >= 0 ? pos : static_cast<std::streamoff>(size);
    return G_SOURCE_CONTINUE;
}

void onTitleNotify(GObject* object, GParamSpec*, gpointer)
{
    auto* view = WEBKIT_WEB_VIEW(object);
    const char* title = webkit_web_view_get_title(view);
    if (title != nullptr && *title != '\0')
        g_message("Fire4Nix WPE title: %s", title);
}

} // namespace

int main(int argc, char** argv)
{
    const LaunchOptions options = parseOptions(argc, argv);

    g_message("Fire4Nix WPE launcher starting");
    g_message("Fire4Nix WPE start URL: %s", options.url.c_str());

    GMainLoop* loop = g_main_loop_new(nullptr, FALSE);
    WebKitWebContext* webContext = createWebContext(options);
    if (webContext == nullptr) {
        g_printerr("Fire4Nix WPE: failed to create WebKitWebContext\n");
        return EXIT_FAILURE;
    }

    WebKitWebView* view = WEBKIT_WEB_VIEW(webkit_web_view_new_with_context(webContext));
    if (view == nullptr) {
        g_printerr("Fire4Nix WPE: failed to create WebKitWebView\n");
        return EXIT_FAILURE;
    }

    applyCookieSettings(webContext, options);
    applyBrowserDefaults(view, options);
    loadContentFilterIfRequested(view, options);

    g_signal_connect(view, "load-changed", G_CALLBACK(onLoadChanged), nullptr);
    g_signal_connect(view, "load-failed", G_CALLBACK(onLoadFailed), nullptr);
    g_signal_connect(view, "load-failed-with-tls-errors", G_CALLBACK(onLoadFailedWithTlsErrors), nullptr);
    g_signal_connect(view, "web-process-terminated", G_CALLBACK(onWebProcessTerminated), nullptr);
    g_signal_connect(view, "notify::title", G_CALLBACK(onTitleNotify), nullptr);

    if (options.privateMode)
        g_message("Fire4Nix WPE private browsing enabled");
    if (options.automationMode)
        g_message("Fire4Nix WPE automation mode enabled");
    if (options.ignoreTlsErrors)
        g_message("Fire4Nix WPE TLS errors will be ignored");
    if (!options.cookiesFile.empty())
        g_message("Fire4Nix WPE cookie jar: %s", options.cookiesFile.c_str());
    if (!options.contentFilter.empty())
        g_message("Fire4Nix WPE content filter: %s", options.contentFilter.c_str());

    g_unix_signal_add(SIGINT, onUnixSignal, loop);
    g_unix_signal_add(SIGTERM, onUnixSignal, loop);

    CommandConsumer commandConsumer { view, commandFilePath(), 0 };
    std::error_code commandEc;
    if (std::filesystem::exists(commandConsumer.path, commandEc))
        commandConsumer.offset = static_cast<std::streamoff>(std::filesystem::file_size(commandConsumer.path, commandEc));
    const guint commandPollSource = g_timeout_add(50, pollBrowserCommands, &commandConsumer);

    webkit_web_view_load_uri(view, options.url.c_str());
    g_main_loop_run(loop);

    if (commandPollSource != 0)
        g_source_remove(commandPollSource);

    if (view != nullptr)
        g_object_unref(view);
    if (webContext != nullptr)
        g_object_unref(webContext);
    if (loop != nullptr)
        g_main_loop_unref(loop);

    g_message("Fire4Nix WPE launcher exiting");
    return EXIT_SUCCESS;
}
