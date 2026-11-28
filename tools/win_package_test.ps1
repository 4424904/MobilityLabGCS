# Windows package test (CI, clean runner: no Qt / Python packages / QGC installed for the app)
#   1. silent install to C:\MLGCS        → files, desktop + start-menu shortcuts, uninstall registry entry
#   2. --simple-boot-test                 → the installed program boots and exits 0
#   3. GUI launch                         → still running after 25 s, screenshot
#   4. portable zip from the installed files (+ portable.txt), unpacked elsewhere → boots, keeps its settings in .\data
#   5. silent uninstall                   → program folder, shortcuts and registry entry gone
#   0. (with -PrevInstaller) upgrade      → the previous release installed and used first; installing this
#                                           version over it keeps the user's settings, missions and logs
# Writes results.json, screenshots and logs to -Out.
param(
    [Parameter(Mandatory = $true)][string]$Installer,
    [Parameter(Mandatory = $true)][string]$Out,
    [Parameter(Mandatory = $true)][string]$Dist,
    [string]$PrevInstaller = ''
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

# ---- 0. upgrade from the previous release ---------------------------------------------
$markerIni = Join-Path $env:APPDATA 'MobilityLab\MobilityLabGCS.ini'
$markerPlan = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'MobilityLab\Missions\upgrade_keep_test.plan'
$markerLog = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'MobilityLab\ACACT\guard_upgrade_keep_test.csv'
if ($PrevInstaller -ne '' -and (Test-Path $PrevInstaller)) {
    Start-Process -FilePath $PrevInstaller -ArgumentList '/S', "/D=$InstDir" -Wait
    $prevExe = Get-ChildItem -Path "$InstDir\bin" -Filter 'MobilityLabGCS.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    $results.prev_installed = [bool]$prevExe
    if ($prevExe) {
        # use it once so it writes its own settings, then add what an operator would have: a setting, a mission, a log
        $p = Start-Process -FilePath $prevExe.FullName -PassThru; Start-Sleep -Seconds 25
        if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force; Start-Sleep -Seconds 3 }
        New-Item -ItemType Directory -Force -Path (Split-Path $markerIni), (Split-Path $markerPlan), (Split-Path $markerLog) | Out-Null
        Add-Content -Path $markerIni -Value "`r`n[MLUpgradeTest]`r`nmarker=keep-1234`r`n"
        Set-Content -Path $markerPlan -Value '{"fileType":"Plan","marker":"keep"}'
        Set-Content -Path $markerLog -Value 't,marker'
        $notes += "previous release installed and used: $PrevInstaller"
    }
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

if ($PrevInstaller -ne '' -and $results.Contains('prev_installed')) {
    $results.upgrade_keeps_settings = (Test-Path $markerIni) -and ((Get-Content $markerIni -Raw) -match 'marker=keep-1234')
    $results.upgrade_keeps_missions = Test-Path $markerPlan
    $results.upgrade_keeps_logs = Test-Path $markerLog
    $ver = Get-ChildItem -Path "$InstDir" -Recurse -Filter 'ML_VERSION.txt' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($ver) { $notes += "installed version file: $((Get-Content $ver.FullName -Raw).Trim())" }
}

# ---- 2/3. boot + GUI -----------------------------------------------------------------
if ($exe) {
    $results.boot_test = BootTest $exe.FullName 'installed'
    $results.gui_runs = GuiTest $exe.FullName 'installed'
}

# ---- 3b. QGC video (v1.2): UDP H.264 test stream from the GStreamer SDK on the build runner -----
# The installed program is pointed at "UDP h.264 Video Stream" on port 5600 and must report
# "Decoding started"; the screenshot shows the moving test pattern. Reported, does not fail the job
# (a runner without a usable H.264 encoder cannot produce the stream).
if ($exe) {
    $gst = Get-Command gst-launch-1.0 -ErrorAction SilentlyContinue
    $enc = $null
    if ($gst) {
        foreach ($e in @('x264enc tune=zerolatency speed-preset=ultrafast key-int-max=30', 'openh264enc', 'mfh264enc')) {
            $name = $e.Split(' ')[0]
            & (Join-Path (Split-Path $gst.Source) 'gst-inspect-1.0.exe') $name *> $null
            if ($LASTEXITCODE -eq 0) { $enc = $e; break }
        }
    }
    if ($enc) {
        $notes += "video test encoder: $enc"
        $pipe = "videotestsrc pattern=ball is-live=true ! video/x-raw,width=640,height=360,framerate=30/1 ! videoconvert ! $enc ! h264parse ! rtph264pay config-interval=1 pt=96 ! udpsink host=127.0.0.1 port=5600"
        $src = Start-Process -FilePath $gst.Source -ArgumentList $pipe -PassThru -WindowStyle Hidden `
            -RedirectStandardOutput (Join-Path $Out 'video-src.out.log') -RedirectStandardError (Join-Path $Out 'video-src.err.log')
        New-Item -ItemType Directory -Force -Path (Split-Path $markerIni) | Out-Null
        # which GStreamer plugins the installed program carries (H.264 path: rtph264depay, h264parse, a decoder)
        $gp = Get-ChildItem -Path $InstDir -Recurse -Filter 'gst*.dll' -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'libav|openh264|d3d11|rtp|udp|videoparsers|qml|playback|nvcodec|mediafoundation' } | Select-Object -ExpandProperty Name
        $notes += "bundled H.264-path plugins: $($gp -join ', ')"
        # run 1: QGC defaults (decoder chosen automatically — hardware/D3D11 first)
        # run 2: QGC setting "Force software decoder" (forceVideoDecoder=1) — the runner has no GPU
        $runs = @(@{ tag = 'video'; key = 'video_udp_h264_decoding'; extra = '' },
                  @{ tag = 'video-sw'; key = 'video_udp_h264_decoding_software'; extra = "forceVideoDecoder=1`r`n" })
        foreach ($r in $runs) {
            Add-Content -Path $markerIni -Value "`r`n[Video]`r`nvideoSource=UDP h.264 Video Stream`r`nudpUrl=0.0.0.0:5600`r`n$($r.extra)"
            $env:QT_FORCE_STDERR_LOGGING = '1'
            $env:QT_LOGGING_RULES = 'Video.*.debug=true'
            $env:MLGCS_NO_ONBOARDING = '1'
            $vp = Start-Process -FilePath $exe.FullName -PassThru `
                -RedirectStandardOutput (Join-Path $Out "$($r.tag)-app.out.log") -RedirectStandardError (Join-Path $Out "$($r.tag)-app.err.log")
            Start-Sleep -Seconds 40
            Shot "installed-$($r.tag).png"   # the test pattern (moving ball) shows when the stream is decoded
            Stop-Process -Id $vp.Id -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 3
            Remove-Item Env:QT_FORCE_STDERR_LOGGING, Env:QT_LOGGING_RULES, Env:MLGCS_NO_ONBOARDING -ErrorAction SilentlyContinue
            $vlog = Get-Content (Join-Path $Out "$($r.tag)-app.err.log") -Raw -ErrorAction SilentlyContinue
            $results[$r.key] = [bool]($vlog -match 'Decoding started')
            $notes += "$($r.tag): stream errors $(([regex]::Matches([string]$vlog, 'Internal data stream error')).Count)"
        }
        Stop-Process -Id $src.Id -Force -ErrorAction SilentlyContinue
    } else {
        $notes += 'video test not run: no gst-launch-1.0 or no H.264 encoder on the runner'
    }
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
$soft = @('portable_settings_local', 'video_udp_h264_decoding', 'video_udp_h264_decoding_software')   # reported, does not fail the job (QSettings may not flush when killed)
$failed = @($results.GetEnumerator() | Where-Object { -not $_.Value -and $soft -notcontains $_.Name })
if ($failed.Count -gt 0) {
    Write-Host "::error::Windows package test failed: $($failed.Name -join ', ')"
    exit 1
}
