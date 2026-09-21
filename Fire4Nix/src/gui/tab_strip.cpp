#include <cstddef>
#include "tab_strip.hpp"

void TabStrip::addTab(const std::string& title)
{
    tabs_.push_back(title);
    if (tabs_.size() == 1) {
        index_ = 0;
    }
}

void TabStrip::openTab(const std::string& title)
{
    if (tabs_.empty()) {
        tabs_.push_back(title);
        index_ = 0;
        return;
    }

    const auto insertAt = tabs_.begin() + static_cast<std::ptrdiff_t>(index_ + 1);
    tabs_.insert(insertAt, title);
    index_ = (index_ + 1 < tabs_.size()) ? index_ + 1 : tabs_.size() - 1;
}

void TabStrip::closeTab(std::size_t index)
{
    if (index >= tabs_.size()) {
        return;
    }

    tabs_.erase(tabs_.begin() + static_cast<std::ptrdiff_t>(index));
    if (tabs_.empty()) {
        tabs_.push_back("Home");
        index_ = 0;
    } else if (index_ >= tabs_.size()) {
        index_ = tabs_.size() - 1;
    }
}

void TabStrip::closeCurrentTab()
{
    closeTab(index_);
}

void TabStrip::nextTab()
{
    if (!tabs_.empty()) {
        index_ = (index_ + 1) % tabs_.size();
    } else {
        ++index_;
    }
}

void TabStrip::previousTab()
{
    if (!tabs_.empty()) {
        index_ = (index_ + tabs_.size() - 1) % tabs_.size();
    } else if (index_ > 0) {
        --index_;
    }
}


void TabStrip::setCurrentTitle(const std::string& title)
{
    if (tabs_.empty()) {
        tabs_.push_back(title);
        index_ = 0;
        return;
    }

    if (index_ >= tabs_.size()) {
        index_ = tabs_.size() - 1;
    }

    tabs_[index_] = title;
}

void TabStrip::reset(int index)
{
    if (index < 0) {
        index = 0;
    }

    index_ = static_cast<std::size_t>(index);
    if (!tabs_.empty() && index_ >= tabs_.size()) {
        index_ = tabs_.size() - 1;
    }
}

bool TabStrip::empty() const
{
    return tabs_.empty();
}

int TabStrip::currentIndex() const
{
    return static_cast<int>(index_);
}

const std::string& TabStrip::currentTitle() const
{
    static const std::string kEmpty;
    if (tabs_.empty() || index_ >= tabs_.size()) {
        return kEmpty;
    }
    return tabs_[index_];
}

std::size_t TabStrip::count() const
{
    return tabs_.size();
}
