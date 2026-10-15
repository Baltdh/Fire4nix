#include "gui_bootstrap.hpp"

namespace fire4nix::gui {

bool GuiBootstrap::start()
{
    return context_.initialize();
}

void GuiBootstrap::stop()
{
    context_.shutdown();
}

bool GuiBootstrap::ready() const
{
    return context_.ready();
}

GuiContext& GuiBootstrap::context()
{
    return context_;
}

const GuiContext& GuiBootstrap::context() const
{
    return context_;
}

} // namespace fire4nix::gui
