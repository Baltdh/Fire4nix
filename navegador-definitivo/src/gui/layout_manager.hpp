#pragma once
namespace fire4nix::gui {
struct LayoutState{int width{0};int height{0};bool dirty{true};};
class LayoutManager {
public:
    void updateLayout(int width, int height);
    void markDirty();
    void clearDirty();
    const LayoutState& state() const;
private:
    LayoutState state_;
};
}
