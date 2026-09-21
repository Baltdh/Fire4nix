#include "fire4nix_renderer.hpp"

namespace fire4nix::renderer {
namespace {
SDL_Window* window = nullptr;
SDL_Renderer* renderer = nullptr;
}

bool attach(SDL_Window* newWindow, SDL_Renderer* newRenderer) {
    detach();
#ifdef FIRE4NIX_SDL_COMPAT_REAL
    if (!newWindow || !newRenderer || SDL_GetRenderer(newWindow) != newRenderer)
        return false;
    window = newWindow;
    renderer = newRenderer;
    return true;
#else
    (void)newWindow;
    (void)newRenderer;
    return false;
#endif
}
void detach() { window = nullptr; renderer = nullptr; }
bool isInitialized() { return window != nullptr && renderer != nullptr; }
bool initialize() { return isInitialized(); }
SDL_Window* nativeWindow() { return window; }
SDL_Renderer* nativeRenderer() { return renderer; }
bool outputSize(int& width, int& height) {
    width = height = 0;
#ifdef FIRE4NIX_SDL_COMPAT_REAL
    if (isInitialized() && SDL_GetRendererOutputSize(renderer, &width, &height) == 0)
        return width > 0 && height > 0;
#endif
    return false;
}
void setClearColor(std::uint8_t r, std::uint8_t g, std::uint8_t b, std::uint8_t a) {
    if (isInitialized()) SDL_SetRenderDrawColor(renderer, r, g, b, a);
}
bool resize(int width, int height) {
    if (!isInitialized() || width <= 0 || height <= 0) return false;
#ifdef FIRE4NIX_SDL_COMPAT_REAL
    SDL_SetWindowSize(window, width, height);
    return true;
#else
    return false;
#endif
}
void resetViewport() {
#ifdef FIRE4NIX_SDL_COMPAT_REAL
    if (isInitialized()) SDL_RenderSetViewport(renderer, nullptr);
#endif
}
// App alone controls frame lifetime and polls events. These hooks must not
// clear the framebuffer, present a second frame or consume window events.
void beginFrame() {}
void render() {}
void renderBrowser() {}
void beginBrowserRender() {}
bool pollEvents() { return false; }
void present() {}
void endFrame() {}
void endBrowserRender() {}
void renderPipeline() {}
void shutdown() { detach(); }
} // namespace fire4nix::renderer
