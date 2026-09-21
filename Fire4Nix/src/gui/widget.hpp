#pragma once

#include <string>

namespace fire4nix::gui {
enum class UiAction;
}

namespace fire4nix {

class Widget {
public:
    virtual ~Widget() = default;
    virtual void update(float dt) = 0;
    virtual void render() = 0;
    virtual bool handleAction(fire4nix::gui::UiAction) { return false; }
    virtual bool handleTextInput(const std::string&) { return false; }
    virtual bool handleDeleteBackward() { return false; }

    virtual void setFocused(bool focused) {
        if (focused_ != focused) {
            focused_ = focused;
            onFocusChanged(focused_);
        } else {
            focused_ = focused;
        }
    }
    bool focused() const { return focused_; }
    virtual void onFocusChanged(bool) {}

protected:
    bool focused_{false};
};

} // namespace fire4nix
