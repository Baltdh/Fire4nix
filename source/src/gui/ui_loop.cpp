#include "ui_loop.hpp"
#include "gui_manager.hpp"

namespace fire4nix {

void UiLoop::attach(GuiManager* m)
{
    manager_ = m;
}

void UiLoop::processInput()
{
    if (manager_) {
        manager_->processInput();
    }
}

void UiLoop::update(float deltaTime)
{
    if (manager_) {
        manager_->update(deltaTime);
    }
}

void UiLoop::render(int width, int height)
{
    if (manager_ && manager_->guiReady() && manager_->needsRender()) {
        manager_->render(width, height);
    }
}

} // namespace fire4nix
