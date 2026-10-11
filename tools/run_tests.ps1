param(
    [string]$Engine = 'C:\Program Files (x86)\Godot\Godot.exe',
    [switch]$View,
    [switch]$Environment,
    [switch]$Art,
    [switch]$Buildings,
    [switch]$Forestry,
    [switch]$WorldMap,
    [switch]$Campaign
)
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath $Engine)) {
    throw "Godot was not found at $Engine. Supply -Engine with a Godot 4.3+ executable."
}
$artifactDir = Join-Path $projectDir 'artifacts'
New-Item -ItemType Directory -Force -Path $artifactDir | Out-Null
$env:APPDATA = Join-Path $artifactDir 'godot-appdata'
New-Item -ItemType Directory -Force -Path $env:APPDATA | Out-Null
$testScript = if ($WorldMap) { 'tests/run_world_map_tests.gd' } elseif ($Campaign) { 'tests/run_campaign_view_tests.gd' } elseif ($Forestry) { 'tests/run_forestry_view_tests.gd' } elseif ($Buildings) { 'tests/run_building_art_tests.gd' } elseif ($Art) { 'tests/run_art_tests.gd' } elseif ($Environment) { 'tests/run_environment_tests.gd' } elseif ($View) { 'tests/run_view_tests.gd' } else { 'tests/run_tests.gd' }
$logFile = Join-Path $artifactDir $(if ($WorldMap) { 'world-map-tests.log' } elseif ($Campaign) { 'campaign-view-tests.log' } elseif ($Forestry) { 'forestry-view-tests.log' } elseif ($Buildings) { 'building-art-tests.log' } elseif ($Art) { 'art-tests.log' } elseif ($Environment) { 'environment-tests.log' } elseif ($View) { 'view-tests.log' } else { 'headless-tests.log' })
$godotArguments = @('--path', ('"{0}"' -f $projectDir), '--log-file', ('"{0}"' -f $logFile), '--script', $testScript)
if (-not ($View -or $Environment -or $Art -or $Buildings -or $Forestry -or $Campaign -or $WorldMap)) { $godotArguments = @('--headless') + $godotArguments }
$godotRun = Start-Process -FilePath $Engine -ArgumentList $godotArguments -WorkingDirectory $projectDir -WindowStyle Hidden -PassThru -Wait
if (Test-Path -LiteralPath $logFile) { Get-Content -LiteralPath $logFile }
exit $godotRun.ExitCode
