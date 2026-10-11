param(
    [string]$Engine = 'C:\Program Files (x86)\Godot\Godot.exe',
    [switch]$View
)
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath $Engine)) {
    throw "Godot was not found at $Engine. Supply -Engine with a Godot 4.3+ executable."
}
$artifactDir = Join-Path $projectDir 'artifacts'
New-Item -ItemType Directory -Force -Path $artifactDir | Out-Null
$testScript = if ($View) { 'tests/run_view_tests.gd' } else { 'tests/run_tests.gd' }
$logFile = Join-Path $artifactDir $(if ($View) { 'view-tests.log' } else { 'headless-tests.log' })
$godotArguments = @('--path', ('"{0}"' -f $projectDir), '--log-file', ('"{0}"' -f $logFile), '--script', $testScript)
if (-not $View) { $godotArguments = @('--headless') + $godotArguments }
$godotRun = Start-Process -FilePath $Engine -ArgumentList $godotArguments -WorkingDirectory $projectDir -WindowStyle Hidden -PassThru -Wait
if (Test-Path -LiteralPath $logFile) { Get-Content -LiteralPath $logFile }
exit $godotRun.ExitCode
