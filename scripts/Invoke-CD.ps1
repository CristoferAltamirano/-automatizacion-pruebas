# Autor: Cristofer Altamirano. Escenario reproducible de despliegue y recuperacion.
[CmdletBinding()]
param([string]$Maven = 'mvn', [string]$MavenRepository = '')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$runtime = Join-Path $root "runtime/demo-$([guid]::NewGuid().ToString('N'))"
Push-Location $root
New-Item -ItemType Directory -Path 'evidence','artifacts' -Force | Out-Null
$transcript = Join-Path $root 'evidence/cd.log'
Start-Transcript -LiteralPath $transcript -Force | Out-Null
try {
    Write-Host 'Autor: Cristofer Altamirano'
    $common = @('-B','-ntp','-DskipTests')
    if ($MavenRepository) { $common += "-Dmaven.repo.local=$MavenRepository" }
    foreach ($version in @('1.0.0','1.1.0')) {
        Write-Host "STAGE BUILD RELEASE $version"
        & $Maven @common "-Drevision=$version" package 2>&1 | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Error construyendo $version" }
        Copy-Item -LiteralPath "target/cotizador-$version.jar" -Destination "artifacts/cotizador-$version.jar" -Force
    }
    & "$PSScriptRoot/Deploy.ps1" -Action Deploy -Artifact 'artifacts/cotizador-1.0.0.jar' -Version '1.0.0' -RuntimeDirectory $runtime
    & "$PSScriptRoot/Deploy.ps1" -Action Deploy -Artifact 'artifacts/cotizador-1.1.0.jar' -Version '1.1.0' -RuntimeDirectory $runtime
    & "$PSScriptRoot/Deploy.ps1" -Action Status -RuntimeDirectory $runtime
    & "$PSScriptRoot/Deploy.ps1" -Action Rollback -RuntimeDirectory $runtime
    & "$PSScriptRoot/Deploy.ps1" -Action Status -RuntimeDirectory $runtime
    $caughtExpectedFailure = $false
    try {
        & "$PSScriptRoot/Deploy.ps1" -Action Deploy -Artifact 'artifacts/cotizador-1.1.0.jar' -Version '1.1.0' -RuntimeDirectory $runtime -SimulateFailure
    } catch {
        if ($_.Exception.Message -notlike '*Incidente controlado*') { throw }
        $caughtExpectedFailure = $true
        Write-Host 'EXPECTED INCIDENT DETECTED; recovery checked next'
    }
    if (-not $caughtExpectedFailure) { throw 'El incidente controlado no se detecto' }
    & "$PSScriptRoot/Deploy.ps1" -Action Status -RuntimeDirectory $runtime
    $state = Get-Content -LiteralPath (Join-Path $runtime 'state.json') -Raw | ConvertFrom-Json
    $baselineHash = (Get-FileHash 'artifacts/cotizador-1.0.0.jar' -Algorithm SHA256).Hash
    if ($state.current.version -ne '1.0.0' -or $state.current.sha256 -ne $baselineHash) { throw 'Rollback no recupero el artefacto original' }
    @{ author = 'Cristofer Altamirano'; executedUtc = [DateTime]::UtcNow.ToString('o');
        baseline = '1.0.0'; candidate = '1.1.0'; restored = $state.current.version;
        baselineSha256 = $baselineHash; candidateSha256 = (Get-FileHash 'artifacts/cotizador-1.1.0.jar' -Algorithm SHA256).Hash;
        manualRollback = 'SUCCESS'; automaticRollback = 'SUCCESS'; acceptanceCasesPerRun = 6;
        staging = 'http://127.0.0.1:18080'; environment = 'laboratorio local temporal' } |
        ConvertTo-Json | Set-Content 'evidence/deployment-summary.json' -Encoding utf8
    Write-Host 'CD SUCCESS | deploy=1.1.0 manualRollback=1.0.0 automaticRollback=1.0.0 hashVerified=true'
} finally {
    try { & "$PSScriptRoot/Deploy.ps1" -Action Stop -RuntimeDirectory $runtime } finally {
        if (Test-Path -LiteralPath (Join-Path $runtime 'deployment.log')) { Copy-Item -LiteralPath (Join-Path $runtime 'deployment.log') 'evidence/deployment.log' -Force }
        Stop-Transcript | Out-Null; Pop-Location
    }
}
