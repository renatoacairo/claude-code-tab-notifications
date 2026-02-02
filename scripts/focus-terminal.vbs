Set shell = CreateObject("WScript.Shell")
' Get the protocol URL argument (e.g., claude-focus://TabName)
Dim protocolUrl
If WScript.Arguments.Count > 0 Then
    protocolUrl = WScript.Arguments(0)
Else
    protocolUrl = ""
End If
shell.Run "conhost.exe --headless powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & shell.ExpandEnvironmentStrings("%USERPROFILE%") & "\.claude\focus-terminal.ps1"" -ProtocolUrl """ & protocolUrl & """", 0, False
