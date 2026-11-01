// The hotkeys-only profiles (no plugin needed: every key sends a keyboard shortcut) travel inside this exe, one per Stream Deck model.
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace ChasePlaneDeckSetup
{
    internal sealed class HkProfile
    {
        public string File, Title;
        public string FileName { get { return "ChasePlane " + File + " (hotkeys only).streamDeckProfile"; } }
    }

    internal static class HotkeyProfiles
    {
        // hk.txt: File|Title  (File = Standard, Mini, XL, ...)
        public static List<HkProfile> List()
        {
            List<HkProfile> list = new List<HkProfile>();
            using (Stream s = typeof(HotkeyProfiles).Assembly.GetManifestResourceStream("hk.txt"))
            using (StreamReader r = new StreamReader(s, Encoding.UTF8))
            {
                string line;
                while ((line = r.ReadLine()) != null)
                {
                    line = line.Trim();
                    if (line.Length == 0 || line[0] == '#') continue;
                    string[] f = line.Split('|');
                    if (f.Length >= 2) list.Add(new HkProfile { File = f[0], Title = f[1] });
                }
            }
            return list;
        }

        public static string Extract(HkProfile p, string dir)
        {
            Directory.CreateDirectory(dir);
            string target = Path.Combine(dir, p.FileName);
            using (Stream s = typeof(HotkeyProfiles).Assembly.GetManifestResourceStream("hk." + p.File + ".streamDeckProfile"))
            using (FileStream o = System.IO.File.Create(target))
            {
                s.CopyTo(o);
            }
            return target;
        }

        public static void ExportAll(string dir)
        {
            foreach (HkProfile p in List()) Extract(p, dir);
        }
    }
}
