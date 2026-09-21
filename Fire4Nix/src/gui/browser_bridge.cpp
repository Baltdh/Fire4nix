#include "browser_bridge.hpp"

#include <algorithm>
#include <chrono>
#include <ctime>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <string>
#include <vector>

namespace fire4nix::gui {
namespace {
BrowserCommandHandler commandHandler;

bool dispatchCommand(const std::string& command)
{
    if (command.size() > 8192 || command.find_first_of("\r\n") != std::string::npos
        || command.find('\0') != std::string::npos || !commandHandler)
        return false;
    return commandHandler(command);
}

std::string trimCopy(const std::string& text)
{
    const auto begin = text.find_first_not_of(" \t\r\n");
    if (begin == std::string::npos) {
        return {};
    }
    const auto end = text.find_last_not_of(" \t\r\n");
    return text.substr(begin, end - begin + 1);
}

std::string envOr(const char* name, const std::string& fallback)
{
    const char* value = std::getenv(name);
    if (value == nullptr || *value == '\0') {
        return fallback;
    }
    return trimCopy(value);
}


std::string nowStamp()
{
    using clock = std::chrono::system_clock;
    const auto now = clock::now();
    const std::time_t tt = clock::to_time_t(now);
    std::tm tm{};
#if defined(_WIN32)
    localtime_s(&tm, &tt);
#else
    localtime_r(&tt, &tm);
#endif
    char buf[32]{};
    std::strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M:%S", &tm);
    return std::string(buf);
}

std::filesystem::path resolveBridgeJournalPath()
{
    if (const char* explicitPath = std::getenv("FIRE4NIX_BRIDGE_JOURNAL"); explicitPath != nullptr && *explicitPath != '\0') {
        return std::filesystem::path(trimCopy(explicitPath));
    }

    if (const char* runtimeDir = std::getenv("FIRE4NIX_RUNTIME_DIR"); runtimeDir != nullptr && *runtimeDir != '\0') {
        return std::filesystem::path(trimCopy(runtimeDir)) / "bridge-journal.log";
    }

    if (const char* configDir = std::getenv("FIRE4NIX_CONFIG_DIR"); configDir != nullptr && *configDir != '\0') {
        return std::filesystem::path(trimCopy(configDir)) / "runtime" / "bridge-journal.log";
    }

    return std::filesystem::path(".fire4nix") / "runtime" / "bridge-journal.log";
}

void appendBridgeJournalLine(const std::string& line)
{
    const auto path = resolveBridgeJournalPath();
    std::error_code ec;
    if (const auto parent = path.parent_path(); !parent.empty()) {
        std::filesystem::create_directories(parent, ec);
    }
    std::ofstream out(path, std::ios::app);
    if (!out.is_open()) {
        return;
    }
    out << line << '\n';
}

class ShellBrowserBridge final : public BrowserBridge {
public:
    bool loadUrl(const std::string& url) override
    {
        const auto target = trimCopy(url);
        if (target.rfind("https://", 0) != 0 && target.rfind("http://", 0) != 0
            && target != "about:home" && target != "about:blank") return false;
        return dispatchCommand("load:" + target);
    }

    bool reload() override
    {
        return dispatchCommand("key:ctrl+r");
    }

    bool goHome() override
    {
        return loadUrl(envOr("FIRE4NIX_HOME_URL", "about:home"));
    }

    bool goBack() override
    {
        return dispatchCommand("back");
    }

    bool goForward() override
    {
        return dispatchCommand("key:alt+Right");
    }

    bool openTab(const std::string& title) override
    {
        (void)title;
        return false; // Tab lifecycle is not yet synchronized with the backend.
    }

    bool closeTab() override
    {
        return false;
    }

    bool toggleFullscreen() override
    {
        return false; // App owns the outer window; do not toggle Firefox alone.
    }

    std::string describe() const override
    {
        return stageLabel() + " • " + stateSummary();
    }

    std::string stageLabel() const override
    {
        return envOr("FIRE4NIX_PROGRESS_STAGE_NAME", envOr("FIRE4NIX_PROGRESS_STAGE", "marco3-start"));
    }

    std::size_t commandCount() const override
    {
        std::lock_guard<std::mutex> lock(mutex_);
        return commands_.size();
    }

    std::string journalSummary() const override
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (commands_.empty()) {
            return "journal idle";
        }
        return std::to_string(commands_.size()) + " commands";
    }

    std::string lastCommand() const override
    {
        std::lock_guard<std::mutex> lock(mutex_);
        return lastCommand_.empty() ? std::string("none") : lastCommand_;
    }

    std::string stateSummary() const override
    {
        return journalSummary() + " • last " + lastCommand() + " • path " + journalPath();
    }

    std::string journalPath() const
    {
        return resolveBridgeJournalPath().string();
    }

private:
    void record(const std::string& command)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        commands_.push_back(command);
        lastCommand_ = command;
        if (commands_.size() > 32) {
            commands_.erase(commands_.begin(), commands_.begin() + static_cast<std::ptrdiff_t>(commands_.size() - 32));
        }

        appendBridgeJournalLine(nowStamp() + " | stage=" + stageLabel() + " | command=" + command);
    }

    mutable std::mutex mutex_;
    std::vector<std::string> commands_;
    std::string lastCommand_;
};

ShellBrowserBridge g_shellBridge;

} // namespace

BrowserBridge& defaultBrowserBridge()
{
    return g_shellBridge;
}

void setBrowserCommandHandler(BrowserCommandHandler handler)
{
    commandHandler = std::move(handler);
}

std::string bridgeJournalSummary()
{
    return g_shellBridge.journalSummary();
}

std::size_t bridgeJournalCommandCount()
{
    return g_shellBridge.commandCount();
}

std::string bridgeJournalLastCommand()
{
    return g_shellBridge.lastCommand();
}

std::string bridgeJournalPath()
{
    return g_shellBridge.journalPath();
}

std::string bridgeJournalStateSummary()
{
    return g_shellBridge.stateSummary();
}

} // namespace fire4nix::gui
