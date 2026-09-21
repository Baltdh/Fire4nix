#include "fire4nix_app.hpp"
#include "fire4nix_build.hpp"
#include "fire4nix_ipc_bridge.hpp"

namespace fire4nix {

bool initializeApplication()
{
    if (!initializeModules())
        return false;
    return initializeIPCBridge();
}

} // namespace fire4nix
