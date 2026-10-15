#pragma once
#include <string>
#include "gui/event_dispatcher.hpp"

namespace fire4nix::input {
void update();
bool is_ready();
fire4nix::gui::UiAction pending_action();
fire4nix::gui::UiAction consume_action();
std::string consume_text_input();
std::string consume_text_editing();
} // namespace fire4nix::input
