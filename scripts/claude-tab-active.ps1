param(
    [string]$TabHint = $env:CLAUDE_TAB_NAME
)

# Reset tab title to active state when the user submits a prompt
if ($TabHint) {
    try { [Console]::Title = "⚡ $TabHint" } catch {}
}
