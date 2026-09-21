#pragma once

#include <cstddef>
#include <string>
#include <vector>

class TabStrip {
public:
    void addTab(const std::string& title);
    void openTab(const std::string& title);
    void closeTab(std::size_t index);
    void closeCurrentTab();
    void nextTab();
    void previousTab();
    void reset(int index = 0);
    void setCurrentTitle(const std::string& title);
    int currentIndex() const;
    const std::string& currentTitle() const;
    std::size_t count() const;
    bool empty() const;

private:
    std::vector<std::string> tabs_;
    std::size_t index_{0};
};
