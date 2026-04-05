-- im-select.nvim configuration module
local M = {}

M.defaults = {
  -- Path to im-select.exe (Windows path accessible from WSL)
  -- Default: auto-detect from Windows USERPROFILE
  exe_path = nil,

  -- Toggle key for fallback keyboard simulation mode (default: RShift)
  toggle_key = "RShift",

  -- SendMessageTimeoutW timeout in ms (passed to im-select.exe --timeout)
  ime_timeout = 500,

  -- Switch to English when leaving Insert mode
  set_en_on_insert_leave = true,

  -- Restore previous IME state when entering Insert mode
  restore_on_insert_enter = true,

  -- Switch to English when entering Command-line mode (:, /, ?)
  set_en_on_cmdline_enter = true,

  -- Use async execution (recommended, avoids blocking Neovim)
  async = true,

  -- Timeout in milliseconds for sync io.popen calls
  timeout = 200,
}

M.options = {}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})

  -- Auto-detect exe_path if not provided
  if not M.options.exe_path then
    M.options.exe_path = M._detect_exe_path()
  end
end

function M._detect_exe_path()
  -- Try to get Windows USERPROFILE from WSL
  local handle = io.popen("cmd.exe /C echo %USERPROFILE% 2>/dev/null")
  if handle then
    local result = handle:read("*l")
    handle:close()
    if result then
      result = result:gsub("\r", ""):gsub("\n", "")
      local wsl_handle = io.popen("wslpath -u '" .. result .. "' 2>/dev/null")
      if wsl_handle then
        local wsl_path = wsl_handle:read("*l")
        wsl_handle:close()
        if wsl_path then
          return wsl_path:gsub("\r", ""):gsub("\n", "") .. "/im-select.exe"
        end
      end
    end
  end
  -- Fallback: common path
  return "/mnt/c/Users/" .. (os.getenv("USER") or "user") .. "/im-select.exe"
end

return M
