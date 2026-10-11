#pragma once
#include <string>
#include <vector>

namespace fire4nix::document_container {
bool initialize();
void shutdown();
std::string loadResource(const std::string& path);
std::vector<unsigned char> loadImage(const std::string& path);
std::string defaultFont();
bool drawText(const std::string& text, int x, int y);
std::string resolveUrl(const std::string& base, const std::string& href);
} // namespace fire4nix::document_container
