# im-select.nvim

在 WSL 中的 Neovim 里自动切换 Windows 输入法中英文模式。

基于 AutoHotkey v2，使用 `SendMessageTimeoutW` + `ImmGetDefaultIMEWnd` 技术（参考 [InputTip](https://github.com/abgox/InputTip)）可靠检测和切换输入法状态，支持微信输入法、搜狗等现代 IME，并提供键盘模拟回退方案。

## 特性

- 通过 `WM_IME_CONTROL` 消息原生检测和切换输入法中英文状态
- 离开 Insert 模式自动切换到英文
- 进入 Insert 模式自动恢复之前的输入法状态（按 buffer 记忆）
- 进入 Command-line 模式（`:`, `/`, `?`）自动切换到英文
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
  event = { "InsertEnter", "InsertLeave", "CmdlineEnter" },
  opts = {
    -- 可选配置，以下为默认值
    toggle_key = "RShift",              -- 回退模式的切换键
    ime_timeout = 500,                  -- SendMessage 超时时间 (ms)
    set_en_on_insert_leave = true,      -- 离开 Insert 切换英文
    restore_on_insert_enter = true,     -- 进入 Insert 恢复状态
    set_en_on_cmdline_enter = true,     -- 进入 Command-line 切换英文
    async = true,                       -- 异步执行
  },
}
```

### 3. 验证安装

在 Neovim 中运行：

```vim
:IMSelectCheck
```

## 配置选项

| 选项 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `exe_path` | string | 自动检测 | im-select.exe 的 WSL 路径 |
| `toggle_key` | string | `"RShift"` | 回退模式的切换键 |
| `ime_timeout` | number | `500` | SendMessageTimeoutW 超时时间（毫秒） |
| `set_en_on_insert_leave` | boolean | `true` | 离开 Insert 模式时切换到英文 |
| `restore_on_insert_enter` | boolean | `true` | 进入 Insert 模式时恢复之前的状态 |
| `set_en_on_cmdline_enter` | boolean | `true` | 进入 Command-line 模式时切换到英文 |
| `async` | boolean | `true` | 异步执行（推荐） |
| `timeout` | number | `200` | 同步模式 io.popen 超时时间（毫秒） |

## 命令

| 命令 | 说明 |
|------|------|
| `:IMSelectGet` | 获取当前输入法状态 |
| `:IMSelectSet en` | 切换到英文模式 |
| `:IMSelectSet zh` | 切换到中文模式 |
| `:IMSelectToggle` | 切换中英文 |
| `:IMSelectCheck` | 运行健康检查 |

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
8. 每个 buffer 独立保存输入法状态，进出 Insert 模式时自动切换/恢复

## 参考

- [InputTip](https://github.com/abgox/InputTip) — IME 状态检测技术参考
- [Tebayaki/AutoHotkeyScripts](https://github.com/Tebayaki/AutoHotkeyScripts) — IME.ahk 原始实现
- WM_IME_CONTROL (0x283) — Windows IME 控制消息
- ImmGetDefaultIMEWnd — 获取 IME 默认窗口 API
- GetGUIThreadInfo — 获取线程 GUI 信息（焦点控件）

## License

MIT
