#pragma once

#include <cstdint>
#include <cstring>

#if defined(__has_include) && !defined(FIRE4NIX_FORCE_SDL_STUB)
#  if __has_include(<SDL2/SDL.h>)
#    include <SDL2/SDL.h>
#    define FIRE4NIX_SDL_COMPAT_REAL 1
#  elif __has_include(<SDL.h>)
#    include <SDL.h>
#    define FIRE4NIX_SDL_COMPAT_REAL 1
#  endif
#endif

#ifndef FIRE4NIX_SDL_COMPAT_REAL

using Uint8 = std::uint8_t;
using Uint16 = std::uint16_t;
using Uint32 = std::uint32_t;
using Uint64 = std::uint64_t;
using Sint8 = std::int8_t;
using Sint16 = std::int16_t;
using Sint32 = std::int32_t;
using Sint64 = std::int64_t;

using SDL_Keycode = std::int32_t;
using SDL_JoystickID = std::int32_t;

struct SDL_Window { int unused; };
struct SDL_Renderer { int unused; };
struct SDL_Texture { int unused; };
struct SDL_GameController { int unused; };
struct SDL_Joystick { int unused; };

struct SDL_Rect { int x; int y; int w; int h; };
struct SDL_Color { Uint8 r; Uint8 g; Uint8 b; Uint8 a; };

struct SDL_Keysym { SDL_Keycode sym; };

struct SDL_KeyboardEvent {
    Uint32 type;
    Uint32 timestamp;
    Uint32 windowID;
    Uint8 state;
    Uint8 repeat;
    Uint8 padding2;
    Uint8 padding3;
    SDL_Keysym keysym;
};

struct SDL_TextInputEvent {
    Uint32 type;
    char text[32];
};

struct SDL_TextEditingEvent {
    Uint32 type;
    char text[32];
};

struct SDL_ControllerButtonEvent {
    Uint32 type;
    Uint32 timestamp;
    int which;
    Uint8 button;
    Uint8 state;
    Uint8 padding1;
    Uint8 padding2;
};

struct SDL_ControllerAxisEvent {
    Uint32 type;
    Uint32 timestamp;
    int which;
    Uint8 axis;
    Uint8 padding1;
    Uint8 padding2;
    Uint8 padding3;
    Sint16 value;
};

struct SDL_JoyButtonEvent {
    Uint32 type;
    Uint32 timestamp;
    SDL_JoystickID which;
    Uint8 button;
    Uint8 state;
    Uint8 padding1;
    Uint8 padding2;
};

struct SDL_JoyAxisEvent {
    Uint32 type;
    Uint32 timestamp;
    SDL_JoystickID which;
    Uint8 axis;
    Uint8 padding1;
    Uint8 padding2;
    Uint8 padding3;
    Sint16 value;
};

struct SDL_JoyHatEvent {
    Uint32 type;
    Uint32 timestamp;
    SDL_JoystickID which;
    Uint8 hat;
    Uint8 value;
    Uint8 padding1;
    Uint8 padding2;
};

struct SDL_WindowEvent {
    Uint32 type;
    Uint32 timestamp;
    Uint32 windowID;
    Uint8 event;
    Uint8 padding1;
    Uint8 padding2;
    Uint8 padding3;
    Sint32 data1;
    Sint32 data2;
};

union SDL_Event {
    Uint32 type;
    SDL_KeyboardEvent key;
    SDL_TextInputEvent text;
    SDL_TextEditingEvent edit;
    SDL_ControllerButtonEvent cbutton;
    SDL_ControllerAxisEvent caxis;
    SDL_JoyButtonEvent jbutton;
    SDL_JoyAxisEvent jaxis;
    SDL_JoyHatEvent jhat;
    SDL_WindowEvent window;
};

struct SDL_RendererInfo {
    const char* name;
    Uint32 flags;
    Uint32 num_texture_formats;
    Uint32 texture_formats[16];
    int max_texture_width;
    int max_texture_height;
};

enum SDL_GameControllerButton {
    SDL_CONTROLLER_BUTTON_INVALID = -1,
    SDL_CONTROLLER_BUTTON_A = 0,
    SDL_CONTROLLER_BUTTON_B = 1,
    SDL_CONTROLLER_BUTTON_X = 2,
    SDL_CONTROLLER_BUTTON_Y = 3,
    SDL_CONTROLLER_BUTTON_BACK = 4,
    SDL_CONTROLLER_BUTTON_GUIDE = 5,
    SDL_CONTROLLER_BUTTON_START = 6,
    SDL_CONTROLLER_BUTTON_LEFTSTICK = 7,
    SDL_CONTROLLER_BUTTON_RIGHTSTICK = 8,
    SDL_CONTROLLER_BUTTON_LEFTSHOULDER = 9,
    SDL_CONTROLLER_BUTTON_RIGHTSHOULDER = 10,
    SDL_CONTROLLER_BUTTON_DPAD_UP = 11,
    SDL_CONTROLLER_BUTTON_DPAD_DOWN = 12,
    SDL_CONTROLLER_BUTTON_DPAD_LEFT = 13,
    SDL_CONTROLLER_BUTTON_DPAD_RIGHT = 14,
};

enum {
    SDL_INIT_VIDEO = 0x00000020u,
    SDL_INIT_EVENTS = 0x00004000u,
    SDL_INIT_JOYSTICK = 0x00000200u,
    SDL_INIT_GAMECONTROLLER = 0x00002000u,
};

enum {
    SDL_WINDOW_SHOWN = 0x00000004u,
    SDL_WINDOW_RESIZABLE = 0x00000020u,
    SDL_WINDOWPOS_CENTERED = 0x2FFF0000u,
};

enum {
    SDL_RENDERER_SOFTWARE = 0x00000001u,
    SDL_RENDERER_ACCELERATED = 0x00000002u,
    SDL_RENDERER_PRESENTVSYNC = 0x00000004u,
    SDL_RENDERER_TARGETTEXTURE = 0x00000008u,
};

enum {
    SDL_TEXTUREACCESS_STREAMING = 1,
    SDL_TEXTUREACCESS_TARGET = 2,
};

enum {
    SDL_PIXELFORMAT_UNKNOWN = 0u,
    SDL_PIXELFORMAT_ARGB8888 = 1u,
    SDL_PIXELFORMAT_RGBA8888 = 2u,
};

enum {
    SDL_BLENDMODE_NONE = 0,
    SDL_BLENDMODE_BLEND = 1,
};

enum {
    SDL_ENABLE = 1,
    SDL_DISABLE = 0,
};

enum {
    SDL_CONTROLLER_AXIS_LEFTX = 0,
    SDL_CONTROLLER_AXIS_LEFTY = 1,
    SDL_CONTROLLER_AXIS_RIGHTX = 2,
    SDL_CONTROLLER_AXIS_RIGHTY = 3,
    SDL_CONTROLLER_AXIS_TRIGGERLEFT = 4,
    SDL_CONTROLLER_AXIS_TRIGGERRIGHT = 5,
};

enum {
    SDL_HAT_CENTERED = 0x00,
    SDL_HAT_UP = 0x01,
    SDL_HAT_RIGHT = 0x02,
    SDL_HAT_DOWN = 0x04,
    SDL_HAT_LEFT = 0x08,
};

enum {
    SDL_QUIT = 0x100,
    SDL_KEYDOWN = 0x300,
    SDL_KEYUP = 0x301,
    SDL_TEXTINPUT = 0x303,
    SDL_TEXTEDITING = 0x304,
    SDL_CONTROLLERAXISMOTION = 0x650,
    SDL_CONTROLLERBUTTONDOWN = 0x651,
    SDL_CONTROLLERBUTTONUP = 0x652,
    SDL_CONTROLLERDEVICEADDED = 0x653,
    SDL_CONTROLLERDEVICEREMOVED = 0x654,
    SDL_JOYAXISMOTION = 0x600,
    SDL_JOYBALLMOTION = 0x601,
    SDL_JOYHATMOTION = 0x602,
    SDL_JOYBUTTONDOWN = 0x603,
    SDL_JOYBUTTONUP = 0x604,
    SDL_WINDOWEVENT = 0x200,
    SDL_WINDOWEVENT_SIZE_CHANGED = 0x05,
};

#define SDL_HINT_RENDER_SCALE_QUALITY "SDL_RENDER_SCALE_QUALITY"
#define SDL_HINT_FRAMEBUFFER_ACCELERATION "SDL_FRAMEBUFFER_ACCELERATION"
#define SDL_HINT_RENDER_VSYNC "SDL_RENDER_VSYNC"

enum : SDL_Keycode {
    SDLK_UNKNOWN = 0,
    SDLK_RETURN = 13,
    SDLK_ESCAPE = 27,
    SDLK_BACKSPACE = 8,
    SDLK_TAB = 9,
    SDLK_SPACE = 32,
    SDLK_PLUS = '+',
    SDLK_EQUALS = '=',
    SDLK_MINUS = '-',
    SDLK_UP = 1001,
    SDLK_DOWN = 1002,
    SDLK_LEFT = 1003,
    SDLK_RIGHT = 1004,
    SDLK_r = 'r',
    SDLK_s = 's',
    SDLK_t = 't',
    SDLK_m = 'm',
    SDLK_q = 'q',
    SDLK_h = 'h',
    SDLK_n = 'n',
    SDLK_w = 'w',
    SDLK_F5 = 2005,
    SDLK_F7 = 2007,
    SDLK_F11 = 2011,
    SDLK_PAGEUP = 2101,
    SDLK_PAGEDOWN = 2102,
    SDLK_HOME = 2103,
    SDLK_RIGHTBRACKET = ']',
};

inline const char* SDL_GetError() { return "SDL stub"; }
inline const char* SDL_GetPixelFormatName(Uint32) { return "SDL_PIXELFORMAT_STUB"; }
inline int SDL_Init(Uint32) { return 0; }
inline void SDL_Quit() {}
inline int SDL_SetHint(const char*, const char*) { return 1; }
inline int SDL_GameControllerEventState(int) { return 1; }
inline int SDL_NumJoysticks() { return 0; }
inline int SDL_IsGameController(int) { return 0; }
inline SDL_GameController* SDL_GameControllerOpen(int) { return reinterpret_cast<SDL_GameController*>(0x1); }
inline void SDL_GameControllerClose(SDL_GameController*) {}
inline const char* SDL_GameControllerName(SDL_GameController*) { return "SDL stub controller"; }
inline const char* SDL_GameControllerGetStringForButton(SDL_GameControllerButton) { return "button"; }
inline int SDL_GameControllerGetButton(SDL_GameController*, SDL_GameControllerButton) { return 0; }
inline SDL_Joystick* SDL_JoystickOpen(int) { return reinterpret_cast<SDL_Joystick*>(0x1); }
inline void SDL_JoystickClose(SDL_Joystick*) {}
inline const char* SDL_JoystickName(SDL_Joystick*) { return "SDL stub joystick"; }
inline SDL_Joystick* SDL_JoystickFromInstanceID(SDL_JoystickID) { return reinterpret_cast<SDL_Joystick*>(0x1); }
inline int SDL_JoystickGetButton(SDL_Joystick*, int) { return 0; }
inline int SDL_PollEvent(SDL_Event*) { return 0; }
inline void SDL_Delay(Uint32) {}
inline void SDL_StartTextInput() {}
inline void SDL_StopTextInput() {}
inline int SDL_ShowCursor(int) { return 0; }
inline void SDL_SetWindowTitle(SDL_Window*, const char*) {}
inline SDL_Window* SDL_CreateWindow(const char*, int, int, int, int, Uint32) { return reinterpret_cast<SDL_Window*>(0x1); }
inline void SDL_DestroyWindow(SDL_Window*) {}
inline SDL_Renderer* SDL_CreateRenderer(SDL_Window*, int, Uint32) { return reinterpret_cast<SDL_Renderer*>(0x1); }
inline void SDL_DestroyRenderer(SDL_Renderer*) {}
inline void SDL_DestroyTexture(SDL_Texture*) {}
inline void SDL_SetRenderDrawColor(SDL_Renderer*, Uint8, Uint8, Uint8, Uint8) {}
inline void SDL_SetRenderDrawBlendMode(SDL_Renderer*, int) {}
inline int SDL_RenderFillRect(SDL_Renderer*, const SDL_Rect*) { return 0; }
inline int SDL_RenderDrawRect(SDL_Renderer*, const SDL_Rect*) { return 0; }
inline int SDL_RenderDrawLine(SDL_Renderer*, int, int, int, int) { return 0; }
inline int SDL_RenderCopy(SDL_Renderer*, SDL_Texture*, const SDL_Rect*, const SDL_Rect*) { return 0; }
inline int SDL_RenderClear(SDL_Renderer*) { return 0; }
inline void SDL_RenderPresent(SDL_Renderer*) {}
inline int SDL_SetRenderTarget(SDL_Renderer*, SDL_Texture*) { return 0; }
inline SDL_Texture* SDL_CreateTexture(SDL_Renderer*, Uint32, int, int, int) { return reinterpret_cast<SDL_Texture*>(0x1); }
inline int SDL_LockTexture(SDL_Texture*, const SDL_Rect*, void**, int*) { return 0; }
inline void SDL_UnlockTexture(SDL_Texture*) {}
inline int SDL_SetTextureBlendMode(SDL_Texture*, int) { return 0; }
inline int SDL_GetWindowSize(SDL_Window*, int* w, int* h) { if (w) *w = 640; if (h) *h = 480; return 0; }
inline int SDL_GetRendererInfo(SDL_Renderer*, SDL_RendererInfo* info) {
    if (info) {
        info->name = "SDL-stub";
        info->flags = SDL_RENDERER_SOFTWARE;
        info->num_texture_formats = 1;
        info->texture_formats[0] = SDL_PIXELFORMAT_ARGB8888;
        info->max_texture_width = 640;
        info->max_texture_height = 480;
    }
    return 0;
}
inline SDL_Texture* SDL_GetRenderTarget(SDL_Renderer*) { return nullptr; }

#endif // FIRE4NIX_SDL_COMPAT_REAL
