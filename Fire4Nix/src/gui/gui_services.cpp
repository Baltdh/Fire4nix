#include "gui_services.hpp"

namespace fire4nix::gui {

bool GuiServices::initialize()
{
    active_ = true;
    accumulatedTime_ = 0.0f;
    return true;
}

void GuiServices::update(float deltaTime)
{
    if (!active_) {
        return;
    }

    accumulatedTime_ += deltaTime;
}

void GuiServices::shutdown()
{
    active_ = false;
    accumulatedTime_ = 0.0f;
}

} // namespace fire4nix::gui
