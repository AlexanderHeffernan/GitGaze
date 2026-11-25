using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using Forms = System.Windows.Forms;

namespace GitGaze;

internal sealed class Tray : IDisposable
{
    private const uint Callback = 0x8001, Add = 0, Modify = 1, Delete = 2, Focus = 3, SetVersion = 4;
    private const uint Message = 1, Icon = 2, Tip = 4, Info = 16, ShowTip = 128;
    private readonly uint taskbarCreated = RegisterWindowMessage("TaskbarCreated");
    private readonly HwndSource host = new(new HwndSourceParameters("GitGaze tray") { WindowStyle = unchecked((int)0x80000000) });
    private IntPtr icon;
    private string tooltip = "GitGaze";
    private bool added;
    public event Action<int, int, int>? Command;

    public Tray() => host.AddHook(WindowMessage);

    public bool SetIcon(System.Drawing.Bitmap bitmap, string text)
    {
        var next = bitmap.GetHicon();
        if (icon != IntPtr.Zero) DestroyIcon(icon);
        icon = next;
        tooltip = text.Length > 127 ? text[..127] : text;
        return Publish();
    }

    private bool Publish()
    {
        if (icon == IntPtr.Zero) return false;
        var data = Data(Icon | Tip | Message | ShowTip);
        data.Icon = icon;
        data.Tip = tooltip;
        if (added && Shell_NotifyIcon(Modify, ref data)) return true;
        added = Shell_NotifyIcon(Add, ref data);
        if (added)
        {
            data.Version = 4;
            if (!Shell_NotifyIcon(SetVersion, ref data))
            {
                Shell_NotifyIcon(Delete, ref data);
                added = false;
            }
        }
        return added;
    }

    public void Notify(string title, string message)
    {
        var data = Data(Info);
        data.Title = title.Length > 63 ? title[..63] : title;
        data.Info = message.Length > 255 ? message[..255] : message;
        data.InfoFlags = 1 | 0x80; // Information, respect quiet time.
        Shell_NotifyIcon(Modify, ref data);
    }

    private IntPtr WindowMessage(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == taskbarCreated) { added = false; Publish(); }
        if (msg != Callback) return IntPtr.Zero;
        handled = true;
        var x = (short)(wParam.ToInt64() & 0xffff);
        var y = (short)((wParam.ToInt64() >> 16) & 0xffff);
        switch (lParam.ToInt64() & 0xffff)
        {
            case 0x400: // NIN_SELECT
            case 0x401: // NIN_KEYSELECT
                Command?.Invoke(1, x, y);
                break;
            case 0x7b: // WM_CONTEXTMENU
                if (x == -1 && y == -1)
                {
                    var point = Anchor(x, y);
                    x = (short)point.Left;
                    y = (short)point.Bottom;
                }
                ShowMenu(x, y);
                break;
        }
        return IntPtr.Zero;
    }

    private void ShowMenu(int x, int y)
    {
        var menu = CreatePopupMenu();
        if (menu == IntPtr.Zero) return;
        uint selected;
        try
        {
            AppendMenu(menu, 0, 2, "Open GitGaze");
            AppendMenu(menu, 0x800, 0, null);
            AppendMenu(menu, 0, 6, "Quit GitGaze");
            SetForegroundWindow(host.Handle);
            selected = TrackPopupMenuEx(menu, 0x100 | 0x2, x, y, host.Handle, IntPtr.Zero);
            PostMessage(host.Handle, 0, IntPtr.Zero, IntPtr.Zero);
        }
        finally { DestroyMenu(menu); }
        if (selected == 0) ReturnFocus();
        else Command?.Invoke((int)selected, x, y);
    }

    public void ReturnFocus()
    {
        var data = Data();
        Shell_NotifyIcon(Focus, ref data);
    }

    private RectPx Anchor(int x, int y)
    {
        var id = new IconIdentifier { Size = Marshal.SizeOf<IconIdentifier>(), Window = host.Handle, Id = 1 };
        if (Shell_NotifyIconGetRect(ref id, out var anchor) == 0 && anchor.Right > anchor.Left && anchor.Bottom > anchor.Top) return anchor;
        if (x == -1 && y == -1) { x = Forms.Cursor.Position.X; y = Forms.Cursor.Position.Y; }
        return new(x, y, x + 1, y + 1);
    }

    public void Show(Window window, int eventX, int eventY)
    {
        var anchor = Anchor(eventX, eventY);
        var work = Forms.Screen.FromRectangle(System.Drawing.Rectangle.FromLTRB(anchor.Left, anchor.Top, anchor.Right, anchor.Bottom)).WorkingArea;
        var hwnd = new WindowInteropHelper(window).EnsureHandle();
        // Move the hidden HWND to the target monitor before reading its per-monitor DPI.
        SetWindowPos(hwnd, IntPtr.Zero, work.Left + 1, work.Top + 1, 0, 0, 0x15);
        var scale = Math.Max(96u, GetDpiForWindow(hwnd)) / 96.0;
        window.Width = Math.Min(384, (work.Width - 16) / scale);
        window.Height = Math.Min(640, (work.Height - 16) / scale);
        var width = (int)Math.Round(window.Width * scale);
        var height = (int)Math.Round(window.Height * scale);
        var (x, y) = Place(anchor, new(work.Left, work.Top, work.Right, work.Bottom), width, height);
        SetWindowPos(hwnd, IntPtr.Zero, x, y, width, height, 0x14);
        window.Show();
        SetWindowPos(hwnd, IntPtr.Zero, x, y, width, height, 0x14);
        window.Activate();
    }

    internal static (int X, int Y) Place(RectPx anchor, RectPx work, int width, int height)
    {
        const int gap = 6;
        var x = anchor.Right - width;
        if (anchor.Right <= work.Left) x = anchor.Right + gap;
        else if (anchor.Left >= work.Right) x = anchor.Left - width - gap;
        var y = anchor.Top - height - gap;
        if (y < work.Top) y = anchor.Bottom + gap;
        return (Math.Clamp(x, work.Left, Math.Max(work.Left, work.Right - width)),
            Math.Clamp(y, work.Top, Math.Max(work.Top, work.Bottom - height)));
    }

    public void Dispose()
    {
        var data = Data();
        Shell_NotifyIcon(Delete, ref data);
        if (icon != IntPtr.Zero) DestroyIcon(icon);
        host.Dispose();
    }

    private NotifyData Data(uint flags = 0) => new() { Size = Marshal.SizeOf<NotifyData>(), Window = host.Handle, Id = 1,
        Flags = flags, Callback = Callback, Tip = "", Info = "", Title = "" };

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NotifyData
    {
        public int Size;
        public IntPtr Window;
        public uint Id, Flags, Callback;
        public IntPtr Icon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Tip;
        public uint State, StateMask;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string Info;
        public uint Version;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string Title;
        public uint InfoFlags;
        public Guid Guid;
        public IntPtr BalloonIcon;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct IconIdentifier { public int Size; public IntPtr Window; public uint Id; public Guid Guid; }
    [StructLayout(LayoutKind.Sequential)]
    internal readonly struct RectPx(int left, int top, int right, int bottom)
    { public readonly int Left = left, Top = top, Right = right, Bottom = bottom; }

    [DllImport("shell32", EntryPoint = "Shell_NotifyIconW")] private static extern bool Shell_NotifyIcon(uint command, ref NotifyData data);
    [DllImport("shell32")] private static extern int Shell_NotifyIconGetRect(ref IconIdentifier id, out RectPx rect);
    [DllImport("user32", CharSet = CharSet.Unicode)] private static extern uint RegisterWindowMessage(string text);
    [DllImport("user32")] private static extern bool DestroyIcon(IntPtr handle);
    [DllImport("user32")] private static extern uint GetDpiForWindow(IntPtr handle);
    [DllImport("user32")] private static extern bool SetWindowPos(IntPtr handle, IntPtr insertAfter, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32")] private static extern IntPtr CreatePopupMenu();
    [DllImport("user32")] private static extern bool DestroyMenu(IntPtr menu);
    [DllImport("user32", CharSet = CharSet.Unicode)] private static extern bool AppendMenu(IntPtr menu, uint flags, uint id, string? text);
    [DllImport("user32")] private static extern uint TrackPopupMenuEx(IntPtr menu, uint flags, int x, int y, IntPtr owner, IntPtr parameters);
    [DllImport("user32")] private static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32", CharSet = CharSet.Unicode)] private static extern bool PostMessage(IntPtr window, uint msg, IntPtr w, IntPtr l);
}
