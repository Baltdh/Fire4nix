# Navigation bridge milestone

The default modular BrowserBridge now uses a main-thread callback bound by App
after backend initialization and cleared before shutdown. Navigation, reload,
back and forward are submitted to the existing Firefox command pipe rather
than merely appended to a log. No second browser process is introduced.

The bridge rejects oversized commands, embedded line breaks/NULs, and URLs
outside HTTP, HTTPS, about:home and about:blank. This is command framing
validation, not a complete network security policy. URLs are not journaled by
this submission path. Backend failure and disconnection return false.

The GUI preserves history on submission failure, does not create unsupported
tabs and no longer declares navigation 100% complete when merely submitted.
Home sends one navigation request. Actual load-complete, redirects, title and
engine history feedback still need to be implemented; requested URL/history
are not authoritative engine state.

Tests: make test-bridge test-navigation test-gui test-renderer, Python security
defaults, host build. The bridge tests use an injected transport callback;
they do not claim live Firefox navigation. Real SDL, GuiBootstrap activation,
focus routing and on-device rendering remain pending, as does WPE integration.
