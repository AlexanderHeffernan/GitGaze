$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing.Common
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class IndependentTrayControl {
    // Version 1 NOTIFYICONDATAW prefix, no WPF, callback, version negotiation or GitGaze code.
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    private struct Data {
        public uint Size;
        public IntPtr Window;
        public uint Id, Flags, Callback;
        public IntPtr Icon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=64)] public string Tip;
    }
    [DllImport("shell32.dll", EntryPoint="Shell_NotifyIconW", ExactSpelling=true)]
    private static extern bool Notify(uint message, ref Data data);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)]
    public static extern IntPtr FindWindow(string name, string title);
    public static bool TryAddAndRemove(IntPtr owner, IntPtr icon) {
        var data = new Data { Size=(uint)Marshal.SizeOf<Data>(), Window=owner, Id=1, Flags=6, Icon=icon, Tip="Independent CI notification control" };
        var added = Notify(0, ref data);
        if (added) Notify(2, ref data);
        return added;
    }
}
'@
$shell = [IndependentTrayControl]::FindWindow('Shell_TrayWnd', $null)
$session = (Get-Process -Id $PID).SessionId
$explorer = @(Get-Process explorer -ErrorAction SilentlyContinue | Where-Object SessionId -eq $session)
$setup = @(Get-Process UserOOBEBroker,CloudExperienceHostBroker -ErrorAction SilentlyContinue | Where-Object SessionId -eq $session)
"Control shell state: session=$session explorer=$($explorer.Count) trayHWND=$($shell -ne [IntPtr]::Zero) setupBrokers=$($setup.Count)"
$form = [Windows.Forms.Form]::new()
try {
    $added = [IndependentTrayControl]::TryAddAndRemove($form.Handle, [Drawing.SystemIcons]::Information.Handle)
    "Independent notification control NIM_ADD=$added"
} finally { $form.Dispose() }
if ($shell -ne [IntPtr]::Zero) {
    $taskbar = [Windows.Automation.AutomationElement]::FromHandle($shell)
    $type = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::Button)
    $buttons = $taskbar.FindAll([Windows.Automation.TreeScope]::Descendants, $type)
    "Control shell state: taskbar accessibility buttons=$($buttons.Count)"
}
