param([Parameter(Mandatory)][string]$Exe, [Parameter(Mandatory)][string]$Evidence)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing.Common
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class TraySmoke {
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int L,T,R,B; }
    [StructLayout(LayoutKind.Sequential)] public struct Icon { public int Size; public IntPtr Window; public uint Id; public Guid Guid; }
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string cls, string title);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr window, out Rect rect);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr window);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint x, uint y, uint data, IntPtr extra);
    [DllImport("user32.dll")] public static extern void keybd_event(byte key, byte scan, uint flags, IntPtr extra);
    [DllImport("shell32.dll")] private static extern int Shell_NotifyIconGetRect(ref Icon id, out Rect rect);
    public static Rect IconRect(IntPtr window) {
        var id = new Icon { Size=Marshal.SizeOf<Icon>(), Window=window, Id=1 };
        return Shell_NotifyIconGetRect(ref id, out Rect rect) == 0 ? rect : default(Rect);
    }
}
'@

function Wait-For($Description, [scriptblock]$Check, $Seconds = 12) {
    $deadline = [Diagnostics.Stopwatch]::StartNew()
    do {
        $value = & $Check
        if ($value) { return $value }
        Start-Sleep -Milliseconds 100
    } while ($deadline.Elapsed.TotalSeconds -lt $Seconds)
    throw "Timed out: $Description"
}
function Click([int]$X, [int]$Y) {
    if (![TraySmoke]::SetCursorPos($X, $Y)) { throw 'Cannot move pointer' }
    Start-Sleep -Milliseconds 50
    [TraySmoke]::mouse_event(2, 0, 0, 0, [IntPtr]::Zero)
    [TraySmoke]::mouse_event(4, 0, 0, 0, [IntPtr]::Zero)
}
function Find-TrayItem {
    $root = [Windows.Automation.AutomationElement]::RootElement
    $name = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty, 'GitGaze · Shared-client review')
    $root.FindFirst([Windows.Automation.TreeScope]::Descendants, $name)
}
function Open-Tray {
    $item = Find-TrayItem
    if (!$item -or $item.Current.IsOffscreen) {
        $taskbar = [Windows.Automation.AutomationElement]::FromHandle([TraySmoke]::FindWindow('Shell_TrayWnd', $null))
        $name = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty, 'Show hidden icons')
        $overflow = $taskbar.FindFirst([Windows.Automation.TreeScope]::Descendants, $name)
        if (!$overflow) { throw 'GitGaze is not visible and the Explorer overflow control could not be located' }
        $bounds = $overflow.Current.BoundingRectangle
        Click ($bounds.X + $bounds.Width / 2) ($bounds.Y + $bounds.Height / 2)
        $item = Wait-For 'visible GitGaze element in Explorer overflow' { $i = Find-TrayItem; if ($i -and !$i.Current.IsOffscreen) { $i } }
        Write-Host 'Opened Explorer overflow with a pointer click'
    }
    $bounds = $item.Current.BoundingRectangle
    Click ($bounds.X + $bounds.Width / 2) ($bounds.Y + $bounds.Height / 2)
}
function Visible-Flyout {
    $window = [TraySmoke]::FindWindow($null, 'GitGaze')
    [uint32]$owner = 0
    if ($window -ne [IntPtr]::Zero -and [TraySmoke]::IsWindowVisible($window)) {
        [void][TraySmoke]::GetWindowThreadProcessId($window, [ref]$owner)
        if ($owner -eq $app.Id) { return $window }
    }
}
function Capture-Flyout($Window) {
    $rect = [TraySmoke+Rect]::new()
    if (![TraySmoke]::GetWindowRect($Window, [ref]$rect)) { throw 'Cannot read flyout bounds' }
    $bitmap = [Drawing.Bitmap]::new($rect.R - $rect.L, $rect.B - $rect.T)
    try {
        $g = [Drawing.Graphics]::FromImage($bitmap)
        try { $g.CopyFromScreen($rect.L, $rect.T, 0, 0, $bitmap.Size) } finally { $g.Dispose() }
        $bitmap.Save((Join-Path $Evidence 'arm64-flyout.png'), [Drawing.Imaging.ImageFormat]::Png)
    } finally { $bitmap.Dispose() }
    Write-Host "Flyout bounds: $($rect.L),$($rect.T)–$($rect.R),$($rect.B); DPI $([TraySmoke]::GetDpiForWindow($Window))"
}

New-Item -ItemType Directory -Force $Evidence | Out-Null
$Evidence = (Resolve-Path $Evidence).Path
$app = Start-Process -FilePath (Resolve-Path $Exe) -ArgumentList '--fixture' -PassThru
try {
    $null = Wait-For 'GitGaze tray icon registered with Explorer' {
        $hostWindow = [TraySmoke]::FindWindow($null, 'GitGaze tray')
        if ($hostWindow -ne [IntPtr]::Zero) {
            $rect = [TraySmoke]::IconRect($hostWindow)
            $rect.R -gt $rect.L -and $rect.B -gt $rect.T
        }
    }
    Open-Tray
    $flyout = Wait-For 'native flyout shown by tray click' { Visible-Flyout }
    $null = Wait-For 'fixture content exposed by WebView2 accessibility' {
        $root = [Windows.Automation.AutomationElement]::FromHandle($flyout)
        $name = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty, '7 contributions today. 53 percent of your next daily record.')
        $root.FindFirst([Windows.Automation.TreeScope]::Descendants, $name)
    } 25
    Capture-Flyout $flyout
    if ([TraySmoke]::GetForegroundWindow() -ne $flyout) { throw 'The flyout is not the foreground window' }
    [TraySmoke]::keybd_event(27, 0, 0, [IntPtr]::Zero)
    [TraySmoke]::keybd_event(27, 0, 2, [IntPtr]::Zero)
    $null = Wait-For 'real Escape key to dismiss flyout' { !(Visible-Flyout) }
    Open-Tray
    $null = Wait-For 'flyout to reopen on second tray click' { Visible-Flyout }
    Write-Host 'PASS: Explorer tray click, WebView2 fixture, foreground focus, Escape dismissal, second open.'
} finally {
    if (!$app.HasExited) { Stop-Process -Id $app.Id }
}
