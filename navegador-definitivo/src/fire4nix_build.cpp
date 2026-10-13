#include "fire4nix_build.hpp"
#include "fire4nix_config.hpp"
#include "fire4nix_logger.hpp"
#include "fire4nix_reference.hpp"

#include <cstdlib>
#include <filesystem>
#include <string>

namespace fire4nix {

bool initializeModules()
{
    const auto cfg = loadDefaultConfig();

    std::error_code ec;
    std::filesystem::create_directories(cfg.configDir, ec);
    std::filesystem::create_directories(cfg.logDir, ec);
    std::filesystem::create_directories(cfg.cacheDir, ec);

    const bool loggingReady = initLogging(cfg.logDir);
    const auto referenceSummary = referencePackSummary();
    const auto referenceManifest = referencePackManifestPath();
    const char* referenceEnv = std::getenv("FIRE4NIX_REFERENCE_ENV");
    const char* referenceFeatures = std::getenv("FIRE4NIX_REFERENCE_FEATURES");
    const char* referenceStatus = std::getenv("FIRE4NIX_REFERENCE_STATUS");
    if (loggingReady) {
        logInfo("Fire4Nix module bootstrap complete: config=" + cfg.configDir + ", cache=" + cfg.cacheDir + ", log=" + cfg.logDir);
        logInfo("Fire4Nix reference pack: " + referenceSummary);
        if (!referenceManifest.empty()) {
            logInfo("Fire4Nix reference manifest: " + referenceManifest);
        }
        if (referenceEnv != nullptr && *referenceEnv != '\0') {
            logInfo(std::string("Fire4Nix reference env: ") + referenceEnv);
        }
        if (referenceFeatures != nullptr && *referenceFeatures != '\0') {
            logInfo(std::string("Fire4Nix reference features: ") + referenceFeatures);
        }
        if (referenceStatus != nullptr && *referenceStatus != '\0') {
            logInfo(std::string("Fire4Nix reference status: ") + referenceStatus);
        }
    } else {
        logWarn("Fire4Nix logging bootstrap failed; continuing with stderr only");
        logWarn("Fire4Nix reference pack: " + referenceSummary);
        if (!referenceManifest.empty()) {
            logWarn("Fire4Nix reference manifest: " + referenceManifest);
        }
        if (referenceEnv != nullptr && *referenceEnv != '\0') {
            logWarn(std::string("Fire4Nix reference env: ") + referenceEnv);
        }
        if (referenceFeatures != nullptr && *referenceFeatures != '\0') {
            logWarn(std::string("Fire4Nix reference features: ") + referenceFeatures);
        }
        if (referenceStatus != nullptr && *referenceStatus != '\0') {
            logWarn(std::string("Fire4Nix reference status: ") + referenceStatus);
        }
    }
    return loggingReady;
}

} // namespace fire4nix
