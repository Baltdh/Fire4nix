#include "gui/browser_chrome.hpp"
#include "gui/widget_manager.hpp"
#include <cassert>
#include <iostream>
#include <cstdlib>
#include <filesystem>
#include <fstream>

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
    const auto runtime = std::filesystem::temp_directory_path() / "fire4nix-browser-state-test";
    std::error_code ec;
    std::filesystem::create_directories(runtime, ec);
#if defined(_WIN32)
    _putenv_s("FIRE4NIX_RUNTIME_DIR", runtime.string().c_str());
#else
    setenv("FIRE4NIX_RUNTIME_DIR", runtime.string().c_str(), 1);
#endif
    {
        std::ofstream state(runtime / "browser.state");
        state << "event=load-finished\nuri=https://example.org/final\ntitle=Example Final\nloading=0\n";
    }
    chrome.pollBrowserState();
    assert(chrome.url() == "https://example.org/final");
    assert(chrome.currentTabTitle() == "Example Final");
    assert(chrome.progress() == 100);
    assert(chrome.status() == "Example Final");

    chrome.beginAddressEditing();
    {
        std::ofstream state(runtime / "browser.state");
        state << "event=load-committed\nuri=https://redirect.example/\ntitle=Redirect\nloading=1\n";
    }
    chrome.pollBrowserState();
    assert(chrome.url() != "https://redirect.example/");
    chrome.cancelAddressEditing();

    {
        std::ofstream state(runtime / "browser.state");
        state << "event=tls-error\nuri=https://bad.example/\ntitle=\nloading=0\ndetail=certificate validation failed\n";
    }
    chrome.pollBrowserState();
    assert(chrome.status().find("certificate validation failed") != std::string::npos);
    std::filesystem::remove_all(runtime, ec);

    const auto historyIndex = chrome.historyIndex();
    setBrowserCommandHandler({});
    chrome.goBack();
    assert(chrome.historyIndex() == historyIndex);
    std::cout << "PASS: GUI preserves state on failure, consumes WPE state, and protects address editing\n";
}
