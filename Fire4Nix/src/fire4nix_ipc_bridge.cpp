#include "fire4nix_ipc_bridge.hpp"
#include "fire4nix_ipc.hpp"
#include "gui/browser_bridge.hpp"

#include <memory>

namespace fire4nix {
namespace {
std::unique_ptr<CommandPipe> g_browserCommands;
}

bool initializeIPCBridge()
{
    auto pipe = std::make_unique<CommandPipe>();
    if (!pipe->create("browser"))
        return false;

    g_browserCommands = std::move(pipe);
    gui::setBrowserCommandHandler([](const std::string& command) {
        return g_browserCommands && g_browserCommands->sendCommand(command);
    });
    return true;
}

void shutdownIPCBridge()
{
    gui::setBrowserCommandHandler({});
    g_browserCommands.reset();
}

bool ipcBridgeReady()
{
    return static_cast<bool>(g_browserCommands);
}

} // namespace fire4nix
