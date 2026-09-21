#pragma once

#include "gui_manager.hpp"
#include "gui_services.hpp"
#include "theme_manager.hpp"
#include "ui_loop.hpp"
#include "widget_manager.hpp"
#include <string>

namespace fire4nix::gui {

class GuiContext {
public:
    bool initialize();
    void frame(float deltaTime, int width = 640, int height = 480);
    void shutdown();

    bool ready() const;
    bool validate(std::string* reason = nullptr) const;

    GuiManager& manager();
    WidgetManager& widgets();
    GuiServices& services();
    ThemeManager& theme();

private:
    GuiServices services_;
    ThemeManager theme_;
    GuiManager manager_;
    WidgetManager widgets_;
    UiLoop loop_;
    bool active_{false};
};

} // namespace fire4nix::gui
