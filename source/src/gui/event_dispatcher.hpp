#pragma once

#if defined(__has_include)
#  if __has_include(<SDL2/SDL.h>)
#    include "sdl_compat.hpp"
#    define FIRE4NIX_HAS_SDL 1
#  endif
#endif

#include <string>

namespace fire4nix::gui {

enum class DispatchResult { Ignored, Handled };

enum class UiAction {
    None,
    FocusNext,
    FocusPrevious,
    Activate,
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

#ifdef FIRE4NIX_HAS_SDL
DispatchResult dispatch_event(const SDL_Event& event);
#endif

UiAction last_action();
void clear_action();
UiAction consume_action();

std::string consume_text_input();
bool has_text_input();

std::string consume_text_editing();
bool has_text_editing();

} // namespace fire4nix::gui
