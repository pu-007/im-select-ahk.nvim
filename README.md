# im-select

在 WSL 中自动切换 Windows 输入法中英文模式，支持 Neovim 插件和 zsh vi-mode。

基于 AutoHotkey v2，使用 `SendMessageTimeoutW` + `ImmGetDefaultIMEWnd` 技术（参考 [InputTip](https://github.com/abgox/InputTip)）可靠检测和切换输入法状态，支持微信输入法、搜狗等现代 IME，并提供键盘模拟回退方案。

## 特性

- 通过 `WM_IME_CONTROL` 消息原生检测和切换输入法中英文状态
- **按模式独立配置** 输入法切换行为（Normal、Insert、Cmdline、Search、Visual、Replace、Terminal、Select）
- 每个模式支持 `"always_en"`（始终英文）、`"restore"`（记忆并恢复状态）或 `false`（不干预）
- 离开 Insert 模式自动切换到英文，进入 Insert 恢复之前状态
- 搜索（`/`、`?`）和命令行（`:`）模式支持输入法状态记忆，离开后自动恢复
- Normal 模式始终保持英文，确保命令输入正常
- 异步执行，不阻塞 Neovim
- 原生 API 失败时自动回退到键盘模拟（可自定义切换键，默认 RShift）
- 健康检查命令，方便排查问题

## 安装

### 1. 编译 im-select.exe

需要 [AutoHotkey v2](https://www.autohotkey.com/) 安装在 Windows 上。

**方法 A: 使用 Ahk2Exe 编译（推荐）**

1. 安装 AutoHotkey v2
2. 右键 `ahk/im-select.ahk` → Compile Script
3. 将生成的 `im-select.exe` 复制到 `%USERPROFILE%\im-select.exe`

**方法 B: 直接用 AHK v2 运行（不编译）**

```cmd
:: 在 Windows 中
copy ahk\im-select.ahk %USERPROFILE%\im-select.ahk
```

然后在插件配置中将 exe_path 指向 AHK v2 解释器：

```lua
exe_path = "/mnt/c/Program Files/AutoHotkey/v2/AutoHotkey.exe /mnt/c/Users/你的用户名/im-select.ahk"
```

### 2. 安装 Neovim 插件

使用 [lazy.nvim](https://github.com/folke/lazy.nvim)：

```lua
{
  "pu-007/im-select-ahk.nvim",
  event = { "InsertEnter", "InsertLeave", "CmdlineEnter", "CmdlineLeave", "ModeChanged" },
  opts = {
    -- 可选配置，以下为默认值
    toggle_key = "RShift",              -- 回退模式的切换键
    ime_timeout = 500,                  -- SendMessage 超时时间 (ms)
    async = true,                       -- 异步执行（推荐）
    mode_config = {
      normal   = "always_en",           -- Normal 模式始终英文
      insert   = "restore",             -- Insert 模式记忆恢复
      cmdline  = "restore",             -- Command-line 模式记忆恢复
      search   = "restore",             -- 搜索模式记忆恢复
      visual   = false,                 -- Visual 模式不干预
      replace  = "restore",             -- Replace 模式记忆恢复
      terminal = false,                 -- Terminal 模式不干预
      select   = false,                 -- Select 模式不干预
    },
  },
}
```

### 3. 验证安装

在 Neovim 中运行：

```vim
:IMSelectCheck
```

### 4. 配置 zsh vi-mode（可选）

如果你在 zsh 中使用 vi-mode，可以通过 [`zsh/im-select-vimmode.zsh`](zsh/im-select-vimmode.zsh) 脚本在进入/退出 normal mode 时自动切换输入法。

**使用方法：**

在你的 `.zshrc` 中添加：

```bash
# 使用同样的 exe 路径配置
export IM_SELECT_EXE_PATH="/mnt/c/Users/你的用户名/im-select.exe"
export IM_SELECT_TOGGLE_KEY="RShift"
export IM_SELECT_TIMEOUT="500"

# 加载脚本
source /path/to/im-select/zsh/im-select-vimmode.zsh
```

或者直接执行脚本的 setup 命令：

```bash
/path/to/im-select/zsh/im-select-vimmode.zsh setup
```

如果你使用 zinit, 可使用:

```zsh
zinit wait'!0' lucid is-snippet nocd for \
  atinit'export IM_SELECT_EXE_PATH="/mnt/c/Users/zionpu/im-select.exe"' \
    https://raw.githubusercontent.com/pu-007/im-select-ahk.nvim/refs/heads/main/zsh/im-select-vimmode.zsh

```

脚本会在进入 normal mode（按 ESC）时自动切换到英文，方便在 zsh 中编辑命令。

## 配置选项

### 基础选项

| 选项          | 类型   | 默认值     | 说明                                 |
| ------------- | ------ | ---------- | ------------------------------------ |
| `exe_path`    | string | 自动检测   | im-select.exe 的 WSL 路径            |
| `toggle_key`  | string | `"RShift"` | 回退模式的切换键                     |
| `ime_timeout` | number | `500`      | SendMessageTimeoutW 超时时间（毫秒） |
| `async`       | bool   | `true`     | 异步执行（推荐）                     |
| `timeout`     | number | `200`      | 同步模式 io.popen 超时时间（毫秒）   |

### 模式配置 (`mode_config`)

每个 Neovim 模式可以独立配置输入法行为：

| 模式名     | 默认值       | 说明                                 |
| ---------- | ------------ | ------------------------------------ |
| `normal`   | `"always_en"` | Normal 模式 — 始终英文，确保命令正常 |
| `insert`   | `"restore"`  | Insert 模式 — 记忆并恢复输入法状态   |
| `cmdline`  | `"restore"`  | Command-line 模式（`:`） — 记忆并恢复 |
| `search`   | `"restore"`  | 搜索模式（`/`、`?`） — 记忆并恢复   |
| `visual`   | `false`      | Visual 模式 — 不干预                 |
| `replace`  | `"restore"`  | Replace 模式 — 记忆并恢复           |
| `terminal` | `false`      | Terminal 模式 — 不干预               |
| `select`   | `false`      | Select 模式 — 不干预                 |

#### 模式配置值说明

| 值           | 行为                                                                 |
| ------------ | -------------------------------------------------------------------- |
| `"always_en"` | 进入该模式时自动切换为英文，离开时也保持英文                         |
| `"restore"`  | 进入该模式时保存当前输入法状态，离开时恢复之前的状态（中英文都记忆） |
| `false`/`nil` | 不对该模式做任何输入法切换                                           |

#### 常用配置示例

**搜索时始终英文（不记忆中文状态）：**

```lua
mode_config = {
  search = "always_en",
}
```

**命令行和搜索都始终英文：**

```lua
mode_config = {
  cmdline = "always_en",
  search  = "always_en",
}
```

**所有模式都不干预（完全手动控制）：**

```lua
mode_config = {
  normal   = false,
  insert   = false,
  cmdline  = false,
  search   = false,
  visual   = false,
  replace  = false,
  terminal = false,
  select   = false,
}
```

## 命令

| 命令              | 说明               |
| ----------------- | ------------------ |
| `:IMSelectGet`    | 获取当前输入法状态 |
| `:IMSelectSet en` | 切换到英文模式     |
| `:IMSelectSet zh` | 切换到中文模式     |
| `:IMSelectToggle` | 切换中英文         |
| `:IMSelectCheck`  | 运行健康检查       |

## im-select.exe 命令行用法

```
im-select.exe <command> [options]

Commands:
  get              输出当前输入法模式: "en" 或 "zh"
  set <en|zh>      切换到指定模式
  toggle           切换中英文
  check            健康检查，输出 JSON 诊断信息

Options:
  --key <name>     指定切换键 (默认: RShift)
  --timeout <ms>   SendMessage 超时时间 (默认: 500)
```

## 工作原理

1. AHK v2 脚本通过 `GetGUIThreadInfo` 获取真正的焦点控件句柄
2. 通过 `ImmGetDefaultIMEWnd` 获取 IME 默认窗口
3. 使用 `SendMessageTimeoutW` 发送 `WM_IME_CONTROL` (0x283) 消息读取/设置状态
4. `OpenStatus` (wParam=0x5) 判断 IME 是否开启，`ConversionMode` (wParam=0x1) 的 bit0 判断中英文
5. 如果原生 API 不可用或超时，回退到发送配置的切换键（默认 RShift）
6. 状态文件作为额外的持久化回退层
7. Neovim 插件通过 `vim.loop.spawn` 异步调用 exe，避免阻塞编辑器
8. 每个 buffer 按模式独立保存输入法状态，进出各模式时按配置自动切换/恢复

## 参考

- [InputTip](https://github.com/abgox/InputTip) — IME 状态检测技术参考
- [Tebayaki/AutoHotkeyScripts](https://github.com/Tebayaki/AutoHotkeyScripts) — IME.ahk 原始实现
- WM_IME_CONTROL (0x283) — Windows IME 控制消息
- ImmGetDefaultIMEWnd — 获取 IME 默认窗口 API
- GetGUIThreadInfo — 获取线程 GUI 信息（焦点控件）

## License

MIT
