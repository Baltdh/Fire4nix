#pragma once

namespace fire4nix::gui {

class GuiServices {
public:
    bool initialize();
    void update(float deltaTime);
    void shutdown();

    bool active() const { return active_; }
    float accumulatedTime() const { return accumulatedTime_; }

private:
    bool active_{false};
    float accumulatedTime_{0.0f};
};

} // namespace fire4nix::gui
