#Requires -Version 5.1
<#
.SYNOPSIS
    Installs claude-code-tab-notifications for the current user.

.DESCRIPTION
    This installer:
    1. Copies notification scripts to ~/.claude/
    2. Registers the claude-focus:// protocol handler
    3. Merges notification hooks into ~/.claude/settings.json
    4. Configures Windows Terminal to allow custom tab titles
    5. Adds the claude-tab function to your PowerShell profile

    Safe to run multiple times (idempotent). Backs up files before modifying.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File install.ps1
#>

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$claudeDir = Join-Path $env:USERPROFILE ".claude"
$backupDir = Join-Path $claudeDir "backups"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

function Write-Step { param([string]$msg) Write-Host "`n[+] $msg" -ForegroundColor Cyan }
function Write-Info { param([string]$msg) Write-Host "    $msg" -ForegroundColor Gray }
function Write-Skip { param([string]$msg) Write-Host "    SKIP: $msg" -ForegroundColor Yellow }
function Write-Done { param([string]$msg) Write-Host "    OK: $msg" -ForegroundColor Green }

function Backup-File {
    param([string]$Path)
    if (Test-Path $Path) {
        if (-not (Test-Path $backupDir)) {
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        }
        $name = Split-Path -Leaf $Path
        $backupPath = Join-Path $backupDir "$name.$timestamp.bak"
        Copy-Item $Path $backupPath -Force
        Write-Info "Backed up to $backupPath"
    }
}

# ============================================================
# 1. Copy scripts to ~/.claude/
# ============================================================
Write-Step "Copying scripts to $claudeDir"

if (-not (Test-Path $claudeDir)) {
    New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
}

$scripts = @(
    "claude-notify.ps1",
    "claude-tab-active.ps1",
    "focus-terminal.ps1",
    "focus-terminal.vbs"
)

foreach ($script in $scripts) {
    $src = Join-Path $scriptRoot "scripts\$script"
    $dst = Join-Path $claudeDir $script
    if (Test-Path $src) {
        Copy-Item $src $dst -Force
        Write-Done $script
    } else {
        Write-Host "    ERROR: Source file not found: $src" -ForegroundColor Red
    }
}

# ============================================================
# 2. Register claude-focus:// protocol handler
# ============================================================
Write-Step "Registering claude-focus:// protocol handler"

$protocolKey = "HKCU:\Software\Classes\claude-focus"
$vbsPath = Join-Path $claudeDir "focus-terminal.vbs"

$existingDefault = $null
if (Test-Path $protocolKey) {
    $existingDefault = (Get-ItemProperty -Path $protocolKey -Name "(Default)" -ErrorAction SilentlyContinue).'(Default)'
}

if ($existingDefault -eq "URL:Claude Focus Protocol") {
    Write-Skip "Protocol already registered"
} else {
    # Create protocol registration
    New-Item -Path $protocolKey -Force | Out-Null
    Set-ItemProperty -Path $protocolKey -Name "(Default)" -Value "URL:Claude Focus Protocol"
    Set-ItemProperty -Path $protocolKey -Name "URL Protocol" -Value ""

    $commandKey = "$protocolKey\shell\open\command"
    New-Item -Path $commandKey -Force | Out-Null
    Set-ItemProperty -Path $commandKey -Name "(Default)" -Value "wscript.exe `"$vbsPath`" `"%1`""
    Write-Done "Registered claude-focus:// protocol"
}

# ============================================================
# 3. Merge hooks into ~/.claude/settings.json
# ============================================================
Write-Step "Configuring Claude Code hooks"

$settingsPath = Join-Path $claudeDir "settings.json"

# Define the hooks we want to ensure exist
$notifyCommand = "powershell -ExecutionPolicy Bypass -File `"$claudeDir\claude-notify.ps1`" -Message `"Your turn`""
$activeCommand = "powershell -ExecutionPolicy Bypass -File `"$claudeDir\claude-tab-active.ps1`""
$permissionCommand = "powershell -ExecutionPolicy Bypass -File `"$claudeDir\claude-notify.ps1`" -Message `"Permission needed`""

# Normalize path separators for JSON
$notifyCommand = $notifyCommand -replace '\\', '\\'
$activeCommand = $activeCommand -replace '\\', '\\'
$permissionCommand = $permissionCommand -replace '\\', '\\'

if (Test-Path $settingsPath) {
    Backup-File $settingsPath
    $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
} else {
    $settings = [PSCustomObject]@{}
}

# Ensure hooks object exists
if (-not ($settings | Get-Member -Name "hooks" -MemberType NoteProperty)) {
    $settings | Add-Member -NotePropertyName "hooks" -NotePropertyValue ([PSCustomObject]@{})
}

$hooksModified = $false

# Helper: check if a hook command already exists in a hook array
function Test-HookExists {
    param($HookArray, [string]$CommandSubstring)
    if (-not $HookArray) { return $false }
    foreach ($entry in $HookArray) {
        foreach ($h in $entry.hooks) {
            if ($h.command -and $h.command -like "*$CommandSubstring*") {
                return $true
            }
        }
    }
    return $false
}

# Stop hook
if (-not (Test-HookExists $settings.hooks.Stop "claude-notify.ps1")) {
    $stopHook = @(
        [PSCustomObject]@{
            matcher = ""
            hooks = @(
                [PSCustomObject]@{
                    type = "command"
                    command = ($notifyCommand -replace '\\\\', '\')
                }
            )
        }
    )
    if ($settings.hooks.Stop) {
        $settings.hooks.Stop = @($settings.hooks.Stop) + $stopHook
    } else {
        $settings.hooks | Add-Member -NotePropertyName "Stop" -NotePropertyValue $stopHook -Force
    }
    $hooksModified = $true
    Write-Done "Added Stop hook (notification on finish)"
} else {
    Write-Skip "Stop hook already configured"
}

# UserPromptSubmit hook
if (-not (Test-HookExists $settings.hooks.UserPromptSubmit "claude-tab-active.ps1")) {
    $submitHook = @(
        [PSCustomObject]@{
            matcher = ""
            hooks = @(
                [PSCustomObject]@{
                    type = "command"
                    command = ($activeCommand -replace '\\\\', '\')
                }
            )
        }
    )
    if ($settings.hooks.UserPromptSubmit) {
        $settings.hooks.UserPromptSubmit = @($settings.hooks.UserPromptSubmit) + $submitHook
    } else {
        $settings.hooks | Add-Member -NotePropertyName "UserPromptSubmit" -NotePropertyValue $submitHook -Force
    }
    $hooksModified = $true
    Write-Done "Added UserPromptSubmit hook (tab title reset)"
} else {
    Write-Skip "UserPromptSubmit hook already configured"
}

# Notification hook
if (-not (Test-HookExists $settings.hooks.Notification "claude-notify.ps1")) {
    $notifHook = @(
        [PSCustomObject]@{
            matcher = "permission_prompt"
            hooks = @(
                [PSCustomObject]@{
                    type = "command"
                    command = ($permissionCommand -replace '\\\\', '\')
                }
            )
        }
    )
    if ($settings.hooks.Notification) {
        $settings.hooks.Notification = @($settings.hooks.Notification) + $notifHook
    } else {
        $settings.hooks | Add-Member -NotePropertyName "Notification" -NotePropertyValue $notifHook -Force
    }
    $hooksModified = $true
    Write-Done "Added Notification hook (permission prompt)"
} else {
    Write-Skip "Notification hook already configured"
}

if ($hooksModified) {
    $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding UTF8
    Write-Done "Saved $settingsPath"
} else {
    Write-Info "No hook changes needed"
}

# ============================================================
# 4. Configure Windows Terminal - suppressApplicationTitle
# ============================================================
Write-Step "Configuring Windows Terminal"

$wtSettingsPaths = @(
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
    "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
)

$wtConfigured = $false
foreach ($wtPath in $wtSettingsPaths) {
    if (Test-Path $wtPath) {
        Backup-File $wtPath

        $wtContent = Get-Content $wtPath -Raw

        # Remove single-line comments for JSON parsing (Windows Terminal uses JSONC)
        $wtClean = $wtContent -replace '//[^\r\n]*', ''
        try {
            $wtSettings = $wtClean | ConvertFrom-Json
        } catch {
            Write-Host "    WARNING: Could not parse $wtPath - skipping" -ForegroundColor Yellow
            continue
        }

        # Ensure profiles.defaults exists
        if (-not ($wtSettings | Get-Member -Name "profiles" -MemberType NoteProperty)) {
            $wtSettings | Add-Member -NotePropertyName "profiles" -NotePropertyValue ([PSCustomObject]@{})
        }
        if (-not ($wtSettings.profiles | Get-Member -Name "defaults" -MemberType NoteProperty)) {
            $wtSettings.profiles | Add-Member -NotePropertyName "defaults" -NotePropertyValue ([PSCustomObject]@{})
        }

        $currentValue = $null
        if ($wtSettings.profiles.defaults | Get-Member -Name "suppressApplicationTitle" -MemberType NoteProperty) {
            $currentValue = $wtSettings.profiles.defaults.suppressApplicationTitle
        }

        if ($currentValue -eq $true) {
            Write-Skip "suppressApplicationTitle already set in $(Split-Path -Leaf $wtPath)"
        } else {
            if ($currentValue -eq $null) {
                $wtSettings.profiles.defaults | Add-Member -NotePropertyName "suppressApplicationTitle" -NotePropertyValue $true
            } else {
                $wtSettings.profiles.defaults.suppressApplicationTitle = $true
            }
            $wtSettings | ConvertTo-Json -Depth 10 | Set-Content $wtPath -Encoding UTF8
            Write-Done "Set suppressApplicationTitle = true in $(Split-Path -Leaf $wtPath)"
        }
        $wtConfigured = $true
        break
    }
}

if (-not $wtConfigured) {
    Write-Host "    WARNING: Windows Terminal settings.json not found. You may need to set suppressApplicationTitle manually." -ForegroundColor Yellow
}

# ============================================================
# 5. Add claude-tab function to PowerShell profile
# ============================================================
Write-Step "Adding claude-tab function to PowerShell profile"

$profilePath = $PROFILE.CurrentUserAllHosts
if (-not $profilePath) {
    $profilePath = $PROFILE
}

$functionBlock = @'

# claude-code-tab-notifications: Tab-aware Claude Code launcher
function claude-tab {
    param([Parameter(Position=0)][string]$Name)
    if ($Name) {
        $env:CLAUDE_TAB_NAME = $Name
        $bolt = [char]::ConvertFromUtf32(0x26A1)
        $host.UI.RawUI.WindowTitle = "$bolt $Name"
    }
    claude @args
}
'@

$functionMarker = "function claude-tab {"

if (Test-Path $profilePath) {
    $profileContent = Get-Content $profilePath -Raw
    if ($profileContent -match [regex]::Escape($functionMarker)) {
        Write-Skip "claude-tab function already in profile"
    } else {
        Backup-File $profilePath
        Add-Content -Path $profilePath -Value $functionBlock
        Write-Done "Added claude-tab function to $profilePath"
    }
} else {
    # Create the profile file
    $profileDir = Split-Path -Parent $profilePath
    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }
    Set-Content -Path $profilePath -Value $functionBlock
    Write-Done "Created profile with claude-tab function at $profilePath"
}

# ============================================================
# Summary
# ============================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Installation complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Scripts installed to: $claudeDir"
Write-Host "  Protocol handler:     claude-focus://"
Write-Host "  Claude hooks:         $settingsPath"
Write-Host "  PowerShell profile:   $profilePath"
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor White
Write-Host "    1. Restart Windows Terminal (or open a new tab)"
Write-Host "    2. Run: claude-tab MyProject"
Write-Host "    3. Switch to another tab and wait for Claude to finish"
Write-Host "    4. You'll get a notification - click it to jump back!"
Write-Host ""
Write-Host "  Backups saved to: $backupDir" -ForegroundColor Gray
Write-Host ""
