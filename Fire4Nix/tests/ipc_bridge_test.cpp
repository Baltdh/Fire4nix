#include "fire4nix_ipc_bridge.hpp"
#include "gui/browser_bridge.hpp"

#include <cassert>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>

int main()
{
    namespace fs = std::filesystem;
    using namespace fire4nix;
    using namespace fire4nix::gui;

    const fs::path runtime = fs::temp_directory_path() / "fire4nix-ipc-test";
    std::error_code ec;
    fs::remove_all(runtime, ec);
    fs::create_directories(runtime, ec);
#if defined(_WIN32)
    _putenv_s("FIRE4NIX_RUNTIME_DIR", runtime.string().c_str());
#else
    setenv("FIRE4NIX_RUNTIME_DIR", runtime.string().c_str(), 1);
#endif

    assert(initializeIPCBridge());
    assert(ipcBridgeReady());
    assert(defaultBrowserBridge().loadUrl("https://example.org/test"));
    assert(defaultBrowserBridge().reload());

    std::ifstream input(runtime / "browser.cmd");
    assert(input.is_open());
    std::string first;
    std::string second;
    std::getline(input, first);
    std::getline(input, second);
    assert(first == "load:https://example.org/test");
    assert(second == "key:ctrl+r");

    shutdownIPCBridge();
    assert(!ipcBridgeReady());
    assert(!defaultBrowserBridge().goBack());

    fs::remove_all(runtime, ec);
    std::cout << "PASS: IPC bridge lifecycle and browser command transport\n";
}
