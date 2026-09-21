# Experimental modular GUI

Enable with `FIRE4NIX_MODULAR_GUI=1` when launching a real SDL build. The
default remains the legacy UI pending visual/device QA.

App initializes GuiContext after the renderer and navigation backend, processes
its input and update methods while focused, draws it within the existing
frame, and shuts it down before releasing SDL resources. No extra browser
process, event polling loop, or window is created.

F7 or SDL GameController BACK (usually SELECT) toggles panel/page focus. On
toggle, pending modular action/text queues are drained. Panel keyboard and
controller events are not forwarded to the page; mouse events are swallowed
in panel mode. Quit/window events still reach App. Analog page updates are
paused while the panel has focus.

Known limits: raw joystick mappings are not implemented for the new panel;
use a mapped SDL GameController or keyboard. Address editing/IME, held-button
transitions, legacy keyboard interactions and screen layout require live QA.
Navigation state is still submitted-request state, not browser load feedback.
The existing dashboard and diagnostic text are provisional. This opt-in is
not a final device package or evidence of successful on-device browsing.

Verification here: host audit compilation, navigation/bridge/input/renderer
logic tests and four Python security-default tests passed. Installing SDL
development libraries failed because this environment disallows the package
manager's user/group operations. No bypass was attempted, so real SDL build
and screenshot validation remain outstanding.
