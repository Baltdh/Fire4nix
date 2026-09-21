AUDIT_MODE ?= 1
BUILD_MODE ?= SDL_ONLY
WARNFLAGS ?= -Wall -Wextra -Werror=return-type
ENABLE_LITEHTML ?= 0
USE_SYSTEM_LITEHTML ?= 1

PKG_CONFIG ?= pkg-config
CXX ?= g++

CURL_CFLAGS ?= $(shell $(PKG_CONFIG) --cflags libcurl 2>/dev/null)
CURL_LIBS ?= $(shell $(PKG_CONFIG) --libs libcurl 2>/dev/null)
TTF_LIBS ?= $(shell $(PKG_CONFIG) --libs SDL2_ttf 2>/dev/null)
IMG_LIBS ?= $(shell $(PKG_CONFIG) --libs SDL2_image 2>/dev/null)
LITEHTML_CFLAGS ?= $(shell $(PKG_CONFIG) --cflags litehtml 2>/dev/null)
LITEHTML_LIBS ?= $(shell $(PKG_CONFIG) --libs litehtml 2>/dev/null)

SDL_PKGS = sdl2 SDL2_image SDL2_ttf SDL2_mixer SDL2_net
SDL_CFLAGS := $(shell $(PKG_CONFIG) --cflags $(SDL_PKGS) 2>/dev/null)
SDL_LIBS := $(shell $(PKG_CONFIG) --libs $(SDL_PKGS) 2>/dev/null)

WPE_PKG_NAME ?= $(shell for pkg in wpe-webkit-2.0 wpe-webkit wpewebkit; do $(PKG_CONFIG) --exists $$pkg >/dev/null 2>&1 && { printf '%s\n' $$pkg; break; }; done; printf '%s\n' wpe-webkit-2.0)
WPE_CFLAGS ?= $(shell if [ -n "$(WPE_PKG_NAME)" ]; then $(PKG_CONFIG) --cflags $(WPE_PKG_NAME) 2>/dev/null; fi)
WPE_LIBS ?= $(shell if [ -n "$(WPE_PKG_NAME)" ]; then $(PKG_CONFIG) --libs $(WPE_PKG_NAME) 2>/dev/null; fi)

TARGET = fire4nix

# Build the launcher wrapper plus the implementation sources, but exclude the
# duplicate runtime bridge/main entry points that are already provided by the
# top-level launcher and runtime files.
SRCS := src/main.cpp \
	$(filter-out src/main.cpp src/fire4nix_runtime_bridge.cpp,$(wildcard src/*.cpp)) \
	$(wildcard src/gui/*.cpp)

OBJS := $(SRCS:.cpp=.o)

CPPFLAGS += -I. -Isrc -Isrc/gui
CXXFLAGS += $(WARNFLAGS) $(CURL_CFLAGS) $(LITEHTML_CFLAGS) -std=c++17 -O2 $(SDL_CFLAGS) -DRK3326_BUILD
LDFLAGS +=
LDLIBS += $(SDL_LIBS) $(IMG_LIBS) $(TTF_LIBS) $(CURL_LIBS) $(LITEHTML_LIBS)

all: $(TARGET)

test-navigation: $(filter-out src/main.o,$(OBJS))
	@mkdir -p build
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -UNDEBUG tests/navigation_state_test.cpp $(filter-out src/main.o,$(OBJS)) $(LDFLAGS) $(LDLIBS) -o build/navigation-state-test
	./build/navigation-state-test

test-bridge:
	@mkdir -p build
	$(CXX) $(CPPFLAGS) -std=c++17 $(WARNFLAGS) -UNDEBUG tests/browser_bridge_test.cpp src/gui/browser_bridge.cpp -o build/browser-bridge-test
	./build/browser-bridge-test

test-renderer:
	@mkdir -p build
	$(CXX) $(CPPFLAGS) -std=c++17 $(WARNFLAGS) -UNDEBUG -DFIRE4NIX_FORCE_SDL_STUB tests/renderer_contract_test.cpp src/fire4nix_renderer.cpp -o build/renderer-contract-test
	./build/renderer-contract-test

test-gui:
	@mkdir -p build
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -UNDEBUG tests/gui_input_test.cpp src/fire4nix_input.cpp src/gui/event_dispatcher.cpp src/gui/widget_manager.cpp src/gui/layout_manager.cpp -o build/gui-input-test
	./build/gui-input-test

$(TARGET): $(OBJS)
	$(CXX) $(OBJS) $(LDFLAGS) $(LDLIBS) -o $@

%.o: %.cpp
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -c $< -o $@

ifeq ($(strip $(WPE_LIBS)),)
wpe-platform-launcher:
	@echo "WPE launcher not built: pkg-config package '$(WPE_PKG_NAME)' not available."
else
wpe-platform-launcher: src/wpe/wpe_platform_launcher.cpp
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(WPE_CFLAGS) $< $(WPE_LIBS) -o fire4nix-wpe-platform
endif

clean:
	rm -f $(OBJS) $(TARGET)

.PHONY: all clean wpe-platform-launcher test-gui test-renderer test-bridge test-navigation
