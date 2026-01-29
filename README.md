# claude-code-tab-notifications

**Tab-Aware Notifications for Claude Code on Windows Terminal**

> Never miss when Claude finishes in another tab. Get the right notification, click to switch to the right tab.

## Features

### Tab-Aware Notifications

Not all notifications are equal. This system detects your context and adapts:

| You are... | What happens | Why |
|---|---|---|
| On the **same tab** where Claude finished | Nothing | You already see it |
| On a **different tab** in Windows Terminal | Ephemeral toast (auto-dismisses) | A gentle nudge - you're already in Terminal |
| **Outside** Windows Terminal entirely | Sticky persistent toast with action button | You need to come back |

### Click-to-Focus

Clicking the toast notification doesn't just bring Windows Terminal to the foreground - it switches to the **exact tab** where Claude finished. This uses Windows UI Automation to find and select the correct tab by name.

### Tab Title Lifecycle

Visual status indicators right in the tab bar, so you can see at a glance which Claude sessions need attention:

- **`⚡ TabName`** - Claude is working (set when you submit a prompt)
- **`👀 TabName`** - Claude is done, waiting for your input (set when Claude stops)

### Zero Dependencies

No external modules. No BurntToast. No npm packages. Just:

- Built-in Windows APIs (user32.dll, kernel32.dll)
- PowerShell 5.1+ (ships with Windows)
- WinRT toast notifications (built into Windows 10/11)
- UI Automation (built into .NET Framework)

### Protocol Handler

Registers a `claude-focus://` protocol so toast notifications can deep-link to specific tabs. The protocol URL encodes the tab name, enabling precise tab switching when you click a notification.

## How It Works

```
You run: claude-tab MyProject
    -> Sets $env:CLAUDE_TAB_NAME = "MyProject"
    -> Tab title becomes "⚡ MyProject"
    -> Launches claude

You submit a prompt (UserPromptSubmit hook)
    -> Tab title resets to "⚡ MyProject"

Claude finishes (Stop hook)
    -> Checks: Is Windows Terminal focused?
        -> Yes: Is THIS tab active? (checks window title for "MyProject")
            -> Yes: No notification (you're looking at it)
            -> No:  Ephemeral toast + tab title becomes "👀 MyProject"
        -> No: Sticky toast with "Go to Claude Code" button
               + tab title becomes "👀 MyProject"

You click the toast
    -> Launches claude-focus://MyProject protocol
    -> focus-terminal.ps1 brings Terminal to front
    -> UI Automation finds and selects the "MyProject" tab
```

## Prerequisites

- Windows 10 or 11
- Windows Terminal (from Microsoft Store or GitHub)
- Claude Code CLI (`claude`)
- PowerShell 5.1+ (included with Windows)

## Installation

### Automated

```powershell
# Clone the repo
git clone https://github.com/your-username/claude-code-tab-notifications.git
cd claude-code-tab-notifications

# Run the installer (safe to run multiple times)
powershell -ExecutionPolicy Bypass -File install.ps1
```

The installer will:
1. Copy scripts to `~/.claude/`
2. Register the `claude-focus://` protocol handler
3. Merge notification hooks into your Claude Code settings
4. Configure Windows Terminal to allow custom tab titles
5. Add the `claude-tab` function to your PowerShell profile

### Manual

1. **Copy scripts** to `~/.claude/`:
   ```
   claude-notify.ps1
   claude-tab-active.ps1
   focus-terminal.ps1
   focus-terminal.vbs
   ```

2. **Register the protocol handler** by adding to the Windows Registry:
   ```
   HKCU\Software\Classes\claude-focus\(Default) = "URL:Claude Focus Protocol"
   HKCU\Software\Classes\claude-focus\URL Protocol = ""
   HKCU\Software\Classes\claude-focus\shell\open\command\(Default) = wscript.exe "%USERPROFILE%\.claude\focus-terminal.vbs" "%1"
   ```

3. **Add hooks** to `~/.claude/settings.json` (see `config/settings-hooks.jsonc`)

4. **Add to Windows Terminal settings** (`settings.json`):
   ```json
   {
       "profiles": {
           "defaults": {
               "suppressApplicationTitle": true
           }
       }
   }
   ```
   This allows the scripts to control tab titles. Without it, the shell overrides custom titles.

5. **Add the `claude-tab` function** to your PowerShell `$PROFILE` (see `config/claude-tab-function.ps1`)

## Usage

```powershell
# Start Claude with a named tab
claude-tab MyProject

# The tab title shows "⚡ MyProject" while Claude works
# When Claude stops, it becomes "👀 MyProject"
# You get a toast notification if you're not looking at that tab

# Works with claude arguments too
claude-tab MyProject --model opus
```

## Files

| File | Purpose |
|---|---|
| `scripts/claude-notify.ps1` | Main notification logic - detects context, shows appropriate toast |
| `scripts/claude-tab-active.ps1` | Resets tab title to "working" state on prompt submit |
| `scripts/focus-terminal.ps1` | Brings Terminal to front and switches to the correct tab via UI Automation |
| `scripts/focus-terminal.vbs` | VBScript wrapper to launch focus-terminal.ps1 hidden (no flash) |
| `config/settings-hooks.jsonc` | Example Claude Code hooks configuration |
| `config/claude-tab-function.ps1` | PowerShell function to add to your profile |
| `install.ps1` | Automated installer |

## How It Compares

| Feature | This project | [claude-code-notify-powershell](https://github.com/soulee-dev/claude-code-notify-powershell) | [claude-wsl](https://github.com/fullstacktard/claude-wsl) | Built-in `--notify` |
|---|:---:|:---:|:---:|:---:|
| Toast notifications | Yes | Yes | Yes | Partial |
| Tab-aware (same vs. different tab) | Yes | No | No | No |
| Click-to-focus (exact tab) | Yes | No | No | No |
| Tab title lifecycle | Yes | No | No | No |
| Protocol handler | Yes | No | No | No |
| Zero dependencies | Yes | BurntToast | WSL tools | N/A |
| Windows native | Yes | Yes | WSL | Cross-platform |

## Troubleshooting

### Tab switching doesn't work

- Make sure `suppressApplicationTitle: true` is set in Windows Terminal settings
- The tab name must be set via `claude-tab` before launching Claude
- Check `~/.claude/focus-debug.log` for UI Automation diagnostics

### No notifications appear

- Ensure Windows notifications are enabled for Windows Terminal in Settings > System > Notifications
- Verify the hooks are in `~/.claude/settings.json` (run `claude-tab` and check)

### Toast appears but clicking does nothing

- Verify the `claude-focus://` protocol is registered: open Run (Win+R) and type `claude-focus://test`
- Check that `focus-terminal.vbs` exists at `~/.claude/focus-terminal.vbs`

## License

MIT License. See [LICENSE](LICENSE).
