// WinSpy: small test helper used to observe and drive only the Multisim
// processes started by the test run (selected by PID, never by name).
//
//   WinSpy list <pid>                       visible top-level windows + child controls (JSON lines)
//   WinSpy shot <hwnd> <file.png>           capture one window (PrintWindow)
//   WinSpy screen <file.png>                capture the whole virtual screen
//   WinSpy click <hwnd> <button text>       BM_CLICK a child button whose text matches (& ignored)
//   WinSpy keys <hwnd> <SendKeys string>    focus window and send keys
//   WinSpy close <hwnd>                     post WM_CLOSE
//   WinSpy children <pid>                   PIDs whose parent is <pid>
//   WinSpy items <hwnd>                     items of a ListBox / ComboBox / SysListView32 / SysTreeView32
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Management;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

internal static class WinSpy
{
    delegate bool EnumProc(IntPtr hwnd, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr parent, EnumProc cb, IntPtr lParam);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr hwnd, StringBuilder sb, int max);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr SendMessage(IntPtr hwnd, uint msg, IntPtr w, StringBuilder l);
    [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr hwnd, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr hwnd, uint msg, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr hwnd, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hwnd, out RECT r);
    [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr hwnd, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr hwnd, uint cmd);
    [DllImport("user32.dll")] static extern int GetDlgCtrlID(IntPtr hwnd);
    [DllImport("user32.dll")] static extern bool IsWindowEnabled(IntPtr hwnd);
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();

    [StructLayout(LayoutKind.Sequential)] struct RECT { public int L, T, R, B; }

    const uint WM_GETTEXT = 0x000D, WM_GETTEXTLENGTH = 0x000E, BM_CLICK = 0x00F5, WM_CLOSE = 0x0010;
    const uint LB_GETCOUNT = 0x018B, LB_GETTEXT = 0x0189, LB_GETTEXTLEN = 0x018A;
    const uint CB_GETCOUNT = 0x0146, CB_GETLBTEXT = 0x0148, CB_GETLBTEXTLEN = 0x0149;
    const uint LVM_GETITEMCOUNT = 0x1004, TVM_GETCOUNT = 0x1105;
    const uint GW_OWNER = 4;

    static string Text(IntPtr h)
    {
        IntPtr n;
        if (SendMessageTimeout(h, WM_GETTEXTLENGTH, IntPtr.Zero, IntPtr.Zero, 2, 1000, out n) == IntPtr.Zero) return "";
        if ((int)n <= 0) return "";
        var sb = new StringBuilder((int)n + 1);
        SendMessage(h, WM_GETTEXT, (IntPtr)((int)n + 1), sb);
        return sb.ToString();
    }

    static string Cls(IntPtr h) { var sb = new StringBuilder(256); GetClassName(h, sb, 256); return sb.ToString(); }

    static string J(string s)
    {
        var sb = new StringBuilder("\"");
        foreach (char c in s ?? "")
        {
            if (c == '"' || c == '\\') sb.Append('\\').Append(c);
            else if (c < 0x20) sb.AppendFormat("\\u{0:x4}", (int)c);
            else sb.Append(c);
        }
        return sb.Append('"').ToString();
    }

    static List<IntPtr> TopWindows(uint pid)
    {
        var list = new List<IntPtr>();
        EnumWindows((h, l) => { uint p; GetWindowThreadProcessId(h, out p); if (p == pid && IsWindowVisible(h)) list.Add(h); return true; }, IntPtr.Zero);
        return list;
    }

    static List<IntPtr> Children(IntPtr parent)
    {
        var list = new List<IntPtr>();
        EnumChildWindows(parent, (h, l) => { list.Add(h); return true; }, IntPtr.Zero);
        return list;
    }

    static int Count(IntPtr h)
    {
        string c = Cls(h).ToLowerInvariant();
        uint msg = c.Contains("listbox") ? LB_GETCOUNT : c.Contains("combobox") ? CB_GETCOUNT
                 : c.Contains("syslistview32") ? LVM_GETITEMCOUNT : c.Contains("systreeview32") ? TVM_GETCOUNT : 0;
        if (msg == 0) return -1;
        IntPtr r;
        if (SendMessageTimeout(h, msg, IntPtr.Zero, IntPtr.Zero, 2, 1000, out r) == IntPtr.Zero) return -1;
        return (int)r;
    }

    static string Rect(IntPtr h) { RECT r; GetWindowRect(h, out r); return string.Format("[{0},{1},{2},{3}]", r.L, r.T, r.R, r.B); }

    static void Shot(IntPtr h, string file)
    {
        RECT r; GetWindowRect(h, out r);
        int w = Math.Max(1, r.R - r.L), hh = Math.Max(1, r.B - r.T);
        using (var bmp = new Bitmap(w, hh))
        {
            using (var g = Graphics.FromImage(bmp))
            {
                IntPtr dc = g.GetHdc();
                bool ok = PrintWindow(h, dc, 2);
                g.ReleaseHdc(dc);
                if (!ok) g.CopyFromScreen(r.L, r.T, 0, 0, new Size(w, hh));
            }
            bmp.Save(file, ImageFormat.Png);
        }
    }

    [STAThread]
    static int Main(string[] a)
    {
        SetProcessDPIAware();
        Console.OutputEncoding = new UTF8Encoding(false);
        try
        {
            switch (a[0])
            {
                case "list":
                    foreach (var h in TopWindows(uint.Parse(a[1])))
                    {
                        Console.WriteLine("{{\"hwnd\":{0},\"class\":{1},\"title\":{2},\"rect\":\"{3}\",\"owner\":{4},\"enabled\":{5},\"children\":[",
                            (long)h, J(Cls(h)), J(Text(h)), Rect(h), (long)GetWindow(h, GW_OWNER), IsWindowEnabled(h) ? "true" : "false");
                        bool first = true;
                        foreach (var c in Children(h))
                        {
                            if (!IsWindowVisible(c)) continue;
                            Console.WriteLine("{0}{{\"hwnd\":{1},\"id\":{2},\"class\":{3},\"text\":{4},\"count\":{5},\"rect\":\"{6}\"}}",
                                first ? " " : ",", (long)c, GetDlgCtrlID(c), J(Cls(c)), J(Text(c)), Count(c), Rect(c));
                            first = false;
                        }
                        Console.WriteLine("]}");
                    }
                    return 0;
                case "shot": Shot((IntPtr)long.Parse(a[1]), a[2]); return 0;
                case "screen":
                {
                    var b = SystemInformation.VirtualScreen;
                    using (var bmp = new Bitmap(b.Width, b.Height))
                    {
                        using (var g = Graphics.FromImage(bmp)) g.CopyFromScreen(b.Left, b.Top, 0, 0, b.Size);
                        bmp.Save(a[1], ImageFormat.Png);
                    }
                    return 0;
                }
                case "click":
                {
                    var parent = (IntPtr)long.Parse(a[1]);
                    string want = a[2].Replace("&", "");
                    foreach (var c in Children(parent))
                        if (Cls(c) == "Button" && Text(c).Replace("&", "").Equals(want, StringComparison.OrdinalIgnoreCase))
                        { PostMessage(c, BM_CLICK, IntPtr.Zero, IntPtr.Zero); Console.WriteLine("clicked " + (long)c); return 0; }
                    Console.WriteLine("button not found"); return 2;
                }
                case "keys":
                    SetForegroundWindow((IntPtr)long.Parse(a[1]));
                    Thread.Sleep(300);
                    SendKeys.SendWait(a[2]);
                    return 0;
                case "close": PostMessage((IntPtr)long.Parse(a[1]), WM_CLOSE, IntPtr.Zero, IntPtr.Zero); return 0;
                case "children":
                    using (var s = new ManagementObjectSearcher("SELECT ProcessId FROM Win32_Process WHERE ParentProcessId=" + uint.Parse(a[1])))
                        foreach (ManagementObject o in s.Get()) Console.WriteLine(o["ProcessId"]);
                    return 0;
                case "items":
                {
                    var h = (IntPtr)long.Parse(a[1]);
                    string c = Cls(h).ToLowerInvariant();
                    int n = Count(h);
                    Console.WriteLine("count " + n);
                    bool lb = c.Contains("listbox");
                    if (lb || c.Contains("combobox"))
                        for (int i = 0; i < n && i < 500; i++)
                        {
                            int len = (int)SendMessage(h, lb ? LB_GETTEXTLEN : CB_GETLBTEXTLEN, (IntPtr)i, IntPtr.Zero);
                            if (len < 0 || len > 4096) { Console.WriteLine(i + "\t<owner-draw/unreadable>"); continue; }
                            var sb = new StringBuilder(len + 2);
                            SendMessage(h, lb ? LB_GETTEXT : CB_GETLBTEXT, (IntPtr)i, sb);
                            Console.WriteLine(i + "\t" + sb);
                        }
                    return 0;
                }
            }
            Console.Error.WriteLine("unknown command");
            return 1;
        }
        catch (Exception e) { Console.Error.WriteLine(e.Message); return 1; }
    }
}
