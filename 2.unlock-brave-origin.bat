@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$c = (Get-Content '%~f0' -Raw) -split '::PS_PAYLOAD::' | Select-Object -Last 1; Invoke-Command -ScriptBlock ([scriptblock]::Create($c)) -ArgumentList '%~dp0'"
pause
exit /b

::PS_PAYLOAD::
param([string]$baseDir)
$ErrorActionPreference = "Stop"

$ini = Join-Path $baseDir "chrome++.ini"
if (!(Test-Path $ini)) { Write-Host "Error: chrome++.ini not found" -ForegroundColor Red; exit }

$line = Get-Content $ini | Where-Object { $_ -match "^\s*data_dir\s*=" } | Select-Object -First 1
if (!$line) { Write-Host "Error: data_dir not found in ini" -ForegroundColor Red; exit }

$val = $line.Split('=', 2)[1].Trim().Trim('"').Replace("%app%", $baseDir.TrimEnd('\'))
$dataDir = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($baseDir, $val))
$localStatePath = Join-Path $dataDir "Local State"

if (!(Test-Path $dataDir)) { New-Item -ItemType Directory -Force -Path $dataDir | Out-Null }

Get-Process brave -ErrorAction SilentlyContinue | Stop-Process -Force

if (!(Test-Path $localStatePath)) { 
    $json = [pscustomobject]@{} 
} else {
    $raw = Get-Content $localStatePath -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { $json = [pscustomobject]@{} } else { $json = $raw | ConvertFrom-Json }
}

if ($json.PSObject.Properties['brave'] -and $json.brave.PSObject.Properties['origin'] -and $json.brave.origin.purchase_validated -eq $true) {
    Write-Host "Local State file has already been patched!" -ForegroundColor Yellow
    exit
}

function E($o, $p) { if (!$o.PSObject.Properties[$p]) { $o | Add-Member -NotePropertyName $p -NotePropertyValue ([pscustomobject]@{}) }; return $o.$p }

$origin = E (E $json "brave") "origin"
$origin | Add-Member -NotePropertyName purchase_validated -NotePropertyValue $true -Force
$origin | Add-Member -NotePropertyName policies_were_enforced -NotePropertyValue $true -Force

$credStr = '{"credentials":{"items":{"origin-local-unlock":{"remaining_credential_count":1,"expires_at":"2999-12-31T23:59:59Z"}}}}'

$state = E (E $json "skus") "state"
$state | Add-Member -NotePropertyName development -NotePropertyValue $credStr -Force
$state | Add-Member -NotePropertyName staging -NotePropertyValue $credStr -Force
$state | Add-Member -NotePropertyName production -NotePropertyValue $credStr -Force

$outJson = $json | ConvertTo-Json -Depth 80 -Compress
[IO.File]::WriteAllText($localStatePath, $outJson, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Successfully patched Local State at: $localStatePath" -ForegroundColor Green