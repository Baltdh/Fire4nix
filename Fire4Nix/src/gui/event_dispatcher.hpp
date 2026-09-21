#pragma once

#include "sdl_compat.hpp"

#include <string>

namespace fire4nix::gui {

enum class DispatchResult { Ignored, Handled };

enum class UiAction {
    None,
    FocusNext,
    FocusPrevious,
    Activate,
    DeleteBackward,
    Back,
    Forward,
    Reload,
    Home,
    Fullscreen,
    PreviousTab,
    NextTab,
    OpenTab,
    CloseTab
};

DispatchResult dispatch_event(int event_type);

DispatchResult dispatch_event(const SDL_Event& event);

UiAction last_action();
void clear_action();
UiAction consume_action();

std::string consume_text_input();
bool has_text_input();

std::string consume_text_editing();
bool has_text_editing();

} // namespace fire4nix::gui
