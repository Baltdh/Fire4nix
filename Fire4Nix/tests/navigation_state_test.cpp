#include "gui/browser_chrome.hpp"
#include "gui/widget_manager.hpp"
#include <cassert>
#include <iostream>

int main() {
    using namespace fire4nix::gui;
    WidgetManager widgets;
    BrowserChrome chrome;
    chrome.attachWidgetManager(&widgets);
    chrome.attachBridge(&defaultBrowserBridge());
    chrome.initializeDefaultWidgets();
    const auto originalHistory = chrome.historyCount();
    chrome.navigateTo("https://example.org");
    assert(chrome.historyCount() == originalHistory);
    assert(chrome.status().find("unavailable") != std::string::npos);
    int submitted = 0;
    setBrowserCommandHandler([&](const std::string&) { ++submitted; return true; });
    chrome.navigateTo("https://example.org");
    assert(chrome.url() == "https://example.org");
    assert(chrome.progress() == 0);
    assert(submitted == 1);
    const auto tabs = chrome.tabCount();
    chrome.openTab("Unsupported");
    assert(chrome.tabCount() == tabs);
    chrome.goHome();
    assert(submitted == 2); // Home must not submit twice.
    const auto historyIndex = chrome.historyIndex();
    setBrowserCommandHandler({});
    chrome.goBack();
    assert(chrome.historyIndex() == historyIndex);
    std::cout << "PASS: GUI preserves state on failure and does not fake load completion\n";
}
