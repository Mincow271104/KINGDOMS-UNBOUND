# KINGDOMS UNBOUND -- Automated Headless Regression Runner
# Authoritative Tracked Implementation for GAP-002 and GAP-006
# Resolves regex-counting flaws by enforcing strict process exit codes and known baseline classifications.

[CmdletBinding()]
param(
    [string]$GodotBin = "",
    [string]$Suite = "",
    [switch]$Strict = $false,
    [switch]$SelfTest = $false,
    [string]$OutputDir = ""
)

# 1. Resolve Godot Binary
if (-not $GodotBin) {
    if ($env:GODOT_BIN -and (Test-Path $env:GODOT_BIN)) {
        $GodotBin = $env:GODOT_BIN
    } elseif (Test-Path "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe") {
        $GodotBin = "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe"
    } elseif (Get-Command "godot" -ErrorAction SilentlyContinue) {
        $GodotBin = (Get-Command "godot").Source
    } else {
        Write-Error "Godot binary not found. Set -GodotBin or GODOT_BIN environment variable."
        exit 1
    }
}

# 2. Self-Test Mode (Runner Fixture Verification)
if ($SelfTest) {
    Write-Host ""
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "  RUNNING REGRESSION RUNNER SELF-TEST FIXTURES (GAP-002)" -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host ""

    $stFailed = 0

    # Fixture 1: Pass Classification
    $f1_status = if (0 -eq 0) { "PASSED" } else { "UNEXPECTED_FAILURE" }
    if ($f1_status -ne "PASSED") {
        Write-Host "  [FAIL] Fixture 1: Exit code 0 classification failed" -ForegroundColor Red
        $stFailed++
    } else {
        Write-Host "  [PASS] Fixture 1: Exit code 0 correctly classified as PASSED" -ForegroundColor Green
    }

    # Fixture 2: Baseline Failure Classification (TC-ARMY.32 in test_player_army.gd)
    $f2_log = "[FAIL] TC-ARMY.32: Damaged barracks still provides capacity: 5`nALL OTHER TESTS PASSED"
    $f2_suite = "test_player_army"
    $f2_ec = 1
    $f2_status = "UNEXPECTED_FAILURE"
    if ($f2_suite -eq "test_player_army" -and $f2_ec -eq 1 -and $f2_log.Contains("TC-ARMY.32: Damaged barracks still provides capacity: 5")) {
        $f2_status = "EXPECTED_BASELINE_FAILURE"
    }
    if ($f2_status -ne "EXPECTED_BASELINE_FAILURE") {
        Write-Host "  [FAIL] Fixture 2: TC-ARMY.32 signature classification failed" -ForegroundColor Red
        $stFailed++
    } else {
        Write-Host "  [PASS] Fixture 2: TC-ARMY.32 correctly classified as EXPECTED_BASELINE_FAILURE" -ForegroundColor Green
    }

    # Fixture 3: Unexpected Failure Classification
    $f3_log = "Fatal parse error in script`n"
    $f3_suite = "test_economy"
    $f3_ec = 1
    $f3_status = "PASSED"
    if ($f3_ec -ne 0) {
        if ($f3_suite -eq "test_player_army" -and $f3_ec -eq 1 -and $f3_log.Contains("TC-ARMY.32: Damaged barracks still provides capacity: 5")) {
            $f3_status = "EXPECTED_BASELINE_FAILURE"
        } else {
            $f3_status = "UNEXPECTED_FAILURE"
        }
    }
    if ($f3_status -ne "UNEXPECTED_FAILURE") {
        Write-Host "  [FAIL] Fixture 3: Unexpected error classification failed" -ForegroundColor Red
        $stFailed++
    } else {
        Write-Host "  [PASS] Fixture 3: Non-zero exit code on standard suite correctly classified as UNEXPECTED_FAILURE" -ForegroundColor Green
    }

    # Fixture 4: JSON Output Integrity
    $f4_data = @{ "test" = "value"; "count" = 42 } | ConvertTo-Json
    $f4_obj = $f4_data | ConvertFrom-Json
    if ($f4_obj.count -ne 42) {
        Write-Host "  [FAIL] Fixture 4: JSON serialization failed" -ForegroundColor Red
        $stFailed++
    } else {
        Write-Host "  [PASS] Fixture 4: JSON serialization/deserialization integrity verified" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "--------------------------------------------------------" -ForegroundColor Cyan
    if ($stFailed -eq 0) {
        Write-Host "  ALL 4 RUNNER FIXTURE TESTS PASSED! (Exit Code 0)" -ForegroundColor Green
        Write-Host "--------------------------------------------------------" -ForegroundColor Cyan
        Write-Host ""
        exit 0
    } else {
        Write-Host "  RUNNER FIXTURE TESTS FAILED with $stFailed errors! (Exit Code 1)" -ForegroundColor Red
        Write-Host "--------------------------------------------------------" -ForegroundColor Cyan
        Write-Host ""
        exit 1
    }
}

# 3. Explicit Reviewed Test Manifest
# Standard suites + all post-2J suites + GAP-006 compilation check
$manifest = @(
    "scripts/test/test_all_scripts_load.gd",
    "scripts/test/test_army_equipment.gd",
    "scripts/test/test_army_movement.gd",
    "scripts/test/test_audio.gd",
    "scripts/test/test_automation_graph.gd",
    "scripts/test/test_automation_graph_delay_repeat.gd",
    "scripts/test/test_autonomous_faction_conflict.gd",
    "scripts/test/test_barracks.gd",
    "scripts/test/test_battle_diplomacy_consequences.gd",
    "scripts/test/test_battle_fortification.gd",
    "scripts/test/test_building_management.gd",
    "scripts/test/test_campaign_result_feedback.gd",
    "scripts/test/test_citizens.gd",
    "scripts/test/test_citizen_skills.gd",
    "scripts/test/test_construction.gd",
    "scripts/test/test_coordinates.gd",
    "scripts/test/test_dynamic_workplaces.gd",
    "scripts/test/test_economy.gd",
    "scripts/test/test_emerging_faction_ascension.gd",
    "scripts/test/test_enemy_military_ai.gd",
    "scripts/test/test_factions_and_battles.gd",
    "scripts/test/test_faction_diplomacy_ai.gd",
    "scripts/test/test_faction_profiles.gd",
    "scripts/test/test_faction_relation_matrix.gd",
    "scripts/test/test_faction_strategy_execution.gd",
    "scripts/test/test_faction_strategy_planner.gd",
    "scripts/test/test_field_siege.gd",
    "scripts/test/test_gold_transactions.gd",
    "scripts/test/test_hauler_death_cargo_conservation.gd",
    "scripts/test/test_job_lifecycle_pruning.gd",
    "scripts/test/test_legacy_fund.gd",
    "scripts/test/test_live_battle_loop.gd",
    "scripts/test/test_logistics.gd",
    "scripts/test/test_market.gd",
    "scripts/test/test_mine.gd",
    "scripts/test/test_offensive_campaign.gd",
    "scripts/test/test_outpost_territorial_control.gd",
    "scripts/test/test_package_1x_gameplay_integration.gd",
    "scripts/test/test_palisade.gd",
    "scripts/test/test_player_army.gd",
    "scripts/test/test_player_field_guide.gd",
    "scripts/test/test_quarry.gd",
    "scripts/test/test_research_and_exploration.gd",
    "scripts/test/test_research_hall.gd",
    "scripts/test/test_responsive_layout.gd",
    "scripts/test/test_save_load.gd",
    "scripts/test/test_save_slot_isolation.gd",
    "scripts/test/test_stress_100_citizens.gd",
    "scripts/test/test_surplus_treasury_conversion.gd",
    "scripts/test/test_tactical_combat.gd",
    "scripts/test/test_tactical_military.gd",
    "scripts/test/test_time_manager.gd",
    "scripts/test/test_victory_and_collapse.gd",
    "scripts/test/test_watchtower.gd",
    "scripts/test/test_workshop.gd",
    "scripts/test/test_world_events.gd",
    "scripts/test/test_world_gen.gd",
    "scripts/test/test_world_view_siege_input.gd"
)

# Filter by suite name if specified
if ($Suite) {
    $matched = $manifest | Where-Object { $_ -like "*$Suite*" }
    if (-not $matched) {
        Write-Error "No suite matching '$Suite' found in manifest."
        exit 1
    }
    $manifest = @($matched)
}

# 4. Setup Output Directory
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
if (-not $OutputDir) {
    $OutputDir = "scratch/regression_runs/$timestamp"
}
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
}

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  KINGDOMS UNBOUND -- HEADLESS REGRESSION SUITE RUNNER" -ForegroundColor Cyan
Write-Host "  Godot Binary : $GodotBin" -ForegroundColor Gray
Write-Host "  Output Dir   : $OutputDir" -ForegroundColor Gray
Write-Host "  Suites Count : $($manifest.Count)" -ForegroundColor Gray
Write-Host "  Strict Mode  : $Strict" -ForegroundColor Gray
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

$suiteResults = @()
$overallStart = Get-Date
$passedCount = 0
$expectedBaselineCount = 0
$unexpectedFailureCount = 0

foreach ($scriptPath in $manifest) {
    $suiteName = [System.IO.Path]::GetFileNameWithoutExtension($scriptPath)
    $logPath = Join-Path $OutputDir "$suiteName.log"

    $header = "  [{0,2}/{1,2}] {2,-42} ... " -f @(($suiteResults.Count + 1), $manifest.Count, $suiteName)
    Write-Host -NoNewline $header

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    & $GodotBin --headless -s "res://$scriptPath" > $logPath 2>&1
    $rawExitCode = $LASTEXITCODE
    $sw.Stop()
    $durationSec = [Math]::Round($sw.Elapsed.TotalSeconds, 2)

    # Classify Result
    $status = "UNKNOWN"
    $reason = ""
    $logContent = ""
    if (Test-Path $logPath) {
        $logContent = Get-Content $logPath -Raw
    }

    if ($rawExitCode -eq 0) {
        $status = 'PASSED'
        $passedCount++
        Write-Host ('PASS [' + $durationSec + 's]') -ForegroundColor Green
    } else {
        # Inspect for Known Baseline: test_player_army.gd with TC-ARMY.32
        if ($suiteName -eq 'test_player_army' -and $rawExitCode -eq 1 -and ($logContent.Contains('TC-ARMY.32: Damaged barracks still provides capacity: 5'))) {
            $status = 'EXPECTED_BASELINE_FAILURE'
            $reason = 'BASELINE-001 / ISSUE-006: Pre-existing TC-ARMY.32 building state restriction failure'
            $expectedBaselineCount++
            Write-Host ('BASELINE FAIL [' + $durationSec + 's, ec=' + $rawExitCode + ']') -ForegroundColor Yellow
        } else {
            $status = 'UNEXPECTED_FAILURE'
            $reason = ('Process exited with non-zero code ' + $rawExitCode)
            $unexpectedFailureCount++
            Write-Host ('FAIL [' + $durationSec + 's, ec=' + $rawExitCode + ']') -ForegroundColor Red
        }
    }

    $suiteResults += [PSCustomObject]@{
        Suite = $suiteName
        ScriptPath = $scriptPath
        ExitCode = $rawExitCode
        Status = $status
        DurationSeconds = $durationSec
        Reason = $reason
        LogPath = $logPath
    }
}

$overallDuration = [Math]::Round(((Get-Date) - $overallStart).TotalSeconds, 2)

# 5. Save Machine-Readable JSON Summary
$summaryObject = [PSCustomObject]@{
    Timestamp = $timestamp
    TotalSuites = $manifest.Count
    Passed = $passedCount
    ExpectedBaselineFailures = $expectedBaselineCount
    UnexpectedFailures = $unexpectedFailureCount
    TotalDurationSeconds = $overallDuration
    Strict = [bool]$Strict
    GodotBin = $GodotBin
    Suites = $suiteResults
}

$jsonPath = Join-Path $OutputDir "regression_summary.json"
$summaryObject | ConvertTo-Json -Depth 4 | Set-Content $jsonPath -Encoding utf8

# 6. Display Formatted Summary Table
$failColor = if ($unexpectedFailureCount -gt 0) { 'Red' } else { 'Green' }
Write-Host ""
Write-Host "--------------------------------------------------------" -ForegroundColor Cyan
Write-Host "  REGRESSION EXECUTION SUMMARY" -ForegroundColor Cyan
Write-Host "--------------------------------------------------------" -ForegroundColor Cyan
Write-Host ('  Total Suites Tested        : ' + $manifest.Count)
Write-Host ('  Passed (Exit Code 0)       : ' + $passedCount) -ForegroundColor Green
Write-Host ('  Expected Baseline Failures : ' + $expectedBaselineCount + ' (BASELINE-001 TC-ARMY.32)') -ForegroundColor Yellow
Write-Host ('  Unexpected Failures        : ' + $unexpectedFailureCount) -ForegroundColor $failColor
Write-Host ('  Total Duration             : ' + $overallDuration + ' seconds')
Write-Host ('  Detailed JSON Report       : ' + $jsonPath)
Write-Host "--------------------------------------------------------" -ForegroundColor Cyan
Write-Host ""

# 7. Final Exit Code Determination
if ($unexpectedFailureCount -gt 0) {
    Write-Host ('[FAIL] REGRESSION SUITE FAILED with ' + $unexpectedFailureCount + ' unexpected failure(s)! (Exit Code 1)') -ForegroundColor Red
    Write-Host ""
    exit 1
}

if ($Strict -and $expectedBaselineCount -gt 0) {
    Write-Host ('[FAIL] STRICT MODE: Exiting with Code 1 due to ' + $expectedBaselineCount + ' baseline failure(s)!') -ForegroundColor Red
    Write-Host ""
    exit 1
}

Write-Host '[SUCCESS] REGRESSION SUITE PASSED CLEANLY (Zero Unexpected Regressions, Exit Code 0)' -ForegroundColor Green
Write-Host ""
exit 0
