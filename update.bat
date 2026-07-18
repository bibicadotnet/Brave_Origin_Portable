@echo off
setlocal enabledelayedexpansion

if "%~1"=="/afterupdate" goto :RUN_PAYLOAD

:: ============================================================
:: STEP 0: SELF-UPDATE (download the latest update.bat and
:: re-launch it BEFORE doing anything else)
:: NOTE: written with plain GOTO (no nested parentheses blocks),
:: because jumping in/out of "IF (...) ELSE (...)" blocks near a
:: label is unreliable in cmd.exe and can cause the rest of the
:: file to be skipped.
:: ============================================================
set "TMPBAT=%TEMP%\update_new_%RANDOM%.bat"
echo Checking for a newer version of update.bat...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "try { (New-Object Net.WebClient).DownloadFile('https://raw.githubusercontent.com/bibicadotnet/Brave_Origin_Portable/main/update.bat', '%TMPBAT%') } catch { }"

if exist "%TMPBAT%" goto :CHECK_DIFF
echo Could not download the latest update.bat, continuing with the current version.
goto :RUN_PAYLOAD

:CHECK_DIFF
fc /b "%TMPBAT%" "%~f0" >nul 2>&1
if errorlevel 1 goto :DO_SELFUPDATE
del "%TMPBAT%" >nul 2>&1
echo update.bat is already the latest version.
goto :RUN_PAYLOAD

:DO_SELFUPDATE
echo A newer version of update.bat was found, updating...
copy /y "%TMPBAT%" "%~f0" >nul
del "%TMPBAT%" >nul 2>&1
call "%~f0" /afterupdate
exit /b

:RUN_PAYLOAD
:: ============================================================
:: STEP 1: extract the PowerShell payload below into a temp
:: .ps1 file and run it with -File (avoids the old
:: [scriptblock]::Create() quoting bug entirely)
:: ============================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$c = (Get-Content -LiteralPath '%~f0' -Raw) -split '::PS_PAYLOAD::' | Select-Object -Last 1; $tmp = Join-Path $env:TEMP ('update_payload_' + [guid]::NewGuid().ToString('N') + '.ps1'); Set-Content -LiteralPath $tmp -Value $c -Encoding UTF8; try { & $tmp '%~dp0' } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }"

if errorlevel 1 (
    echo.
    echo update.bat exited with an error. See the output above.
    pause
)

exit /b

::PS_PAYLOAD::
param([string]$currentDir)
$ErrorActionPreference = "Stop"
$exePath = Join-Path $currentDir "brave.exe"
$apiUrl = "https://api.github.com/repos/brave/brave-browser/releases/latest"
$tempDir = Join-Path $currentDir "BraveOriginUpdateTemp"

try {
  # 1. Download utility scripts and config files
  Write-Host "Downloading helper files from GitHub..." -ForegroundColor Yellow
  $webClient = New-Object System.Net.WebClient
  try {
    $webClient.DownloadFile("https://raw.githubusercontent.com/bibicadotnet/Brave_Origin_Portable/main/unlock-brave-origin.bat", (Join-Path $currentDir "unlock-brave-origin.bat"))
    $webClient.DownloadFile("https://raw.githubusercontent.com/bibicadotnet/Brave_Origin_Portable/main/register-default-browser.bat", (Join-Path $currentDir "register-default-browser.bat"))
    $webClient.DownloadFile("https://raw.githubusercontent.com/bibicadotnet/Brave_Origin_Portable/main/chrome++.ini", (Join-Path $currentDir "chrome++.ini"))
    Write-Host "Successfully updated helper files and chrome++.ini." -ForegroundColor Green
  } catch {
    Write-Warning "Failed to download helper files: $_"
  }

  # 2. Check Brave Version
  $currentVersion = if (Test-Path $exePath) { (Get-Item $exePath).VersionInfo.ProductVersion } else { "Not installed" }
  $release = Invoke-RestMethod -Uri $apiUrl
  $asset = $release.assets | Where-Object { $_.name -like "brave-origin-v*-win32-x64.zip" } | Select-Object -First 1
  if (-not $asset) { throw "Could not find brave-origin win32-x64 file in the latest release." }
  $braveVersion = [regex]::Match($asset.name, '\d+\.\d+\.\d+').Value
  $chromiumMajor = [regex]::Match($release.name, 'Chromium (\d+)').Groups[1].Value
  $latestVersion = "$chromiumMajor.$braveVersion"
  $downloadUrl = $asset.browser_download_url

  Write-Host "Current version: $currentVersion" -ForegroundColor Yellow
  Write-Host "Latest version: $latestVersion" -ForegroundColor Yellow
  Write-Host

  $confirm = Read-Host "Do you want to update Brave and Chrome++? (y/N)"
  if ($confirm -ne 'y' -and $confirm -ne 'Y') { exit }

  if (Test-Path $exePath) {
    Write-Host "Stopping Brave processes..."
    Stop-Process -Name brave,chrome_proxy,brave_crashpad_handler -Force -ErrorAction SilentlyContinue
    Start-Sleep 2
  }

  if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
  $downloadDir = Join-Path $tempDir "download"
  $extractDir = Join-Path $tempDir "extracted"
  New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
  New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
  $zipFile = Join-Path $downloadDir "update.zip"

  # 3. Download Brave
  Write-Host "Downloading Brave from: $downloadUrl"
  $webClient.DownloadFile($downloadUrl, $zipFile)

  Write-Host "Extracting Brave..."
  Expand-Archive -Path $zipFile -DestinationPath $extractDir -Force

  $topDirs = Get-ChildItem $extractDir -Directory
  $topFiles = Get-ChildItem $extractDir -File
  if ($topDirs.Count -eq 1 -and $topFiles.Count -eq 0) { $extractedRoot = $topDirs[0].FullName } else { $extractedRoot = $extractDir }

  Write-Host "Removing old files..."
  if (Test-Path (Join-Path $currentDir "brave.exe")) { Remove-Item (Join-Path $currentDir "brave.exe") -Force }
  Get-ChildItem $currentDir -Directory -ErrorAction SilentlyContinue | Where-Object { ($_.Name -replace '[0-9.]','') -eq '' } | ForEach-Object { Remove-Item $_.FullName -Recurse -Force }

  Write-Host "Copying new files..."
  Get-ChildItem $extractedRoot -Recurse | ForEach-Object {
    $relativePath = $_.FullName.Substring($extractedRoot.Length + 1)
    $destPath = Join-Path $currentDir $relativePath
    if ($_.PSIsContainer) {
      New-Item -ItemType Directory -Path $destPath -Force | Out-Null
    } elseif ($_.Name -eq "chrome_proxy.exe") {
      Write-Host "Skipping file: chrome_proxy.exe"
    } else {
      $destFolder = Split-Path $destPath -Parent
      if (-not (Test-Path $destFolder)) { New-Item -ItemType Directory -Path $destFolder -Force | Out-Null }
      Copy-Item $_.FullName -Destination $destPath -Force
    }
  }

  # 4. Download and Install Chrome++ Next Mini (version.dll only)
  Write-Host "Downloading and installing Chrome++ Next Mini..."
  $chromeNextMiniApiUrl = "https://api.github.com/repos/bibicadotnet/chrome-next-mini/releases/latest"
  try {
    $chromeNextRelease = Invoke-RestMethod -Uri $chromeNextMiniApiUrl
    $chromeNextAsset = $chromeNextRelease.assets | Where-Object { $_.name -like "edge_portable-v*.zip" } | Select-Object -First 1
    if (-not $chromeNextAsset) { throw "Could not find edge_portable*.zip in the latest release of chrome-next-mini." }
    $chromeNextDownloadUrl = $chromeNextAsset.browser_download_url
    $chromeNextZip = Join-Path $downloadDir "chrome-next-mini.zip"

    Write-Host "Downloading Chrome++ Next Mini from: $chromeNextDownloadUrl"
    $webClient.DownloadFile($chromeNextDownloadUrl, $chromeNextZip)

    Write-Host "Extracting Chrome++ Next Mini..."
    $chromeNextExtractDir = Join-Path $tempDir "chrome-next-mini-extracted"
    New-Item -ItemType Directory -Path $chromeNextExtractDir -Force | Out-Null
    Expand-Archive -Path $chromeNextZip -DestinationPath $chromeNextExtractDir -Force

    $dllFile = Get-ChildItem $chromeNextExtractDir -Filter "version.dll" -Recurse | Select-Object -First 1

    if ($dllFile) {
        Write-Host "Copying version.dll to the current directory..."
        Copy-Item $dllFile.FullName -Destination (Join-Path $currentDir "version.dll") -Force
        Write-Host "Successfully installed Chrome++ Next Mini version.dll!" -ForegroundColor Green
    } else {
        throw "Could not find version.dll in the extracted zip file."
    }
  } catch {
    Write-Warning "Failed to install Chrome++ Next Mini: $_"
  }

  # 5. Run unlock-brave-origin.bat directly, attached to the SAME console window
  #    (Start-Process -NoNewWindow -Wait keeps it in this window instead of popping
  #    a separate one, and lets its own self-contained batch/PS header run as designed)
  $unlockScript = Join-Path $currentDir "unlock-brave-origin.bat"
  if (Test-Path $unlockScript) {
      Write-Host "Running unlock-brave-origin..." -ForegroundColor Yellow
      try {
          $p = Start-Process -FilePath $unlockScript -WorkingDirectory $currentDir -NoNewWindow -PassThru -Wait
          if ($p.ExitCode -ne 0) {
              Write-Warning "unlock-brave-origin exited with code $($p.ExitCode)"
          }
      } catch {
          Write-Warning "Could not run unlock-brave-origin: $_"
      }
  }

  Remove-Item $tempDir -Recurse -Force
  $newVersion = if (Test-Path $exePath) { (Get-Item $exePath).VersionInfo.ProductVersion } else { "Not installed" }
  if ($newVersion -like "$latestVersion*") {
    Write-Host "Update completed! Version: $newVersion" -ForegroundColor Green
  } else {
    Write-Host "Error or update failed. Expected: $latestVersion, Actual: $newVersion" -ForegroundColor Yellow
  }

} catch {
  Write-Host "Error: $_" -ForegroundColor Red
}

Read-Host "Press Enter to exit"
