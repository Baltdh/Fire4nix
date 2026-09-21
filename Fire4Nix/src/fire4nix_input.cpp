#include "fire4nix_input.hpp"

namespace fire4nix::input {
// The owning application dispatches SDL events. Do not poll here: doing so
// would steal window/quit events from its main loop.
void update() {}
bool is_ready() { return true; }
gui::UiAction pending_action() { return gui::last_action(); }
gui::UiAction consume_action() { return gui::consume_action(); }
std::string consume_text_input() { return gui::consume_text_input(); }
std::string consume_text_editing() { return gui::consume_text_editing(); }
} // namespace fire4nix::input
