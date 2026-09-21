#include "fire4nix_runtime_bridge.hpp"
#include "fire4nix_app.hpp"
namespace fire4nix {
bool startup(){ return initializeApplication(); }
void shutdown(){}
}
