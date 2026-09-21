#include "widget_manager.hpp"

#include "widget.hpp"
#include "focus_manager.hpp"
#include "event_dispatcher.hpp"

void WidgetManager::add(fire4nix::Widget* w)
{
    widgets_.push_back(w);
    if (focus_) {
        focus_->setCount(widgets_.size());
        syncFocus();
    }
}

void WidgetManager::clear()
{
    for (auto* w : widgets_) {
        if (w) {
            w->setFocused(false);
        }
    }
    widgets_.clear();
    if (focus_) {
        focus_->reset();
    }
}

void WidgetManager::attachFocusManager(FocusManager* f)
{
    focus_ = f;
    if (focus_) {
        focus_->setCount(widgets_.size());
        syncFocus();
    }
}

void WidgetManager::syncFocus()
{
    if (!focus_) {
        return;
    }

    const auto count = widgets_.size();
    const auto current = focus_->current();

    for (std::size_t i = 0; i < count; ++i) {
        if (widgets_[i]) {
            widgets_[i]->setFocused(i == current);
        }
    }
}

void WidgetManager::update(float dt)
{
    syncFocus();
    for (auto* w : widgets_) {
        if (w) {
            w->update(dt);
        }
    }
}

void WidgetManager::render()
{
    for (auto* w : widgets_) {
        if (w) {
            w->render();
        }
    }
}

std::size_t WidgetManager::widgetCount() const
{
    return widgets_.size();
}

std::size_t WidgetManager::focusedIndex() const
{
    return focus_ ? focus_->current() : 0;
}

fire4nix::Widget* WidgetManager::widgetAt(std::size_t index) const
{
    if (index >= widgets_.size()) {
        return nullptr;
    }
    return widgets_[index];
}

bool WidgetManager::focusIndex(std::size_t index)
{
    if (!focus_ || index >= widgets_.size()) {
        return false;
    }

    focus_->setCurrent(index);
    syncFocus();
    return true;
}

bool WidgetManager::validate(std::string* reason) const
{
    if (!focus_) {
        if (reason) {
            *reason = "FocusManager missing";
        }
        return false;
    }

    if (focus_->count() != widgets_.size()) {
        if (reason) {
            *reason = "FocusManager count mismatch";
        }
        return false;
    }

    for (std::size_t i = 0; i < widgets_.size(); ++i) {
        if (!widgets_[i]) {
            if (reason) {
                *reason = "Null widget in widget list";
            }
            return false;
        }
    }

    if (!widgets_.empty()) {
        const auto idx = focus_->current();
        if (idx >= widgets_.size()) {
            if (reason) {
                *reason = "Focused widget index out of range";
            }
            return false;
        }
    }

    return true;
}


fire4nix::Widget* WidgetManager::focusedWidget() const
{
    if (!focus_ || widgets_.empty()) {
        return nullptr;
    }

    const auto idx = focus_->current();
    if (idx >= widgets_.size()) {
        return nullptr;
    }

    return widgets_[idx];
}

bool WidgetManager::dispatchAction(fire4nix::gui::UiAction action)
{
    if (!focus_) {
        return false;
    }

    switch (action) {
    case fire4nix::gui::UiAction::FocusNext:
        focus_->next();
        syncFocus();
        return true;
    case fire4nix::gui::UiAction::FocusPrevious:
        focus_->previous();
        syncFocus();
        return true;
    case fire4nix::gui::UiAction::DeleteBackward:
        if (auto* w = focusedWidget()) {
            return w->handleDeleteBackward();
        }
        return false;
    case fire4nix::gui::UiAction::Activate:
    case fire4nix::gui::UiAction::Back:
    case fire4nix::gui::UiAction::Forward:
        if (auto* w = focusedWidget()) {
            return w->handleAction(action);
        }
        return false;
    case fire4nix::gui::UiAction::None:
    default:
        return false;
    }
}

bool WidgetManager::dispatchTextInput(const std::string& text)
{
    if (auto* w = focusedWidget()) {
        return w->handleTextInput(text);
    }
    return false;
}
