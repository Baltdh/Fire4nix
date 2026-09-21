#include "fire4nix_renderer.hpp"
#include <cassert>
#include <iostream>

int main() {
    namespace renderer = fire4nix::renderer;
    assert(!renderer::initialize());
    assert(!renderer::isInitialized());
    assert(!renderer::attach(nullptr, nullptr));
    SDL_Window window{};
    SDL_Renderer fakeRenderer{};
    assert(!renderer::attach(&window, &fakeRenderer));
    assert(renderer::nativeRenderer() == nullptr);
    assert(renderer::nativeWindow() == nullptr);
    int width = 640, height = 480;
    assert(!renderer::outputSize(width, height));
    assert(width == 0 && height == 0);
    assert(!renderer::resize(640, 480));
    renderer::resetViewport();
    renderer::shutdown();
    renderer::shutdown();
    assert(!renderer::isInitialized());
    std::cout << "PASS: renderer rejects simulated handles and detaches safely\n";
}
