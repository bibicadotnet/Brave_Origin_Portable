@echo off
setlocal
echo Brave Origin Portable Updater v1.0
echo ================================
echo.
(
echo # Brave Origin Portable Updater
echo $ErrorActionPreference = "Stop"
echo $exePath = Join-Path "%~dp0" "brave.exe"
echo $apiUrl = "https://api.github.com/repos/brave/brave-browser/releases/latest"
echo $currentDir = "%~dp0"
echo $tempDir = Join-Path $currentDir "BraveOriginUpdateTemp"
echo.
echo try {
echo   $currentVersion = if ^(Test-Path $exePath^) { ^(Get-Item $exePath^).VersionInfo.ProductVersion } else { "Not installed" }
echo   $release = Invoke-RestMethod -Uri $apiUrl
echo   $asset = $release.assets ^| Where-Object { $_.name -like "brave-origin-v*-win32-x64.zip" } ^| Select-Object -First 1
echo   if ^(-not $asset^) { throw "Khong tim thay file brave-origin cho win32-x64 trong release moi nhat." }
echo   $braveVersion = [regex]::Match^($asset.name, '\d+\.\d+\.\d+'^).Value
echo   $chromiumMajor = [regex]::Match^($release.name, 'Chromium ^(\d+^)'^).Groups[1].Value
echo   $latestVersion = "$chromiumMajor.$braveVersion"
echo   $downloadUrl = $asset.browser_download_url
echo.
echo   Write-Host "Current version: $currentVersion" -ForegroundColor Yellow
echo   Write-Host "Latest version: $latestVersion" -ForegroundColor Yellow
echo   Write-Host
echo.
echo   $confirm = Read-Host "Do you want to update? (y/N)"
echo   if ^($confirm -ne 'y' -and $confirm -ne 'Y'^) { exit }
echo.
echo   if ^(Test-Path $exePath^) {
echo     Write-Host "Stopping processes..."
echo     Stop-Process -Name brave,chrome_proxy,brave_crashpad_handler -Force -ErrorAction SilentlyContinue
echo     Start-Sleep 2
echo   }
echo.
echo   if ^(Test-Path $tempDir^) { Remove-Item $tempDir -Recurse -Force }
echo   $downloadDir = Join-Path $tempDir "download"
echo   $extractDir = Join-Path $tempDir "extracted"
echo   New-Item -ItemType Directory -Path $downloadDir -Force ^| Out-Null
echo   New-Item -ItemType Directory -Path $extractDir -Force ^| Out-Null
echo   $zipFile = Join-Path $downloadDir "update.zip"
echo.
echo   Write-Host "Downloading from: $downloadUrl"
echo   ^(New-Object System.Net.WebClient^).DownloadFile^($downloadUrl, $zipFile^)
echo.
echo   Write-Host "Extracting..."
echo   Expand-Archive -Path $zipFile -DestinationPath $extractDir -Force
echo.
echo   $topDirs = Get-ChildItem $extractDir -Directory
echo   $topFiles = Get-ChildItem $extractDir -File
echo   if ^($topDirs.Count -eq 1 -and $topFiles.Count -eq 0^) { $extractedRoot = $topDirs[0].FullName } else { $extractedRoot = $extractDir }
echo.
echo   Write-Host "Removing old files..."
echo   if ^(Test-Path ^(Join-Path $currentDir "brave.exe"^)^) { Remove-Item ^(Join-Path $currentDir "brave.exe"^) -Force }
echo   Get-ChildItem $currentDir -Directory -ErrorAction SilentlyContinue ^| Where-Object { ^($_.Name -replace '[0-9.]',''^) -eq '' } ^| ForEach-Object { Remove-Item $_.FullName -Recurse -Force }
echo.
echo   Write-Host "Copying new files..."
echo   Get-ChildItem $extractedRoot -Recurse ^| ForEach-Object {
echo     $relativePath = $_.FullName.Substring^($extractedRoot.Length + 1^)
echo     $destPath = Join-Path $currentDir $relativePath
echo     if ^($_.PSIsContainer^) {
echo       New-Item -ItemType Directory -Path $destPath -Force ^| Out-Null
echo     } elseif ^($_.Name -eq "chrome_proxy.exe"^) {
echo       Write-Host "Skipping: chrome_proxy.exe"
echo     } else {
echo       $destFolder = Split-Path $destPath -Parent
echo       if ^(-not ^(Test-Path $destFolder^)^) { New-Item -ItemType Directory -Path $destFolder -Force ^| Out-Null }
echo       Copy-Item $_.FullName -Destination $destPath -Force
echo     }
echo   }
echo.
echo   Remove-Item $tempDir -Recurse -Force
echo   $newVersion = if ^(Test-Path $exePath^) { ^(Get-Item $exePath^).VersionInfo.ProductVersion } else { "Not installed" }
echo   if ^($newVersion -like "$latestVersion*"^) {
echo     Write-Host "Update completed successfully! Version: $newVersion" -ForegroundColor Green
echo   } else {
echo     Write-Host "Update may not be successful. Expected: $latestVersion, Actual: $newVersion" -ForegroundColor Yellow
echo   }
echo.
echo } catch {
echo   Write-Host "Error: $_" -ForegroundColor Red
echo }
echo.
echo Read-Host "Press Enter to exit"
) > "%TEMP%\brave_origin_update.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\brave_origin_update.ps1"
del "%TEMP%\brave_origin_update.ps1" 2>nul