#pragma once
#include "sdl_compat.hpp"
#include <cstdint>

namespace fire4nix::renderer {
// Borrowed handles: App owns creation, event polling, presentation and deletion.
bool attach(SDL_Window* window, SDL_Renderer* renderer);
void detach();
bool initialize();
void beginFrame();
void render();
void renderBrowser();
void beginBrowserRender();
SDL_Renderer* nativeRenderer();
SDL_Window* nativeWindow();
bool outputSize(int& width, int& height);
void setClearColor(std::uint8_t r, std::uint8_t g, std::uint8_t b, std::uint8_t a);
bool resize(int width, int height);
bool pollEvents();
void present();
void resetViewport();
void endFrame();
void endBrowserRender();
void shutdown();
bool isInitialized();
void renderPipeline();
} // namespace fire4nix::renderer
