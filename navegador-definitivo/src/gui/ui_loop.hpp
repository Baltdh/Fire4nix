#pragma once

namespace fire4nix {
class GuiManager;
class UiLoop {
    GuiManager* manager_{nullptr};
public:
    void attach(GuiManager* m);
    void processInput();
    void update(float deltaTime);
    void render(int width = 640, int height = 480);
};
}
