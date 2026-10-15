#pragma once

#include <cstddef>
#include <string>
#include <vector>

#include "widget.hpp"
#include "address_bar.hpp"
#include "status_bar.hpp"
#include "tab_strip.hpp"
#include "browser_bridge.hpp"

class WidgetManager;

namespace fire4nix::gui {
enum class UiAction;
}

namespace fire4nix::gui {

class BrowserChrome {
public:
    BrowserChrome() = default;

    void attachWidgetManager(WidgetManager*);
    void attachBridge(BrowserBridge*);
    void initializeDefaultWidgets();
    void reset();

    void renderTopBar(bool focused);
    void renderBottomBar(bool focused);
    void renderAddressBar(bool focused);

    void setUrl(const std::string& url);
    void setStatus(const std::string& text);
    void setProgress(int progress);
    void setTabTitle(const std::string& title);
    void navigateTo(const std::string& url);
    void goBack();
    void goForward();
    void reload();
    void goHome();
    void toggleFullscreen();
    bool canGoBack() const;
    bool canGoForward() const;
    void nextTab();
    void previousTab();
    void openTab(const std::string& title = "New Tab");
    void closeCurrentTab();
    void resetTabs(int index = 0);
    void applyAction(UiAction action);

    void beginAddressEditing();
    void cancelAddressEditing();
    void commitAddressEditing();
    void appendAddressText(const std::string& text);
    void backspaceAddress();
    bool isAddressEditing() const;

    bool widgetsReady() const;
    std::size_t tabCount() const;
    std::size_t historyCount() const;
    std::size_t historyIndex() const;
    const std::string& currentTabTitle() const;
    std::string betaSummary() const;
    std::string diagnosticSummary() const;
    bool validate(std::string* reason = nullptr) const;
    bool needsRender() const;
    void markDirty();
    void clearDirty();
    const std::string& url() const;
    const std::string& status() const;
    int progress() const;
    int readinessScore() const;
    std::string readinessSummary() const;

private:
    struct TopBarWidget : fire4nix::Widget {
        BrowserChrome* owner{nullptr};
        void update(float dt) override;
        void render() override;
        void onFocusChanged(bool focused) override;
        bool handleAction(fire4nix::gui::UiAction action) override;
    };

    struct AddressBarWidget : fire4nix::Widget {
        BrowserChrome* owner{nullptr};
        void update(float dt) override;
        void render() override;
        void onFocusChanged(bool focused) override;
        bool handleAction(fire4nix::gui::UiAction action) override;
        bool handleTextInput(const std::string& text) override;
    };

    struct BottomBarWidget : fire4nix::Widget {
        BrowserChrome* owner{nullptr};
        void update(float dt) override;
        void render() override;
        void onFocusChanged(bool focused) override;
        bool handleAction(fire4nix::gui::UiAction action) override;
    };

    void syncLoadedUrl(const std::string& url);
    void pushHistory(const std::string& url);
    WidgetManager* widgets_{nullptr};
    BrowserBridge* bridge_{nullptr};
    bool widgetsInitialized_{false};
    bool dirty_{true};
    fire4nix::AddressBar addressBar_;
    ::TabStrip tabStrip_;
    ::StatusBar statusBar_;
    std::vector<std::string> history_;
    std::size_t historyIndex_{0};
    TopBarWidget topWidget_{};
    AddressBarWidget addressWidget_{};
    BottomBarWidget bottomWidget_{};
};

} // namespace fire4nix::gui
