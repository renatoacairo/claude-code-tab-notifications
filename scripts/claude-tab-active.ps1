param(
    [string]$TabHint = $env:CLAUDE_TAB_NAME
)

# Reset tab title to active state when the user submits a prompt
if ($TabHint) {
    try {
        $bolt = [char]::ConvertFromUtf32(0x26A1)
        [Console]::Title = "$bolt $TabHint"
    } catch {}
}

# Dismiss any pending notifications since the user is back at Terminal
try {
    $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
    $AppId = "Microsoft.WindowsTerminal_8wekyb3d8bbwe!App"
    [Windows.UI.Notifications.ToastNotificationManager]::History.Clear($AppId)
} catch {}
