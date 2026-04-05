#!/bin/zsh
# im-select zsh vimmode integration
# Auto switch Windows IME when entering/exiting vi mode in zsh

# Configuration
: ${IM_SELECT_EXE_PATH:="/mnt/c/Users/$USERNAME/im-select.exe"}
: ${IM_SELECT_TOGGLE_KEY:="RShift"}
: ${IM_SELECT_TIMEOUT:="500"}

# Saved IME state for restoration
_IM_SELECT_SAVED_STATE=""

# Build command string
_im_select_build_cmd() {
  local args="$1"
  local cmd="$IM_SELECT_EXE_PATH"
  
  if [[ -n "$args" ]]; then
    cmd="$cmd $args"
  fi
  
  if [[ -n "$IM_SELECT_TOGGLE_KEY" ]]; then
    cmd="$cmd --key $IM_SELECT_TOGGLE_KEY"
  fi
  
  if [[ -n "$IM_SELECT_TIMEOUT" && "$IM_SELECT_TIMEOUT" -gt 0 ]]; then
    cmd="$cmd --timeout $IM_SELECT_TIMEOUT"
  fi
  
  echo "$cmd"
}

# Execute im-select.exe synchronously, completely suppress all output
_im_select_exec_silent() {
  local args="$1"
  local cmd=$(_im_select_build_cmd "$args")
  eval "$cmd" >/dev/null 2>&1
}

# Execute im-select.exe and capture output, suppress display
_im_select_exec_capture() {
  local args="$1"
  local cmd=$(_im_select_build_cmd "$args")
  eval "$cmd" 2>/dev/null
}

# Get current IME status: "en" or "zh"
im_select_get() {
  _im_select_exec_capture "get"
}

# Set IME to specific mode: "en" or "zh", suppress all output
im_select_set() {
  local mode="$1"
  if [[ "$mode" != "en" && "$mode" != "zh" ]]; then
    echo "Usage: im_select_set <en|zh>" >&2
    return 1
  fi
  _im_select_exec_silent "set $mode"
}

# Toggle IME mode
im_select_toggle() {
  _im_select_exec_silent "toggle"
}

# Health check
im_select_check() {
  local result=$(_im_select_exec_capture "check")
  if [[ -n "$result" ]]; then
    echo "$result"
  else
    echo "im-select: failed to run health check. Is im-select.exe accessible?" >&2
    return 1
  fi
}

# Called when entering normal mode (ESC)
# Save current IME state and switch to English
_im_select_on_normal_mode() {
  # Get current IME state before switching
  local current_state=$(im_select_get)
  
  # Save the state for later restoration
  _IM_SELECT_SAVED_STATE="$current_state"
  
  # Switch to English only if not already in English
  if [[ "$current_state" == "zh" ]]; then
    im_select_set "en"
  fi
}

# Called when entering insert mode
# Restore previous IME state
_im_select_on_insert_mode() {
  # Restore to saved state if it was Chinese
  if [[ "$_IM_SELECT_SAVED_STATE" == "zh" ]]; then
    im_select_set "zh"
  fi
}

# Setup zsh vimmode integration
im_select_setup_vimmode() {
  # Check if zsh vi mode is available
  if [[ -z "$ZSH_VERSION" ]]; then
    echo "This script requires zsh" >&2
    return 1
  fi
  
  # Enable vi mode
  bindkey -v
  
  # Hook into vi mode changes
  # When ESC is pressed (entering normal mode)
  function zle-keymap-select {
    if [[ "$KEYMAP" == "vicmd" ]]; then
      _im_select_on_normal_mode
    elif [[ "$KEYMAP" == "main" ]]; then
      _im_select_on_insert_mode
    fi
  }
  zle -N zle-keymap-select
  
  # Also handle when returning to insert mode
  function zle-line-init {
    if [[ "$KEYMAP" == "vicmd" ]]; then
      _im_select_on_normal_mode
    fi
  }
  zle -N zle-line-init
}

# Auto-setup if sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Script is being executed directly
  case "$1" in
    get)
      im_select_get
      ;;
    set)
      im_select_set "$2"
      ;;
    toggle)
      im_select_toggle
      ;;
    check)
      im_select_check
      ;;
    setup)
      im_select_setup_vimmode
      ;;
    *)
      echo "Usage: $0 {get|set <en|zh>|toggle|check|setup}" >&2
      exit 1
      ;;
  esac
else
  # Script is being sourced
  im_select_setup_vimmode
fi
