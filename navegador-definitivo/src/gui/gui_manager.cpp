#include "gui_manager.hpp"

#include "fire4nix_input.hpp"
#include "src/fire4nix_version.hpp"
#include "widget_manager.hpp"
#include "src/fire4nix_reference.hpp"
#include "widget.hpp"
#include "browser_bridge.hpp"

#include <cstdlib>
#include <string>

namespace fire4nix {

bool GuiManager::initialize()
{
    if (!widgets_) {
        return false;
    }

    initialized_ = true;
    frameCounter_ = 0;
    widgets_->attachFocusManager(&focus_);
    browserChrome_.attachWidgetManager(widgets_);
    browserChrome_.attachBridge(&fire4nix::gui::defaultBrowserBridge());
    browserChrome_.initializeDefaultWidgets();
    const char* referenceManifest = std::getenv("FIRE4NIX_REFERENCE_MANIFEST");
    const char* referenceEnv = std::getenv("FIRE4NIX_REFERENCE_ENV");
    const char* referenceStatus = std::getenv("FIRE4NIX_REFERENCE_STATUS");
    const std::string manifestNote = (referenceManifest != nullptr && *referenceManifest != '\0')
        ? std::string(" • manifest ") + referenceManifest
        : std::string();
    const std::string envNote = (referenceEnv != nullptr && *referenceEnv != '\0')
        ? std::string(" • env ") + referenceEnv
        : std::string();
    const std::string statusNote = (referenceStatus != nullptr && *referenceStatus != '\0')
        ? std::string(" • status ") + referenceStatus
        : std::string();
    browserChrome_.setStatus(std::string("Fire4Nix ") + FIRE4NIX_VERSION + " beta shell ready for Marco 3 start on " + FIRE4NIX_PLATFORM + " • refs " + fire4nix::referencePackSummary() + manifestNote + envNote + statusNote + " • " + browserChrome_.betaSummary() + " • " + browserChrome_.diagnosticSummary());
    resize(640, 480);
    widgets_->syncFocus();
    if (widgets_->widgetCount() > 1) {
        widgets_->focusIndex(1);
    }
    requestRender();

    if (!validate(nullptr)) {
        shutdown();
        return false;
    }

    return true;
}

void GuiManager::attachWidgetManager(WidgetManager* wm)
{
    widgets_ = wm;
    if (widgets_) {
        widgets_->attachFocusManager(&focus_);
    }
    browserChrome_.attachWidgetManager(widgets_);
    if (initialized_ && widgets_) {
        browserChrome_.initializeDefaultWidgets();
        widgets_->syncFocus();
    }
}

bool GuiManager::hasWidgetManager() const
{
    return widgets_ != nullptr;
}

bool GuiManager::guiReady() const
{
    return initialized_ && hasWidgetManager();
}

bool GuiManager::validate(std::string* reason) const
{
    if (!initialized_) {
        if (reason) {
            *reason = "GuiManager not initialized";
        }
        return false;
    }

    if (!widgets_) {
        if (reason) {
            *reason = "WidgetManager missing";
        }
        return false;
    }

    if (!browserChrome_.widgetsReady()) {
        if (reason) {
            *reason = "BrowserChrome widgets are not ready";
        }
        return false;
    }

    if (!widgets_->validate(reason)) {
        return false;
    }

    if (layout_.state().width <= 0 || layout_.state().height <= 0) {
        if (reason) {
            *reason = "Layout dimensions invalid";
        }
        return false;
    }

    if (!browserChrome_.validate(reason)) {
        return false;
    }

    if (widgets_->widgetCount() < 3) {
        if (reason) {
            *reason = "Expected at least three chrome widgets";
        }
        return false;
    }

    if (browserChrome_.isAddressEditing()) {
        const auto focused = widgets_->focusedWidget();
        if (focused == nullptr || widgets_->focusedIndex() != 1) {
            if (reason) {
                *reason = "Address editing active without address bar focus";
            }
            return false;
        }
    }

    return true;
}

void GuiManager::requestRender()
{
    invalidateLayout();
    browserChrome_.markDirty();
}



void GuiManager::resize(int width, int height)
{
    if (width <= 0 || height <= 0) {
        return;
    }

    layout_.updateLayout(width, height);
    requestRender();

    if (widgets_) {
        widgets_->syncFocus();
    }
}

bool GuiManager::needsRender() const
{
    return layout_.state().dirty || browserChrome_.needsRender() || scheduler_.frameActive();
}

void GuiManager::processInput()
{
    if (!initialized_) {
        return;
    }

    bool changed = false;

    for (auto action = fire4nix::input::consume_action();
         action != fire4nix::gui::UiAction::None;
         action = fire4nix::input::consume_action()) {
        bool handled = false;
        if (widgets_) {
            handled = widgets_->dispatchAction(action);
        }

        if (!handled) {
            browserChrome_.applyAction(action);
            handled = true;
        }

        changed = changed || handled;
    }

    if (widgets_) {
        widgets_->syncFocus();
    }

    for (auto textInput = fire4nix::input::consume_text_input();
         !textInput.empty();
         textInput = fire4nix::input::consume_text_input()) {
        bool handled = false;
        const bool wasEditing = browserChrome_.isAddressEditing();
        if (widgets_) {
            handled = widgets_->dispatchTextInput(textInput);
        }
        if (!handled) {
            browserChrome_.appendAddressText(textInput);
            handled = browserChrome_.isAddressEditing();
            if (!wasEditing && browserChrome_.isAddressEditing() && widgets_) {
                widgets_->focusIndex(1);
            }
        }
        changed = changed || handled;
    }

    for (auto composition = fire4nix::input::consume_text_editing();
         !composition.empty();
         composition = fire4nix::input::consume_text_editing()) {
        if (browserChrome_.isAddressEditing()) {
            browserChrome_.setStatus(std::string("Composing: ") + composition);
            changed = true;
        }
    }

    if (changed) {
        requestRender();
    }
}

void GuiManager::invalidateLayout()
{
    layout_.markDirty();
}

void GuiManager::update(float dt)
{
    if (!initialized_ || !widgets_) {
        return;
    }

    widgets_->syncFocus();
    std::string reason;
    if (!validate(&reason)) {
        shutdown();
        return;
    }

    widgets_->update(dt);
    if (needsRender()) {
        requestRender();
    }
}

void GuiManager::render(int width, int height)
{
    if (!validate(nullptr) || width <= 0 || height <= 0) {
        return;
    }

    layout_.updateLayout(width, height);

    if (!scheduler_.frameActive()) {
        scheduler_.beginFrame();
    }

    if (!scheduler_.frameActive()) {
        return;
    }

    if (widgets_) {
        widgets_->render();
    }

    layout_.clearDirty();
    browserChrome_.clearDirty();
    ++frameCounter_;
    scheduler_.endFrame();
}

void GuiManager::shutdown()
{
    scheduler_.endFrame();
    browserChrome_.reset();
    browserChrome_.attachWidgetManager(nullptr);
    focus_.reset();
    if (widgets_) {
        widgets_->clear();
    }
    initialized_ = false;
    widgets_ = nullptr;
}

} // namespace fire4nix
