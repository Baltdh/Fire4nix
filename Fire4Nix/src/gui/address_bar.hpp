#pragma once

#include <string>

namespace fire4nix {

class AddressBar {
public:
    void setUrl(const std::string& url);
    const std::string& url() const;

    void beginEditing();
    void cancelEditing();
    void commitEditing();

    void appendText(const std::string& text);
    void backspace();

    bool editing() const;
    const std::string& editedUrl() const;

private:
    std::string current_;
    std::string editingBuffer_;
    bool editing_{false};
};

} // namespace fire4nix
