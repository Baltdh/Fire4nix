#include "layout_manager.hpp"

namespace fire4nix::gui {

void LayoutManager::updateLayout(int w, int h)
{
    const bool changed = state_.width != w || state_.height != h;
    state_.width = w;
    state_.height = h;
    if (changed) {
        state_.dirty = true;
    }
}

void LayoutManager::markDirty()
{
    state_.dirty = true;
}

const LayoutState& LayoutManager::state() const
{
    return state_;
}

void LayoutManager::clearDirty()
{
    state_.dirty = false;
}

} // namespace fire4nix::gui
