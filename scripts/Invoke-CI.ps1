# Autor: Cristofer Altamirano
[CmdletBinding()]
param([string]$Maven = 'mvn', [string]$Revision = '1.1.0', [string]$MavenRepository = '')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
    New-Item -ItemType Directory -Path 'evidence' -Force | Out-Null
    $log = Join-Path $root 'evidence/ci.log'
    "Autor: Cristofer Altamirano`nInicio UTC: $([DateTime]::UtcNow.ToString('o'))" | Set-Content $log -Encoding utf8
    $common = @('-B', '-ntp', "-Drevision=$Revision")
    if ($MavenRepository) { $common += "-Dmaven.repo.local=$MavenRepository" }
    $stages = @(
        @{ Name = 'BUILD'; Goals = @('clean', 'compile') },
        @{ Name = 'UNIT TESTS'; Goals = @('test') },
        @{ Name = 'INTEGRATION TESTS'; Goals = @('failsafe:integration-test', 'failsafe:verify') },
        @{ Name = 'PACKAGE'; Goals = @('-DskipTests', 'package') }
    )
    foreach ($stage in $stages) {
        $message = "STAGE $($stage.Name) | $([DateTime]::UtcNow.ToString('o'))"
        Write-Host $message; Add-Content $log $message -Encoding utf8
        & $Maven @common @($stage.Goals) 2>&1 | Tee-Object -FilePath $log -Append | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Fallo en $($stage.Name), codigo $LASTEXITCODE" }
        Add-Content $log "STAGE $($stage.Name) SUCCESS" -Encoding utf8
    }
    $unit = [xml](Get-Content 'target/surefire-reports/TEST-cl.cristoferaltamirano.QuoteServiceTest.xml' -Raw)
    $integration = [xml](Get-Content 'target/failsafe-reports/TEST-cl.cristoferaltamirano.ApiIT.xml' -Raw)
    $summary = "CI SUCCESS | unit=$($unit.testsuite.tests) integration=$($integration.testsuite.tests) | failures=$([int]$unit.testsuite.failures + [int]$integration.testsuite.failures) errors=$([int]$unit.testsuite.errors + [int]$integration.testsuite.errors)"
    Write-Host $summary; Add-Content $log $summary -Encoding utf8
    Copy-Item 'target/surefire-reports/*.txt' 'evidence/' -Force
    Copy-Item 'target/failsafe-reports/*.txt' 'evidence/' -Force
} finally { Pop-Location }
