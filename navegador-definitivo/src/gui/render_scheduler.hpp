#pragma once
namespace fire4nix::gui {
class RenderScheduler{
public:
 void beginFrame();
 void endFrame();
 bool frameActive() const;
private:
 bool active_{false};
};
}
