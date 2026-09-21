#include "fire4nix_input.hpp"
#include "gui/widget_manager.hpp"
#include "gui/focus_manager.hpp"
#include "gui/widget.hpp"
#include "gui/layout_manager.hpp"
#include <cassert>
#include <cstring>
#include <iostream>

struct TestWidget : fire4nix::Widget {
    int activations = 0;
    std::string text;
    void update(float) override {}
    void render() override {}
    bool handleAction(fire4nix::gui::UiAction action) override {
        if (action != fire4nix::gui::UiAction::Activate) return false;
        ++activations;
        return true;
    }
    bool handleTextInput(const std::string& value) override {
        text += value;
        return true;
    }
};

int main() {
    using namespace fire4nix::gui;
    namespace input = fire4nix::input;
    TestWidget first, second;
    FocusManager focus;
    WidgetManager widgets;
    widgets.attachFocusManager(&focus);
    widgets.add(&first);
    widgets.add(&second);
    assert(widgets.validate());
    assert(first.focused() && !second.focused());

    SDL_Event event{};
    event.type = SDL_CONTROLLERBUTTONDOWN;
    event.cbutton.button = SDL_CONTROLLER_BUTTON_DPAD_RIGHT;
    assert(dispatch_event(event) == DispatchResult::Handled);
    event.cbutton.button = SDL_CONTROLLER_BUTTON_A;
    dispatch_event(event);
    assert(input::pending_action() == UiAction::FocusNext);
    assert(widgets.dispatchAction(input::consume_action()));
    assert(second.focused() && !first.focused());
    assert(widgets.dispatchAction(input::consume_action()));
    assert(second.activations == 1);
    assert(input::consume_action() == UiAction::None);

    event = {};
    event.type = SDL_TEXTINPUT;
    std::strcpy(event.text.text, "https://example.org");
    dispatch_event(event);
    assert(widgets.dispatchTextInput(input::consume_text_input()));
    assert(second.text == "https://example.org");
    assert(input::consume_text_input().empty());
    event = {};
    event.type = SDL_TEXTEDITING;
    std::strcpy(event.edit.text, "composicao");
    dispatch_event(event);
    assert(input::consume_text_editing() == "composicao");
    assert(input::consume_text_editing().empty());

    event = {};
    event.type = SDL_CONTROLLERAXISMOTION;
    event.caxis.axis = SDL_CONTROLLER_AXIS_LEFTX;
    event.caxis.value = 1000;
    assert(dispatch_event(event) == DispatchResult::Ignored);
    event.caxis.value = -20000;
    dispatch_event(event);
    assert(widgets.dispatchAction(input::consume_action()));
    assert(first.focused());
    assert(widgets.dispatchAction(UiAction::FocusPrevious));
    assert(second.focused());
    assert(widgets.dispatchAction(UiAction::FocusNext));
    assert(first.focused());
    event = {};
    event.type = SDL_QUIT;
    assert(dispatch_event(event) == DispatchResult::Ignored);

    LayoutManager layout;
    layout.updateLayout(640, 480);
    assert(layout.state().width == 640 && layout.state().height == 480);
    layout.clearDirty();
    layout.updateLayout(640, 480);
    assert(!layout.state().dirty);
    layout.updateLayout(480, 640);
    assert(layout.state().dirty);
    widgets.clear();
    assert(!first.focused() && !second.focused());
    assert(widgets.focusedWidget() == nullptr);
    std::cout << "PASS: GUI input queues, focus, activation, text, deadzone, layout\n";
}
