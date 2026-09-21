#include "browser_chrome.hpp"
#include "browser_bridge.hpp"

#include "event_dispatcher.hpp"
#include "widget_manager.hpp"
#include "fire4nix_renderer.hpp"
#include "fire4nix_ui.hpp"
#include "fire4nix_document_container.hpp"
#include "src/fire4nix_version.hpp"

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <sstream>
#include <string>
#include <vector>

#include "sdl_compat.hpp"
#include <cstdint>

namespace {

constexpr int kTopBarHeight = 34;
constexpr int kAddressBarHeight = 30;
constexpr int kBottomBarHeight = 24;

using Glyph = std::array<std::uint8_t, 7>;

Glyph glyphFor(char ch)
{
    switch (static_cast<unsigned char>(std::toupper(static_cast<unsigned char>(ch)))) {
    case 'A': return {14, 17, 17, 31, 17, 17, 17};
    case 'B': return {30, 17, 17, 30, 17, 17, 30};
    case 'C': return {14, 17, 16, 16, 16, 17, 14};
    case 'D': return {30, 17, 17, 17, 17, 17, 30};
    case 'E': return {31, 16, 16, 30, 16, 16, 31};
    case 'F': return {31, 16, 16, 30, 16, 16, 16};
    case 'G': return {14, 17, 16, 23, 17, 17, 15};
    case 'H': return {17, 17, 17, 31, 17, 17, 17};
    case 'I': return {31, 4, 4, 4, 4, 4, 31};
    case 'J': return {7, 2, 2, 2, 18, 18, 12};
    case 'K': return {17, 18, 20, 24, 20, 18, 17};
    case 'L': return {16, 16, 16, 16, 16, 16, 31};
    case 'M': return {17, 27, 21, 17, 17, 17, 17};
    case 'N': return {17, 25, 21, 19, 17, 17, 17};
    case 'O': return {14, 17, 17, 17, 17, 17, 14};
    case 'P': return {30, 17, 17, 30, 16, 16, 16};
    case 'Q': return {14, 17, 17, 17, 21, 18, 13};
    case 'R': return {30, 17, 17, 30, 20, 18, 17};
    case 'S': return {15, 16, 16, 14, 1, 1, 30};
    case 'T': return {31, 4, 4, 4, 4, 4, 4};
    case 'U': return {17, 17, 17, 17, 17, 17, 14};
    case 'V': return {17, 17, 17, 17, 17, 10, 4};
    case 'W': return {17, 17, 17, 17, 21, 21, 10};
    case 'X': return {17, 17, 10, 4, 10, 17, 17};
    case 'Y': return {17, 17, 10, 4, 4, 4, 4};
    case 'Z': return {31, 1, 2, 4, 8, 16, 31};
    case '0': return {14, 17, 19, 21, 25, 17, 14};
    case '1': return {4, 12, 4, 4, 4, 4, 14};
    case '2': return {14, 17, 1, 2, 4, 8, 31};
    case '3': return {30, 1, 1, 6, 1, 1, 30};
    case '4': return {2, 6, 10, 18, 31, 2, 2};
    case '5': return {31, 16, 16, 30, 1, 1, 30};
    case '6': return {14, 16, 16, 30, 17, 17, 14};
    case '7': return {31, 1, 2, 4, 8, 8, 8};
    case '8': return {14, 17, 17, 14, 17, 17, 14};
    case '9': return {14, 17, 17, 15, 1, 1, 14};
    case '-': return {0, 0, 0, 31, 0, 0, 0};
    case '.': return {0, 0, 0, 0, 0, 6, 6};
    case '/': return {1, 2, 2, 4, 8, 8, 16};
    case ':': return {0, 6, 6, 0, 6, 6, 0};
    case '_': return {0, 0, 0, 0, 0, 0, 31};
    case '?': return {14, 17, 1, 2, 4, 0, 4};
    case '@': return {14, 17, 1, 13, 21, 21, 14};
    case '&': return {12, 18, 20, 8, 21, 18, 13};
    case '=': return {0, 31, 0, 31, 0, 0, 0};
    case '+': return {0, 4, 4, 31, 4, 4, 0};
    case '%': return {24, 25, 2, 4, 8, 19, 3};
    case '#': return {10, 10, 31, 10, 31, 10, 10};
    case '!': return {4, 4, 4, 4, 4, 0, 4};
    case '(': return {2, 4, 8, 8, 8, 4, 2};
    case ')': return {8, 4, 2, 2, 2, 4, 8};
    case '[': return {14, 8, 8, 8, 8, 8, 14};
    case ']': return {14, 2, 2, 2, 2, 2, 14};
    case '{': return {2, 4, 4, 8, 4, 4, 2};
    case '}': return {8, 4, 4, 2, 4, 4, 8};
    case '<': return {2, 4, 8, 16, 8, 4, 2};
    case '>': return {8, 4, 2, 1, 2, 4, 8};
    case ';': return {0, 4, 4, 0, 4, 4, 8};
    case '\'': return {4, 4, 2, 0, 0, 0, 0};
    case '"': return {10, 10, 4, 0, 0, 0, 0};
    case '\\': return {16, 8, 8, 4, 2, 2, 1};
    case '|': return {4, 4, 4, 4, 4, 4, 4};
    case '~': return {0, 0, 13, 18, 0, 0, 0};
    case '`': return {8, 4, 2, 0, 0, 0, 0};
    case ' ': return {0, 0, 0, 0, 0, 0, 0};
    default: return {0, 0, 0, 0, 0, 0, 0};
    }
}

void drawGlyph(SDL_Renderer* renderer, int x, int y, char ch, int scale, SDL_Color color)
{
    SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a);
    const auto glyph = glyphFor(ch);
    for (int row = 0; row < 7; ++row) {
        for (int col = 0; col < 5; ++col) {
            if ((glyph[static_cast<size_t>(row)] >> (4 - col)) & 1U) {
                const SDL_Rect pixel{x + col * scale, y + row * scale, scale, scale};
                SDL_RenderFillRect(renderer, &pixel);
            }
        }
    }
}

void drawText(SDL_Renderer* renderer, int x, int y, const std::string& text, int scale, SDL_Color color)
{
    int cursor = x;
    for (char ch : text) {
        drawGlyph(renderer, cursor, y, ch, scale, color);
        cursor += scale * 6;
    }
}

void drawBox(SDL_Renderer* renderer, const SDL_Rect& rect, SDL_Color fill, SDL_Color outline)
{
    SDL_SetRenderDrawColor(renderer, fill.r, fill.g, fill.b, fill.a);
    SDL_RenderFillRect(renderer, &rect);
    SDL_SetRenderDrawColor(renderer, outline.r, outline.g, outline.b, outline.a);
    SDL_RenderDrawRect(renderer, &rect);
}

std::string clipText(const std::string& text, std::size_t maxChars)
{
    if (text.size() <= maxChars) {
        return text;
    }
    if (maxChars <= 3) {
        return text.substr(0, maxChars);
    }
    return text.substr(0, maxChars - 3) + "...";
}

std::string trimCopy(const std::string& text);
std::string toLowerCopy(std::string text);

bool isHomeUrl(const std::string& url)
{
    const auto lower = toLowerCopy(trimCopy(url));
    return lower.empty() || lower == "about:blank" || lower == "about:home" || lower == "home" || lower == "start";
}

bool isSearchUrl(const std::string& url)
{
    const auto lower = toLowerCopy(trimCopy(url));
    return lower.rfind("search:", 0) == 0 ||
           lower.rfind("https://duckduckgo.com/?q=", 0) == 0 ||
           lower.rfind("http://duckduckgo.com/?q=", 0) == 0;
}

std::string deriveTabTitle(const std::string& url)
{
    std::string lower = url;
    std::transform(lower.begin(), lower.end(), lower.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });

    if (isHomeUrl(url)) {
        return "ROCKNIX Home";
    }

    if (lower.rfind("search:", 0) == 0) {
        return "Search";
    }

    const auto schemePos = url.find("://");
    const auto start = schemePos == std::string::npos ? 0 : schemePos + 3;
    const auto end = url.find_first_of("/?#", start);
    auto host = url.substr(start, end == std::string::npos ? std::string::npos : end - start);

    if (host.empty()) {
        const auto colonPos = url.find(':');
        if (colonPos != std::string::npos && colonPos > 0) {
            return url.substr(0, colonPos);
        }
        return "ROCKNIX Home";
    }

    // Strip common subdomain for a cleaner tab label.
    if (host.rfind("www.", 0) == 0 && host.size() > 4) {
        host.erase(0, 4);
    }

    return host;
}

SDL_Color makeColor(std::uint8_t r, std::uint8_t g, std::uint8_t b, std::uint8_t a = 255)
{
    return SDL_Color{r, g, b, a};
}

std::string envOr(const char* name, const std::string& fallback)
{
    const char* value = std::getenv(name);
    if (value == nullptr || *value == '\0') {
        return fallback;
    }
    return std::string(value);
}


std::string trimCopy(const std::string& text);
std::string browserModeLabel();
std::string uiProfileLabel();
std::string engineLabel();
std::string engineSourceLabel();
std::string themeLabel();
std::string themeSourceLabel();
std::string engineSourceDetail();
std::string themeSourceDetail();
std::string sessionLabel();
std::string progressStageLabel();
std::string progressStageName();
std::string progressStageFocus();
std::string progressStageSummary();
std::string progressNextAction();
std::string progressAcceptance();
std::string bridgeJournalSummary();
std::size_t bridgeJournalCommandCount();
std::string bridgeJournalLastCommand();
std::string bridgeJournalPath();
std::string bridgeJournalStateSummary();

std::string bridgeJournalSummary() { return ::fire4nix::gui::bridgeJournalSummary(); }
std::size_t bridgeJournalCommandCount() { return ::fire4nix::gui::bridgeJournalCommandCount(); }
std::string bridgeJournalLastCommand() { return ::fire4nix::gui::bridgeJournalLastCommand(); }
std::string bridgeJournalPath() { return ::fire4nix::gui::bridgeJournalPath(); }
std::string bridgeJournalStateSummary() { return ::fire4nix::gui::bridgeJournalStateSummary(); }

std::string readTrimmedFile(const std::filesystem::path& path)
{
    std::ifstream file(path);
    if (!file.is_open()) {
        return {};
    }

    std::string value;
    std::getline(file, value);
    return trimCopy(value);
}

std::string joinWithBullet(const std::vector<std::string>& parts)
{
    std::string result;
    for (const auto& part : parts) {
        if (part.empty()) {
            continue;
        }
        if (!result.empty()) {
            result += " • ";
        }
        result += part;
    }
    return result;
}


std::string progressStageFocus()
{
    return envOr("FIRE4NIX_PROGRESS_FOCUS", "begin the native WPE runtime handoff, keep the bridge journal synchronized, and keep Cog fallback available");
}

std::string progressStageSummary()
{
    if (const auto value = trimCopy(envOr("FIRE4NIX_PROGRESS_STAGE_SUMMARY", "")); !value.empty()) {
        return value;
    }
    return progressStageName() + ": " + progressStageFocus();
}

std::string progressNextAction()
{
    return envOr("FIRE4NIX_PROGRESS_NEXT", "wire the native WPE launcher into the runtime bridge and keep the shell and chrome snapshots aligned");
}

std::string progressAcceptance()
{
    return envOr("FIRE4NIX_PROGRESS_ACCEPTANCE", "Marco 3 has started, the bridge journal and chrome status stay synchronized, and the native WPE runtime handoff is the active focus with Cog fallback preserved");
}

std::string betaContext()
{
    return std::string(FIRE4NIX_VERSION) + " • " + browserModeLabel() + " • stage " + progressStageLabel() + " (" + progressStageName() + ") • summary " + progressStageSummary() + " • focus " + progressStageFocus() + " • " + uiProfileLabel() + " • theme " + themeLabel() + " [" + themeSourceLabel() + "] • engine " + engineLabel() + " [" + engineSourceLabel() + "] • bridge " + bridgeJournalStateSummary() + " • commands " + std::to_string(bridgeJournalCommandCount()) + " • next " + progressNextAction() + " • acceptance " + progressAcceptance();
}

std::string statusWithContext(const std::string& prefix)
{
    return prefix + " • " + betaContext();
}

std::string editingStatus(const std::string& prefix)
{
    return prefix + " • " + betaContext() + " • press Enter to search";
}

std::string tabStatus(const std::string& prefix, std::size_t index, const std::string& title)
{
    return prefix + " " + std::to_string(index + 1) + ": " + title + " • " + betaContext();
}

std::string trimCopy(const std::string& text)
{
    const auto first = text.find_first_not_of(" \t\r\n");
    if (first == std::string::npos) {
        return {};
    }
    const auto last = text.find_last_not_of(" \t\r\n");
    return text.substr(first, last - first + 1);
}

std::string toLowerCopy(std::string text)
{
    std::transform(text.begin(), text.end(), text.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return text;
}

std::string percentEncode(const std::string& text)
{
    static constexpr char hex[] = "0123456789ABCDEF";
    std::string encoded;
    encoded.reserve(text.size() * 3);
    for (unsigned char c : text) {
        if (std::isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~') {
            encoded.push_back(static_cast<char>(c));
        } else if (c == ' ') {
            encoded.push_back('+');
        } else {
            encoded.push_back('%');
            encoded.push_back(hex[(c >> 4) & 0xF]);
            encoded.push_back(hex[c & 0xF]);
        }
    }
    return encoded;
}

std::string buildSearchUrl(const std::string& query)
{
    const std::string trimmed = trimCopy(query);
    if (trimmed.empty()) {
        return envOr("FIRE4NIX_HOME_URL", "about:home");
    }

    std::string searchUrl = envOr("FIRE4NIX_SEARCH_URL", "https://duckduckgo.com/?q=%s");
    const std::string encoded = percentEncode(trimmed);
    const auto placeholder = searchUrl.find("%s");
    if (placeholder != std::string::npos) {
        searchUrl.replace(placeholder, 2, encoded);
        return searchUrl;
    }

    if (searchUrl.find('?') == std::string::npos) {
        searchUrl += "?q=";
    } else if (!searchUrl.empty() && searchUrl.back() != '?' && searchUrl.back() != '&' && searchUrl.back() != '=') {
        searchUrl.push_back('&');
        searchUrl += "q=";
    }
    searchUrl += encoded;
    return searchUrl;
}

bool looksLikeHostInput(const std::string& text)
{
    if (text.empty()) {
        return false;
    }

    if (text.find(' ') != std::string::npos) {
        return false;
    }

    if (text.find('/') != std::string::npos) {
        return true;
    }

    if (text.find('.') != std::string::npos) {
        return true;
    }

    return text == "localhost" || text.rfind("localhost.", 0) == 0;
}

bool hasKnownScheme(const std::string& text)
{
    const auto lower = toLowerCopy(text);
    return lower.rfind("http://", 0) == 0 ||
           lower.rfind("https://", 0) == 0 ||
           lower.rfind("file://", 0) == 0 ||
           lower.rfind("about:", 0) == 0 ||
           lower.rfind("data:", 0) == 0 ||
           lower.rfind("mailto:", 0) == 0 ||
           lower.rfind("ftp://", 0) == 0;
}

std::string normalizeUrlInput(const std::string& input)
{
    const std::string text = trimCopy(input);
    if (text.empty()) {
        return envOr("FIRE4NIX_HOME_URL", "about:home");
    }

    const auto lower = toLowerCopy(text);
    if (isHomeUrl(text)) {
        return envOr("FIRE4NIX_HOME_URL", "about:home");
    }

    if (lower.rfind("search:", 0) == 0) {
        return buildSearchUrl(trimCopy(text.substr(7)));
    }

    if (lower.rfind("search ", 0) == 0) {
        return buildSearchUrl(trimCopy(text.substr(7)));
    }

    if (lower.rfind("q=", 0) == 0) {
        return buildSearchUrl(trimCopy(text.substr(2)));
    }

    if (hasKnownScheme(text)) {
        return text;
    }

    if (lower.rfind("www.", 0) == 0) {
        return std::string("https://") + text;
    }

    if (looksLikeHostInput(text)) {
        return std::string("https://") + text;
    }

    return buildSearchUrl(text);
}

std::string startupUrl()
{
    const auto explicitStart = envOr("FIRE4NIX_START_PAGE", "");
    if (!trimCopy(explicitStart).empty()) {
        return normalizeUrlInput(explicitStart);
    }

    return normalizeUrlInput(envOr("FIRE4NIX_HOME_URL", "about:home"));
}

std::string defaultTabLabel()
{
    return std::string("Fire4Nix Beta Home");
}

std::string uiProfileLabel()
{
    return envOr("FIRE4NIX_UI_PROFILE", "compact");
}

std::string engineLabel()
{
    const auto engineFile = trimCopy(envOr("FIRE4NIX_ENGINE_FILE", ""));
    if (!engineFile.empty()) {
        const auto fromFile = readTrimmedFile(std::filesystem::path(engineFile));
        if (!fromFile.empty()) {
            return fromFile;
        }
    }

    const auto engine = trimCopy(envOr("FIRE4NIX_ENGINE", "auto"));
    if (!engine.empty()) {
        return engine;
    }

    return "auto";
}

std::string engineSourceLabel()
{
    if (const auto file = trimCopy(envOr("FIRE4NIX_ENGINE_FILE", "")); !file.empty()) {
        return "file";
    }
    if (const auto value = trimCopy(envOr("FIRE4NIX_ENGINE", "")); !value.empty()) {
        return "environment";
    }
    return "default";
}

std::string themeLabel()
{
    const auto themeFile = trimCopy(envOr("FIRE4NIX_THEME_FILE", ""));
    if (!themeFile.empty()) {
        const auto fromFile = readTrimmedFile(std::filesystem::path(themeFile));
        if (!fromFile.empty()) {
            return fromFile;
        }
    }

    const auto theme = trimCopy(envOr("FIRE4NIX_THEME", "beta-dark"));
    if (!theme.empty()) {
        return theme;
    }

    return "beta-dark";
}

std::string themeSourceLabel()
{
    if (const auto file = trimCopy(envOr("FIRE4NIX_THEME_FILE", "")); !file.empty()) {
        return "file";
    }
    if (const auto value = trimCopy(envOr("FIRE4NIX_THEME", "")); !value.empty()) {
        return "environment";
    }
    return "default";
}

std::string browserModeLabel()
{
    return envOr("FIRE4NIX_BROWSER_MODE", "beta");
}

std::string progressStageLabel()
{
    return envOr("FIRE4NIX_PROGRESS_STAGE", "marco3-start");
}

std::string progressStageName()
{
    if (const auto value = trimCopy(envOr("FIRE4NIX_PROGRESS_STAGE_NAME", "")); !value.empty()) {
        return value;
    }

    const auto stage = progressStageLabel();
    if (stage == "marco1-cleanup" || stage == "phase2-continuation") {
        return "Marco 1 complete";
    }
    if (stage == "phase2-browser-bridge") {
        return "browser bridge prep";
    }
    if (stage == "marco2-complete") {
        return "Marco 2 complete";
    }
    if (stage == "marco3-start") {
        return "Marco 3 start";
    }
    if (stage == "phase2-wpe-runtime" || stage == "phase3-wpe-runtime") {
        return "wpe runtime handoff";
    }
    if (stage == "phase2-rocknix-validation" || stage == "phase3-rocknix-validation") {
        return "rocknix validation";
    }
    return stage;
}

std::string engineSourceDetail()
{
    if (const auto file = trimCopy(envOr("FIRE4NIX_ENGINE_FILE", "")); !file.empty()) {
        return std::string("file:") + file;
    }

    if (const auto value = trimCopy(envOr("FIRE4NIX_ENGINE", "")); !value.empty()) {
        return std::string("env:") + value;
    }

    return "default";
}

std::string themeSourceDetail()
{
    if (const auto file = trimCopy(envOr("FIRE4NIX_THEME_FILE", "")); !file.empty()) {
        return std::string("file:") + file;
    }

    if (const auto value = trimCopy(envOr("FIRE4NIX_THEME", "")); !value.empty()) {
        return std::string("env:") + value;
    }

    return "default";
}

std::string sessionLabel()
{
    return envOr("FIRE4NIX_SESSION_LABEL", "Fire4Nix beta");
}

bool rendererDimensions(int& width, int& height)
{
    if (!fire4nix::ui::size(width, height)) {
        return false;
    }
    return width > 0 && height > 0;
}

struct PagePreviewCache {
    std::string url;
    std::string summary;
};

PagePreviewCache& pagePreviewCache()
{
    static PagePreviewCache cache;
    return cache;
}

std::string stripMarkupAndNormalize(const std::string& text)
{
    std::string output;
    output.reserve(text.size());

    bool inTag = false;
    bool entityMode = false;
    for (char ch : text) {
        if (ch == '<') {
            inTag = true;
            entityMode = false;
            continue;
        }
        if (ch == '>') {
            inTag = false;
            output.push_back(' ');
            continue;
        }
        if (inTag) {
            continue;
        }

        if (ch == '&') {
            entityMode = true;
            continue;
        }
        if (entityMode) {
            if (ch == ';') {
                entityMode = false;
                output.push_back(' ');
            }
            continue;
        }

        if (std::isspace(static_cast<unsigned char>(ch))) {
            if (!output.empty() && output.back() != ' ') {
                output.push_back(' ');
            }
        } else {
            output.push_back(ch);
        }
    }

    return trimCopy(output);
}

std::string pagePreviewForUrl(const std::string& url)
{
    auto& cache = pagePreviewCache();
    if (cache.url == url && !cache.summary.empty()) {
        return cache.summary;
    }

    cache.url = url;
    const auto resource = fire4nix::document_container::loadResource(url);
    auto text = stripMarkupAndNormalize(resource);
    if (text.empty()) {
        text = trimCopy(resource);
    }
    if (text.empty()) {
        text = "No page content available yet.";
    }

    cache.summary = clipText(text, 220);
    return cache.summary;
}

void renderHomeDashboard(const fire4nix::gui::BrowserChrome& chrome)
{
    auto* renderer = fire4nix::renderer::nativeRenderer();
    if (!renderer) {
        return;
    }

    int width = 640;
    int height = 480;
    if (!rendererDimensions(width, height)) {
        return;
    }

    const int panelY = kTopBarHeight + kAddressBarHeight + 10;
    const int panelH = std::max(84, height - panelY - kBottomBarHeight - 10);
    if (panelH <= 0) {
        return;
    }

    const SDL_Rect panel{8, panelY, width - 16, panelH};
    drawBox(renderer, panel, makeColor(19, 23, 31, 255), makeColor(58, 72, 92, 255));

    const auto currentUrl = chrome.url().empty() ? std::string("about:home") : chrome.url();
    const auto currentTitle = chrome.currentTabTitle().empty() ? std::string("ROCKNIX Home") : chrome.currentTabTitle();
    const auto historyCount = chrome.historyCount();
    const auto historyIndex = chrome.historyCount() == 0 ? 0 : chrome.historyIndex() + 1;

    drawText(renderer, panel.x + 12, panel.y + 10, "FIRE4NIX BETA DASHBOARD", 2, makeColor(240, 246, 255, 255));
    drawText(renderer, panel.x + 12, panel.y + 28, clipText(std::string("Session: ") + sessionLabel(), static_cast<std::size_t>(std::max(8, (panel.w - 24) / 12))), 1, makeColor(184, 200, 220, 255));
    drawText(renderer, panel.x + 12, panel.y + 40, clipText(std::string("Version: ") + FIRE4NIX_VERSION + "  •  Platform: " + FIRE4NIX_PLATFORM, static_cast<std::size_t>(std::max(8, (panel.w - 24) / 12))), 1, makeColor(184, 200, 220, 255));
    drawText(renderer, panel.x + 12, panel.y + 52, clipText(std::string("Theme: ") + themeLabel() + " [" + themeSourceLabel() + "]  •  Engine: " + engineLabel() + " [" + engineSourceLabel() + "]  •  Profile: " + uiProfileLabel(), static_cast<std::size_t>(std::max(8, (panel.w - 24) / 12))), 1, makeColor(184, 200, 220, 255));
    drawText(renderer, panel.x + 12, panel.y + 64, clipText(std::string("Mode: ") + browserModeLabel() + "  •  Tabs: " + std::to_string(chrome.tabCount()) + "  •  History: " + std::to_string(historyIndex) + "/" + std::to_string(historyCount), static_cast<std::size_t>(std::max(8, (panel.w - 24) / 12))), 1, makeColor(170, 190, 214, 255));
    drawText(renderer, panel.x + 12, panel.y + 76, clipText(std::string("Home: ") + currentUrl, static_cast<std::size_t>(std::max(8, (panel.w - 24) / 12))), 1, makeColor(170, 190, 214, 255));
    drawText(renderer, panel.x + 12, panel.y + 88, clipText(std::string("Readiness: ") + chrome.readinessSummary(), static_cast<std::size_t>(std::max(8, (panel.w - 24) / 12))), 1, makeColor(170, 190, 214, 255));
    drawText(renderer, panel.x + 12, panel.y + 100, clipText(std::string("Diagnostics: ") + chrome.diagnosticSummary(), static_cast<std::size_t>(std::max(8, (panel.w - 24) / 12))), 1, makeColor(170, 190, 214, 255));

    const auto pagePreview = pagePreviewForUrl(currentUrl);
    const int previewY = panel.y + 116;
    drawText(renderer, panel.x + 12, previewY, "Page preview", 1, makeColor(230, 236, 246, 255));
    drawText(renderer, panel.x + 12, previewY + 12, clipText(pagePreview, static_cast<std::size_t>(std::max(8, (panel.w - 24) / 12))), 1, makeColor(170, 190, 214, 255));
    drawText(renderer, panel.x + 12, previewY + 24, clipText(std::string("Source: ") + currentUrl, static_cast<std::size_t>(std::max(8, (panel.w - 24) / 12))), 1, makeColor(170, 190, 214, 255));

    const int checklistY = panel.y + 154;
    drawText(renderer, panel.x + 12, checklistY, "Beta test checklist", 1, makeColor(230, 236, 246, 255));
    drawText(renderer, panel.x + 12, checklistY + 12, "1. A = edit address", 1, makeColor(170, 190, 214, 255));
    drawText(renderer, panel.x + 12, checklistY + 24, "2. Type a domain or search", 1, makeColor(170, 190, 214, 255));
    drawText(renderer, panel.x + 12, checklistY + 36, "3. B = back, X = forward", 1, makeColor(170, 190, 214, 255));
    drawText(renderer, panel.x + 12, checklistY + 48, "4. Y = new tab, R1 = toggle UI", 1, makeColor(170, 190, 214, 255));
    drawText(renderer, panel.x + 12, checklistY + 60, "5. Open about:home to return here", 1, makeColor(170, 190, 214, 255));
    drawText(renderer, panel.x + 12, checklistY + 72, "6. Confirm readiness summary, stage summary, and next step", 1, makeColor(170, 190, 214, 255));
    drawText(renderer, panel.x + 12, checklistY + 84, "7. Run browser_manager.sh advance to capture the next stage snapshot", 1, makeColor(170, 190, 214, 255));

    const int shortcutsY = panel.y + panel.h - 30;
    drawText(renderer, panel.x + 12, shortcutsY, "A edit • B back • X forward • Y new tab", 1, makeColor(230, 236, 246, 255));
    drawText(renderer, panel.x + 12, shortcutsY + 12, "Theme, engine, and profile are read live for beta testing.", 1, makeColor(170, 190, 214, 255));
}

#if defined(__has_include)
#  if __has_include(<SDL2/SDL.h>)
void ensureTextInputEnabled()
{
    SDL_StartTextInput();
}

void ensureTextInputDisabled()
{
    SDL_StopTextInput();
}
#  else
void ensureTextInputEnabled() {}
void ensureTextInputDisabled() {}
#  endif
#else
void ensureTextInputEnabled() {}
void ensureTextInputDisabled() {}
#endif

} // namespace

namespace fire4nix::gui {

void BrowserChrome::attachWidgetManager(WidgetManager* wm)
{
    widgets_ = wm;
    if (widgets_ && !widgetsInitialized_) {
        initializeDefaultWidgets();
    }
}

void BrowserChrome::attachBridge(BrowserBridge* bridge)
{
    bridge_ = bridge != nullptr ? bridge : &defaultBrowserBridge();
    setStatus(statusWithContext(std::string("Bridge ready: ") + bridge_->describe()));
    markDirty();
}

bool BrowserChrome::widgetsReady() const
{
    return widgets_ != nullptr && widgetsInitialized_;
}

std::size_t BrowserChrome::tabCount() const
{
    return tabStrip_.count();
}

std::size_t BrowserChrome::historyCount() const
{
    return history_.size();
}

std::size_t BrowserChrome::historyIndex() const
{
    return history_.empty() ? 0 : std::min(historyIndex_, history_.size() - 1);
}

const std::string& BrowserChrome::currentTabTitle() const
{
    return tabStrip_.currentTitle();
}


int BrowserChrome::readinessScore() const
{
    int score = 0;
    score += widgetsReady() ? 1 : 0;
    score += tabCount() > 0 ? 1 : 0;
    score += historyCount() > 0 ? 1 : 0;
    score += !url().empty() ? 1 : 0;
    score += !currentTabTitle().empty() ? 1 : 0;
    score += !status().empty() ? 1 : 0;
    score += !themeLabel().empty() ? 1 : 0;
    score += !engineLabel().empty() ? 1 : 0;
    return score;
}

std::string BrowserChrome::readinessSummary() const
{
    std::vector<std::string> checks;
    checks.reserve(8);

    checks.push_back(std::string("widgets ") + (widgetsReady() ? "ok" : "missing"));
    checks.push_back(std::string("tabs ") + (tabCount() > 0 ? "ok" : "missing"));
    checks.push_back(std::string("history ") + (historyCount() > 0 ? "ok" : "missing"));
    checks.push_back(std::string("url ") + (!url().empty() ? "ok" : "missing"));
    checks.push_back(std::string("title ") + (!currentTabTitle().empty() ? "ok" : "missing"));
    checks.push_back(std::string("status ") + (!status().empty() ? "ok" : "missing"));
    checks.push_back(std::string("theme ") + (themeLabel().empty() ? "missing" : themeLabel()) + " [" + themeSourceDetail() + "]");
    checks.push_back(std::string("engine ") + (engineLabel().empty() ? "missing" : engineLabel()) + " [" + engineSourceDetail() + "]");

    return std::string("Beta readiness ") + std::to_string(readinessScore()) + "/8 • " + joinWithBullet(checks);
}

std::string BrowserChrome::betaSummary() const
{
    const auto currentTitle = currentTabTitle().empty() ? std::string("ROCKNIX Home") : currentTabTitle();
    const auto bridgeLabel = bridge_ != nullptr ? bridge_->describe() : std::string("bridge-unbound");
    return std::string(FIRE4NIX_VERSION) + " • " + browserModeLabel() + " • stage " + progressStageLabel() + " (" + progressStageName() + ") • focus " + progressStageFocus() + " • " + uiProfileLabel() + " • " + themeLabel() + " [" + themeSourceLabel() + "] • " + engineLabel() + " [" + engineSourceLabel() + "] • bridge " + bridgeLabel + " • next " + progressNextAction() + " • acceptance " + progressAcceptance() + " • readiness " + std::to_string(readinessScore()) + "/8 • tab " + currentTitle + " • tabs " + std::to_string(tabCount()) + " • history " + std::to_string(historyCount());
}

std::string BrowserChrome::diagnosticSummary() const
{
    const auto bridgeLabel = bridge_ != nullptr ? bridge_->describe() : std::string("bridge-unbound");
    return std::string("theme source ") + themeSourceDetail() + " • engine source " + engineSourceDetail() + " • bridge " + bridgeLabel + " • journal " + bridgeJournalStateSummary() + " • " + readinessSummary() + " • stage " + progressStageName() + " • summary " + progressStageSummary() + " • focus " + progressStageFocus() + " • next " + progressNextAction() + " • acceptance " + progressAcceptance();
}

bool BrowserChrome::needsRender() const
{
    return widgetsInitialized_ && dirty_;
}

void BrowserChrome::markDirty()
{
    dirty_ = true;
}

void BrowserChrome::clearDirty()
{
    dirty_ = false;
}

bool BrowserChrome::validate(std::string* reason) const
{
    if (!widgets_) {
        if (reason) {
            *reason = "WidgetManager missing";
        }
        return false;
    }

    if (!widgetsInitialized_) {
        if (reason) {
            *reason = "Chrome widgets not initialized";
        }
        return false;
    }

    if (tabStrip_.empty()) {
        if (reason) {
            *reason = "TabStrip is empty";
        }
        return false;
    }

    if (tabStrip_.count() == 0) {
        if (reason) {
            *reason = "TabStrip count invalid";
        }
        return false;
    }

    const auto currentIndex = tabStrip_.currentIndex();
    if (currentIndex < 0 || static_cast<std::size_t>(currentIndex) >= tabStrip_.count()) {
        if (reason) {
            *reason = "TabStrip current index out of range";
        }
        return false;
    }

    if (history_.empty()) {
        if (reason) {
            *reason = "History is empty";
        }
        return false;
    }

    if (historyIndex_ >= history_.size()) {
        if (reason) {
            *reason = "History index out of range";
        }
        return false;
    }

    return true;
}

void BrowserChrome::reset()
{
    ensureTextInputDisabled();
    widgetsInitialized_ = false;
    dirty_ = true;
    widgets_ = nullptr;
    topWidget_.owner = nullptr;
    addressWidget_.owner = nullptr;
    bottomWidget_.owner = nullptr;
    addressBar_ = fire4nix::AddressBar{};
    tabStrip_ = ::TabStrip{};
    statusBar_ = ::StatusBar{};
    history_.clear();
    historyIndex_ = 0;
}

void BrowserChrome::pollBrowserState()
{
    std::filesystem::path path;
    if (const char* explicitPath = std::getenv("FIRE4NIX_BROWSER_STATE_FILE"); explicitPath && *explicitPath)
        path = explicitPath;
    else if (const char* runtime = std::getenv("FIRE4NIX_RUNTIME_DIR"); runtime && *runtime)
        path = std::filesystem::path(runtime) / "browser.state";
    else
        path = std::filesystem::path(".fire4nix") / "runtime" / "browser.state";

    std::ifstream input(path);
    if (!input.is_open()) return;
    std::string raw((std::istreambuf_iterator<char>(input)), std::istreambuf_iterator<char>());
    if (raw.empty() || raw == lastBrowserState_) return;
    lastBrowserState_ = raw;

    std::string event, uri, title, detail;
    bool loading = false;
    std::istringstream stream(raw);
    for (std::string line; std::getline(stream, line); ) {
        const auto pos = line.find('=');
        if (pos == std::string::npos) continue;
        const auto key = line.substr(0, pos);
        const auto value = line.substr(pos + 1);
        if (key == "event") event = value;
        else if (key == "uri") uri = value;
        else if (key == "title") title = value;
        else if (key == "detail") detail = value;
        else if (key == "loading") loading = value == "1";
    }

    if (!uri.empty() && !addressBar_.editing()) {
        addressBar_.setUrl(uri);
        pushHistory(uri);
    }
    if (!title.empty()) setTabTitle(title);
    if (event == "load-started") setProgress(10);
    else if (event == "load-committed") setProgress(55);
    else if (event == "load-finished") setProgress(100);
    else if (loading) setProgress(std::max(10, std::min(90, progress())));

    if (event == "load-failed" || event == "tls-error" || event == "web-process-terminated")
        setStatus("Browser error: " + (detail.empty() ? event : detail));
    else if (event == "load-finished")
        setStatus(title.empty() ? (uri.empty() ? "Page loaded" : uri) : title);
    markDirty();
}

void BrowserChrome::setUrl(const std::string& url)
{
    syncLoadedUrl(url);
}

void BrowserChrome::setStatus(const std::string& text)
{
    statusBar_.setStatus(text);
    markDirty();
}

void BrowserChrome::setProgress(int progress)
{
    statusBar_.setProgress(progress);
    markDirty();
}

void BrowserChrome::setTabTitle(const std::string& title)
{
    tabStrip_.setCurrentTitle(title);
    markDirty();
}

void BrowserChrome::navigateTo(const std::string& url)
{
    const auto committedUrl = normalizeUrlInput(url);
    const bool bridged = bridge_ != nullptr && bridge_->loadUrl(committedUrl);

    if (!bridged) {
        setStatus("Navigation unavailable: backend disconnected or URL rejected");
        return;
    }

    pushHistory(committedUrl);
    syncLoadedUrl(committedUrl);
    setProgress(0); // Submission is not confirmation of page loading.
    if (isHomeUrl(committedUrl)) {
        setStatus("Home requested; waiting for browser");
    } else if (isSearchUrl(committedUrl)) {
        setStatus("Search requested; waiting for browser");
    } else {
        setStatus("Navigation requested; waiting for browser");
    }
    markDirty();
}

void BrowserChrome::goBack()
{
    if (!canGoBack()) {
        return;
    }

    const bool bridged = bridge_ != nullptr && bridge_->goBack();
    if (!bridged) { setStatus("Back unavailable"); return; }
    --historyIndex_;
    const auto& target = history_[historyIndex_];
    syncLoadedUrl(target);
    setProgress(0);
    setStatus(statusWithContext(std::string(bridged ? "Bridge back: " : "Back: ") + target));
    markDirty();
}

void BrowserChrome::goForward()
{
    if (!canGoForward()) {
        return;
    }

    const bool bridged = bridge_ != nullptr && bridge_->goForward();
    if (!bridged) { setStatus("Forward unavailable"); return; }
    ++historyIndex_;
    const auto& target = history_[historyIndex_];
    syncLoadedUrl(target);
    setProgress(0);
    setStatus(statusWithContext(std::string(bridged ? "Bridge forward: " : "Forward: ") + target));
    markDirty();
}

void BrowserChrome::reload()
{
    const auto currentUrl = url().empty() ? normalizeUrlInput(envOr("FIRE4NIX_HOME_URL", "about:home")) : url();
    const bool bridged = bridge_ != nullptr && bridge_->reload();
    if (!bridged) { setStatus("Reload unavailable"); return; }
    setProgress(0);
    setStatus(statusWithContext(std::string(bridged ? "Bridge reload: " : "Reload requested: ") + currentUrl));
    markDirty();
}

void BrowserChrome::goHome()
{
    const auto homeUrl = normalizeUrlInput(envOr("FIRE4NIX_HOME_URL", "about:home"));
    navigateTo(homeUrl);
    markDirty();
}

void BrowserChrome::toggleFullscreen()
{
    const bool bridged = bridge_ != nullptr && bridge_->toggleFullscreen();
    setStatus(statusWithContext(bridged ? "Bridge fullscreen toggle" : "Fullscreen toggle requested"));
    setProgress(0);
    markDirty();
}

bool BrowserChrome::canGoBack() const
{
    return !history_.empty() && historyIndex_ > 0;
}

bool BrowserChrome::canGoForward() const
{
    return !history_.empty() && historyIndex_ + 1 < history_.size();
}

const std::string& BrowserChrome::url() const
{
    return addressBar_.url();
}

const std::string& BrowserChrome::status() const
{
    return statusBar_.status();
}

int BrowserChrome::progress() const
{
    return statusBar_.progress();
}

void BrowserChrome::beginAddressEditing()
{
    ensureTextInputEnabled();
    addressBar_.beginEditing();
    setStatus(editingStatus(std::string("Editing: ") + addressBar_.editedUrl()));
    setProgress(0);
    markDirty();
}

void BrowserChrome::cancelAddressEditing()
{
    addressBar_.cancelEditing();
    ensureTextInputDisabled();
    setStatus(addressBar_.url().empty() ? statusWithContext("Address cancelled") : statusWithContext(std::string("Address restored: ") + addressBar_.url()));
    markDirty();
}

void BrowserChrome::commitAddressEditing()
{
    const auto target = normalizeUrlInput(addressBar_.url());
    addressBar_.commitEditing();
    ensureTextInputDisabled();
    navigateTo(target);
    markDirty();
}

void BrowserChrome::appendAddressText(const std::string& text)
{
    if (text.empty()) {
        return;
    }

    if (!addressBar_.editing()) {
        beginAddressEditing();
    }

    addressBar_.appendText(text);
    setStatus(editingStatus(std::string("Editing: ") + addressBar_.editedUrl()));
    setProgress(std::min(99, std::max(0, static_cast<int>(addressBar_.editedUrl().size()) * 2)));
    markDirty();
}

void BrowserChrome::backspaceAddress()
{
    addressBar_.backspace();
    setStatus(editingStatus(std::string("Editing: ") + addressBar_.editedUrl()));
    setProgress(std::min(99, std::max(0, static_cast<int>(addressBar_.editedUrl().size()) * 2)));
    markDirty();
}

bool BrowserChrome::isAddressEditing() const
{
    return addressBar_.editing();
}
void BrowserChrome::pushHistory(const std::string& url)
{
    if (url.empty()) {
        return;
    }

    if (!history_.empty() && historyIndex_ < history_.size() && history_[historyIndex_] == url) {
        return;
    }

    if (!history_.empty() && historyIndex_ + 1 < history_.size()) {
        history_.erase(history_.begin() + static_cast<std::ptrdiff_t>(historyIndex_ + 1), history_.end());
    }

    if (!history_.empty() && history_.back() == url) {
        historyIndex_ = history_.size() - 1;
        return;
    }

    history_.push_back(url);
    constexpr std::size_t kMaxHistoryEntries = 32;
    if (history_.size() > kMaxHistoryEntries) {
        const auto excess = history_.size() - kMaxHistoryEntries;
        history_.erase(history_.begin(), history_.begin() + static_cast<std::ptrdiff_t>(excess));
    }
    historyIndex_ = history_.empty() ? 0 : history_.size() - 1;
}

void BrowserChrome::syncLoadedUrl(const std::string& url)
{
    const auto normalized = normalizeUrlInput(url);
    addressBar_.setUrl(normalized);
    const auto title = deriveTabTitle(normalized);
    setTabTitle(title);
    markDirty();

    if (isHomeUrl(normalized)) {
        setStatus(statusWithContext(sessionLabel() + " • home • " + std::to_string(tabCount()) + " tabs"));
        setProgress(0);
    } else if (isSearchUrl(normalized)) {
        setStatus(statusWithContext("Search ready • " + std::to_string(historyCount()) + " history entries"));
    } else {
        setStatus(statusWithContext(normalized + " • " + std::to_string(historyCount()) + " history entries"));
    }
}
void BrowserChrome::nextTab()
{
    tabStrip_.nextTab();
    const auto title = tabStrip_.currentTitle().empty() ? std::string("ROCKNIX Home") : tabStrip_.currentTitle();
    setStatus(tabStatus("Tab", static_cast<std::size_t>(tabStrip_.currentIndex()), title));
    markDirty();
}

void BrowserChrome::previousTab()
{
    tabStrip_.previousTab();
    const auto title = tabStrip_.currentTitle().empty() ? std::string("ROCKNIX Home") : tabStrip_.currentTitle();
    setStatus(tabStatus("Tab", static_cast<std::size_t>(tabStrip_.currentIndex()), title));
    markDirty();
}

void BrowserChrome::openTab(const std::string& title)
{
    const auto effectiveTitle = title.empty() ? std::string("New Tab") : title;
    const bool bridged = bridge_ != nullptr && bridge_->openTab(effectiveTitle);
    if (!bridged) { setStatus("Multiple browser tabs are not available yet"); return; }
    tabStrip_.openTab(effectiveTitle);
    const auto currentTitle = tabStrip_.currentTitle().empty() ? std::string("New Tab") : tabStrip_.currentTitle();
    setStatus(statusWithContext(std::string(bridged ? "Bridge tab opened " : "Opened beta tab ") + std::to_string(tabStrip_.currentIndex() + 1) + ": " + currentTitle));
    setProgress(0);
    markDirty();
}

void BrowserChrome::closeCurrentTab()
{
    if (tabStrip_.count() <= 1) {
        tabStrip_.reset(0);
        if (tabStrip_.count() == 0) {
            tabStrip_.addTab("ROCKNIX Home");
        }
        if (bridge_ != nullptr) {
            bridge_->closeTab();
        }
        setStatus(statusWithContext(std::string("Last tab kept open on ") + FIRE4NIX_PLATFORM + " • beta safe mode"));
        markDirty();
        return;
    }

    const bool bridged = bridge_ != nullptr && bridge_->closeTab();
    if (!bridged) { setStatus("Close tab unavailable"); return; }
    tabStrip_.closeCurrentTab();
    const auto currentTitle = tabStrip_.currentTitle().empty() ? std::string("ROCKNIX Home") : tabStrip_.currentTitle();
    setStatus(statusWithContext(std::string(bridged ? "Bridge tab closed, now on " : "Closed beta tab, now on ") + std::to_string(tabStrip_.currentIndex() + 1) + ": " + currentTitle));
    setProgress(0);
    markDirty();
}

void BrowserChrome::resetTabs(int index)
{
    if (tabStrip_.count() == 0) {
        tabStrip_.addTab(defaultTabLabel());
    }
    tabStrip_.reset(index);
    if (tabStrip_.count() == 0) {
        tabStrip_.addTab(defaultTabLabel());
    }
    if (history_.empty()) {
        history_.push_back(envOr("FIRE4NIX_HOME_URL", "about:blank"));
        historyIndex_ = 0;
    } else if (historyIndex_ >= history_.size()) {
        historyIndex_ = history_.size() - 1;
    }
    const auto title = tabStrip_.currentTitle().empty() ? defaultTabLabel() : tabStrip_.currentTitle();
    setStatus(tabStatus("Tab", static_cast<std::size_t>(tabStrip_.currentIndex()), title));
    markDirty();
}

void BrowserChrome::applyAction(UiAction action)
{
    switch (action) {
    case UiAction::DeleteBackward:
        if (addressBar_.editing()) {
            backspaceAddress();
        }
        break;
    case UiAction::Activate:
        if (addressBar_.editing()) {
            commitAddressEditing();
        } else {
            beginAddressEditing();
        }
        break;
    case UiAction::Back:
        if (addressBar_.editing()) {
            if (!addressBar_.editedUrl().empty()) {
                backspaceAddress();
            } else {
                cancelAddressEditing();
            }
        } else if (canGoBack()) {
            goBack();
        } else {
            previousTab();
        }
        break;
    case UiAction::Forward:
        if (addressBar_.editing()) {
            commitAddressEditing();
        } else if (canGoForward()) {
            goForward();
        } else {
            nextTab();
        }
        break;
    case UiAction::Reload:
        reload();
        break;
    case UiAction::Home:
        goHome();
        break;
    case UiAction::Fullscreen:
        toggleFullscreen();
        break;
    case UiAction::PreviousTab:
        previousTab();
        break;
    case UiAction::NextTab:
        nextTab();
        break;
    case UiAction::OpenTab:
        openTab();
        break;
    case UiAction::CloseTab:
        closeCurrentTab();
        break;
    default:
        break;
    }
}

void BrowserChrome::renderTopBar(bool focused)
{
    auto* renderer = fire4nix::renderer::nativeRenderer();
    if (!renderer) {
        return;
    }

    int width = 640;
    int height = 480;
    if (!rendererDimensions(width, height)) {
        return;
    }
    (void)height;

    const SDL_Rect bar{0, 0, width, kTopBarHeight};
    drawBox(renderer, bar, makeColor(16, 20, 28, 255), focused ? makeColor(92, 178, 255, 255) : makeColor(46, 56, 72, 255));

    drawText(renderer, 10, 8, "FIRE4NIX BETA", 2, makeColor(212, 232, 255, 255));
    drawText(renderer, 10, 20, clipText(sessionLabel() + " • stage " + progressStageLabel() + " (" + progressStageName() + ") • " + readinessSummary(), 36), 1, makeColor(170, 190, 214, 255));

    const auto tabTitle = clipText(tabStrip_.currentTitle().empty() ? std::string("ROCKNIX Home") : tabStrip_.currentTitle(), 20);
    drawText(renderer, 140, 9, tabTitle, 2, makeColor(240, 240, 250, 255));

    const auto tabCount = std::max<std::size_t>(1, tabStrip_.count());
    const SDL_Rect navBack{width - 112, 6, 26, 20};
    const SDL_Rect navFwd{width - 82, 6, 26, 20};
    const SDL_Rect navTab{width - 52, 6, 20, 20};
    const SDL_Rect navClose{width - 28, 6, 20, 20};
    const auto backOutline = canGoBack() ? makeColor(92, 178, 255, 255) : makeColor(78, 90, 110, 255);
    const auto fwdOutline = canGoForward() ? makeColor(92, 178, 255, 255) : makeColor(78, 90, 110, 255);
    drawBox(renderer, navBack, makeColor(36, 44, 58, 255), focused ? backOutline : makeColor(78, 90, 110, 255));
    drawBox(renderer, navFwd, makeColor(36, 44, 58, 255), focused ? fwdOutline : makeColor(78, 90, 110, 255));
    drawBox(renderer, navTab, makeColor(36, 44, 58, 255), focused ? makeColor(92, 178, 255, 255) : makeColor(78, 90, 110, 255));
    drawBox(renderer, navClose, makeColor(58, 32, 36, 255), focused ? makeColor(255, 110, 110, 255) : makeColor(122, 74, 74, 255));
    drawText(renderer, navBack.x + 7, navBack.y + 3, "<", 2, makeColor(240, 240, 245, 255));
    drawText(renderer, navFwd.x + 7, navFwd.y + 3, ">", 2, makeColor(240, 240, 245, 255));
    drawText(renderer, navTab.x + 5, navTab.y + 3, std::to_string(tabStrip_.currentIndex() + 1), 2, makeColor(240, 240, 245, 255));
    drawText(renderer, navClose.x + 4, navClose.y + 3, "X", 2, makeColor(240, 240, 245, 255));
    drawText(renderer, width - 206, 9, std::to_string(tabCount) + " tabs", 1, makeColor(210, 218, 228, 255));
    drawText(renderer, width - 206, 19, clipText(std::string("engine ") + engineLabel(), 28), 1, makeColor(170, 190, 214, 255));
    drawText(renderer, width - 206, 27, clipText(std::string("profile ") + uiProfileLabel(), 28), 1, makeColor(155, 176, 198, 255));
}

void BrowserChrome::renderBottomBar(bool focused)
{
    auto* renderer = fire4nix::renderer::nativeRenderer();
    if (!renderer) {
        return;
    }

    int width = 640;
    int height = 480;
    if (!rendererDimensions(width, height)) {
        return;
    }

    const int y = height - kBottomBarHeight;
    const SDL_Rect bar{0, y, width, kBottomBarHeight};
    drawBox(renderer, bar, makeColor(16, 18, 24, 255), focused ? makeColor(92, 178, 255, 255) : makeColor(46, 56, 72, 255));

    const auto statusText = clipText(statusBar_.status(), static_cast<std::size_t>(std::max(6, (width - 260) / 12)));
    drawText(renderer, 10, y + 6, statusText, 1, makeColor(232, 238, 244, 255));
    drawText(renderer, width - 254, y + 6, "A edit • B back • X forward", 1, makeColor(170, 190, 214, 255));
    drawText(renderer, width - 254, y + 14, clipText(std::string("beta ") + betaContext(), 34), 1, makeColor(160, 180, 200, 255));

    const SDL_Rect progressBox{width - 124, y + 6, 106, 12};
    drawBox(renderer, progressBox, makeColor(28, 34, 44, 255), makeColor(70, 82, 100, 255));
    const int progressWidth = std::clamp(statusBar_.progress(), 0, 100) * (progressBox.w - 4) / 100;
    const SDL_Rect progressFill{progressBox.x + 2, progressBox.y + 2, progressWidth, progressBox.h - 4};
    SDL_SetRenderDrawColor(renderer, 80, 180, 255, 255);
    SDL_RenderFillRect(renderer, &progressFill);

    drawText(renderer, width - 116, y + 18, std::to_string(std::clamp(statusBar_.progress(), 0, 100)) + "%", 1, makeColor(220, 230, 240, 255));
}

void BrowserChrome::renderAddressBar(bool focused)
{
    auto* renderer = fire4nix::renderer::nativeRenderer();
    if (!renderer) {
        return;
    }

    int width = 640;
    int height = 480;
    if (!rendererDimensions(width, height)) {
        return;
    }

    const int y = kTopBarHeight + 4;
    const SDL_Rect field{8, y, width - 16, kAddressBarHeight};
    drawBox(renderer, field, makeColor(24, 29, 36, 255), focused ? makeColor(92, 178, 255, 255) : makeColor(64, 78, 96, 255));

    std::string text = addressBar_.url();
    if (isHomeUrl(text)) {
        text = addressBar_.editing() ? "Type URL, search, or www.site" : "about:home (A to edit)";
    }
    if (addressBar_.editing()) {
        text.push_back('_');
    }

    const int maxChars = std::max(4, (field.w - 20) / 12);
    drawText(renderer, field.x + 10, field.y + 8, clipText(text, static_cast<std::size_t>(maxChars)), 2, makeColor(250, 250, 250, 255));
}

void BrowserChrome::initializeDefaultWidgets()
{
    if (!widgets_ || widgetsInitialized_) {
        return;
    }

    topWidget_.owner = this;
    addressWidget_.owner = this;
    bottomWidget_.owner = this;

    if (tabStrip_.count() == 0) {
        tabStrip_.addTab(defaultTabLabel());
    }

    history_.clear();
    historyIndex_ = 0;

    const auto homeUrl = startupUrl();
    setUrl(homeUrl);
    setStatus(statusWithContext(std::string("Fire4Nix beta test ready on ") + FIRE4NIX_PLATFORM + " • start " + homeUrl + " • " + betaSummary() + " • " + diagnosticSummary()));
    setProgress(0);
    dirty_ = true;
    resetTabs(0);
    addressBar_.cancelEditing();
    pushHistory(homeUrl);

    widgets_->add(&topWidget_);
    widgets_->add(&addressWidget_);
    widgets_->add(&bottomWidget_);

    widgetsInitialized_ = true;
    markDirty();
}

void BrowserChrome::TopBarWidget::update(float dt)
{
    (void)dt;
    if (owner) owner->pollBrowserState();
}

void BrowserChrome::TopBarWidget::render()
{
    if (owner) {
        owner->renderTopBar(focused());
    }
}

void BrowserChrome::TopBarWidget::onFocusChanged(bool focusedNow)
{
    if (owner && focusedNow) {
        owner->setStatus(std::string("Tab strip focused • ") + sessionLabel());
    }
}

bool BrowserChrome::TopBarWidget::handleAction(fire4nix::gui::UiAction action)
{
    if (!owner) {
        return false;
    }
    switch (action) {
    case UiAction::Activate:
        owner->openTab("New Tab");
        return true;
    case UiAction::Back:
        if (owner->canGoBack()) {
            owner->goBack();
        } else {
            owner->closeCurrentTab();
        }
        return true;
    case UiAction::Forward:
        if (owner->canGoForward()) {
            owner->goForward();
        } else {
            owner->nextTab();
        }
        return true;
    default:
        return false;
    }
}

void BrowserChrome::AddressBarWidget::update(float dt)
{
    (void)dt;
}

void BrowserChrome::AddressBarWidget::render()
{
    if (owner) {
        owner->renderAddressBar(focused());
        if (isHomeUrl(owner->url()) && !owner->isAddressEditing()) {
            renderHomeDashboard(*owner);
        }
    }
}

void BrowserChrome::AddressBarWidget::onFocusChanged(bool focusedNow)
{
    if (owner && focusedNow) {
        if (owner->isAddressEditing()) {
            owner->setStatus(std::string("Editing address • ") + sessionLabel());
        } else {
            owner->setStatus(std::string("Address bar focused • ") + uiProfileLabel());
        }
    }
}

bool BrowserChrome::AddressBarWidget::handleAction(fire4nix::gui::UiAction action)
{
    if (!owner) {
        return false;
    }

    switch (action) {
    case UiAction::Activate:
        if (owner->isAddressEditing()) {
            owner->commitAddressEditing();
        } else {
            owner->beginAddressEditing();
        }
        return true;
    case UiAction::Back:
        if (owner->isAddressEditing()) {
            if (!owner->url().empty()) {
                owner->backspaceAddress();
            } else {
                owner->cancelAddressEditing();
            }
            return true;
        }
        return false;
    case UiAction::Forward:
        if (owner->isAddressEditing()) {
            owner->commitAddressEditing();
            return true;
        }
        return false;
    default:
        return false;
    }
}

bool BrowserChrome::AddressBarWidget::handleTextInput(const std::string& text)
{
    if (!owner || text.empty()) {
        return false;
    }

    if (!owner->isAddressEditing()) {
        owner->beginAddressEditing();
    }

    owner->appendAddressText(text);
    return true;
}

bool BrowserChrome::AddressBarWidget::handleDeleteBackward()
{
    if (!owner || !owner->isAddressEditing()) {
        return false;
    }

    owner->backspaceAddress();
    return true;
}

void BrowserChrome::BottomBarWidget::update(float dt)
{
    (void)dt;
}

void BrowserChrome::BottomBarWidget::render()
{
    if (owner) {
        owner->renderBottomBar(focused());
    }
}

void BrowserChrome::BottomBarWidget::onFocusChanged(bool focusedNow)
{
    if (owner && focusedNow) {
        owner->setStatus(std::string("Status bar focused • ") + browserModeLabel());
    }
}

bool BrowserChrome::BottomBarWidget::handleAction(fire4nix::gui::UiAction action)
{
    if (!owner) {
        return false;
    }
    switch (action) {
    case UiAction::Activate:
        owner->setStatus("Status acknowledged");
        owner->setProgress(100);
        return true;
    case UiAction::Back:
        owner->setStatus("Status dismissed");
        owner->setProgress(0);
        return true;
    case UiAction::Forward:
        owner->setProgress(std::min(100, owner->progress() + 10));
        owner->setStatus("Status advanced");
        return true;
    default:
        return false;
    }
}

} // namespace fire4nix::gui
