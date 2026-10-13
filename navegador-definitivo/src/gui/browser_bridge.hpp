#pragma once

#include <cstddef>
#include <string>

namespace fire4nix::gui {

class BrowserBridge {
public:
    virtual ~BrowserBridge() = default;

    virtual bool loadUrl(const std::string& url) = 0;
    virtual bool reload() = 0;
    virtual bool goHome() = 0;
    virtual bool goBack() = 0;
    virtual bool goForward() = 0;
    virtual bool openTab(const std::string& title) = 0;
    virtual bool closeTab() = 0;
    virtual bool toggleFullscreen() = 0;
    virtual std::string describe() const = 0;
    virtual std::string stageLabel() const { return "marco3-start"; }
    virtual std::size_t commandCount() const { return 0; }
    virtual std::string journalSummary() const { return {}; }
    virtual std::string lastCommand() const { return {}; }
    virtual std::string stateSummary() const { return journalSummary(); }
};

BrowserBridge& defaultBrowserBridge();

std::string bridgeJournalSummary();
std::size_t bridgeJournalCommandCount();
std::string bridgeJournalLastCommand();
std::string bridgeJournalPath();
std::string bridgeJournalStateSummary();

} // namespace fire4nix::gui

