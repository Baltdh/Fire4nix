#include "address_bar.hpp"

namespace fire4nix {

void AddressBar::setUrl(const std::string& u)
{
    current_ = u;
    if (!editing_) {
        editingBuffer_ = current_;
    }
}

const std::string& AddressBar::url() const
{
    return editing_ ? editingBuffer_ : current_;
}

void AddressBar::beginEditing()
{
    editing_ = true;
    editingBuffer_ = current_;
}

void AddressBar::cancelEditing()
{
    editing_ = false;
    editingBuffer_ = current_;
}

void AddressBar::commitEditing()
{
    current_ = editingBuffer_;
    editing_ = false;
}

void AddressBar::appendText(const std::string& text)
{
    if (editing_) {
        editingBuffer_ += text;
    }
}

void AddressBar::backspace()
{
    if (editing_ && !editingBuffer_.empty()) {
        editingBuffer_.pop_back();
    }
}

bool AddressBar::editing() const
{
    return editing_;
}

const std::string& AddressBar::editedUrl() const
{
    return editingBuffer_.empty() ? current_ : editingBuffer_;
}

} // namespace fire4nix
