# Renderer integration

App now lends its SDL window and renderer to the modular renderer adapter
after creation and detaches them before destruction. The adapter does not
create a second window, poll events, clear frames or present a second frame.
The real SDL path checks that the renderer belongs to the supplied window.
The audit/stub path rejects handles instead of reporting fake success.

Validated: clean host audit build, make test-gui, make test-renderer,
four Python security-default tests and the --version command.
Real SDL compilation, rendering and hardware validation remain pending because
this host lacks the development dependencies. The new test exercises only
stub rejection and detached lifecycle, not successful real SDL attachment.

GuiBootstrap still needs to be started in App, with explicit focus ownership
and navigation bridge wiring. This is an adapter milestone, not a completed
GUI. Screenshot QA at 640x480 and WPE runtime integration remain pending.
