#include "status_bar.hpp"

namespace {
int clamp_progress(int value)
{
    if (value < 0) {
        return 0;
    }
    if (value > 100) {
        return 100;
    }
    return value;
}
} // namespace

void StatusBar::setStatus(const std::string& text)
{
    current_ = text;
}

const std::string& StatusBar::status() const
{
    return current_;
}

void StatusBar::setProgress(int progress)
{
    progress_ = clamp_progress(progress);
}

int StatusBar::progress() const
{
    return progress_;
}
