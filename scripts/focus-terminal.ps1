param(
    [string]$ProtocolUrl = ""
)

# Extract tab hint from protocol URL (claude-focus://TabName)
# Windows adds trailing slash to protocol URLs, so we trim it
$tabHint = ""
if ($ProtocolUrl -match "^claude-focus://(.+)$") {
    $tabHint = [System.Uri]::UnescapeDataString($Matches[1]).TrimEnd('/')
}

# Focus existing Windows Terminal window - bypasses foreground lock
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class FocusHelper {
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, IntPtr ProcessId);
    [DllImport("kernel32.dll")]
    public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")]
    public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);
}
"@

$terminal = Get-Process -Name "WindowsTerminal" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($terminal -and $terminal.MainWindowHandle -ne [IntPtr]::Zero) {
    $hwnd = $terminal.MainWindowHandle
    $foreground = [FocusHelper]::GetForegroundWindow()
    $foregroundThread = [FocusHelper]::GetWindowThreadProcessId($foreground, [IntPtr]::Zero)
    $currentThread = [FocusHelper]::GetCurrentThreadId()

    # Attach to foreground thread to gain focus privileges
    [FocusHelper]::AttachThreadInput($currentThread, $foregroundThread, $true) | Out-Null

    # Only restore if minimized - preserves maximized state; otherwise just bring to front
    if ([FocusHelper]::IsIconic($hwnd)) {
        [FocusHelper]::ShowWindow($hwnd, 9) | Out-Null  # SW_RESTORE
    }
    [FocusHelper]::BringWindowToTop($hwnd) | Out-Null
    [FocusHelper]::SetForegroundWindow($hwnd) | Out-Null

    # Detach
    [FocusHelper]::AttachThreadInput($currentThread, $foregroundThread, $false) | Out-Null

    # If we have a tab hint, try to find and focus that tab using UI Automation
    if ($tabHint) {
        Start-Sleep -Milliseconds 100  # Give window time to focus

        $logFile = "$env:USERPROFILE\.claude\focus-debug.log"
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -Path $logFile -Value "--- $timestamp ---"
        Add-Content -Path $logFile -Value "Looking for tab: '$tabHint'"

        try {
            Add-Type -AssemblyName UIAutomationClient -ErrorAction SilentlyContinue
            Add-Type -AssemblyName UIAutomationTypes -ErrorAction SilentlyContinue

            $root = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)

            # Find all TabItem elements (the tabs)
            $tabItemCondition = New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                [System.Windows.Automation.ControlType]::TabItem
            )

            $tabs = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $tabItemCondition)
            Add-Content -Path $logFile -Value "Found $($tabs.Count) tabs"

            # Search for a tab whose name contains our hint
            $found = $false
            foreach ($tab in $tabs) {
                $tabName = $tab.Current.Name
                Add-Content -Path $logFile -Value "  Checking: '$tabName'"
                if ($tabName -and $tabName -like "*$tabHint*") {
                    Add-Content -Path $logFile -Value "  MATCH! Attempting to select..."
                    $found = $true
                    # Found matching tab - select it
                    try {
                        $selectPattern = $tab.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
                        if ($selectPattern) {
                            $selectPattern.Select()
                            Add-Content -Path $logFile -Value "  Select() called successfully"
                        } else {
                            Add-Content -Path $logFile -Value "  SelectPattern was null"
                        }
                    } catch {
                        Add-Content -Path $logFile -Value "  Select error: $($_.Exception.Message)"
                    }
                    break
                }
            }
            if (-not $found) {
                Add-Content -Path $logFile -Value "No matching tab found for '$tabHint'"
            }
        } catch {
            Add-Content -Path $logFile -Value "UI Automation error: $($_.Exception.Message)"
        }
    }
}
