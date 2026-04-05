-- im-select.nvim - Auto switch Windows IME from Neovim in WSL
-- v2: Uses IME API (SendMessageTimeoutW + ImmGetDefaultIMEWnd) with keyboard fallback
local config = require("im-select.config")

local M = {}

-- Buffer-local saved IME state for each mode
local saved_im_state = {}

-- Build the command string for im-select.exe
local function build_cmd(args)
  local opts = config.options
  local cmd = opts.exe_path

  -- Subcommand must come immediately after the exe path
  if args then
    cmd = cmd .. " " .. args
  end

  if opts.toggle_key and opts.toggle_key ~= "" then
    cmd = cmd .. " --key " .. opts.toggle_key
  end

  if opts.ime_timeout and opts.ime_timeout > 0 then
    cmd = cmd .. " --timeout " .. tostring(opts.ime_timeout)
  end

  return cmd
end

-- Execute im-select.exe synchronously, return trimmed stdout
local function exec_sync(args)
  local cmd = build_cmd(args)
  local handle = io.popen(cmd .. " 2>/dev/null")
  if not handle then return nil end
  local result = handle:read("*a")
  handle:close()
  if result then
    return result:gsub("%s+$", "")
  end
  return nil
end

-- Execute im-select.exe asynchronously via vim.loop
local function exec_async(args, callback)
  local cmd = build_cmd(args)
  local stdout = vim.loop.new_pipe(false)
  local output = ""

  local handle
  handle = vim.loop.spawn("sh", {
    args = { "-c", cmd },
    stdio = { nil, stdout, nil },
  }, function(code)
    stdout:read_stop()
    stdout:close()
    if handle then handle:close() end
    if callback then
      vim.schedule(function()
        callback(output:gsub("%s+$", ""), code)
      end)
    end
  end)

  if handle then
    stdout:read_start(function(err, data)
      if data then output = output .. data end
    end)
  end
end

-- Get current IME status: "en" or "zh"
function M.get()
  if config.options.async then
    exec_async("get", function(result)
      if result then
        vim.notify("IME: " .. result, vim.log.levels.INFO)
      end
    end)
  else
    return exec_sync("get")
  end
end

-- Set IME to specific mode: "en" or "zh"
function M.set(mode)
  if config.options.async then
    exec_async("set " .. mode, nil)
  else
    exec_sync("set " .. mode)
  end
end

-- Toggle IME mode
function M.toggle()
  if config.options.async then
    exec_async("toggle", function(result)
      if result then
        vim.notify("IME: " .. result, vim.log.levels.INFO)
      end
    end)
  else
    return exec_sync("toggle")
  end
end

-- Health check
function M.check()
  local result = exec_sync("check")
  if result then
    local ok, json = pcall(vim.json.decode, result)
    if ok and json then
      local lines = {
        "im-select health check:",
        "  AHK version:       " .. (json.ahk_version or "unknown"),
        "  Mode:              " .. (json.mode or "unknown"),
        "  API working:       " .. tostring(json.api_working),
        "  Foreground window: " .. tostring(json.foreground_window),
        "  Window title:      " .. (json.foreground_title or ""),
        "  IME window:        " .. tostring(json.ime_window),
        "  Open status:       " .. tostring(json.open_status),
        "  Conversion mode:   " .. tostring(json.conversion_mode),
        "  Keyboard layout:   " .. (json.keyboard_layout or "unknown"),
        "  Current state:     " .. (json.current_state or "unknown"),
        "  Toggle key:        " .. (json.toggle_key or "RShift"),
        "  Timeout:           " .. tostring(json.timeout or 500) .. "ms",
        "  State file:        " .. (json.state_file or ""),
      }

      -- Check exe accessibility
      local exe_exists = vim.fn.executable(config.options.exe_path) == 1
          or vim.fn.filereadable(config.options.exe_path) == 1
      table.insert(lines, "  Exe path:          " .. config.options.exe_path)
      table.insert(lines, "  Exe accessible:    " .. tostring(exe_exists))

      vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
    else
      vim.notify("im-select check raw output:\n" .. result, vim.log.levels.INFO)
    end
  else
    vim.notify("im-select: failed to run health check. Is im-select.exe accessible?",
      vim.log.levels.ERROR)
  end
end

-- Save IME state for a specific mode
local function save_state_for_mode(bufnr, mode, state)
  if not saved_im_state[bufnr] then
    saved_im_state[bufnr] = {}
  end
  saved_im_state[bufnr][mode] = state
  vim.notify(string.format("[DEBUG] save_state_for_mode: bufnr=%d, mode=%s, state=%s, all_states=%s",
    bufnr, mode, tostring(state), vim.inspect(saved_im_state[bufnr])), vim.log.levels.DEBUG)
end

-- Get saved IME state for a specific mode
local function get_saved_state_for_mode(bufnr, mode)
  if saved_im_state[bufnr] then
    local state = saved_im_state[bufnr][mode]
    vim.notify(string.format("[DEBUG] get_saved_state_for_mode: bufnr=%d, mode=%s, state=%s, all_states=%s",
      bufnr, mode, tostring(state), vim.inspect(saved_im_state[bufnr])), vim.log.levels.DEBUG)
    return state
  end
  vim.notify(string.format("[DEBUG] get_saved_state_for_mode: bufnr=%d, mode=%s, no saved states for this buffer",
    bufnr, mode), vim.log.levels.DEBUG)
  return nil
end

-- Get mode config for a given mode name
local function get_mode_config(mode_name)
  local mode_cfg = config.options.mode_config
  if mode_cfg and mode_cfg[mode_name] then
    return mode_cfg[mode_name]
  end
  return nil
end

-- Handle mode-specific IME switching
local function handle_mode_ime(mode_name, entering)
  local bufnr = vim.api.nvim_get_current_buf()
  local mode_cfg = get_mode_config(mode_name)

  if not mode_cfg then return end

  vim.notify(string.format("[DEBUG] handle_mode_ime: mode=%s, entering=%s, bufnr=%d, cfg=%s",
    mode_name, tostring(entering), bufnr, tostring(mode_cfg)), vim.log.levels.DEBUG)

  if entering then
    -- Entering a mode
    if mode_cfg == "always_en" then
      -- Always switch to English
      if config.options.async then
        exec_async("get", function(result)
          vim.notify(string.format("[DEBUG] always_en entering: got current state=%s", tostring(result)), vim.log.levels.DEBUG)
          if result then
            save_state_for_mode(bufnr, mode_name, result)
            vim.notify(string.format("[DEBUG] saved state for mode %s: %s", mode_name, result), vim.log.levels.DEBUG)
          end
          exec_async("set en", nil)
        end)
      else
        local current = exec_sync("get")
        vim.notify(string.format("[DEBUG] always_en entering (sync): got current state=%s", tostring(current)), vim.log.levels.DEBUG)
        if current then
          save_state_for_mode(bufnr, mode_name, current)
          vim.notify(string.format("[DEBUG] saved state for mode %s: %s", mode_name, current), vim.log.levels.DEBUG)
        end
        exec_sync("set en")
      end
    elseif mode_cfg == "restore" then
      -- Entering mode: restore saved state if any
      local saved = get_saved_state_for_mode(bufnr, mode_name)
      vim.notify(string.format("[DEBUG] restore entering: saved state for mode %s = %s", mode_name, tostring(saved)), vim.log.levels.DEBUG)
      if saved and saved == "zh" then
        vim.notify(string.format("[DEBUG] restoring to zh"), vim.log.levels.DEBUG)
        if config.options.async then
          exec_async("set zh", nil)
        else
          exec_sync("set zh")
        end
      else
        vim.notify(string.format("[DEBUG] no saved state or not zh, defaulting to en"), vim.log.levels.DEBUG)
        if config.options.async then
          exec_async("set en", nil)
        else
          exec_sync("set en")
        end
      end
    end
  else
    -- Leaving a mode
    if mode_cfg == "always_en" then
      -- Ensure English when leaving
      vim.notify(string.format("[DEBUG] always_en leaving: setting to en"), vim.log.levels.DEBUG)
      if config.options.async then
        exec_async("set en", nil)
      else
        exec_sync("set en")
      end
    elseif mode_cfg == "restore" then
      -- Leaving mode: save current state
      if config.options.async then
        exec_async("get", function(result)
          if result then
            save_state_for_mode(bufnr, mode_name, result)
            vim.notify(string.format("[DEBUG] saved state for mode %s on leave: %s", mode_name, result), vim.log.levels.DEBUG)
          end
        end)
      else
        local current = exec_sync("get")
        if current then
          save_state_for_mode(bufnr, mode_name, current)
          vim.notify(string.format("[DEBUG] saved state for mode %s on leave: %s", mode_name, current), vim.log.levels.DEBUG)
        end
      end
    end
  end
end

-- Called on InsertEnter
function M.on_insert_enter()
  handle_mode_ime("insert", true)
end

-- Called on InsertLeave
function M.on_insert_leave()
  handle_mode_ime("insert", false)
end

-- Called on CmdlineEnter
function M.on_cmdline_enter()
  handle_mode_ime("cmdline", true)
end

-- Called on CmdlineLeave
function M.on_cmdline_leave()
  handle_mode_ime("cmdline", false)
end

-- Called on ModeChanged to handle search mode and normal mode
function M.on_mode_changed()
  local mode = vim.fn.mode()
  
  -- Handle search mode (/ or ?)
  if mode == "/" or mode == "?" then
    handle_mode_ime("search", true)
  -- Handle normal mode
  elseif mode == "n" then
    handle_mode_ime("normal", true)
  -- Handle visual mode
  elseif mode == "v" or mode == "V" or mode == "\22" then
    handle_mode_ime("visual", true)
  -- Handle replace mode
  elseif mode == "R" then
    handle_mode_ime("replace", true)
  -- Handle terminal mode
  elseif mode == "t" then
    handle_mode_ime("terminal", true)
  -- Handle select mode
  elseif mode == "s" or mode == "S" or mode == "\19" then
    handle_mode_ime("select", true)
  else
    -- Leaving other modes: handle leaving for search, visual, replace, terminal, select
    handle_mode_ime("search", false)
    handle_mode_ime("visual", false)
    handle_mode_ime("replace", false)
    handle_mode_ime("terminal", false)
    handle_mode_ime("select", false)
  end
end

-- Setup function: configure and create autocommands
function M.setup(opts)
  config.setup(opts)

  -- Create autocommand group
  local group = vim.api.nvim_create_augroup("im_select", { clear = true })

  -- Insert mode autocommands
  local insert_cfg = get_mode_config("insert")
  if insert_cfg then
    vim.api.nvim_create_autocmd("InsertEnter", {
      group = group,
      callback = M.on_insert_enter,
      desc = "im-select: handle IME on InsertEnter",
    })

    vim.api.nvim_create_autocmd("InsertLeave", {
      group = group,
      callback = M.on_insert_leave,
      desc = "im-select: handle IME on InsertLeave",
    })
  end

  -- Cmdline mode autocommands
  local cmdline_cfg = get_mode_config("cmdline")
  if cmdline_cfg then
    vim.api.nvim_create_autocmd("CmdlineEnter", {
      group = group,
      callback = M.on_cmdline_enter,
      desc = "im-select: handle IME on CmdlineEnter",
    })

    vim.api.nvim_create_autocmd("CmdlineLeave", {
      group = group,
      callback = M.on_cmdline_leave,
      desc = "im-select: handle IME on CmdlineLeave",
    })
  end

  -- ModeChanged autocommand for all other modes
  local has_mode_changed = false
  for mode_name, mode_cfg in pairs(config.options.mode_config) do
    if mode_cfg and mode_name ~= "insert" and mode_name ~= "cmdline" then
      has_mode_changed = true
      break
    end
  end

  if has_mode_changed then
    vim.api.nvim_create_autocmd("ModeChanged", {
      group = group,
      callback = M.on_mode_changed,
      desc = "im-select: handle IME on mode changes",
    })
  end

  -- Clean up saved state when buffer is deleted
  vim.api.nvim_create_autocmd("BufDelete", {
    group = group,
    callback = function(ev)
      saved_im_state[ev.buf] = nil
    end,
    desc = "im-select: clean up saved IME state",
  })

  -- Register user commands
  vim.api.nvim_create_user_command("IMSelectGet", function()
    M.get()
  end, { desc = "Get current IME status" })

  vim.api.nvim_create_user_command("IMSelectSet", function(cmd_opts)
    local mode = cmd_opts.args
    if mode ~= "en" and mode ~= "zh" then
      vim.notify("Usage: :IMSelectSet <en|zh>", vim.log.levels.WARN)
      return
    end
    M.set(mode)
  end, { nargs = 1, complete = function() return { "en", "zh" } end,
    desc = "Set IME to en or zh" })

  vim.api.nvim_create_user_command("IMSelectToggle", function()
    M.toggle()
  end, { desc = "Toggle IME mode" })

  vim.api.nvim_create_user_command("IMSelectCheck", function()
    M.check()
  end, { desc = "Run im-select health check" })
end

return M
