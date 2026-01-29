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
