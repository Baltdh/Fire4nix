#include "rocknix_platform.hpp"

#include <cstdlib>
#include <filesystem>
#include <string>

namespace fire4nix {
namespace {

std::string envOrDefault(const char* name, const std::string& fallback)
{
    const char* value = std::getenv(name);
    if (value == nullptr || *value == '\0') {
        return fallback;
    }
    return std::string(value);
}

std::string defaultConfigRoot()
{
    if (const char* xdg = std::getenv("XDG_CONFIG_HOME"); xdg != nullptr && *xdg != '\0') {
        return std::string(xdg) + "/fire4nix";
    }

    // ROCKNIX exposes a persistent /storage mount for user data. Prefer it when
    // available so the native C++ layer matches the shell launcher behavior.
    if (std::filesystem::exists("/storage")) {
        return "/storage/.config/fire4nix";
    }

    if (const char* home = std::getenv("HOME"); home != nullptr && *home != '\0') {
        return std::string(home) + "/.config/fire4nix";
    }
    return ".fire4nix";
}


std::string defaultReferenceRoot(const std::string& home)
{
    if (const char* ref = std::getenv("FIRE4NIX_REFERENCE_ROOT"); ref != nullptr && *ref != '\0') {
        return std::string(ref);
    }

    const std::filesystem::path candidate = std::filesystem::path(home) / "rocknix_reference";
    if (std::filesystem::exists(candidate)) {
        return candidate.string();
    }

    if (const char* cfg = std::getenv("FIRE4NIX_CONFIG_DIR"); cfg != nullptr && *cfg != '\0') {
        const std::filesystem::path staged = std::filesystem::path(cfg) / "reference";
        if (std::filesystem::exists(staged)) {
            return staged.string();
        }
    }

    return candidate.string();
}

} // namespace

PlatformInfo detectPlatform()
{
    const std::string home = envOrDefault("FIRE4NIX_HOME", defaultConfigRoot());
    const std::string config = envOrDefault("FIRE4NIX_CONFIG_DIR", home);
    const std::string cache = envOrDefault("FIRE4NIX_CACHE_DIR", config + "/cache");
    const std::string logs = envOrDefault("FIRE4NIX_LOG_DIR", config + "/logs");
    const std::string reference = envOrDefault("FIRE4NIX_REFERENCE_ROOT", defaultReferenceRoot(home));
    return {
        "ROCKNIX",
        config,
        cache,
        logs,
        home,
        reference,
    };
}

bool ensurePlatformDirectories(const PlatformInfo& info)
{
    std::error_code ec;
    std::filesystem::create_directories(info.homePath, ec);
    std::filesystem::create_directories(info.configPath, ec);
    std::filesystem::create_directories(info.cachePath, ec);
    std::filesystem::create_directories(info.logPath, ec);
    return true;
}

} // namespace fire4nix
