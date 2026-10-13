#pragma once

#include <cstddef>
#include <string>

namespace fire4nix {

struct ReferencePackReport {
    bool available{false};
    std::string root;
    std::size_t anchorCount{0};
    std::size_t presentCount{0};
    std::size_t fileCount{0};
    std::string summary;
};

ReferencePackReport detectReferencePack();
std::string referencePackSummary();
std::string referencePackManifestPath();

} // namespace fire4nix
