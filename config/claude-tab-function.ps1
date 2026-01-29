# Add this function to your PowerShell profile ($PROFILE).
# It wraps the claude CLI with tab naming and title lifecycle support.
#
# Usage:
#   claude-tab MyProject          # Start Claude with tab name "MyProject"
#   claude-tab MyProject --model opus  # Pass extra args to claude
#
function claude-tab {
    param([Parameter(Position=0)][string]$Name)
    if ($Name) {
        $env:CLAUDE_TAB_NAME = $Name
        $host.UI.RawUI.WindowTitle = "⚡ $Name"
    }
    claude @args
}
