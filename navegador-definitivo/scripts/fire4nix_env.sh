#!/bin/bash
# Shared Fire4Nix environment helpers for ROCKNIX-safe launches and installs.

fire4nix_script_dir() {
    local source_path="${BASH_SOURCE[0]:-$0}"
    local resolved
    resolved="$(readlink -f "$source_path" 2>/dev/null || python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$source_path" 2>/dev/null || printf '%s\n' "$source_path")"
    cd "$(dirname "$resolved")" && pwd
}

fire4nix_resolve_app_dir() {
    local script_dir="${1:-$(fire4nix_script_dir)}"
    case "$script_dir" in
        */scripts) cd "$script_dir/.." && pwd ;;
        *) printf '%s\n' "$script_dir" ;;
    esac
}

fire4nix_resolve_config_root() {
    local app_dir="${1:-$(fire4nix_resolve_app_dir)}"
    local candidate

    if [ -n "${FIRE4NIX_CONFIG_DIR:-}" ]; then
        candidate="$FIRE4NIX_CONFIG_DIR"
    elif [ -n "${XDG_CONFIG_HOME:-}" ]; then
        candidate="${XDG_CONFIG_HOME%/}/fire4nix"
    elif [ -n "${HOME:-}" ]; then
        candidate="${HOME%/}/.config/fire4nix"
    elif [ -d /storage ] || [ -w /storage ] 2>/dev/null; then
        candidate="/storage/.config/fire4nix"
    else
        candidate="$app_dir/.fire4nix"
    fi

    mkdir -p "$candidate" 2>/dev/null || true
    if [ -w "$candidate" ]; then
        printf '%s
' "$candidate"
        return 0
    fi

    candidate="$app_dir/.fire4nix"
    mkdir -p "$candidate" 2>/dev/null || true
    printf '%s
' "$candidate"
}

fire4nix_resolve_runtime_dir() {
    local app_dir="${1:-$(fire4nix_resolve_app_dir)}"
    if [ -n "${FIRE4NIX_RUNTIME_DIR:-}" ]; then
        printf '%s\n' "$FIRE4NIX_RUNTIME_DIR"
        return 0
    fi
    if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d "${XDG_RUNTIME_DIR:-}" ] && [ -w "${XDG_RUNTIME_DIR:-}" ]; then
        printf '%s\n' "$XDG_RUNTIME_DIR"
        return 0
    fi
    local candidate="/run/user/$(id -u 2>/dev/null || echo 0)"
    if [ -d "$candidate" ] && [ -w "$candidate" ]; then
        printf '%s\n' "$candidate"
        return 0
    fi
    printf '%s\n' "$app_dir/.fire4nix/runtime"
}

fire4nix_prepend_path_unique() {
    local var_name="$1"
    local new_path="$2"
    local current_value
    [ -n "$var_name" ] || return 0
    [ -n "$new_path" ] || return 0

    current_value="${!var_name:-}"
    case ":$current_value:" in
        *":$new_path:"*) return 0 ;;
        ":") current_value="$new_path" ;;
        "") current_value="$new_path" ;;
        *) current_value="$new_path:$current_value" ;;
    esac

    printf -v "$var_name" '%s' "$current_value"
    export "$var_name"
}


fire4nix_choose_audio_driver() {
    if [ -n "${SDL_AUDIODRIVER:-}" ]; then
        printf '%s\n' "$SDL_AUDIODRIVER"
        return 0
    fi

    case "${FIRE4NIX_AUDIO_BACKEND:-auto}" in
        pulse)
            printf '%s\n' pulse
            return 0
            ;;
        alsa)
            printf '%s\n' alsa
            return 0
            ;;
        auto)
            if [ -e /dev/snd ] || [ -d /dev/snd ]; then
                printf '%s\n' alsa
                return 0
            fi
            if command -v pactl >/dev/null 2>&1 || command -v pulseaudio >/dev/null 2>&1; then
                printf '%s\n' pulse
                return 0
            fi
            ;;
    esac

    printf '%s\n' ""
}

fire4nix_resolve_reference_root() {
    local app_dir="${1:-$(fire4nix_resolve_app_dir)}"
    if [ -n "${FIRE4NIX_REFERENCE_ROOT:-}" ]; then
        printf '%s\n' "$FIRE4NIX_REFERENCE_ROOT"
        return 0
    fi
    if [ -d "$app_dir/rocknix_reference" ]; then
        printf '%s\n' "$app_dir/rocknix_reference"
        return 0
    fi
    if [ -n "${FIRE4NIX_CONFIG_DIR:-}" ] && [ -d "${FIRE4NIX_CONFIG_DIR:-}/reference" ]; then
        printf '%s\n' "$FIRE4NIX_CONFIG_DIR/reference"
        return 0
    fi
    printf '%s\n' "$app_dir/rocknix_reference"
}

fire4nix_prepare_directories() {
    local config_dir="$1"
    local runtime_dir="$2"
    mkdir -p \
        "$config_dir/cache" \
        "$config_dir/logs" \
        "$config_dir/profiles/chromium" \
        "$config_dir/profiles/firefox" \
        "$config_dir/profiles/cog" \
        "$config_dir/profiles/wpe" \
        "$config_dir/profiles/wpe-platform" \
        "$runtime_dir" 2>/dev/null || true
    chmod 700 "$runtime_dir" 2>/dev/null || true
}

fire4nix_engine_profile_dir() {
    local engine="$(fire4nix_trim "${1:-}")"
    local config_root="${FIRE4NIX_CONFIG_DIR:-}"
    if [ -z "$config_root" ]; then
        config_root="$(fire4nix_resolve_config_root)"
    fi

    case "${engine,,}" in
        cog|wpe-launcher|wpe-browser|mini-browser|wpe-webkit-launcher|wpewebkit-launcher)
            printf '%s\n' "$config_root/profiles/cog"
            ;;
        wpe|wpe-platform|wpe-native|wpe-platform-launcher)
            printf '%s\n' "$config_root/profiles/wpe-platform"
            ;;
        chromium|chromium-browser)
            printf '%s\n' "$config_root/profiles/chromium"
            ;;
        firefox|firefox-esr)
            printf '%s\n' "$config_root/profiles/firefox"
            ;;
        *)
            printf '%s\n' "$config_root/profiles/${engine:-default}"
            ;;
    esac
}

fire4nix_trim() {
    printf '%s' "${1:-}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

fire4nix_read_trimmed_file() {
    local path="${1:-}"
    if [ -z "$path" ] || [ ! -f "$path" ]; then
        return 1
    fi
    tr -d '\r\n' < "$path" 2>/dev/null || true
}

fire4nix_progress_stage_label() {
    printf '%s
' "${FIRE4NIX_PROGRESS_STAGE:-marco3-start}"
}

fire4nix_progress_stage_name() {
    case "$(fire4nix_progress_stage_label)" in
        marco1-cleanup|phase2-continuation)
            printf '%s
' "Marco 1 complete"
            ;;
        phase2-browser-bridge)
            printf '%s
' "browser bridge prep"
            ;;
        marco2-complete)
            printf '%s
' "Marco 2 complete"
            ;;
        marco3-start)
            printf '%s
' "Marco 3 start"
            ;;
        phase2-wpe-runtime|phase3-wpe-runtime)
            printf '%s
' "wpe runtime handoff"
            ;;
        phase2-rocknix-validation|phase3-rocknix-validation)
            printf '%s
' "rocknix validation"
            ;;
        *)
            printf '%s
' "$(fire4nix_progress_stage_label)"
            ;;
    esac
}

fire4nix_progress_stage_summary() {
    printf '%s
' "$(fire4nix_progress_stage_name): $(fire4nix_progress_focus)"
}

fire4nix_progress_focus() {
    case "$(fire4nix_progress_stage_label)" in
        marco1-cleanup|phase2-continuation)
            cat <<'EOF'
mark Marco 1 complete, keep the shared launcher helpers centralized, and preserve the clean audit base
EOF
            ;;
        phase2-browser-bridge)
            cat <<'EOF'
connect browser chrome actions to the shell bridge journal and keep the status context synchronized
EOF
            ;;
        marco2-complete)
            cat <<'EOF'
seal the browser bridge handoff, keep the chrome and shell snapshots synchronized, and prepare the WPE runtime pass
EOF
            ;;
        marco3-start)
            cat <<'EOF'
map the upstream WPE source bundles to Fire4Nix launcher, backend, and platform roles before wiring the native runtime handoff
EOF
            ;;
        phase2-wpe-runtime|phase3-wpe-runtime)
            cat <<'EOF'
resolve the native WPE launcher at runtime and keep Cog as the fallback path
EOF
            ;;
        phase2-rocknix-validation|phase3-rocknix-validation)
            cat <<'EOF'
run the ROCKNIX smoke pass and lock the next handoff snapshot
EOF
            ;;
        *)
            cat <<'EOF'
normalize shared launcher helpers, remove duplicate launch logic, and keep the browser status aligned
EOF
            ;;
    esac
}

fire4nix_progress_next_action() {
    case "$(fire4nix_progress_stage_label)" in
        marco1-cleanup|phase2-continuation)
            cat <<'EOF'
finalize Marco 1 completion, export the consistent snapshot, and hand off to the browser bridge prep stage
EOF
            ;;
        phase2-browser-bridge)
            cat <<'EOF'
record open, back, forward, reload, home, fullscreen, and tab actions in the bridge journal
EOF
            ;;
        marco2-complete)
            cat <<'EOF'
advance the active handoff to the WPE runtime pass and keep Cog fallback plus profile separation intact
EOF
            ;;
        marco3-start)
            cat <<'EOF'
map the WPE source bundles and wire the native WPE launcher into the runtime bridge
EOF
            ;;
        phase2-wpe-runtime|phase3-wpe-runtime)
            cat <<'EOF'
connect the native WPE launcher while preserving Cog fallback and profile separation
EOF
            ;;
        phase2-rocknix-validation|phase3-rocknix-validation)
            cat <<'EOF'
verify open, back, forward, reload, home, fullscreen, and controller/menu actions on ROCKNIX
EOF
            ;;
        *)
            cat <<'EOF'
run the audit, trim stale references, and prepare the native WPE bridge
EOF
            ;;
    esac
}

fire4nix_progress_acceptance() {
    case "$(fire4nix_progress_stage_label)" in
        marco1-cleanup|phase2-continuation)
            cat <<'EOF'
Marco 1 is complete, the snapshot is consistent, and the package is ready for the bridge stage
EOF
            ;;
        phase2-browser-bridge)
            cat <<'EOF'
shell snapshots, bridge journal, and chrome status show the same stage, focus, next action, command count, and last command
EOF
            ;;
        marco2-complete)
            cat <<'EOF'
Marco 2 is complete, the bridge journal and chrome status stay synchronized, and the WPE runtime pass is the next handoff
EOF
            ;;
        marco3-start)
            cat <<'EOF'
Marco 3 is now grounded in the WPE source map, with the launcher, backend, and platform roles recorded before the native runtime handoff
EOF
            ;;
        phase2-wpe-runtime|phase3-wpe-runtime)
            cat <<'EOF'
native WPE launches when present and Cog stays the clean fallback when it is not
EOF
            ;;
        phase2-rocknix-validation|phase3-rocknix-validation)
            cat <<'EOF'
launch, navigation, and controller/menu actions hold steady across the beta handoff on ROCKNIX
EOF
            ;;
        *)
            cat <<'EOF'
shared launcher helpers are centralized and the audit passes cleanly
EOF
            ;;
    esac
}

fire4nix_bridge_journal_path() {
    if [ -n "${FIRE4NIX_BRIDGE_JOURNAL:-}" ]; then
        printf '%s
' "${FIRE4NIX_BRIDGE_JOURNAL}"
        return 0
    fi
    printf '%s
' "${FIRE4NIX_RUNTIME_DIR:-$(fire4nix_resolve_runtime_dir)}/bridge-journal.log"
}

fire4nix_bridge_journal_count() {
    local path
    path="$(fire4nix_bridge_journal_path)"
    if [ -f "$path" ]; then
        wc -l < "$path" 2>/dev/null | tr -d '[:space:]'
        return 0
    fi
    printf '%s
' "0"
}

fire4nix_bridge_journal_last_command() {
    local path
    path="$(fire4nix_bridge_journal_path)"
    if [ -f "$path" ]; then
        tail -n 1 "$path" 2>/dev/null | sed 's/^[[:space:]]*//'
        return 0
    fi
    printf '%s
' "none"
}

fire4nix_bridge_journal_state() {
    printf '%s commands • last %s • path %s
' "$(fire4nix_bridge_journal_count)" "$(fire4nix_bridge_journal_last_command)" "$(fire4nix_bridge_journal_path)"
}

fire4nix_progress_plan() {
    case "$(fire4nix_progress_stage_label)" in
        phase2-continuation)
            cat <<'EOF'
step_1=close out Marco 1 and prepare the bridge stage
step_2=stabilize the live progress snapshot and shell helpers
step_3=verify the package is clean for the bridge prep stage
step_4=handoff to browser bridge preparation
EOF
            ;;
        phase2-browser-bridge)
            cat <<'EOF'
step_1=connect browser chrome actions to the engine bridge
step_2=keep the current stage summary visible in shell snapshots and the UI
step_3=verify open, back, forward, reload, home, fullscreen, and tab handling
step_4=carry the result into the WPE runtime handoff pass
EOF
            ;;
        marco2-complete)
            cat <<'EOF'
step_1=close the browser bridge loop and freeze the shared journal snapshot
step_2=confirm the chrome and shell status show the same Marco 2 completion line
step_3=preserve Cog fallback, separate profiles, and the native WPE launcher path
step_4=handoff to the WPE runtime pass
EOF
            ;;
        marco3-start)
            cat <<'EOF'
step_1=map the WPE source bundles to Fire4Nix launcher, backend, and platform roles
step_2=wire the native WPE launcher into the runtime bridge
step_3=keep the chrome, shell snapshot, and bridge journal on the same Marco 3 start line
step_4=prepare the phase 3 WPE runtime pass
EOF
            ;;
        phase2-wpe-runtime|phase3-wpe-runtime)
            cat <<'EOF'
step_1=resolve the native WPE launcher at runtime
step_2=preserve Cog fallback for stock ROCKNIX installs
step_3=keep separate profile directories for WPE, Cog, Chromium, and Firefox
step_4=prepare the ROCKNIX validation pass
EOF
            ;;
        phase2-rocknix-validation|phase3-rocknix-validation)
            cat <<'EOF'
step_1=run the full beta smoke test on ROCKNIX
step_2=confirm the launcher, engine selector, and browser chrome stay in sync
step_3=lock the final handoff notes for the next backup
step_4=package the stabilized browser flow
EOF
            ;;
        *)
            cat <<'EOF'
step_1=wire browser controls to the selected engine
step_2=export the stage summary into the shell snapshot and the browser chrome
step_3=record the next action and acceptance line for the handoff
step_4=package the updated browser flow for the next backup
EOF
            ;;
    esac
}

fire4nix_progress_plan_step() {
    local plan="${1:-$(fire4nix_progress_plan)}"
    local step="${2:-1}"
    printf '%s
' "$plan" | sed -n "${step}p" | sed 's/^step_[0-9]\+=//'
}

fire4nix_progress_snapshot() {
    local plan
    plan="$(fire4nix_progress_plan)"
    cat <<EOF
progress_stage=$(fire4nix_progress_stage_label)
progress_stage_name=$(fire4nix_progress_stage_name)
progress_stage_summary=$(fire4nix_progress_stage_summary)
focus=$(fire4nix_progress_focus)
implemented=engine auto-detection, Wayland bootstrap, WPE/Cog fallback, reference pack staging, Marco 1 complete, Marco 2 complete, Marco 3 start, beta snapshots, and live progress snapshots
next=$(fire4nix_progress_next_action)
acceptance=$(fire4nix_progress_acceptance)
bridge_journal_path=$(fire4nix_bridge_journal_path)
bridge_journal_count=$(fire4nix_bridge_journal_count)
bridge_journal_state=$(fire4nix_bridge_journal_state)
plan_step_1=$(fire4nix_progress_plan_step "$plan" 1)
plan_step_2=$(fire4nix_progress_plan_step "$plan" 2)
plan_step_3=$(fire4nix_progress_plan_step "$plan" 3)
plan_step_4=$(fire4nix_progress_plan_step "$plan" 4)
EOF
}

fire4nix_sync_progress_context() {
    export FIRE4NIX_PROGRESS_STAGE="${FIRE4NIX_PROGRESS_STAGE:-marco3-start}"
    export FIRE4NIX_PROGRESS_STAGE_NAME="${FIRE4NIX_PROGRESS_STAGE_NAME:-$(fire4nix_progress_stage_name)}"
    export FIRE4NIX_PROGRESS_FOCUS="${FIRE4NIX_PROGRESS_FOCUS:-$(fire4nix_progress_focus)}"
    export FIRE4NIX_PROGRESS_STAGE_SUMMARY="${FIRE4NIX_PROGRESS_STAGE_SUMMARY:-$(fire4nix_progress_stage_summary)}"
    export FIRE4NIX_PROGRESS_NEXT="${FIRE4NIX_PROGRESS_NEXT:-$(fire4nix_progress_next_action)}"
    export FIRE4NIX_PROGRESS_ACCEPTANCE="${FIRE4NIX_PROGRESS_ACCEPTANCE:-$(fire4nix_progress_acceptance)}"
    export FIRE4NIX_BRIDGE_JOURNAL="${FIRE4NIX_BRIDGE_JOURNAL:-${FIRE4NIX_RUNTIME_DIR:-$(fire4nix_resolve_runtime_dir)}/bridge-journal.log}"
    export FIRE4NIX_BRIDGE_JOURNAL_PATH="${FIRE4NIX_BRIDGE_JOURNAL_PATH:-$(fire4nix_bridge_journal_path)}"
    export FIRE4NIX_BRIDGE_JOURNAL_COUNT="${FIRE4NIX_BRIDGE_JOURNAL_COUNT:-$(fire4nix_bridge_journal_count)}"
    export FIRE4NIX_BRIDGE_JOURNAL_STATE="${FIRE4NIX_BRIDGE_JOURNAL_STATE:-$(fire4nix_bridge_journal_state)}"
}

fire4nix_load_key_value_config() {
    local config_file="${1:-${FIRE4NIX_CONF:-}}"
    [ -n "$config_file" ] || return 0
    [ -f "$config_file" ] || return 0

    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        line="$(fire4nix_trim "$line")"
        case "$line" in
            ""|\#*)
                continue
                ;;
        esac

        case "$line" in
            *=*)
                local key value
                key="${line%%=*}"
                value="${line#*=}"
                key="$(fire4nix_trim "$key")"
                value="$(fire4nix_trim "$value")"
                value="${value#\"}"
                value="${value%\"}"
                value="${value#\'}"
                value="${value%\'}"
                case "${key,,}" in
                    home_url) export FIRE4NIX_HOME_URL="$value" ;;
                    start_page) export FIRE4NIX_START_PAGE="$value" ;;
                    search_url) export FIRE4NIX_SEARCH_URL="$value" ;;
                    browser_mode) export FIRE4NIX_BROWSER_MODE="$value" ;;
                    ui_profile) export FIRE4NIX_UI_PROFILE="$value" ;;
                    theme) export FIRE4NIX_THEME="$value" ;;
                    engine) export FIRE4NIX_ENGINE="$value" ;;
                    browser_binary) export FIRE4NIX_BROWSER_BINARY="$value" ;;
                    session_label) export FIRE4NIX_SESSION_LABEL="$value" ;;
                    startup_hint) export FIRE4NIX_STARTUP_HINT="$value" ;;
                    beta_ready) export FIRE4NIX_BETA_READY="$value" ;;
                    wayland_preferred) export FIRE4NIX_WAYLAND_PREFERRED="$value" ;;
                    runtime_env_preflight) export FIRE4NIX_RUNTIME_ENV_PREFLIGHT="$value" ;;
                    display_width) export FIRE4NIX_DISPLAY_WIDTH="$value" ;;
                    display_height) export FIRE4NIX_DISPLAY_HEIGHT="$value" ;;
                    cog_platform) export FIRE4NIX_COG_PLATFORM="$value" ;;
                    cog_platform_params) export FIRE4NIX_COG_PLATFORM_PARAMS="$value" ;;
                    wpe_display) export FIRE4NIX_WPE_DISPLAY="$value" ;;
                    cog_allow_file_access) export FIRE4NIX_COG_ALLOW_FILE_ACCESS="$value" ;;
                    cog_allow_permissions) export FIRE4NIX_COG_ALLOW_PERMISSIONS="$value" ;;
                    cog_enable_media) export FIRE4NIX_COG_ENABLE_MEDIA="$value" ;;
                    cog_console) export FIRE4NIX_COG_CONSOLE="$value" ;;
                    wpe_platform_binary) export FIRE4NIX_WPE_PLATFORM_BINARY="$value" ;;
                    engine_priority) export FIRE4NIX_ENGINE_PRIORITY="$value" ;;
                esac
                ;;
        esac
    done < "$config_file"
}

fire4nix_default_home_url() {
    printf '%s\n' "${FIRE4NIX_DEFAULT_HOME_URL:-https://lite.duckduckgo.com/lite/}"
}

fire4nix_is_url_like() {
    case "${1:-}" in
        *://*|about:*|data:*|file:*)
            return 0
            ;;
    esac
    return 1
}

fire4nix_normalize_target() {
    local raw
    raw="$(fire4nix_trim "${1:-}")"
    if [ -z "$raw" ]; then
        fire4nix_default_home_url
        return 0
    fi

    if fire4nix_is_url_like "$raw"; then
        printf '%s
' "$raw"
        return 0
    fi

    case "$raw" in
        /*)
            if [ -e "$raw" ]; then
                python3 - "$raw" <<'PY'
import pathlib, sys
print(pathlib.Path(sys.argv[1]).resolve().as_uri())
PY
                return 0
            fi
            ;;
        *[[:space:]]*)
            ;;
        *.*)
            printf 'https://%s
' "$raw"
            return 0
            ;;
        *:*)
            printf 'http://%s
' "$raw"
            return 0
            ;;
    esac

    local encoded
    encoded="$(python3 - "$raw" <<'PY'
import sys, urllib.parse
print(urllib.parse.quote_plus(sys.argv[1]))
PY
)"
    printf '%s
' "${FIRE4NIX_SEARCH_URL:-https://duckduckgo.com/?q=%s}" | sed "s/%s/${encoded}/g"
}

fire4nix_is_legacy_engine_label() {
    case "$(fire4nix_trim "${1:-}" | tr '[:upper:]' '[:lower:]')" in
        ""|auto|"sdl browser"|"wayland browser"|"rocknix beta browser"|"auto detect (wayland preferred)")
            return 0
            ;;
    esac
    return 1
}
fire4nix_wpe_display_name() {
    case "${FIRE4NIX_WPE_DISPLAY:-auto}" in
        wpe-display-wayland|wayland|wl)
            printf '%s\n' "wpe-display-wayland"
            return 0
            ;;
        wpe-display-drm|drm|kms)
            printf '%s\n' "wpe-display-drm"
            return 0
            ;;
        wpe-display-headless|headless)
            printf '%s\n' "wpe-display-headless"
            return 0
            ;;
        auto)
            if [ -n "${WAYLAND_DISPLAY:-}" ] && [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" ]; then
                printf '%s\n' "wpe-display-wayland"
                return 0
            fi
            if [ -e /dev/dri/card0 ] || [ -e /dev/dri/renderD128 ] || [ -d /dev/dri ]; then
                printf '%s\n' "wpe-display-drm"
                return 0
            fi
            printf '%s\n' "wpe-display-headless"
            return 0
            ;;
    esac

    printf '%s\n' "wpe-display-wayland"
}

fire4nix_cog_platform_name() {
    case "${FIRE4NIX_COG_PLATFORM:-auto}" in
        wl|wayland|fdo)
            printf '%s\n' "wl"
            return 0
            ;;
        drm|kms)
            printf '%s\n' "drm"
            return 0
            ;;
        auto)
            if [ -n "${WAYLAND_DISPLAY:-}" ] && [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" ]; then
                printf '%s\n' "wl"
                return 0
            fi
            if [ -e /dev/dri/card0 ] || [ -e /dev/dri/renderD128 ] || [ -d /dev/dri ]; then
                printf '%s\n' "drm"
                return 0
            fi
            printf '%s\n' "wl"
            return 0
            ;;
    esac

    printf '%s\n' "${FIRE4NIX_COG_PLATFORM:-wl}"
}

fire4nix_wpe_runtime_env() {
    local display="$(fire4nix_wpe_display_name)"
    local platform="$(fire4nix_cog_platform_name)"
    local width="${FIRE4NIX_DISPLAY_WIDTH:-640}"
    local height="${FIRE4NIX_DISPLAY_HEIGHT:-480}"

    export WPE_DISPLAY="$display"
    export FIRE4NIX_WPE_PLATFORM_MODE="$display"
    export COG_PLATFORM_NAME="$platform"
    export COG_PLATFORM_PARAMS="${COG_PLATFORM_PARAMS:-${FIRE4NIX_COG_PLATFORM_PARAMS:-}}"
    export COG_PLATFORM_WL_VIEW_FULLSCREEN="${COG_PLATFORM_WL_VIEW_FULLSCREEN:-1}"
    export COG_PLATFORM_WL_VIEW_MAXIMIZE="${COG_PLATFORM_WL_VIEW_MAXIMIZE:-1}"
    export COG_PLATFORM_WL_VIEW_WIDTH="${COG_PLATFORM_WL_VIEW_WIDTH:-$width}"
    export COG_PLATFORM_WL_VIEW_HEIGHT="${COG_PLATFORM_WL_VIEW_HEIGHT:-$height}"
    export COG_PLATFORM_FDO_VIEW_FULLSCREEN="${COG_PLATFORM_FDO_VIEW_FULLSCREEN:-1}"
    export COG_PLATFORM_FDO_VIEW_MAXIMIZE="${COG_PLATFORM_FDO_VIEW_MAXIMIZE:-1}"
    export COG_PLATFORM_FDO_VIEW_WIDTH="${COG_PLATFORM_FDO_VIEW_WIDTH:-$width}"
    export COG_PLATFORM_FDO_VIEW_HEIGHT="${COG_PLATFORM_FDO_VIEW_HEIGHT:-$height}"
}

fire4nix_cog_runtime_env() {
    fire4nix_wpe_runtime_env
}

fire4nix_apply_engine_selection() {
    local engine="$(fire4nix_trim "${1:-auto}")"
    local profile_dir
    profile_dir="$(fire4nix_engine_profile_dir "$engine")"
    mkdir -p "$profile_dir" 2>/dev/null || true
    export FIRE4NIX_ENGINE_SELECTED="$engine"
    export FIRE4NIX_ENGINE_PROFILE_DIR="$profile_dir"
    printf '%s\n' "$profile_dir"
}


fire4nix_wpe_platform_binary() {
    local candidates=(
        "${FIRE4NIX_WPE_PLATFORM_BINARY:-}"
        "${FIRE4NIX_HOME:-$APP_DIR}/bin/wpe-platform-launcher"
        "${FIRE4NIX_HOME:-$APP_DIR}/bin/wpe-platform"
        "${FIRE4NIX_HOME:-$APP_DIR}/build/fire4nix-wpe-platform"
        "${FIRE4NIX_HOME:-$APP_DIR}/build/wpe-platform-launcher"
        "${FIRE4NIX_HOME:-$APP_DIR}/build/wpe-platform"
        "${FIRE4NIX_HOME:-$APP_DIR}/bin/fire4nix-wpe-platform"
    )

    local candidate
    for candidate in "${candidates[@]}"; do
        if [ -n "${candidate:-}" ] && [ -x "$candidate" ]; then
            printf '%s
' "$candidate"
            return 0
        fi
    done

    printf '%s
' ""
}

fire4nix_export_wpe_common_env() {
    export FIRE4NIX_WPE_BACKGROUND_COLOR="${FIRE4NIX_WPE_BACKGROUND_COLOR:-${FIRE4NIX_BG_COLOR:-white}}"
    export FIRE4NIX_WPE_CONTENT_FILTER="${FIRE4NIX_WPE_CONTENT_FILTER:-${FIRE4NIX_CONTENT_FILTER:-}}"
    export FIRE4NIX_WPE_COOKIES_FILE="${FIRE4NIX_WPE_COOKIES_FILE:-${FIRE4NIX_COOKIES_FILE:-}}"
    export FIRE4NIX_WPE_COOKIES_POLICY="${FIRE4NIX_WPE_COOKIES_POLICY:-${FIRE4NIX_COOKIES_POLICY:-}}"
    export FIRE4NIX_WPE_PROXY="${FIRE4NIX_WPE_PROXY:-${FIRE4NIX_PROXY:-}}"
    export FIRE4NIX_WPE_IGNORE_HOSTS="${FIRE4NIX_WPE_IGNORE_HOSTS:-${FIRE4NIX_PROXY_IGNORE_HOSTS:-}}"
    export FIRE4NIX_WPE_IGNORE_TLS_ERRORS="${FIRE4NIX_WPE_IGNORE_TLS_ERRORS:-${FIRE4NIX_IGNORE_TLS_ERRORS:-0}}"
    export FIRE4NIX_WPE_AUTOMATION_MODE="${FIRE4NIX_WPE_AUTOMATION_MODE:-${FIRE4NIX_AUTOMATION_MODE:-0}}"
    export FIRE4NIX_WPE_PRIVATE_MODE="${FIRE4NIX_WPE_PRIVATE_MODE:-${FIRE4NIX_PRIVATE_MODE:-0}}"
    export FIRE4NIX_WPE_ENABLE_ITP="${FIRE4NIX_WPE_ENABLE_ITP:-${FIRE4NIX_ENABLE_ITP:-0}}"
    export FIRE4NIX_WPE_HEADLESS_MODE="${FIRE4NIX_WPE_HEADLESS_MODE:-${FIRE4NIX_HEADLESS_MODE:-0}}"
    export FIRE4NIX_WPE_FULLSCREEN="${FIRE4NIX_WPE_FULLSCREEN:-${FIRE4NIX_FULLSCREEN:-1}}"
    export FIRE4NIX_WPE_MAXIMIZE="${FIRE4NIX_WPE_MAXIMIZE:-${FIRE4NIX_MAXIMIZE:-1}}"
    export FIRE4NIX_WPE_TIME_ZONE="${FIRE4NIX_WPE_TIME_ZONE:-${FIRE4NIX_TIME_ZONE:-}}"
    export FIRE4NIX_WPE_START_PAGE="${FIRE4NIX_WPE_START_PAGE:-${FIRE4NIX_START_PAGE:-${FIRE4NIX_HOME_URL:-}}}"
}

fire4nix_cog_launch_args() {
    local platform="$1"
    local args=(--platform="$platform")

    case "${COG_PLATFORM_PARAMS:-${FIRE4NIX_COG_PLATFORM_PARAMS:-}}" in
        "")
            ;;
        *)
            args+=(--platform-params="${COG_PLATFORM_PARAMS:-${FIRE4NIX_COG_PLATFORM_PARAMS:-}}")
            ;;
    esac

    case "${FIRE4NIX_COG_CONFIG_FILE:-}" in
        "")
            ;;
        *)
            args+=(--config="${FIRE4NIX_COG_CONFIG_FILE}")
            ;;
    esac

    case "${FIRE4NIX_COG_WEB_EXTENSIONS_DIR:-}" in
        "")
            ;;
        *)
            args+=(--web-extensions-dir="${FIRE4NIX_COG_WEB_EXTENSIONS_DIR}")
            ;;
    esac

    case "${FIRE4NIX_COG_BACKGROUND_COLOR:-${FIRE4NIX_BG_COLOR:-}}" in
        "")
            ;;
        *)
            args+=(--bg-color="${FIRE4NIX_COG_BACKGROUND_COLOR:-${FIRE4NIX_BG_COLOR:-}}")
            ;;
    esac

    case "${FIRE4NIX_COG_CONTENT_FILTER:-${FIRE4NIX_CONTENT_FILTER:-}}" in
        "")
            ;;
        *)
            args+=(--content-filter="${FIRE4NIX_COG_CONTENT_FILTER:-${FIRE4NIX_CONTENT_FILTER:-}}")
            ;;
    esac

    case "${FIRE4NIX_COG_IGNORE_TLS_ERRORS:-${FIRE4NIX_IGNORE_TLS_ERRORS:-0}}" in
        1|true|yes|on)
            args+=(--ignore-tls-errors)
            ;;
    esac

    case "${FIRE4NIX_COG_AUTOMATION:-${FIRE4NIX_AUTOMATION_MODE:-0}}" in
        1|true|yes|on)
            args+=(--automation)
            ;;
    esac

    case "${FIRE4NIX_COG_PROXY:-${FIRE4NIX_PROXY:-}}" in
        "")
            ;;
        *)
            args+=(--proxy="${FIRE4NIX_COG_PROXY:-${FIRE4NIX_PROXY:-}}")
            ;;
    esac

    case "${FIRE4NIX_COG_IGNORE_HOSTS:-${FIRE4NIX_PROXY_IGNORE_HOSTS:-}}" in
        "")
            ;;
        *)
            local host
            for host in $(printf '%s' "${FIRE4NIX_COG_IGNORE_HOSTS:-${FIRE4NIX_PROXY_IGNORE_HOSTS:-}}" | tr ',;' '  '); do
                host="$(fire4nix_trim "$host")"
                [ -n "$host" ] && args+=(--ignore-host="$host")
            done
            ;;
    esac

    case "${FIRE4NIX_COG_ALLOW_PERMISSIONS:-1}" in
        1|true|yes|on)
            args+=(--set-permissions=all)
            ;;
    esac

    case "${FIRE4NIX_COG_ALLOW_FILE_ACCESS:-1}" in
        1|true|yes|on)
            args+=(--allow-file-access-from-file-urls=true --allow-universal-access-from-file-urls=true)
            ;;
    esac

    case "${FIRE4NIX_COG_ENABLE_MEDIA:-1}" in
        1|true|yes|on)
            args+=(--enable-media=true --enable-media-capabilities=true --enable-media-stream=true --enable-mediasource=true)
            ;;
    esac

    case "${FIRE4NIX_COG_CONSOLE:-1}" in
        1|true|yes|on)
            args+=(--enable-write-console-messages-to-stdout=true)
            ;;
    esac

    printf '%s
' "${args[@]}"
}

fire4nix_prepare_browser_binary() {
    local candidate
    for candidate in         "${FIRE4NIX_HOME:-$APP_DIR}/bin/browser.arm64"         "${FIRE4NIX_HOME:-$APP_DIR}/bin/fire4nix-wpe-platform"; do
        if [ -f "$candidate" ] && [ ! -x "$candidate" ]; then
            chmod +x "$candidate" 2>/dev/null || true
        fi
    done
}

fire4nix_detect_engine() {
    fire4nix_prepare_browser_binary

    local candidate priority_list
    if [ -n "${FIRE4NIX_ENGINE_PRIORITY:-}" ]; then
        priority_list="$(printf '%s' "$FIRE4NIX_ENGINE_PRIORITY" | tr ',;' '  ')"
        for candidate in $priority_list; do
            candidate="$(fire4nix_trim "$candidate")"
            case "${candidate,,}" in
                wpe|wpe-launcher|wpe-browser|wpe-platform|wpe-platform-launcher|wpe-native|wpe-native-launcher|mini-browser|wpe-webkit-launcher|wpewebkit-launcher)
                    if [ -n "$(fire4nix_wpe_platform_binary)" ]; then
                        printf '%s
' "wpe-platform"
                        return 0
                    fi
                    if command -v cog >/dev/null 2>&1; then
                        printf '%s
' "cog"
                        return 0
                    fi
                    ;;
                cog)
                    if command -v cog >/dev/null 2>&1; then
                        printf '%s
' "cog"
                        return 0
                    fi
                    ;;
                browser|fire4nix)
                    candidate="browser.arm64"
                    ;;
            esac
            case "${candidate,,}" in
                chromium|chromium-browser|firefox|firefox-esr|surf)
                    if command -v "$candidate" >/dev/null 2>&1; then
                        printf '%s
' "${candidate,,}"
                        return 0
                    fi
                    ;;
                browser.arm64)
                    if [ -x "${FIRE4NIX_BINARY:-}" ] && [ "${FIRE4NIX_BINARY##*/}" = "browser.arm64" ]; then
                        printf '%s
' "browser.arm64"
                        return 0
                    fi
                    if [ -x "${FIRE4NIX_HOME:-$APP_DIR}/bin/browser.arm64" ]; then
                        printf '%s
' "browser.arm64"
                        return 0
                    fi
                    ;;
            esac
        done
    fi

    if [ -n "$(fire4nix_wpe_platform_binary)" ]; then
        printf '%s
' "wpe-platform"
        return 0
    fi

    for candidate in cog chromium chromium-browser firefox-esr firefox surf; do
        if command -v "$candidate" >/dev/null 2>&1; then
            printf '%s
' "$candidate"
            return 0
        fi
    done

    if [ -n "${FIRE4NIX_BINARY:-}" ] && [ -x "${FIRE4NIX_BINARY:-}" ]; then
        case "${FIRE4NIX_BINARY##*/}" in
            browser.arm64|browser|fire4nix)
                printf '%s
' "${FIRE4NIX_BINARY##*/}"
                return 0
                ;;
        esac
    fi

    if [ -x "${FIRE4NIX_HOME:-$APP_DIR}/bin/browser.arm64" ]; then
        printf '%s
' "browser.arm64"
        return 0
    fi

    printf '%s
' "auto"
}

fire4nix_resolve_engine() {

    local requested
    requested="$(fire4nix_trim "${1:-${FIRE4NIX_ENGINE:-auto}}")"
    if fire4nix_is_legacy_engine_label "$requested"; then
        fire4nix_detect_engine
        return 0
    fi

    case "${requested,,}" in
        cog|wpe-platform|wpe-native|wpe-launcher|wpe-browser|wpe-platform-launcher|mini-browser|wpe-webkit-launcher|wpewebkit-launcher|chromium|chromium-browser|firefox|firefox-esr|surf|browser.arm64|browser|fire4nix)
            case "${requested,,}" in
                wpe-launcher|wpe-browser|wpe-platform-launcher|mini-browser|wpe-webkit-launcher|wpewebkit-launcher|wpe-native|wpe)
                    printf '%s
' "wpe-platform"
                    ;;
                *)
                    printf '%s
' "$requested"
                    ;;
            esac
            return 0
            ;;
        "")
            fire4nix_detect_engine
            return 0
            ;;
    esac

    if command -v "$requested" >/dev/null 2>&1; then
        printf '%s
' "$requested"
        return 0
    fi

    fire4nix_detect_engine
}

fire4nix_engine_binary() {
    local engine
    engine="$(fire4nix_resolve_engine "${1:-}")"
    case "${engine,,}" in
        browser.arm64|browser|fire4nix)
            for candidate in "${FIRE4NIX_BINARY:-}" "${FIRE4NIX_HOME:-$APP_DIR}/bin/browser.arm64" "${FIRE4NIX_HOME:-$APP_DIR}/bin/browser" "${FIRE4NIX_HOME:-$APP_DIR}/build/browser.arm64" "${FIRE4NIX_HOME:-$APP_DIR}/build/browser" "${FIRE4NIX_HOME:-$APP_DIR}/browser.arm64" "${FIRE4NIX_HOME:-$APP_DIR}/browser"; do
                if [ -n "$candidate" ] && [ -x "$candidate" ]; then
                    printf '%s
' "$candidate"
                    return 0
                fi
            done
            ;;
        wpe-platform|wpe-native)
            local native
            native="$(fire4nix_wpe_platform_binary)"
            if [ -n "$native" ]; then
                printf '%s
' "$native"
                return 0
            fi
            if command -v cog >/dev/null 2>&1; then
                command -v cog
                return 0
            fi
            ;;
        *)
            if command -v "$engine" >/dev/null 2>&1; then
                command -v "$engine"
                return 0
            fi
            ;;
    esac

    printf '%s
' ""
}

fire4nix_launch_wpe_platform() {
    local url="$1"
    shift || true

    local engine_name="wpe-platform"
    local profile_dir native_binary cog_platform wpe_mode
    profile_dir="$(fire4nix_apply_engine_selection "$engine_name")"
    native_binary="$(fire4nix_wpe_platform_binary)"
    wpe_mode="$(fire4nix_wpe_display_name)"

    export FIRE4NIX_ENGINE_SELECTED="$engine_name"
    export FIRE4NIX_ENGINE_PROFILE_DIR="$profile_dir"
    export FIRE4NIX_WPE_PLATFORM_MODE="$wpe_mode"

    if [ -n "$native_binary" ]; then
        fire4nix_wpe_runtime_env
        exec "$native_binary" "$url" "$@"
    fi

    cog_platform="$(fire4nix_cog_platform_name)"
    fire4nix_cog_runtime_env "$cog_platform"
    local -a cog_args
    mapfile -t cog_args < <(fire4nix_cog_launch_args "$cog_platform")
    exec cog "${cog_args[@]}" "$url" "$@"
}

fire4nix_launch_engine() {
    fire4nix_prepare_browser_binary
    local requested_engine="${1:-auto}"
    local url="${2:-${FIRE4NIX_START_PAGE:-${FIRE4NIX_HOME_URL:-}}}"
    shift 2 2>/dev/null || true

    local engine normalized_url profile_dir
    engine="$(fire4nix_resolve_engine "$requested_engine")"
    normalized_url="$(fire4nix_normalize_target "$url")"
    profile_dir="$(fire4nix_apply_engine_selection "$engine")"

    export FIRE4NIX_ENGINE_SELECTED="$engine"
    export FIRE4NIX_ENGINE_PROFILE_DIR="$profile_dir"

    case "${engine,,}" in
        wpe-platform|wpe-native|wpe-platform-launcher)
            fire4nix_launch_wpe_platform "$normalized_url" "$@"
            ;;
        cog|wpe|wpe-launcher|wpe-browser|wpe-platform-launcher|mini-browser|wpe-webkit-launcher|wpewebkit-launcher)
            local cog_platform
            local -a cog_args
            cog_platform="$(fire4nix_cog_platform_name)"
            fire4nix_cog_runtime_env "$cog_platform"
            mapfile -t cog_args < <(fire4nix_cog_launch_args "$cog_platform")
            exec cog "${cog_args[@]}" "$normalized_url" "$@"
            ;;
        chromium|chromium-browser)
            mkdir -p "$profile_dir" "$profile_dir/Cache" 2>/dev/null || true
            local extra_args=(
                --ozone-platform=wayland
                --enable-features=UseOzonePlatform
                --start-fullscreen
                --no-first-run
                --disable-session-crashed-bubble
                --disable-infobars
                --user-data-dir="$profile_dir"
                --disk-cache-dir="$profile_dir/Cache"
                --app="$normalized_url"
            )
            if [ "$(id -u 2>/dev/null || echo 0)" -eq 0 ]; then
                extra_args+=(--no-sandbox --disable-gpu-sandbox --disable-dev-shm-usage)
            fi
            exec "$engine" "${extra_args[@]}" "$@"
            ;;
        firefox|firefox-esr)
            mkdir -p "$profile_dir" 2>/dev/null || true
            exec "$engine" \
                --kiosk \
                --new-window \
                --no-remote \
                -profile "$profile_dir" \
                "$normalized_url" \
                "$@"
            ;;
        surf)
            exec surf -F "$normalized_url" "$@"
            ;;
        browser.arm64|browser|fire4nix)
            local binary
            binary="$(fire4nix_engine_binary "$engine")"
            if [ -n "$binary" ]; then
                exec "$binary" "$normalized_url" "$@"
            fi
            ;;
        *)
            if command -v "$engine" >/dev/null 2>&1; then
                exec "$engine" "$normalized_url" "$@"
            fi
            ;;
    esac

    return 1
}

fire4nix_reference_features() {

    local reference_root="${1:-}"
    if [ -z "$reference_root" ]; then
        reference_root="$(fire4nix_resolve_reference_root)"
    fi

    [ -d "$reference_root" ] || {
        printf '%s
' ""
        return 0
    }

    local features=()
    [ -f "$reference_root/etc/dbus-1/session.conf" ] && features+=("dbus-session")
    [ -f "$reference_root/etc/dbus-1/system.conf" ] && features+=("dbus-system")
    [ -d "$reference_root/etc/dbus-1/system.d" ] && features+=("dbus-policies")
    [ -f "$reference_root/etc/dbus-1/system.d/nm-priv-helper.conf" ] && features+=("nm-priv-helper")
    [ -f "$reference_root/etc/dbus-1/system.d/nm-dispatcher.conf" ] && features+=("nm-dispatcher")
    [ -f "$reference_root/etc/dbus-1/system.d/org.freedesktop.NetworkManager.conf" ] && features+=("networkmanager")
    [ -f "$reference_root/etc/dbus-1/system.d/avahi-dbus.conf" ] && features+=("avahi")
    [ -f "$reference_root/etc/fonts/fonts.conf" ] && features+=("fonts")
    [ -f "$reference_root/etc/ssl/certs/cacert.pem.system" ] && features+=("ssl")
    [ -f "$reference_root/etc/systemd/system.conf" ] && features+=("systemd")
    [ -f "$reference_root/etc/systemd/logind.conf" ] && features+=("logind")
    [ -f "$reference_root/etc/systemd/journald.conf" ] && features+=("journald")
    [ -f "$reference_root/etc/systemd/oomd.conf" ] && features+=("oomd")
    [ -f "$reference_root/etc/systemd/resolved.conf" ] && features+=("resolved")
    [ -f "$reference_root/etc/systemd/sleep.conf" ] && features+=("sleep")
    [ -f "$reference_root/etc/systemd/timesyncd.conf" ] && features+=("timesyncd")
    [ -f "$reference_root/etc/systemd/pstore.conf" ] && features+=("pstore")
    [ -f "$reference_root/etc/systemd/iocost.conf" ] && features+=("iocost")
    [ -f "$reference_root/etc/systemd/user.conf" ] && features+=("systemd-user")
    [ -f "$reference_root/etc/udev/udev.conf" ] && features+=("udev")
    [ -f "$reference_root/etc/gtk-3.0/im-multipress.conf" ] && features+=("gtk-im")
    [ -f "$reference_root/etc/xdg/autostart/at-spi-dbus-bus.desktop" ] && features+=("at-spi")
    [ -f "$reference_root/etc/foot.ini" ] && features+=("foot")
    [ -f "$reference_root/swayimgrc" ] && features+=("swayimg")
    [ -f "$reference_root/MangoHud.aarch64.json" ] && features+=("mangohud")
    [ -f "$reference_root/etc/profile.d/001-functions" ] && features+=("profile-001")
    [ -f "$reference_root/etc/profile.d/002-autostart" ] && features+=("profile-002")
    [ -f "$reference_root/etc/profile.d/010-wlr-randr" ] && features+=("profile-010")
    [ -f "$reference_root/etc/profile.d/045-xorg-server.conf" ] && features+=("profile-045")
    [ -f "$reference_root/etc/profile.d/050-sway.conf" ] && features+=("profile-050")
    [ -f "$reference_root/etc/profile.d/090-systemd.conf" ] && features+=("profile-090")
    [ -f "$reference_root/etc/profile.d/095-zerotier.conf" ] && features+=("profile-095")
    [ -f "$reference_root/etc/profile.d/098-box64.conf" ] && features+=("profile-098")
    [ -f "$reference_root/etc/profile.d/101-gpu-functions" ] && features+=("profile-101")

    printf '%s
' "${features[*]}"
}

fire4nix_reference_summary() {
    local reference_root="${1:-}"
    if [ -z "$reference_root" ]; then
        reference_root="$(fire4nix_resolve_reference_root)"
    fi

    [ -d "$reference_root" ] || {
        printf '%s\n' "reference pack unavailable"
        return 0
    }

    local groups=()
    [ -f "$reference_root/etc/dbus-1/session.conf" ] && groups+=("dbus-session")
    [ -f "$reference_root/etc/dbus-1/system.conf" ] && groups+=("dbus-system")
    [ -d "$reference_root/etc/dbus-1/system.d" ] && groups+=("network-manager")
    [ -f "$reference_root/etc/fonts/fonts.conf" ] && groups+=("fonts")
    [ -f "$reference_root/etc/ssl/certs/cacert.pem.system" ] && groups+=("ssl")
    [ -f "$reference_root/etc/systemd/system.conf" ] && groups+=("systemd")
    [ -f "$reference_root/etc/systemd/logind.conf" ] && groups+=("logind")
    [ -f "$reference_root/etc/systemd/journald.conf" ] && groups+=("journald")
    [ -f "$reference_root/etc/systemd/iocost.conf" ] && groups+=("iocost")
    [ -f "$reference_root/etc/udev/udev.conf" ] && groups+=("udev")
    [ -f "$reference_root/etc/gtk-3.0/im-multipress.conf" ] && groups+=("gtk-im")
    [ -f "$reference_root/etc/xdg/autostart/at-spi-dbus-bus.desktop" ] && groups+=("at-spi")
    [ -f "$reference_root/etc/foot.ini" ] && groups+=("foot")
    [ -f "$reference_root/swayimgrc" ] && groups+=("swayimg")
    [ -f "$reference_root/MangoHud.aarch64.json" ] && groups+=("mangohud")
    [ -f "$reference_root/etc/profile.d/050-sway.conf" ] && groups+=("wayland")
    [ -f "$reference_root/etc/profile.d/090-systemd.conf" ] && groups+=("systemd-profile")
    [ -f "$reference_root/etc/profile.d/098-box64.conf" ] && groups+=("box64")
    [ -f "$reference_root/etc/profile.d/101-gpu-functions" ] && groups+=("gpu")

    local summary="reference root=${reference_root}"
    if [ "${#groups[@]}" -gt 0 ]; then
        summary="${summary} • ${groups[*]}"
    fi
    printf '%s\n' "$summary"
}

fire4nix_reference_manifest_path() {
    local config_dir="${1:-${FIRE4NIX_CONFIG_DIR:-$(fire4nix_resolve_config_root)}}"
    printf '%s\n' "$config_dir/reference-manifest.txt"
}

fire4nix_reference_status() {
    local reference_root="${1:-}"
    if [ -z "$reference_root" ]; then
        reference_root="$(fire4nix_resolve_reference_root)"
    fi

    local summary
    local features
    local manifest
    local env_file
    summary="$(fire4nix_reference_summary "$reference_root")"
    features="$(fire4nix_reference_features "$reference_root")"
    manifest="$(fire4nix_reference_manifest_path "$reference_root")"
    env_file="$(fire4nix_reference_env_path "${FIRE4NIX_CONFIG_DIR:-$(fire4nix_resolve_config_root)}")"

    printf '%s\n' "reference_root=${reference_root} • reference_summary=${summary} • reference_features=${features} • reference_manifest=${manifest:-none} • reference_env=${env_file}"
}

fire4nix_apply_reference_environment() {
    local reference_root="${1:-}"
    if [ -z "$reference_root" ]; then
        reference_root="$(fire4nix_resolve_reference_root)"
    fi

    export FIRE4NIX_REFERENCE_ROOT="$reference_root"
    export FIRE4NIX_REFERENCE_SUMMARY="$(fire4nix_reference_summary "$reference_root")"
    export FIRE4NIX_REFERENCE_FEATURES="$(fire4nix_reference_features "$reference_root")"
    export FIRE4NIX_REFERENCE_STATUS="$(fire4nix_reference_status "$reference_root")"

    if [ -f "$reference_root/etc/fonts/fonts.conf" ] && [ -z "${FONTCONFIG_FILE:-}" ]; then
        export FONTCONFIG_FILE="$reference_root/etc/fonts/fonts.conf"
    fi
    if [ -f "$reference_root/etc/ssl/certs/cacert.pem.system" ] && [ -z "${SSL_CERT_FILE:-}" ]; then
        export SSL_CERT_FILE="$reference_root/etc/ssl/certs/cacert.pem.system"
    fi
    if [ -f "$reference_root/etc/profile.d/050-sway.conf" ] && [ -z "${XKB_CONFIG_ROOT:-}" ]; then
        export XKB_CONFIG_ROOT="/usr/share/X11/xkb"
    fi
    if [ -f "$reference_root/etc/profile.d/090-systemd.conf" ] && [ -z "${SYSTEMD_COLORS:-}" ]; then
        export SYSTEMD_COLORS=0
    fi
    if [ -f "$reference_root/etc/profile.d/098-box64.conf" ]; then
        export BOX64_PREFER_EMULATED="${BOX64_PREFER_EMULATED:-1}"
        export BOX64_LD_LIBRARY_PATH="${BOX64_LD_LIBRARY_PATH:-/usr/share/box64/lib}"
        export BOX64_BASH="${BOX64_BASH:-/usr/bin/bash-x64}"
        export BOX64_LOG="${BOX64_LOG:-0}"
    fi
    if [ -d "$reference_root/devkit/python313" ] && [ -z "${FIRE4NIX_PYTHON313_ROOT:-}" ]; then
        export FIRE4NIX_PYTHON313_ROOT="$reference_root/devkit/python313"
    fi
    if [ -d "$reference_root/devkit/armhf/pkgconfig" ]; then
        fire4nix_prepend_path_unique PKG_CONFIG_PATH "$reference_root/devkit/armhf/pkgconfig"
    fi
    if [ -d "$reference_root/runtime-libs/armhf/lib32-snapshot" ]; then
        fire4nix_prepend_path_unique LD_LIBRARY_PATH "$reference_root/runtime-libs/armhf/lib32-snapshot"
        fire4nix_prepend_path_unique LIBRARY_PATH "$reference_root/runtime-libs/armhf/lib32-snapshot"
    fi
    if [ -d "$reference_root/etc/tmpfiles.d" ] && [ -z "${FIRE4NIX_TMPFILES_DIR:-}" ]; then
        export FIRE4NIX_TMPFILES_DIR="$reference_root/etc/tmpfiles.d"
    fi
    if [ -f "$reference_root/etc/xdg/autostart/at-spi-dbus-bus.desktop" ]; then
        export GTK_ENABLE_ACCESSIBILITY="${GTK_ENABLE_ACCESSIBILITY:-1}"
        if [ -n "${GTK_MODULES:-}" ]; then
            case ":$GTK_MODULES:" in
                *:atk-bridge:*) : ;;
                *) export GTK_MODULES="${GTK_MODULES}:atk-bridge" ;;
            esac
        else
            export GTK_MODULES="atk-bridge"
        fi
        export QT_ACCESSIBILITY="${QT_ACCESSIBILITY:-1}"
        export NO_AT_BRIDGE="${NO_AT_BRIDGE:-0}"
    fi
    if [ -f "$reference_root/etc/gtk-3.0/im-multipress.conf" ] && [ -z "${GTK_IM_MODULE:-}" ]; then
        export GTK_IM_MODULE="simple"
    fi
    if [ -f "$reference_root/etc/profile.d/050-sway.conf" ] && [ -z "${XDG_CURRENT_DESKTOP:-}" ]; then
        export XDG_CURRENT_DESKTOP="Sway"
    fi
    if [ -n "${FIRE4NIX_REFERENCE_MANIFEST:-}" ]; then
        export FIRE4NIX_REFERENCE_MANIFEST
    fi
    if [ -n "${FIRE4NIX_REFERENCE_ENV:-}" ]; then
        export FIRE4NIX_REFERENCE_ENV
    fi
    export FIRE4NIX_REFERENCE_READY=1

    if [ -z "${XDG_CONFIG_DIRS:-}" ]; then
        export XDG_CONFIG_DIRS="/etc/xdg"
    fi
    if [ -z "${XDG_DATA_DIRS:-}" ]; then
        export XDG_DATA_DIRS="/usr/local/share:/usr/share"
    fi
}


fire4nix_reference_env_path() {
    local config_dir="${1:-${FIRE4NIX_CONFIG_DIR:-$(fire4nix_resolve_config_root)}}"
    printf '%s\n' "$config_dir/reference.env"
}

fire4nix_write_reference_manifest() {
    local reference_root="${1:-}"
    local config_dir="${2:-}"
    [ -n "$reference_root" ] || return 0
    [ -d "$reference_root" ] || return 0
    [ -n "$config_dir" ] || return 0

    local manifest="$config_dir/reference-manifest.txt"
    local env_file
    local summary
    local features
    local status
    env_file="$(fire4nix_reference_env_path "$config_dir")"
    summary="$(fire4nix_reference_summary "$reference_root")"
    features="$(fire4nix_reference_features "$reference_root")"
    status="$(fire4nix_reference_status "$reference_root")"
    {
        printf '%s\n' "# Fire4Nix reference manifest"
        printf '%s\n' "reference_root=$reference_root"
        printf '%s\n' "reference_summary=$summary"
        printf '%s\n' "reference_features=$features"
        printf '%s\n' "reference_status=$status"
        printf '%s\n' "reference_files=$(find "$reference_root" -type f 2>/dev/null | wc -l | tr -d ' ')"
        printf '%s\n' "reference_directories=$(find "$reference_root" -type d 2>/dev/null | wc -l | tr -d ' ')"
        printf '%s\n' ''
        printf '%s\n' '[Files]'
        find "$reference_root" -type f 2>/dev/null | sed "s#^$reference_root/##" | sort
    } > "$manifest" 2>/dev/null || true

    {
        printf '%s\n' "# Fire4Nix staged reference environment"
        printf 'export FIRE4NIX_REFERENCE_ROOT=%q\n' "$reference_root"
        printf 'export FIRE4NIX_REFERENCE_SUMMARY=%q\n' "$summary"
        printf 'export FIRE4NIX_REFERENCE_FEATURES=%q\n' "$features"
        printf 'export FIRE4NIX_REFERENCE_STATUS=%q\n' "$status"
        printf 'export FIRE4NIX_REFERENCE_MANIFEST=%q\n' "$manifest"
        printf 'export FIRE4NIX_REFERENCE_ENV=%q\n' "$env_file"
        if [ -f "$reference_root/etc/fonts/fonts.conf" ]; then
            printf 'export FONTCONFIG_FILE=%q\n' "${FONTCONFIG_FILE:-$reference_root/etc/fonts/fonts.conf}"
        fi
        if [ -f "$reference_root/etc/ssl/certs/cacert.pem.system" ]; then
            printf 'export SSL_CERT_FILE=%q\n' "${SSL_CERT_FILE:-$reference_root/etc/ssl/certs/cacert.pem.system}"
        fi
        if [ -f "$reference_root/etc/gtk-3.0/im-multipress.conf" ]; then
            printf 'export GTK_IM_MODULE=%q\n' "${GTK_IM_MODULE:-simple}"
        fi
        if [ -d "$reference_root/devkit/python313" ]; then
            printf 'export FIRE4NIX_PYTHON313_ROOT=%q\n' "${FIRE4NIX_PYTHON313_ROOT:-$reference_root/devkit/python313}"
        fi
        if [ -d "$reference_root/devkit/armhf/pkgconfig" ]; then
            printf 'export PKG_CONFIG_PATH=%q\n' "${PKG_CONFIG_PATH:-$reference_root/devkit/armhf/pkgconfig}"
        fi
        if [ -d "$reference_root/runtime-libs/armhf/lib32-snapshot" ]; then
            printf 'export LD_LIBRARY_PATH=%q\n' "${LD_LIBRARY_PATH:-$reference_root/runtime-libs/armhf/lib32-snapshot}"
            printf 'export LIBRARY_PATH=%q\n' "${LIBRARY_PATH:-$reference_root/runtime-libs/armhf/lib32-snapshot}"
        fi
        if [ -d "$reference_root/etc/tmpfiles.d" ]; then
            printf 'export FIRE4NIX_TMPFILES_DIR=%q\n' "${FIRE4NIX_TMPFILES_DIR:-$reference_root/etc/tmpfiles.d}"
        fi
        if [ -f "$reference_root/etc/xdg/autostart/at-spi-dbus-bus.desktop" ]; then
            printf 'export GTK_ENABLE_ACCESSIBILITY=%q\n' "${GTK_ENABLE_ACCESSIBILITY:-1}"
            if [ -n "${GTK_MODULES:-}" ]; then
                case ":$GTK_MODULES:" in
                    *:atk-bridge:*) printf 'export GTK_MODULES=%q\n' "$GTK_MODULES" ;;
                    *) printf 'export GTK_MODULES=%q\n' "$GTK_MODULES:atk-bridge" ;;
                esac
            else
                printf 'export GTK_MODULES=%q\n' "atk-bridge"
            fi
            printf 'export QT_ACCESSIBILITY=%q\n' "${QT_ACCESSIBILITY:-1}"
            printf 'export NO_AT_BRIDGE=%q\n' "${NO_AT_BRIDGE:-0}"
        fi
        if [ -f "$reference_root/etc/profile.d/050-sway.conf" ]; then
            printf 'export XDG_CURRENT_DESKTOP=%q\n' "${XDG_CURRENT_DESKTOP:-Sway}"
        fi
        if [ -f "$reference_root/etc/systemd/system.conf" ]; then
            printf 'export SYSTEMD_COLORS=%q\n' "${SYSTEMD_COLORS:-0}"
        fi
        if [ -f "$reference_root/etc/profile.d/098-box64.conf" ]; then
            printf 'export BOX64_PREFER_EMULATED=%q\n' "${BOX64_PREFER_EMULATED:-1}"
            printf 'export BOX64_LD_LIBRARY_PATH=%q\n' "${BOX64_LD_LIBRARY_PATH:-/usr/share/box64/lib}"
            printf 'export BOX64_BASH=%q\n' "${BOX64_BASH:-/usr/bin/bash-x64}"
            printf 'export BOX64_LOG=%q\n' "${BOX64_LOG:-0}"
        fi
        printf '%s\n' "export XDG_CONFIG_DIRS=${XDG_CONFIG_DIRS:-/etc/xdg}"
        printf '%s\n' "export XDG_DATA_DIRS=${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    } > "$env_file" 2>/dev/null || true
    chmod 600 "$env_file" 2>/dev/null || true
    export FIRE4NIX_REFERENCE_MANIFEST="$manifest"
    export FIRE4NIX_REFERENCE_ENV="$env_file"
}

fire4nix_stage_reference_pack() {
    local app_dir="${1:-$(fire4nix_resolve_app_dir)}"
    local config_dir="${2:-${FIRE4NIX_CONFIG_DIR:-$(fire4nix_resolve_config_root "$app_dir")}}"
    local src="$app_dir/rocknix_reference"
    local dst="$config_dir/reference"

    [ -d "$src" ] || return 0
    mkdir -p "$dst" 2>/dev/null || return 0
    cp -a "$src"/. "$dst"/ 2>/dev/null || return 0
    export FIRE4NIX_REFERENCE_ROOT="$dst"
    fire4nix_write_reference_manifest "$dst" "$config_dir"
    if [ -f "${FIRE4NIX_REFERENCE_ENV:-}" ]; then
        # shellcheck disable=SC1090
        . "$FIRE4NIX_REFERENCE_ENV" 2>/dev/null || true
    fi
}

fire4nix_bootstrap_environment() {
    local app_dir="${1:-$(fire4nix_resolve_app_dir)}"

    export FIRE4NIX_HOME="${FIRE4NIX_HOME:-$app_dir}"
    export FIRE4NIX_CONFIG_DIR="${FIRE4NIX_CONFIG_DIR:-$(fire4nix_resolve_config_root "$app_dir")}"
    export FIRE4NIX_CONF="${FIRE4NIX_CONF:-$FIRE4NIX_CONFIG_DIR/fire4nix.conf}"
    export FIRE4NIX_CACHE_DIR="${FIRE4NIX_CACHE_DIR:-$FIRE4NIX_CONFIG_DIR/cache}"
    export FIRE4NIX_LOG_DIR="${FIRE4NIX_LOG_DIR:-$FIRE4NIX_CONFIG_DIR/logs}"
    export FIRE4NIX_RUNTIME_DIR="${FIRE4NIX_RUNTIME_DIR:-$(fire4nix_resolve_runtime_dir "$app_dir")}"
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$FIRE4NIX_RUNTIME_DIR}"
    export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
    export MOZ_ENABLE_WAYLAND="${MOZ_ENABLE_WAYLAND:-1}"
    export GDK_BACKEND="${GDK_BACKEND:-wayland}"
    export SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-wayland}"
    export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland}"
    export FIRE4NIX_COG_PLATFORM="${FIRE4NIX_COG_PLATFORM:-auto}"
    export FIRE4NIX_COG_PLATFORM_PARAMS="${FIRE4NIX_COG_PLATFORM_PARAMS:-}"
    export FIRE4NIX_WPE_DISPLAY="${FIRE4NIX_WPE_DISPLAY:-auto}"
    export FIRE4NIX_COG_ALLOW_FILE_ACCESS="${FIRE4NIX_COG_ALLOW_FILE_ACCESS:-1}"
    export FIRE4NIX_COG_ALLOW_PERMISSIONS="${FIRE4NIX_COG_ALLOW_PERMISSIONS:-1}"
    export FIRE4NIX_COG_ENABLE_MEDIA="${FIRE4NIX_COG_ENABLE_MEDIA:-1}"
    export FIRE4NIX_COG_CONSOLE="${FIRE4NIX_COG_CONSOLE:-1}"
    export FIRE4NIX_PROGRESS_STAGE="${FIRE4NIX_PROGRESS_STAGE:-marco3-start}"
    export FIRE4NIX_BRIDGE_JOURNAL="${FIRE4NIX_BRIDGE_JOURNAL:-$FIRE4NIX_RUNTIME_DIR/bridge-journal.log}"
    export FIRE4NIX_PROGRESS_NEXT="${FIRE4NIX_PROGRESS_NEXT:-$(fire4nix_progress_next_action)}"
    export FIRE4NIX_PROGRESS_ACCEPTANCE="${FIRE4NIX_PROGRESS_ACCEPTANCE:-$(fire4nix_progress_acceptance)}"

    fire4nix_prepare_directories "$FIRE4NIX_CONFIG_DIR" "$FIRE4NIX_RUNTIME_DIR"
    if [ -f "$FIRE4NIX_CONF" ]; then
        fire4nix_load_key_value_config "$FIRE4NIX_CONF"
    fi
    fire4nix_stage_reference_pack "$app_dir" "$FIRE4NIX_CONFIG_DIR"
    if [ -f "${FIRE4NIX_REFERENCE_ENV:-}" ]; then
        # shellcheck disable=SC1090
        . "$FIRE4NIX_REFERENCE_ENV" 2>/dev/null || true
    fi
    fire4nix_apply_reference_environment "$(fire4nix_resolve_reference_root "$app_dir")"
    fire4nix_sync_progress_context
}
fire4nix_log_reference_summary() {
    local reference_root="${1:-${FIRE4NIX_REFERENCE_ROOT:-}}"
    if [ -n "$reference_root" ] && [ -d "$reference_root" ]; then
        printf '[Fire4Nix] reference_root=%s\n' "$reference_root"
        printf '[Fire4Nix] reference_summary=%s\n' "${FIRE4NIX_REFERENCE_SUMMARY:-$(fire4nix_reference_summary "$reference_root")}"
        printf '[Fire4Nix] reference_features=%s\n' "${FIRE4NIX_REFERENCE_FEATURES:-$(fire4nix_reference_features "$reference_root")}"
        if [ -n "${FIRE4NIX_REFERENCE_ENV:-}" ]; then
            printf '[Fire4Nix] reference_env=%s\n' "$FIRE4NIX_REFERENCE_ENV"
        fi
        if [ -n "${FIRE4NIX_REFERENCE_STATUS:-}" ]; then
            printf '[Fire4Nix] reference_status=%s\n' "$FIRE4NIX_REFERENCE_STATUS"
        fi
    fi
}
