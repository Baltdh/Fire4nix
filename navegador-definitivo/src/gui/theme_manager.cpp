#include "theme_manager.hpp"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <string>

namespace {
std::string trimCopy(const std::string& text)
{
    const auto first = text.find_first_not_of(" \t\r\n");
    if (first == std::string::npos) {
        return {};
    }
    const auto last = text.find_last_not_of(" \t\r\n");
    return text.substr(first, last - first + 1);
}

const char* envAny(const char* primary, const char* fallback = nullptr)
{
    if (const char* value = std::getenv(primary); value && *value) {
        return value;
    }
    if (fallback && *fallback) {
        if (const char* value = std::getenv(fallback); value && *value) {
            return value;
        }
    }
    return nullptr;
}

std::string readTrimmedFile(const std::filesystem::path& path)
{
    std::ifstream file(path);
    if (!file.is_open()) {
        return {};
    }

    std::string value;
    std::getline(file, value);
    return trimCopy(value);
}

bool isAllowedTheme(const std::string& theme)
{
    return theme == "beta-dark" ||
           theme == "beta-light" ||
           theme == "compact-dark" ||
           theme == "compact-light";
}

std::string resolvedThemeOrDefault(const std::string& candidate)
{
    const auto trimmed = trimCopy(candidate);
    if (trimmed.empty() || !isAllowedTheme(trimmed)) {
        return "beta-dark";
    }
    return trimmed;
}
} // namespace

namespace fire4nix::gui {

void ThemeManager::loadDefaultTheme()
{
    themeName_ = "beta-dark";
    source_ = ThemeSource::Default;
    sourceDetail_.clear();
    loaded_ = true;
}

void ThemeManager::loadFromEnvironment()
{
    if (const char* filePath = envAny("FIRE4NIX_THEME_FILE")) {
        const auto raw = readTrimmedFile(std::filesystem::path(filePath));
        if (!raw.empty()) {
            themeName_ = resolvedThemeOrDefault(raw);
            source_ = ThemeSource::EnvironmentFile;
            sourceDetail_ = std::string("FIRE4NIX_THEME_FILE=") + filePath;
            loaded_ = true;
            return;
        }
    }

    if (const char* theme = envAny("FIRE4NIX_THEME")) {
        const auto value = resolvedThemeOrDefault(theme);
        if (!value.empty()) {
            themeName_ = value;
            source_ = ThemeSource::EnvironmentValue;
            sourceDetail_ = std::string("FIRE4NIX_THEME=") + theme;
            loaded_ = true;
            return;
        }
    }

    loadDefaultTheme();
}

void ThemeManager::reset()
{
    themeName_.clear();
    sourceDetail_.clear();
    source_ = ThemeSource::Default;
    loaded_ = false;
}

bool ThemeManager::loaded() const
{
    return loaded_;
}

const std::string& ThemeManager::themeName() const
{
    return themeName_;
}

ThemeSource ThemeManager::source() const
{
    return source_;
}

std::string ThemeManager::sourceLabel() const
{
    switch (source_) {
    case ThemeSource::EnvironmentFile:
        return "file";
    case ThemeSource::EnvironmentValue:
        return "environment";
    case ThemeSource::Default:
    default:
        return loaded_ ? "default" : "unset";
    }
}

std::string ThemeManager::summary() const
{
    if (themeName_.empty()) {
        return "unset";
    }

    std::string summary = themeName_ + " (" + sourceLabel();
    if (!sourceDetail_.empty()) {
        summary += ": " + sourceDetail_;
    }
    summary += ")";
    return summary;
}

const std::string& ThemeManager::sourceDetail() const
{
    return sourceDetail_;
}

} // namespace fire4nix::gui
