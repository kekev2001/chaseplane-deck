// keysend: a tiny helper of the ChasePlane Deck plugin. It reads commands from stdin and presses / releases keyboard keys with SendInput,
// so the plugin can use whatever key the user has assigned to a ChasePlane command (a Stream Deck plugin cannot press keys by itself).
//
//   down <vk> [<vk> ...]   press the keys in this order and keep them down
//   up   <vk> [<vk> ...]   release the keys (in reverse order)
//   tap  <vk> [<vk> ...]   press, wait 40 ms, release
//   release                release every key that is still down
//   foreground             answer with the name of the program whose window is in front
//   quit                   release everything and stop
// With --require-foreground <text> "down" and "tap" are only carried out while the program in front has <text> in its name (e.g. FlightSimulator),
// so keys are never typed into some other window; the answer is then "err not-foreground <name>". "up" and "release" always work.
//
// <vk> = Windows virtual-key codes, the numbers ChasePlane stores in its key list (Shift 160, Ctrl 162, Alt 164, F13 124, ...).
// Every command is answered with one line: "ok" or "err <reason>". With --dry nothing is sent; the answer says what would have been sent.
// A key must never get stuck, so three things release every key that is still down: stdin closing, the plugin process going away
// (--parent <pid>: closing stdin is not reliable on Windows when the parent is killed) and a limit of 2 minutes per key.
// Build: C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /target:exe /optimize+ /out:keysend.exe KeySend.cs
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace ChasePlaneDeck
{
    internal static class KeySend
    {
        const uint INPUT_KEYBOARD = 1;
        const uint KEYEVENTF_EXTENDEDKEY = 0x0001;
        const uint KEYEVENTF_KEYUP = 0x0002;
        const uint MAPVK_VK_TO_VSC_EX = 4;

        [StructLayout(LayoutKind.Sequential)]
        struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }

        [StructLayout(LayoutKind.Sequential)]
        struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }

        [StructLayout(LayoutKind.Explicit)]
        struct INPUTUNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }

        [StructLayout(LayoutKind.Sequential)]
        struct INPUT { public uint type; public INPUTUNION u; }

        [DllImport("user32.dll", SetLastError = true)]
        static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

        [DllImport("user32.dll")]
        static extern uint MapVirtualKey(uint uCode, uint uMapType);

        [DllImport("user32.dll")]
        static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

        static string requireForeground;                               // null = any window is fine

        static string ForegroundName()
        {
            try
            {
                uint pid;
                GetWindowThreadProcessId(GetForegroundWindow(), out pid);
                return System.Diagnostics.Process.GetProcessById((int)pid).ProcessName;
            }
            catch (Exception) { return "?"; }
        }

        static bool dry;
        static readonly object gate = new object();                    // stdin handling, the watchdog and the parent watch all touch the key state
        static readonly List<int> down = new List<int>();              // keys we hold, in the order they went down
        static readonly Dictionary<int, DateTime> since = new Dictionary<int, DateTime>();
        static readonly StringBuilder dryLog = new StringBuilder();
        static readonly TimeSpan MaxHold = TimeSpan.FromMinutes(2);

        // the keys that need the "extended key" flag (the grey block next to the main keys, arrows, right Ctrl / Alt, numpad divide ...)
        static bool IsExtended(int vk)
        {
            switch (vk)
            {
                case 0x21: case 0x22: case 0x23: case 0x24:            // PageUp PageDown End Home
                case 0x25: case 0x26: case 0x27: case 0x28:            // arrows
                case 0x2C: case 0x2D: case 0x2E:                       // PrintScreen Insert Delete
                case 0x6F: case 0x90:                                  // numpad divide, NumLock
                case 0xA3: case 0xA5:                                  // right Ctrl, right Alt
                    return true;
            }
            uint sc = MapVirtualKey((uint)vk, MAPVK_VK_TO_VSC_EX);
            return (sc & 0xFF00) == 0xE000;
        }

        static void Press(int vk, bool up)
        {
            if (dry) { dryLog.Append(up ? " -" : " +").Append(vk); return; }
            INPUT[] input = new INPUT[1];
            input[0].type = INPUT_KEYBOARD;
            input[0].u.ki.wVk = (ushort)vk;
            input[0].u.ki.wScan = (ushort)(MapVirtualKey((uint)vk, 0) & 0xFF);
            input[0].u.ki.dwFlags = (IsExtended(vk) ? KEYEVENTF_EXTENDEDKEY : 0) | (up ? KEYEVENTF_KEYUP : 0);
            if (SendInput(1, input, Marshal.SizeOf(typeof(INPUT))) != 1) throw new InvalidOperationException("SendInput failed (" + Marshal.GetLastWin32Error() + ")");
        }

        static void Down(List<int> keys)
        {
            foreach (int vk in keys)
            {
                Press(vk, false);
                if (!down.Contains(vk)) down.Add(vk);
                since[vk] = DateTime.UtcNow;
            }
        }

        static void Up(List<int> keys)
        {
            for (int i = keys.Count - 1; i >= 0; i--)
            {
                Press(keys[i], true);
                down.Remove(keys[i]);
                since.Remove(keys[i]);
            }
        }

        static void ReleaseAll()
        {
            lock (gate)
            {
                for (int i = down.Count - 1; i >= 0; i--)
                {
                    try { Press(down[i], true); } catch (Exception) { }
                }
                down.Clear();
                since.Clear();
            }
        }

        // keys that have been down for far longer than any real key press are released (a lost "up")
        static void Watchdog()
        {
            while (true)
            {
                Thread.Sleep(5000);
                lock (gate)
                {
                    for (int i = down.Count - 1; i >= 0; i--)
                    {
                        DateTime t;
                        if (since.TryGetValue(down[i], out t) && DateTime.UtcNow - t > MaxHold)
                        {
                            try { Press(down[i], true); } catch (Exception) { }
                            since.Remove(down[i]);
                            down.RemoveAt(i);
                        }
                    }
                }
            }
        }

        // end together with the plugin that started us, whatever happened to the pipes
        static void WatchParent(int pid)
        {
            try
            {
                System.Diagnostics.Process parent = System.Diagnostics.Process.GetProcessById(pid);
                parent.WaitForExit();
            }
            catch (Exception) { /* the process is already gone */ }
            ReleaseAll();
            Environment.Exit(0);
        }

        static List<int> Parse(string[] parts)
        {
            List<int> keys = new List<int>();
            for (int i = 1; i < parts.Length; i++)
            {
                int vk;
                if (!int.TryParse(parts[i], out vk) || vk < 1 || vk > 254) throw new ArgumentException("bad key code '" + parts[i] + "'");
                keys.Add(vk);
            }
            if (keys.Count == 0) throw new ArgumentException("no key codes");
            if (keys.Count > 6) throw new ArgumentException("too many keys");
            return keys;
        }

        static string Handle(string line)
        {
            string[] parts = line.Split(new char[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length == 0) return null;
            dryLog.Length = 0;
            string verb = parts[0].ToLowerInvariant();
            if (requireForeground != null && (verb == "down" || verb == "tap"))
            {
                string front = ForegroundName();
                if (front.IndexOf(requireForeground, StringComparison.OrdinalIgnoreCase) < 0) return "err not-foreground " + front;
            }
            if (verb == "foreground") return "ok " + ForegroundName();
            if (verb == "down") Down(Parse(parts));
            else if (verb == "up") Up(Parse(parts));
            else if (verb == "tap")
            {
                List<int> keys = Parse(parts);
                Down(keys);
                if (!dry) Thread.Sleep(40);
                Up(keys);
            }
            else if (verb == "release") ReleaseAll();
            else if (verb == "quit") return "quit";
            else throw new ArgumentException("unknown command '" + parts[0] + "'");
            return dry ? "ok dry" + dryLog : "ok";
        }

        static int Main(string[] args)
        {
            dry = Array.IndexOf(args, "--dry") >= 0;
            Console.CancelKeyPress += delegate { ReleaseAll(); };
            AppDomain.CurrentDomain.ProcessExit += delegate { ReleaseAll(); };
            int rf = Array.IndexOf(args, "--require-foreground");
            if (rf >= 0 && rf + 1 < args.Length) requireForeground = args[rf + 1];
            int parentPid;
            int p = Array.IndexOf(args, "--parent");
            if (p >= 0 && p + 1 < args.Length && int.TryParse(args[p + 1], out parentPid))
            {
                Thread watch = new Thread(delegate() { WatchParent(parentPid); });
                watch.IsBackground = true;
                watch.Start();
            }
            Thread dog = new Thread(Watchdog);
            dog.IsBackground = true;
            dog.Start();
            string line;
            try
            {
                while ((line = Console.In.ReadLine()) != null)
                {
                    string answer;
                    try { lock (gate) { answer = Handle(line); } }
                    catch (Exception ex) { answer = "err " + ex.Message; }
                    if (answer == null) continue;
                    if (answer == "quit") break;
                    Console.Out.WriteLine(answer);
                    Console.Out.Flush();
                }
            }
            finally
            {
                dryLog.Length = 0;
                ReleaseAll();
                if (dry) { Console.Out.WriteLine("bye dry" + dryLog); Console.Out.Flush(); }
            }
            return 0;
        }
    }
}
