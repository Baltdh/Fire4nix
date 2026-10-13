#pragma once

#include <string>

namespace fire4nix::gui {

enum class ThemeSource {
    Default,
    EnvironmentFile,
    EnvironmentValue,
};

class ThemeManager {
public:
    void loadDefaultTheme();
    void loadFromEnvironment();
    void reset();
    bool loaded() const;
    const std::string& themeName() const;
    ThemeSource source() const;
    std::string sourceLabel() const;
    std::string summary() const;
    const std::string& sourceDetail() const;

private:
    bool loaded_{false};
    ThemeSource source_{ThemeSource::Default};
    std::string themeName_;
    std::string sourceDetail_;
};

} // namespace fire4nix::gui
