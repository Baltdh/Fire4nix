
#include "event_dispatcher.hpp"

#include <deque>
#include <string>

namespace fire4nix::gui {

namespace {

std::deque<UiAction> g_action_queue;
std::deque<std::string> g_last_text_inputs;
std::deque<std::string> g_last_text_editings;

void set_action(UiAction action)
{
    if (action != UiAction::None) {
        g_action_queue.push_back(action);
    }
}

void set_text_input(const char* text)
{
    if (text != nullptr && *text != '\0') {
        g_last_text_inputs.emplace_back(text);
    }
}

void set_text_editing(const char* text)
{
    if (text != nullptr && *text != '\0') {
        g_last_text_editings.emplace_back(text);
    }
}

UiAction map_key_action(const SDL_KeyboardEvent& key)
{
    switch (key.keysym.sym) {
    case SDLK_RIGHT:
    case SDLK_DOWN:
    case SDLK_TAB:
        return UiAction::FocusNext;
    case SDLK_LEFT:
    case SDLK_UP:
        return UiAction::FocusPrevious;
    case SDLK_RETURN:
    case SDLK_SPACE:
        return UiAction::Activate;
    case SDLK_ESCAPE:
    case SDLK_BACKSPACE:
        return UiAction::Back;
    case SDLK_RIGHTBRACKET:
    case SDLK_F7:
        return UiAction::Forward;
    case SDLK_PAGEUP:
        return UiAction::PreviousTab;
    case SDLK_PAGEDOWN:
        return UiAction::NextTab;
    case SDLK_r:
    case SDLK_F5:
        return UiAction::Reload;
    case SDLK_h:
    case SDLK_HOME:
        return UiAction::Home;
    case SDLK_F11:
        return UiAction::Fullscreen;
    case SDLK_n:
        return UiAction::OpenTab;
    case SDLK_w:
        return UiAction::CloseTab;
    default:
        return UiAction::None;
    }
}

UiAction map_controller_button_action(const SDL_ControllerButtonEvent& button)
{
    switch (button.button) {
    case SDL_CONTROLLER_BUTTON_DPAD_RIGHT:
    case SDL_CONTROLLER_BUTTON_DPAD_DOWN:
        return UiAction::FocusNext;
    case SDL_CONTROLLER_BUTTON_DPAD_LEFT:
    case SDL_CONTROLLER_BUTTON_DPAD_UP:
        return UiAction::FocusPrevious;
    case SDL_CONTROLLER_BUTTON_A:
        return UiAction::Activate;
    case SDL_CONTROLLER_BUTTON_B:
        return UiAction::Back;
    case SDL_CONTROLLER_BUTTON_X:
        return UiAction::Forward;
    case SDL_CONTROLLER_BUTTON_Y:
        return UiAction::Reload;
    case SDL_CONTROLLER_BUTTON_LEFTSHOULDER:
        return UiAction::PreviousTab;
    case SDL_CONTROLLER_BUTTON_RIGHTSHOULDER:
        return UiAction::NextTab;
    case SDL_CONTROLLER_BUTTON_START:
        return UiAction::OpenTab;
    case SDL_CONTROLLER_BUTTON_BACK:
        return UiAction::Home;
    default:
        return UiAction::None;
    }
}

UiAction map_controller_axis_action(const SDL_ControllerAxisEvent& axis)
{
    constexpr auto threshold = 16000;

    switch (axis.axis) {
    case SDL_CONTROLLER_AXIS_LEFTX:
    case SDL_CONTROLLER_AXIS_LEFTY:
        if (axis.value > threshold) {
            return UiAction::FocusNext;
        }
        if (axis.value < -threshold) {
            return UiAction::FocusPrevious;
        }
        break;
    default:
        break;
    }

    return UiAction::None;
}

} // namespace

DispatchResult dispatch_event(int event_type)
{
    switch (event_type) {
    case 0:
        return DispatchResult::Handled;
    default:
        return DispatchResult::Ignored;
    }
}

DispatchResult dispatch_event(const SDL_Event& event)
{
    switch (event.type) {
    case SDL_KEYDOWN: {
        const auto action = map_key_action(event.key);
        if (action == UiAction::None) {
            return DispatchResult::Ignored;
        }
        set_action(action);
        return DispatchResult::Handled;
    }
    case SDL_TEXTINPUT:
        set_text_input(event.text.text);
        return DispatchResult::Handled;
    case SDL_TEXTEDITING:
        set_text_editing(event.edit.text);
        return DispatchResult::Handled;
    case SDL_CONTROLLERBUTTONDOWN: {
        const auto action = map_controller_button_action(event.cbutton);
        if (action == UiAction::None) {
            return DispatchResult::Ignored;
        }
        set_action(action);
        return DispatchResult::Handled;
    }
    case SDL_CONTROLLERAXISMOTION: {
        const auto action = map_controller_axis_action(event.caxis);
        if (action == UiAction::None) {
            return DispatchResult::Ignored;
        }
        set_action(action);
        return DispatchResult::Handled;
    }
    default:
        return DispatchResult::Ignored;
    }
}

UiAction last_action()
{
    return g_action_queue.empty() ? UiAction::None : g_action_queue.front();
}

void clear_action()
{
    g_action_queue.clear();
}

UiAction consume_action()
{
    if (g_action_queue.empty()) {
        return UiAction::None;
    }

    auto action = g_action_queue.front();
    g_action_queue.pop_front();
    return action;
}

std::string consume_text_input()
{
    if (g_last_text_inputs.empty()) {
        return {};
    }

    std::string text = std::move(g_last_text_inputs.front());
    g_last_text_inputs.pop_front();
    return text;
}

bool has_text_input()
{
    return !g_last_text_inputs.empty();
}

std::string consume_text_editing()
{
    if (g_last_text_editings.empty()) {
        return {};
    }

    std::string text = std::move(g_last_text_editings.front());
    g_last_text_editings.pop_front();
    return text;
}

bool has_text_editing()
{
    return !g_last_text_editings.empty();
}

} // namespace fire4nix::gui
