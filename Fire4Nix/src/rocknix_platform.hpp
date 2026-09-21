#pragma once

#include <string>

namespace fire4nix {

struct PlatformInfo {
    std::string platformName;
    std::string configPath;
    std::string cachePath;
    std::string logPath;
    std::string homePath;
    std::string referencePath;
};

PlatformInfo detectPlatform();
bool ensurePlatformDirectories(const PlatformInfo& info);

} // namespace fire4nix
