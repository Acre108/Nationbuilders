# Test tiers:
#   (no switch)  quick headless checks, a few seconds; run on every change
#   -Headless    every headless check, including whole-campaign saves and the hour-long run
#   -Full        every suite, one at a time, with a summary; run before committing or at milestones
# Single suites: -Sites, -View, -Campaign, -WorldMap, -GeneratedSites, -Forestry, -Art, -Buildings, -Environment.
# GPU suites open a window; run them one at a time.
param(
    [string]$Engine = 'C:\Program Files (x86)\Godot\Godot.exe',
    [switch]$Full,
    [switch]$Headless,
    [switch]$View,
    [switch]$Environment,
    [switch]$Art,
    [switch]$Buildings,
    [switch]$Forestry,
    [switch]$WorldMap,
    [switch]$Sites,
    [switch]$GeneratedSites,
    [switch]$Campaign
)
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath $Engine)) {
    throw "Godot was not found at $Engine. Supply -Engine with a Godot 4.7.2 executable."
}
$artifactDir = Join-Path $projectDir 'artifacts'
New-Item -ItemType Directory -Force -Path $artifactDir | Out-Null
$env:APPDATA = Join-Path $artifactDir 'godot-appdata'
New-Item -ItemType Directory -Force -Path $env:APPDATA | Out-Null

# Name -> script, log file, whether it runs headless, and extra user arguments.
$suites = [ordered]@{
    Quick          = @('tests/run_tests.gd', 'quick-tests.log', $true, @('--quick'))
    Headless       = @('tests/run_tests.gd', 'headless-tests.log', $true, @())
    Sites          = @('tests/run_site_gen_tests.gd', 'site-gen-tests.log', $true, @())
    View           = @('tests/run_view_tests.gd', 'view-tests.log', $false, @())
    Campaign       = @('tests/run_campaign_view_tests.gd', 'campaign-view-tests.log', $false, @())
    WorldMap       = @('tests/run_world_map_tests.gd', 'world-map-tests.log', $false, @())
    GeneratedSites = @('tests/run_generated_site_view_tests.gd', 'generated-site-view-tests.log', $false, @())
    Forestry       = @('tests/run_forestry_view_tests.gd', 'forestry-view-tests.log', $false, @())
    Art            = @('tests/run_art_tests.gd', 'art-tests.log', $false, @())
    Buildings      = @('tests/run_building_art_tests.gd', 'building-art-tests.log', $false, @())
    Environment    = @('tests/run_environment_tests.gd', 'environment-tests.log', $false, @())
}

function Invoke-Suite([string]$name) {
    $script, $log, $isHeadless, $userArgs = $suites[$name]
    $logFile = Join-Path $artifactDir $log
    $arguments = @('--path', ('"{0}"' -f $projectDir), '--log-file', ('"{0}"' -f $logFile), '--script', $script)
    if ($isHeadless) { $arguments = @('--headless') + $arguments }
    if ($userArgs.Count -gt 0) { $arguments += @('--') + $userArgs }
    $run = Start-Process -FilePath $Engine -ArgumentList $arguments -WorkingDirectory $projectDir -WindowStyle Hidden -PassThru -Wait
    return @{ Code = $run.ExitCode; Log = $logFile }
}

if ($Full) {
    $failed = 0
    foreach ($name in @($suites.Keys | Where-Object { $_ -ne 'Quick' })) {
        $clock = [Diagnostics.Stopwatch]::StartNew()
        $result = Invoke-Suite $name
        $summary = ''
        if (Test-Path -LiteralPath $result.Log) {
            $summary = Get-Content -LiteralPath $result.Log | Where-Object { $_ -match '\d+ checks, \d+ failures' } | Select-Object -Last 1
        }
        if ($result.Code -ne 0) { $failed += 1 }
        $status = if ($result.Code -eq 0) { 'ok  ' } else { 'FAIL' }
        '{0} {1,-15} {2,5:N0} s  {3}' -f $status, $name, $clock.Elapsed.TotalSeconds, $summary
    }
    if ($failed -gt 0) { "$failed suite(s) failed; logs are in $artifactDir" }
    exit $(if ($failed -gt 0) { 1 } else { 0 })
}

$selected = 'Quick'
foreach ($name in @($suites.Keys)) {
    if ($PSBoundParameters.ContainsKey($name)) { $selected = $name }
}
$result = Invoke-Suite $selected
if (Test-Path -LiteralPath $result.Log) { Get-Content -LiteralPath $result.Log }
exit $result.Code
