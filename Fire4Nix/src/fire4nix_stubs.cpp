#include "fire4nix_renderer.hpp"
#include "fire4nix_ui.hpp"
#include "fire4nix_document_container.hpp"
#include "fire4nix_input.hpp"
#include "sdl_compat.hpp"

#include <string>
#include <vector>

namespace fire4nix::renderer {
static SDL_Renderer* g_renderer = nullptr;
static SDL_Window* g_window = nullptr;
bool initialize(){ return true; }
void beginFrame(){}
void render(){}
void renderBrowser(){}
void beginBrowserRender(){}
SDL_Renderer* nativeRenderer(){ return g_renderer; }
SDL_Window* nativeWindow(){ return g_window; }
bool outputSize(int& width, int& height){ width = 640; height = 480; return true; }
void setClearColor(std::uint8_t, std::uint8_t, std::uint8_t, std::uint8_t){}
bool resize(int, int){ return true; }
bool pollEvents(){ return false; }
void present(){}
void resetViewport(){}
void endFrame(){}
void endBrowserRender(){}
void shutdown(){}
bool isInitialized(){ return true; }
void renderPipeline(){}
} // namespace fire4nix::renderer

namespace fire4nix::ui {
bool initialize(){ return true; }
void render(){}
void shutdown(){}
bool ready(){ return true; }
bool validate(std::string* reason){ if(reason) *reason = ""; return true; }
bool size(int& width, int& height){ width = 640; height = 480; return true; }
bool resize(int, int){ return true; }
bool needsRender(){ return false; }
} // namespace fire4nix::ui

namespace fire4nix::document_container {
bool initialize(){ return true; }
void shutdown(){}
std::string loadResource(const std::string&){ return {}; }
std::vector<unsigned char> loadImage(const std::string&){ return {}; }
std::string defaultFont(){ return {}; }
bool drawText(const std::string&,int,int){ return true; }
std::string resolveUrl(const std::string&,const std::string& href){ return href; }
} // namespace fire4nix::document_container
