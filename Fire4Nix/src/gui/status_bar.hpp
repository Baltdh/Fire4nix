#pragma once

#include <string>

class StatusBar {
public:
    void setStatus(const std::string& text);
    const std::string& status() const;

    void setProgress(int progress);
    int progress() const;

private:
    std::string current_{"Ready"};
    int progress_{0};
};
