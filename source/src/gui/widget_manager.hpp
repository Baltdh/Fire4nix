#pragma once

#include <cstddef>
#include <vector>
#include <string>

namespace fire4nix {
class Widget;
}

namespace fire4nix::gui {
enum class UiAction;
}

class FocusManager;

class WidgetManager {
public:
    void add(fire4nix::Widget*);
    void clear();
    void attachFocusManager(FocusManager*);
    void syncFocus();
    void update(float dt);
    void render();
    std::size_t widgetCount() const;
    std::size_t focusedIndex() const;
    fire4nix::Widget* focusedWidget() const;
    fire4nix::Widget* widgetAt(std::size_t index) const;
    bool focusIndex(std::size_t index);
    bool validate(std::string* reason = nullptr) const;
    bool dispatchAction(fire4nix::gui::UiAction action);
    bool dispatchTextInput(const std::string& text);

private:
    std::vector<fire4nix::Widget*> widgets_;
    FocusManager* focus_{nullptr};
};
