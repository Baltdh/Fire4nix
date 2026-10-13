#pragma once

#include <cstddef>
#include <cstdint>

namespace fire4nix {
class FramebufferReader;
class ShmFrameReader;

struct Framebuffer {
    std::uint8_t* pixels = nullptr;
    std::size_t width = 0;
    std::size_t height = 0;
    std::size_t stride = 0;
    std::size_t bytes = 0;
    bool dirty = false;
};
}
