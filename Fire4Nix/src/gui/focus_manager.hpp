#pragma once

#include <cstddef>

class FocusManager {
public:
    void setCount(std::size_t count)
    {
        count_ = count;
        if (count_ == 0 || index_ >= count_) {
            index_ = 0;
        }
    }

    void setCurrent(std::size_t index)
    {
        if (count_ == 0) {
            index_ = 0;
            return;
        }
        index_ = index % count_;
    }

    void next()
    {
        if (count_) {
            index_ = (index_ + 1) % count_;
        }
    }

    void previous()
    {
        if (count_) {
            index_ = (index_ + count_ - 1) % count_;
        }
    }

    void reset()
    {
        count_ = 0;
        index_ = 0;
    }

    std::size_t current() const { return index_; }
    std::size_t count() const { return count_; }
    bool hasFocus() const { return count_ != 0; }

private:
    std::size_t count_{0};
    std::size_t index_{0};
};
