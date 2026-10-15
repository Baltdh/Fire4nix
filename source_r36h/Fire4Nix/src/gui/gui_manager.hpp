#pragma once

#include "browser_chrome.hpp"
#include "focus_manager.hpp"
#include <string>
#include "layout_manager.hpp"
#include "render_scheduler.hpp"

class WidgetManager;

namespace fire4nix {

class GuiManager {
public:
    bool initialize();
    void attachWidgetManager(WidgetManager*);
    bool hasWidgetManager() const;
    bool guiReady() const;
    bool validate(std::string* reason = nullptr) const;
    void requestRender();
    bool needsRender() const;
    void processInput();
    void invalidateLayout();
    void resize(int width, int height);
    void update(float dt);
    void render(int width = 640, int height = 480);
    void shutdown();

    bool initialized() const { return initialized_; }
    unsigned long frameCounter() const { return frameCounter_; }
    fire4nix::gui::LayoutManager& layout() { return layout_; }
    fire4nix::gui::RenderScheduler& scheduler() { return scheduler_; }

private:
    bool initialized_{false};
    unsigned long frameCounter_{0};
    fire4nix::gui::LayoutManager layout_;
    fire4nix::gui::RenderScheduler scheduler_;
    WidgetManager* widgets_{nullptr};
    fire4nix::gui::BrowserChrome browserChrome_;
    FocusManager focus_;
};

} // namespace fire4nix
