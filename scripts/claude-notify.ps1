param(
    [string]$Title = "Claude Code",
    [string]$Message = "Waiting for your input",
    [string]$TabHint = $env:CLAUDE_TAB_NAME
)

# Check if Windows Terminal is in focus and determine which tab is active
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class FocusCheck {
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
}
"@

$foregroundWindow = [FocusCheck]::GetForegroundWindow()
$processId = 0
[FocusCheck]::GetWindowThreadProcessId($foregroundWindow, [ref]$processId) | Out-Null

$terminalFocusedDifferentTab = $false

if ($processId -gt 0) {
    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if ($process -and $process.ProcessName -eq "WindowsTerminal") {
        # Terminal is focused - check if THIS tab is the active one
        $windowTitle = New-Object System.Text.StringBuilder 256
        [FocusCheck]::GetWindowText($foregroundWindow, $windowTitle, 256) | Out-Null
        $titleText = $windowTitle.ToString()

        if ($TabHint -and $titleText -match [regex]::Escape($TabHint)) {
            # This tab is active - no notification needed
            exit 0
        }
        # Terminal focused but on a different tab - show ephemeral toast
        $terminalFocusedDifferentTab = $true
    }
}

# Mark this tab as waiting - visible at a glance in the tab bar
if ($TabHint) {
    try {
        $eyes = [char]::ConvertFromUtf32(0x1F440)
        [Console]::Title = "$eyes $TabHint"
    } catch {}
}

# Load Windows Runtime assemblies
$null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
$null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]

# Windows Terminal AUMID - enables click-to-focus
$AppId = "Microsoft.WindowsTerminal_8wekyb3d8bbwe!App"

# Build protocol URL with tab hint if provided
$protocolUrl = "claude-focus://"
if ($TabHint) {
    $encodedHint = [System.Uri]::EscapeDataString($TabHint)
    $protocolUrl = "claude-focus://$encodedHint"
}

# Add tab name to message if provided
$displayMessage = $Message
if ($TabHint) {
    $displayMessage = "$Message - $TabHint"
}

# Toast XML - ephemeral for different-tab, sticky for out-of-focus
if ($terminalFocusedDifferentTab) {
    # Ephemeral toast: no scenario, auto-dismisses after a few seconds
    $template = @"
<toast activationType="protocol" launch="$protocolUrl">
    <visual>
        <binding template="ToastGeneric">
            <text>$Title</text>
            <text>$displayMessage</text>
        </binding>
    </visual>
    <audio silent="true"/>
</toast>
"@
} else {
    # Sticky toast for when Terminal is not focused at all
    $template = @"
<toast activationType="protocol" launch="$protocolUrl" scenario="incomingCall">
    <visual>
        <binding template="ToastGeneric">
            <text>$Title</text>
            <text>$displayMessage</text>
        </binding>
    </visual>
    <actions>
        <action content="Go to Claude Code" activationType="protocol" arguments="$protocolUrl"/>
    </actions>
    <audio silent="true"/>
</toast>
"@
}

# Create and show notification (tag ensures Windows replaces any existing one)
$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
$xml.LoadXml($template)
$toast = New-Object Windows.UI.Notifications.ToastNotification $xml
$toast.Tag = "claude-code"
$toast.Group = "claude-code"
$notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppId)
[Windows.UI.Notifications.ToastNotificationManager]::History.Clear($AppId)
$notifier.Show($toast)
