#include "render_scheduler.hpp"
namespace fire4nix::gui{
void RenderScheduler::beginFrame(){active_=true;}
void RenderScheduler::endFrame(){active_=false;}
bool RenderScheduler::frameActive() const{return active_;}
}
