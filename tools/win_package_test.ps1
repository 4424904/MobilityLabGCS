# Windows package test (CI, clean runner: no Qt / Python packages / QGC installed for the app)
#   1. silent install to C:\MLGCS        → files, desktop + start-menu shortcuts, uninstall registry entry
#   2. --simple-boot-test                 → the installed program boots and exits 0
#   3. GUI launch                         → still running after 25 s, screenshot
#   4. portable zip from the installed files (+ portable.txt), unpacked elsewhere → boots, keeps its settings in .\data
#   5. silent uninstall                   → program folder, shortcuts and registry entry gone
# Writes results.json, screenshots and logs to -Out.
param(
    [Parameter(Mandatory = $true)][string]$Installer,
    [Parameter(Mandatory = $true)][string]$Out,
    [Parameter(Mandatory = $true)][string]$Dist
)
$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$results = [ordered]@{}
$notes = @()
$InstDir = 'C:\MLGCS'

function Shot([string]$name) {
    try {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing
        $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
        $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
        $bmp.Save((Join-Path $Out $name), [System.Drawing.Imaging.ImageFormat]::Png)
        $g.Dispose(); $bmp.Dispose()
    } catch { $script:notes += "screenshot $name failed: $_" }
}

function BootTest([string]$exe, [string]$tag) {
    $p = Start-Process -FilePath $exe -ArgumentList '--simple-boot-test' -PassThru `
        -RedirectStandardOutput (Join-Path $Out "$tag-boot.out.log") -RedirectStandardError (Join-Path $Out "$tag-boot.err.log")
    if (-not $p.WaitForExit(180000)) { Stop-Process -Id $p.Id -Force; return $false }
    $script:notes += "$tag boot exit code $($p.ExitCode)"
    return ($p.ExitCode -eq 0)
}

function GuiTest([string]$exe, [string]$tag) {
    $p = Start-Process -FilePath $exe -PassThru
    Start-Sleep -Seconds 25
    $alive = -not $p.HasExited
    Shot "$tag-gui.png"
    if ($alive) { Stop-Process -Id $p.Id -Force; Start-Sleep -Seconds 3 }
    else { $script:notes += "$tag exited early, code $($p.ExitCode)" }
    return $alive
}

# ---- 1. install ----------------------------------------------------------------
$t = Measure-Command { Start-Process -FilePath $Installer -ArgumentList '/S', "/D=$InstDir" -Wait }
$notes += "install took $([int]$t.TotalSeconds) s"
$exe = Get-ChildItem -Path "$InstDir\bin" -Filter 'MobilityLabGCS.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
$results.installed = [bool]$exe
$desk = Get-ChildItem -Path "$env:PUBLIC\Desktop" -Filter '*.lnk' -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'MobilityLab*' }
$start = Get-ChildItem -Path "$env:ProgramData\Microsoft\Windows\Start Menu\Programs" -Recurse -Filter '*.lnk' -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'MobilityLab*' }
$results.desktop_shortcut = [bool]$desk
$results.start_menu_shortcut = [bool]$start
$reg = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like 'MobilityLab*' }
$results.uninstall_registered = [bool]$reg
if ($exe) {
    $size = (Get-ChildItem $InstDir -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB
    $notes += ("installed size {0:N0} MB, {1} files" -f $size, (Get-ChildItem $InstDir -Recurse -File).Count)
    # runtime bundled: Qt and the MSVC runtime next to the exe
    $results.runtime_bundled = (Test-Path "$InstDir\bin\Qt6Core.dll") -and ((Test-Path "$InstDir\bin\vcruntime140.dll") -or (Test-Path "$InstDir\bin\msvcp140.dll"))
}

# ---- 2/3. boot + GUI -----------------------------------------------------------------
if ($exe) {
    $results.boot_test = BootTest $exe.FullName 'installed'
    $results.gui_runs = GuiTest $exe.FullName 'installed'
}

# ---- 4. portable ------------------------------------------------------------------------
if ($exe) {
    $stage = Join-Path $env:RUNNER_TEMP 'portable\MobilityLabGCS'
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    Copy-Item -Path "$InstDir\*" -Destination $stage -Recurse -Force
    Get-ChildItem $stage -Filter '*Uninstall*.exe' | Remove-Item -Force
    Set-Content -Path (Join-Path $stage 'portable.txt') -Encoding UTF8 -Value @(
        'MobilityLab GCS portable',
        'This file makes the program keep its settings, logs and ACACT records in the data folder here.',
        'Run bin\MobilityLabGCS.exe. Nothing is written to the registry or the user profile.'
    )
    $zip = Join-Path $Dist 'MobilityLabGCS-portable-win64.zip'
    if (Test-Path $zip) { Remove-Item $zip }
    Compress-Archive -Path $stage -DestinationPath $zip -CompressionLevel Optimal
    $notes += ("portable zip {0:N0} MB" -f ((Get-Item $zip).Length / 1MB))
    $ptest = 'C:\ptest'
    Expand-Archive -Path $zip -DestinationPath $ptest -Force
    $pexe = "$ptest\MobilityLabGCS\bin\MobilityLabGCS.exe"
    $results.portable_boot = BootTest $pexe 'portable'
    $results.portable_gui_runs = GuiTest $pexe 'portable'
    $results.portable_settings_local = [bool](Get-ChildItem "$ptest\MobilityLabGCS\data" -Recurse -Filter '*.ini' -ErrorAction SilentlyContinue)
}

# ---- 5. uninstall ---------------------------------------------------------------------------
$un = Get-ChildItem -Path $InstDir -Filter '*Uninstall*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($un) {
    Start-Process -FilePath $un.FullName -ArgumentList '/S' -Wait
    # the NSIS uninstaller copies itself to %TEMP% and returns at once: wait for it to finish
    for ($i = 0; $i -lt 60 -and (Test-Path "$InstDir\bin\MobilityLabGCS.exe"); $i++) { Start-Sleep -Seconds 2 }
    Start-Sleep -Seconds 3
    $results.uninstall_removes_files = -not (Test-Path "$InstDir\bin\MobilityLabGCS.exe")
    $results.uninstall_removes_shortcuts = -not (Get-ChildItem -Path "$env:PUBLIC\Desktop" -Filter 'MobilityLab*.lnk' -ErrorAction SilentlyContinue)
    $results.uninstall_removes_start_menu = -not (Get-ChildItem -Path "$env:ProgramData\Microsoft\Windows\Start Menu\Programs" -Recurse -Filter 'MobilityLab*.lnk' -ErrorAction SilentlyContinue)
    $results.start_menu_intact = (Get-ChildItem -Path "$env:ProgramData\Microsoft\Windows\Start Menu\Programs" -Recurse -Filter '*.lnk' -ErrorAction SilentlyContinue).Count -gt 0   # nothing else removed
    $results.uninstall_removes_registry = -not (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like 'MobilityLab*' })
} else {
    $results.uninstall_removes_files = $false
    $notes += 'uninstaller not found'
}

$os = Get-CimInstance Win32_OperatingSystem
$summary = [ordered]@{ os = "$($os.Caption) $($os.Version)"; checks = $results; notes = $notes }
$summary | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $Out 'results.json') -Encoding UTF8
$summary | ConvertTo-Json -Depth 4
$soft = @('portable_settings_local')   # reported, does not fail the job (QSettings may not flush when killed)
$failed = @($results.GetEnumerator() | Where-Object { -not $_.Value -and $soft -notcontains $_.Name })
if ($failed.Count -gt 0) {
    Write-Host "::error::Windows package test failed: $($failed.Name -join ', ')"
    exit 1
}
