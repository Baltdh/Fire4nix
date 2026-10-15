#include "gui_context.hpp"

#if defined(__has_include)
#  if __has_include(<SDL2/SDL.h>)
#    include "sdl_compat.hpp"
#  endif
#endif

namespace fire4nix::gui {

bool GuiContext::initialize()
{
    if (active_) {
        return true;
    }

    if (!services_.initialize()) {
        return false;
    }

    theme_.loadFromEnvironment();
    if (!theme_.loaded() || theme_.themeName().empty()) {
        services_.shutdown();
        return false;
    }

    manager_.attachWidgetManager(&widgets_);
    if (!manager_.initialize()) {
        services_.shutdown();
        return false;
    }

    if (!validate(nullptr)) {
        manager_.shutdown();
        services_.shutdown();
        return false;
    }

    loop_.attach(&manager_);
    active_ = true;
    return true;
}

void GuiContext::frame(float deltaTime, int width, int height)
{
    if (!active_) {
        return;
    }

    if (!validate(nullptr)) {
        shutdown();
        return;
    }

    services_.update(deltaTime);
    loop_.processInput();
    loop_.update(deltaTime);
    loop_.render(width, height);
}

void GuiContext::shutdown()
{
    if (!active_) {
        return;
    }

    loop_.attach(nullptr);
    manager_.shutdown();
    widgets_.clear();
    theme_.reset();
    services_.shutdown();
    active_ = false;
}

bool GuiContext::validate(std::string* reason) const
{
    if (!services_.active()) {
        if (reason) {
            *reason = "GuiServices inactive";
        }
        return false;
    }

    if (!theme_.loaded()) {
        if (reason) {
            *reason = "Theme not loaded (" + theme_.summary() + ")";
        }
        return false;
    }

    if (theme_.themeName().empty()) {
        if (reason) {
            *reason = "Theme name missing (" + theme_.summary() + ")";
        }
        return false;
    }

    if (!manager_.validate(reason)) {
        return false;
    }

    if (!manager_.guiReady()) {
        if (reason) {
            *reason = "GuiManager not ready";
        }
        return false;
    }

    return true;
}

bool GuiContext::ready() const
{
    return active_ && manager_.guiReady() && validate(nullptr);
}

GuiManager& GuiContext::manager()
{
    return manager_;
}

WidgetManager& GuiContext::widgets()
{
    return widgets_;
}

GuiServices& GuiContext::services()
{
    return services_;
}

ThemeManager& GuiContext::theme()
{
    return theme_;
}

} // namespace fire4nix::gui
