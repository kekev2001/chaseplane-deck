// Two languages in one installer: English and Dutch. Starts in the Windows display language (Dutch on a Dutch Windows,
// English otherwise); /lang:nl or /lang:en overrides it, and the window has a language box.
using System;
using System.Globalization;

namespace ChasePlaneDeckSetup
{
    internal static class Loc
    {
        public static string Lang = "en";
        public static bool IsNl { get { return Lang == "nl"; } }

        public static void Detect()
        {
            string two = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName;
            Lang = (two == "nl") ? "nl" : "en";
        }

        public static void Set(string lang)
        {
            Lang = (lang != null && lang.ToLowerInvariant().StartsWith("nl")) ? "nl" : "en";
        }

        // T("english", "nederlands", args...): picks the text and formats it ({0}, {1}, ...) when arguments are given
        public static string T(string en, string nl, params object[] args)
        {
            string s = IsNl ? nl : en;
            return args.Length == 0 ? s : string.Format(s, args);
        }
    }
}
