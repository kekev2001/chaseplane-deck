// Update check. If an update address was built in (build\Build-Installer.ps1 -UpdateUrl), Setup fetches a small JSON file when it starts:
//   { "version": "1.1.0.0", "url": "https://example.com/ChasePlane-Deck-1.1.zip", "notes": "What is new" }
// and, when that version is newer than this Setup, shows a link to the download page. Nothing is downloaded or run automatically;
// the only thing sent is the HTTP request for that one file. Without an address built in, Setup never touches the network.
using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Reflection;
using System.Text;
using System.Web.Script.Serialization;

namespace ChasePlaneDeckSetup
{
    internal sealed class UpdateInfo
    {
        public Version Version;
        public string Url, Notes;
    }

    internal static class Updater
    {
        public static Version Current { get { return Assembly.GetExecutingAssembly().GetName().Version; } }

        // address of the JSON file (embedded at build time; CPDECK_UPDATE_URL overrides it for tests)
        public static string ConfiguredUrl()
        {
            string o = Environment.GetEnvironmentVariable("CPDECK_UPDATE_URL");
            if (!string.IsNullOrEmpty(o)) return o;
            try
            {
                using (Stream s = typeof(Updater).Assembly.GetManifestResourceStream("update.txt"))
                {
                    if (s == null) return null;
                    using (StreamReader r = new StreamReader(s, Encoding.UTF8)) { string t = r.ReadToEnd().Trim(); return t.Length == 0 ? null : t; }
                }
            }
            catch (Exception) { return null; }
        }

        static bool IsAllowedSource(string url)
        {
            Uri u;
            if (!Uri.TryCreate(url, UriKind.Absolute, out u)) return false;
            if (u.Scheme == Uri.UriSchemeHttps) return true;
            return u.Scheme == Uri.UriSchemeHttp && u.IsLoopback;      // plain http only for a test server on this PC
        }

        // the download link is opened in the browser, so only https links are accepted
        public static bool IsSafeDownload(string url)
        {
            Uri u;
            return Uri.TryCreate(url, UriKind.Absolute, out u) && u.Scheme == Uri.UriSchemeHttps;
        }

        // returns the update when a newer version is announced; null when up to date, not configured, or not reachable
        public static UpdateInfo Check()
        {
            string url = ConfiguredUrl();
            if (url == null) { LastStatus = "no update address built in"; return null; }
            if (!IsAllowedSource(url)) { LastStatus = "update address refused (needs https)"; return null; }
            try
            {
                ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072;     // TLS 1.2
                HttpWebRequest req = (HttpWebRequest)WebRequest.Create(url);
                req.Timeout = 5000; req.ReadWriteTimeout = 5000; req.UserAgent = "ChasePlaneDeckSetup/" + Current;
                req.Proxy = WebRequest.GetSystemWebProxy();
                string text;
                using (WebResponse resp = req.GetResponse())
                using (StreamReader r = new StreamReader(resp.GetResponseStream(), Encoding.UTF8))
                {
                    char[] buf = new char[65536]; int n = r.Read(buf, 0, buf.Length);    // the file is tiny; never read more than 64 KB
                    text = new string(buf, 0, Math.Max(n, 0));
                }
                Dictionary<string, object> d = new JavaScriptSerializer().DeserializeObject(text) as Dictionary<string, object>;
                if (d == null || !d.ContainsKey("version") || !d.ContainsKey("url")) { LastStatus = "answer not understood"; return null; }
                Version v;
                if (!Version.TryParse(Convert.ToString(d["version"]), out v)) { LastStatus = "answer not understood (version)"; return null; }
                string link = Convert.ToString(d["url"]);
                if (v <= Current) { LastStatus = "up to date (latest announced: " + v + ")"; return null; }
                if (!IsSafeDownload(link)) { LastStatus = "newer version announced but its link is not https; ignored"; return null; }
                string notes = d.ContainsKey("notes") ? Convert.ToString(d["notes"]) : "";
                if (notes.Length > 300) notes = notes.Substring(0, 300);
                LastStatus = "update available: " + v;
                return new UpdateInfo { Version = v, Url = link, Notes = notes };
            }
            catch (Exception ex) { LastStatus = "address not reachable or answer unreadable: " + ex.Message; return null; }
        }

        public static string LastStatus = "";
    }
}
