#include "fire4nix_config.hpp"
#include "rocknix_platform.hpp"

#include <filesystem>

namespace fire4nix {

Config loadDefaultConfig()
{
    auto platform = detectPlatform();
    ensurePlatformDirectories(platform);
    return {
        platform.configPath,
        platform.logPath,
        platform.cachePath,
    };
}

} // namespace fire4nix
