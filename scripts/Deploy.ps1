# Autor: Cristofer Altamirano. Despliegue por artefactos y rollback verificado.
[CmdletBinding()]
param(
    [ValidateSet('Deploy','Rollback','Status','Stop')][string]$Action = 'Deploy',
    [string]$Artifact, [string]$Version,
    [int]$Port = 18080, [int]$CandidatePort = 18081,
    [string]$RuntimeDirectory = '', [switch]$SimulateFailure
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (-not $RuntimeDirectory) { $RuntimeDirectory = Join-Path $root 'runtime/staging' }
$runtime = [IO.Path]::GetFullPath($RuntimeDirectory)
New-Item -ItemType Directory -Path $runtime -Force | Out-Null
$stateFile = Join-Path $runtime 'state.json'
$pidFile = Join-Path $runtime 'process.json'
$log = Join-Path $runtime 'deployment.log'
Add-Type -AssemblyName System.Net.Http
$client = New-Object System.Net.Http.HttpClient
$client.Timeout = [TimeSpan]::FromSeconds(2)
function Log([string]$Message) {
    $line = "$([DateTime]::UtcNow.ToString('o')) | $Message"
    Write-Host $line; Add-Content $log $line -Encoding utf8
}
function Read-State {
    if (Test-Path -LiteralPath $stateFile) { return Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json }
    return [pscustomobject]@{ current = $null; previous = $null; author = 'Cristofer Altamirano' }
}
function Save-State($State) { $State | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $stateFile -Encoding utf8 }
function Start-App([string]$Jar, [int]$ListenPort, [string]$Label) {
    # Usa la JVM real para registrar y detener su PID, evitando launchers de Oracle.
    $javaSettings = (& java -XshowSettings:properties -version 2>&1 | Out-String)
    $javaHomeMatch = [regex]::Match($javaSettings, 'java.home\s*=\s*(.+)')
    if (-not $javaHomeMatch.Success) { throw 'No se pudo resolver java.home' }
    $javaPath = Join-Path $javaHomeMatch.Groups[1].Value.Trim() 'bin/java.exe'
    $parameters = @{ FilePath = $javaPath; ArgumentList = @('-jar', "`"$Jar`"", "$ListenPort"); PassThru = $true;
        RedirectStandardOutput = (Join-Path $runtime "$Label.stdout.log"); RedirectStandardError = (Join-Path $runtime "$Label.stderr.log") }
    if ($env:OS -eq 'Windows_NT') { $parameters.WindowStyle = 'Hidden' }
    return Start-Process @parameters
}
function Stop-Tracked {
    if (Test-Path -LiteralPath $pidFile) {
        $record = Get-Content -LiteralPath $pidFile -Raw | ConvertFrom-Json
        $process = Get-Process -Id $record.pid -ErrorAction SilentlyContinue
        if ($process) {
            if ($process.StartTime.ToUniversalTime().Ticks.ToString() -ne $record.startedTicks) { throw 'PID reutilizado; no se detuvo un proceso ajeno' }
            Stop-Process -Id $record.pid -Force
            $process.WaitForExit(5000) | Out-Null
        }
        Remove-Item -LiteralPath $pidFile -Force
    }
}
function Wait-Healthy([int]$ListenPort, [string]$ExpectedVersion) {
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        try {
            $response = $client.GetAsync("http://127.0.0.1:$ListenPort/version").GetAwaiter().GetResult()
            try {
                $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
                if ($response.IsSuccessStatusCode -and $body.version -eq $ExpectedVersion) { return }
            } finally { $response.Dispose() }
        } catch { }
        Start-Sleep -Milliseconds 250
    }
    throw "Servicio no disponible o version inesperada en puerto $ListenPort"
}
function Activate($Release) {
    Stop-Tracked
    $process = Start-App $Release.path $Port 'active'
    @{ pid = $process.Id; startedTicks = $process.StartTime.ToUniversalTime().Ticks.ToString(); author = 'Cristofer Altamirano' } |
        ConvertTo-Json | Set-Content -LiteralPath $pidFile -Encoding utf8
    Wait-Healthy $Port $Release.version
}
$candidateProcess = $null
try {
    $state = Read-State
    switch ($Action) {
        'Status' {
            if (-not $state.current) { throw 'No existe despliegue activo' }
            Wait-Healthy $Port $state.current.version
            Log "STATUS UP version=$($state.current.version) sha256=$($state.current.sha256) port=$Port"
        }
        'Stop' { Stop-Tracked; Log 'STOP SUCCESS' }
        'Rollback' {
            if (-not $state.previous) { throw 'No existe una version anterior para rollback' }
            if ((Get-FileHash -LiteralPath $state.previous.path -Algorithm SHA256).Hash -ne $state.previous.sha256) { throw 'Hash del artefacto anterior alterado' }
            $oldCurrent = $state.current
            Activate $state.previous
            & "$PSScriptRoot/Test-Acceptance.ps1" -BaseUrl "http://127.0.0.1:$Port" -ExpectedVersion $state.previous.version
            $state.current = $state.previous; $state.previous = $oldCurrent; Save-State $state
            Log "ROLLBACK SUCCESS version=$($state.current.version) sha256=$($state.current.sha256) port=$Port"
        }
        'Deploy' {
            if (-not $Artifact -or $Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Indique Artifact y Version en formato X.Y.Z' }
            if ($Port -eq $CandidatePort) { throw 'El puerto candidato debe ser diferente del activo' }
            $artifactPath = (Resolve-Path -LiteralPath $Artifact).Path
            $hash = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash
            $releaseDirectory = Join-Path $runtime 'releases'
            New-Item -ItemType Directory -Path $releaseDirectory -Force | Out-Null
            $releasePath = Join-Path $releaseDirectory "cotizador-$Version-$hash.jar"
            Copy-Item -LiteralPath $artifactPath -Destination $releasePath -Force
            $release = [pscustomobject]@{ path = $releasePath; version = $Version; sha256 = $hash }
            Log "STAGE ACCEPTANCE candidate=$Version port=$CandidatePort"
            $candidateProcess = Start-App $release.path $CandidatePort 'candidate'
            Wait-Healthy $CandidatePort $Version
            & "$PSScriptRoot/Test-Acceptance.ps1" -BaseUrl "http://127.0.0.1:$CandidatePort" -ExpectedVersion $Version
            Stop-Process -Id $candidateProcess.Id -Force; $candidateProcess.WaitForExit(5000) | Out-Null; $candidateProcess = $null
            Log "STAGE DEPLOY staging version=$Version sha256=$hash port=$Port"
            $previous = $state.current
            try {
                Activate $release
                & "$PSScriptRoot/Test-Acceptance.ps1" -BaseUrl "http://127.0.0.1:$Port" -ExpectedVersion $Version
                if ($SimulateFailure) { throw 'Incidente controlado despues del despliegue' }
                $state.previous = $previous; $state.current = $release; Save-State $state
                Log "DEPLOY SUCCESS version=$Version sha256=$hash port=$Port"
            } catch {
                Log "DEPLOY FAILED reason=$($_.Exception.Message)"
                if ($previous) {
                    if ((Get-FileHash -LiteralPath $previous.path -Algorithm SHA256).Hash -ne $previous.sha256) { throw 'Hash previo alterado; rollback abortado' }
                    Activate $previous
                    & "$PSScriptRoot/Test-Acceptance.ps1" -BaseUrl "http://127.0.0.1:$Port" -ExpectedVersion $previous.version
                    Log "AUTOMATIC ROLLBACK SUCCESS version=$($previous.version) sha256=$($previous.sha256) port=$Port"
                } else { Stop-Tracked }
                throw
            }
        }
    }
} finally {
    if ($candidateProcess -and -not $candidateProcess.HasExited) { Stop-Process -Id $candidateProcess.Id -Force }
    $client.Dispose()
}
