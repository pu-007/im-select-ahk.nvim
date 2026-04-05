-- im-select.nvim - Auto switch Windows IME from Neovim in WSL
-- v2: Uses IME API (SendMessageTimeoutW + ImmGetDefaultIMEWnd) with keyboard fallback
local config = require("im-select.config")

local M = {}

-- Buffer-local saved IME state
local saved_im = {}

-- Build the command string for im-select.exe
local function build_cmd(args)
  local opts = config.options
  local cmd = opts.exe_path

  if opts.toggle_key and opts.toggle_key ~= "" then
    cmd = cmd .. " --key " .. opts.toggle_key
  end

  if opts.ime_timeout and opts.ime_timeout > 0 then
    cmd = cmd .. " --timeout " .. tostring(opts.ime_timeout)
  end

  if args then
    cmd = cmd .. " " .. args
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

-- Save IME state for a buffer
local function save_state(bufnr, state)
  saved_im[bufnr] = state
end

-- Get saved IME state for a buffer
local function get_saved_state(bufnr)
  return saved_im[bufnr]
end

-- Called on InsertLeave: save current state, switch to English
function M.on_insert_leave()
  if not config.options.set_en_on_insert_leave then return end
  local bufnr = vim.api.nvim_get_current_buf()

  if config.options.async then
    exec_async("get", function(result)
      if result then
        save_state(bufnr, result)
        if result == "zh" then
          exec_async("set en", nil)
        end
      end
    end)
  else
    local current = exec_sync("get")
    if current then
      save_state(bufnr, current)
      if current == "zh" then
        exec_sync("set en")
      end
    end
  end
end

-- Called on InsertEnter: restore saved state
function M.on_insert_enter()
  if not config.options.restore_on_insert_enter then return end
  local bufnr = vim.api.nvim_get_current_buf()
  local prev = get_saved_state(bufnr)

  if prev and prev == "zh" then
    if config.options.async then
      exec_async("set zh", nil)
    else
      exec_sync("set zh")
    end
  end
end

-- Called on CmdlineEnter: switch to English
function M.on_cmdline_enter()
  if not config.options.set_en_on_cmdline_enter then return end
  if config.options.async then
    exec_async("set en", nil)
  else
    exec_sync("set en")
  end
end

-- Setup function: configure and create autocommands
function M.setup(opts)
  config.setup(opts)

  -- Create autocommand group
  local group = vim.api.nvim_create_augroup("im_select", { clear = true })

  if config.options.set_en_on_insert_leave then
    vim.api.nvim_create_autocmd("InsertLeave", {
      group = group,
      callback = M.on_insert_leave,
      desc = "im-select: switch to English on InsertLeave",
    })
  end

  if config.options.restore_on_insert_enter then
    vim.api.nvim_create_autocmd("InsertEnter", {
      group = group,
      callback = M.on_insert_enter,
      desc = "im-select: restore IME state on InsertEnter",
    })
  end

  if config.options.set_en_on_cmdline_enter then
    vim.api.nvim_create_autocmd("CmdlineEnter", {
      group = group,
      callback = M.on_cmdline_enter,
      desc = "im-select: switch to English on Command-line mode",
    })
  end

  -- Clean up saved state when buffer is deleted
  vim.api.nvim_create_autocmd("BufDelete", {
    group = group,
    callback = function(ev)
      saved_im[ev.buf] = nil
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
