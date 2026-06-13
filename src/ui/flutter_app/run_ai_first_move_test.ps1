# AI hang smoke test (alias for the first-move hang scenario on native path).

param(
    [string]$Device = "windows"
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
& "$ScriptDir\run_ai_hang_test.ps1" -Device $Device
