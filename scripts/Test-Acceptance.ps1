# Autor: Cristofer Altamirano. Valida el JAR desplegado por HTTP desde otro proceso.
[CmdletBinding()]
param([string]$BaseUrl = 'http://127.0.0.1:18080', [Parameter(Mandatory)][string]$ExpectedVersion)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http
$client = New-Object System.Net.Http.HttpClient
$client.Timeout = [TimeSpan]::FromSeconds(5)
function Check([string]$Name, [string]$Path, [int]$Status, [scriptblock]$BodyCheck) {
    $response = $client.GetAsync("$BaseUrl$Path").GetAwaiter().GetResult()
    try {
        $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
        if ([int]$response.StatusCode -ne $Status -or -not (& $BodyCheck $body)) { throw "FAIL $Name" }
        Write-Host "PASS $Name | HTTP $Status"
    } finally { $response.Dispose() }
}
try {
    Check 'A01 disponibilidad' '/health' 200 { param($b) $b.status -eq 'UP' }
    Check 'A02 version desplegada' '/version' 200 { param($b) $b.version -eq $ExpectedVersion }
    Check 'A03 cotizacion con descuento' '/quote?price=1000&quantity=2&discount=0.1' 200 { param($b) $b.total -eq 2142 -and $b.currency -eq 'CLP' }
    Check 'A04 cotizacion sin descuento' '/quote?price=1000&quantity=1' 200 { param($b) $b.total -eq 1190 }
    Check 'A05 rechazo de cantidad invalida' '/quote?price=1000&quantity=0' 400 { param($b) $b.error -eq 'invalid_parameters' }
    Check 'A06 ruta inexistente' '/missing' 404 { param($b) $b.error -eq 'not_found' }
    Write-Host "ACCEPTANCE SUCCESS | 6/6 | version=$ExpectedVersion | $BaseUrl"
} finally { $client.Dispose() }
