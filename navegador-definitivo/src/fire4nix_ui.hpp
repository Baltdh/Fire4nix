#pragma once
#include <string>

namespace fire4nix::ui {
bool initialize();
void render();
void shutdown();
bool ready();
bool validate(std::string* reason);
bool size(int& width, int& height);
bool resize(int width, int height);
bool needsRender();
} // namespace fire4nix::ui
