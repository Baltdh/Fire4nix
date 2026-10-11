#pragma once

#include "gui_context.hpp"

namespace fire4nix::gui {

class GuiBootstrap {
public:
    bool start();
    void stop();

    bool ready() const;

    GuiContext& context();
    const GuiContext& context() const;

private:
    GuiContext context_;
};

} // namespace fire4nix::gui
