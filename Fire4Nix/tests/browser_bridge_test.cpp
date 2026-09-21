#include "gui/browser_bridge.hpp"
#include <cassert>
#include <iostream>
#include <vector>

int main() {
    using namespace fire4nix::gui;
    auto& bridge = defaultBrowserBridge();
    assert(!bridge.loadUrl("https://example.org"));
    std::vector<std::string> sent;
    setBrowserCommandHandler([&](const std::string& command) {
        sent.push_back(command);
        return true;
    });
    assert(bridge.loadUrl("https://example.org/?q=test"));
    assert(sent.back() == "load:https://example.org/?q=test");
    assert(bridge.reload() && sent.back() == "key:ctrl+r");
    assert(bridge.goBack() && sent.back() == "back");
    assert(bridge.goForward() && sent.back() == "key:alt+Right");
    const auto count = sent.size();
    assert(!bridge.loadUrl("https://example.org/\nkey:ctrl+w"));
    assert(!bridge.loadUrl("javascript:alert(1)"));
    assert(!bridge.loadUrl("file:///etc/passwd"));
    assert(!bridge.loadUrl("https://example.org/" + std::string(9000, 'x')));
    assert(!bridge.openTab("test") && !bridge.closeTab() && !bridge.toggleFullscreen());
    assert(sent.size() == count);
    setBrowserCommandHandler([](const std::string&) { return false; });
    assert(!bridge.reload());
    setBrowserCommandHandler({});
    assert(!bridge.goBack());
    std::cout << "PASS: bridge delivery, disconnect, backend rejection and URL validation\n";
}
