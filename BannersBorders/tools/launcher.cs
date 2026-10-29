// launcher.cs - single-file, self-extracting launcher for Banners & Borders.
// Built by tools\package.ps1 with the .NET Framework 4 csc.exe (C# 5: no string interpolation).
// The exported game folder (PhasmaExport output) is embedded as the resource "payload.zip";
// "version.txt" holds a content hash of that folder.
//
// On run: extract once per version into <root>\<version>  (root = %LOCALAPPDATA%\BannersBorders,
// or an ASCII-only fallback when that path has non-ASCII characters, because the engine resolves
// its own folder with ANSI GetModuleFileNameA), carry Assets\Save (and the shader cache) over from
// the previous version, then start <root>\<version>\BannersBorders.exe and exit.
//
// Flags (all other arguments are passed through to the game, e.g. --api dx12):
//   --extract-only          extract/verify only, never start the game (exit code 0 = OK)
//   --install-root <dir>    use <dir> instead of the default root
// Saves are never deleted: old versions beyond the newest two are trimmed down to their Assets\Save.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("Banners & Borders")]
[assembly: AssemblyProduct("Banners & Borders")]
[assembly: AssemblyDescription("Banners & Borders (Phasma Engine) launcher")]

static class Launcher
{
    const string GameFolderName = "BannersBorders";
    const string InnerExe = "BannersBorders.exe";
    const string StampFile = ".extracted";
    const int KeepFullVersions = 2;

    static string s_logPath;

    [STAThread]
    static int Main(string[] args)
    {
        bool extractOnly = false;
        string rootOverride = null;
        List<string> passThrough = new List<string>();
        for (int i = 0; i < args.Length; ++i)
        {
            if (args[i] == "--extract-only") extractOnly = true;
            else if (args[i] == "--install-root" && i + 1 < args.Length) rootOverride = args[++i];
            else passThrough.Add(args[i]);
        }

        try
        {
            string version = ReadResourceText("version.txt").Trim();
            if (version.Length == 0 || !IsAscii(version)) throw new Exception("Launcher has no valid embedded version.");

            string note = "install root from --install-root";
            string root = rootOverride != null ? Path.GetFullPath(rootOverride) : ChooseRoot(out note);
            Directory.CreateDirectory(root);
            s_logPath = Path.Combine(root, "launcher.log");
            Log("---- launcher start, version " + version + (extractOnly ? " (extract-only)" : ""));
            Log("root: " + root + " (" + note + ")");
            if (!IsAscii(root)) Log("WARNING: install root contains non-ASCII characters; the engine may fail to find its files.");

            string dir = Path.Combine(root, version);
            using (Mutex mutex = new Mutex(false, "Local\\BannersBorders.Launcher"))
            {
                try { mutex.WaitOne(); } catch (AbandonedMutexException) { }
                try
                {
                    EnsureExtracted(root, dir, version);
                    TrimOldVersions(root, version);
                }
                finally { mutex.ReleaseMutex(); }
            }

            string exe = Path.Combine(dir, InnerExe);
            if (extractOnly)
            {
                Log("extract-only: ready at " + dir);
                return 0;
            }

            ProcessStartInfo psi = new ProcessStartInfo(exe, JoinArgs(passThrough));
            psi.WorkingDirectory = dir;
            psi.UseShellExecute = false;
            Process.Start(psi);
            Log("started " + exe + " " + psi.Arguments);
            return 0;
        }
        catch (Exception e)
        {
            Log("ERROR: " + e);
            if (!extractOnly)
                MessageBox.Show("Banners & Borders could not start.\n\n" + e.Message +
                                (s_logPath != null ? "\n\nLog: " + s_logPath : ""),
                                "Banners & Borders", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    // ---- install root -------------------------------------------------------------------------

    static string ChooseRoot(out string note)
    {
        List<KeyValuePair<string, string>> candidates = new List<KeyValuePair<string, string>>();
        candidates.Add(new KeyValuePair<string, string>(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "%LOCALAPPDATA%"));
        candidates.Add(new KeyValuePair<string, string>(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "%ProgramData% fallback (shared by all users of this PC)"));
        candidates.Add(new KeyValuePair<string, string>(Environment.GetEnvironmentVariable("PUBLIC"), "%PUBLIC% fallback (shared by all users of this PC)"));
        string sysDrive = Environment.GetEnvironmentVariable("SystemDrive");
        candidates.Add(new KeyValuePair<string, string>(string.IsNullOrEmpty(sysDrive) ? "C:\\" : sysDrive + "\\", "system drive fallback"));

        string firstWritable = null, firstNote = null;
        List<string> skipped = new List<string>();
        foreach (KeyValuePair<string, string> c in candidates)
        {
            if (string.IsNullOrEmpty(c.Key)) continue;
            string root = Path.Combine(c.Key, GameFolderName);
            if (!IsWritable(root)) { skipped.Add(root + " (not writable)"); continue; }
            if (firstWritable == null) { firstWritable = root; firstNote = c.Value; }
            if (!IsAscii(root)) { skipped.Add(root + " (non-ASCII path)"); continue; }
            note = c.Value + (skipped.Count > 0 ? "; skipped: " + string.Join(", ", skipped.ToArray()) : "");
            return root;
        }
        if (firstWritable == null) throw new Exception("No writable folder found to unpack the game into.");
        note = firstNote + " (no ASCII-only location was writable)";
        return firstWritable;
    }

    static bool IsWritable(string dir)
    {
        try
        {
            Directory.CreateDirectory(dir);
            string probe = Path.Combine(dir, ".write-probe-" + Process.GetCurrentProcess().Id);
            File.WriteAllText(probe, "ok");
            File.Delete(probe);
            return true;
        }
        catch { return false; }
    }

    static bool IsAscii(string s)
    {
        foreach (char ch in s) if (ch > 127) return false;
        return true;
    }

    // ---- extraction ---------------------------------------------------------------------------

    static bool IsComplete(string dir, string version)
    {
        string stamp = Path.Combine(dir, StampFile);
        return File.Exists(stamp) && File.Exists(Path.Combine(dir, InnerExe)) &&
               File.Exists(Path.Combine(dir, "game.pepak")) &&
               File.ReadAllText(stamp).Trim().StartsWith(version);
    }

    static void EnsureExtracted(string root, string dir, string version)
    {
        if (IsComplete(dir, version)) { Log("already extracted: " + dir); return; }

        // A damaged/partial folder of this version may still hold saves: keep it aside, migrate from it.
        string migrateFrom = null;
        if (Directory.Exists(dir))
        {
            string aside = dir + ".bak-" + DateTime.Now.ToString("yyyyMMddHHmmss");
            Directory.Move(dir, aside);
            Log("incomplete folder moved aside: " + aside);
            migrateFrom = aside;
        }
        migrateFrom = PickMigrationSource(root, version, migrateFrom);

        foreach (string stale in Directory.GetDirectories(root, version + ".tmp-*"))
            TryDeleteDir(stale); // temp folders never hold the only copy of a save

        string tmp = dir + ".tmp-" + Process.GetCurrentProcess().Id;
        Directory.CreateDirectory(tmp);
        int files = ExtractPayload(tmp);
        Log("extracted " + files + " files into " + tmp);

        if (migrateFrom != null)
        {
            int saves = CopyTree(Path.Combine(migrateFrom, "Assets", "Save"), Path.Combine(tmp, "Assets", "Save"));
            int shaders = CopyTree(Path.Combine(migrateFrom, "ShaderCache"), Path.Combine(tmp, "ShaderCache"));
            Log("migrated from " + migrateFrom + ": " + saves + " save file(s), " + shaders + " shader cache file(s)");
        }

        File.WriteAllText(Path.Combine(tmp, StampFile), version + " " + DateTime.UtcNow.ToString("o") + "\n");
        Directory.Move(tmp, dir);
        Log("ready: " + dir);
    }

    static int ExtractPayload(string target)
    {
        string fullTarget = Path.GetFullPath(target).TrimEnd('\\') + "\\";
        int count = 0;
        using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip"))
        {
            if (s == null) throw new Exception("Launcher has no embedded game payload.");
            using (ZipArchive zip = new ZipArchive(s, ZipArchiveMode.Read))
            {
                foreach (ZipArchiveEntry entry in zip.Entries)
                {
                    string name = entry.FullName.Replace('/', '\\');
                    string dest = Path.GetFullPath(Path.Combine(target, name));
                    if (!dest.StartsWith(fullTarget, StringComparison.OrdinalIgnoreCase))
                        throw new Exception("Bad path in payload: " + entry.FullName);
                    if (name.EndsWith("\\")) { Directory.CreateDirectory(dest); continue; }
                    Directory.CreateDirectory(Path.GetDirectoryName(dest));
                    using (Stream input = entry.Open())
                    using (FileStream output = File.Create(dest))
                        input.CopyTo(output);
                    if (new FileInfo(dest).Length != entry.Length)
                        throw new Exception("Size mismatch while unpacking " + entry.FullName);
                    ++count;
                }
            }
        }
        return count;
    }

    // ---- versions -----------------------------------------------------------------------------

    static List<DirectoryInfo> CompletedVersions(string root)
    {
        List<DirectoryInfo> result = new List<DirectoryInfo>();
        foreach (DirectoryInfo d in new DirectoryInfo(root).GetDirectories())
            if (File.Exists(Path.Combine(d.FullName, StampFile))) result.Add(d);
        result.Sort(delegate(DirectoryInfo a, DirectoryInfo b)
        {
            return File.GetLastWriteTimeUtc(Path.Combine(b.FullName, StampFile))
                .CompareTo(File.GetLastWriteTimeUtc(Path.Combine(a.FullName, StampFile)));
        });
        return result; // newest first
    }

    // The folder whose Assets\Save holds the most recently written save wins (falls back to the newest
    // other version when no save exists yet, so the shader cache still carries over).
    static string PickMigrationSource(string root, string version, string aside)
    {
        List<string> candidates = new List<string>();
        if (aside != null) candidates.Add(aside);
        foreach (DirectoryInfo d in CompletedVersions(root))
            if (!string.Equals(d.Name, version, StringComparison.OrdinalIgnoreCase)) candidates.Add(d.FullName);
        foreach (string b in Directory.GetDirectories(root, "*.bak-*")) if (!candidates.Contains(b)) candidates.Add(b);

        string best = null;
        DateTime bestTime = DateTime.MinValue;
        foreach (string c in candidates)
        {
            string save = Path.Combine(c, "Assets", "Save");
            if (!Directory.Exists(save)) continue;
            foreach (string f in Directory.GetFiles(save, "*", SearchOption.AllDirectories))
            {
                DateTime t = File.GetLastWriteTimeUtc(f);
                if (t > bestTime) { bestTime = t; best = c; }
            }
        }
        if (best != null) return best;
        foreach (string c in candidates)
            if (!c.Contains(".bak-") && Directory.Exists(Path.Combine(c, "ShaderCache"))) return c;
        return null;
    }

    // Keep the current and previous full versions; older ones are reduced to Assets\Save (never deleted).
    static void TrimOldVersions(string root, string current)
    {
        List<DirectoryInfo> versions = CompletedVersions(root);
        versions.RemoveAll(delegate(DirectoryInfo d) { return string.Equals(d.Name, current, StringComparison.OrdinalIgnoreCase); });
        for (int i = KeepFullVersions - 1; i < versions.Count; ++i)
        {
            DirectoryInfo d = versions[i];
            if (File.Exists(Path.Combine(d.FullName, ".trimmed"))) continue;
            try
            {
                foreach (FileInfo f in d.GetFiles())
                    if (f.Name != StampFile) f.Delete();
                foreach (DirectoryInfo sub in d.GetDirectories())
                {
                    if (string.Equals(sub.Name, "Assets", StringComparison.OrdinalIgnoreCase))
                    {
                        foreach (FileInfo f in sub.GetFiles()) f.Delete();
                        foreach (DirectoryInfo a in sub.GetDirectories())
                            if (!string.Equals(a.Name, "Save", StringComparison.OrdinalIgnoreCase)) a.Delete(true);
                    }
                    else sub.Delete(true);
                }
                File.WriteAllText(Path.Combine(d.FullName, ".trimmed"), "Old version: only Assets\\Save is kept.\n");
                Log("trimmed old version (saves kept): " + d.FullName);
            }
            catch (Exception e) { Log("could not trim " + d.FullName + ": " + e.Message); }
        }
    }

    // ---- helpers ------------------------------------------------------------------------------

    static int CopyTree(string from, string to)
    {
        if (!Directory.Exists(from)) return 0;
        int n = 0;
        Directory.CreateDirectory(to);
        foreach (string f in Directory.GetFiles(from)) { File.Copy(f, Path.Combine(to, Path.GetFileName(f)), true); ++n; }
        foreach (string d in Directory.GetDirectories(from)) n += CopyTree(d, Path.Combine(to, Path.GetFileName(d)));
        return n;
    }

    static void TryDeleteDir(string d) { try { Directory.Delete(d, true); } catch { } }

    static string ReadResourceText(string name)
    {
        using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream(name))
        {
            if (s == null) return "";
            using (StreamReader r = new StreamReader(s, Encoding.UTF8)) return r.ReadToEnd();
        }
    }

    static string JoinArgs(List<string> args)
    {
        StringBuilder sb = new StringBuilder();
        foreach (string a in args)
        {
            if (sb.Length > 0) sb.Append(' ');
            if (a.Length > 0 && a.IndexOfAny(new char[] { ' ', '\t', '"' }) < 0) { sb.Append(a); continue; }
            sb.Append('"');
            int slashes = 0;
            foreach (char c in a)
            {
                if (c == '\\') { ++slashes; continue; }
                if (c == '"') { sb.Append('\\', slashes * 2 + 1); sb.Append('"'); }
                else { sb.Append('\\', slashes); sb.Append(c); }
                slashes = 0;
            }
            sb.Append('\\', slashes * 2);
            sb.Append('"');
        }
        return sb.ToString();
    }

    static void Log(string line)
    {
        if (s_logPath == null) return;
        try { File.AppendAllText(s_logPath, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + line + "\r\n"); }
        catch { }
    }
}
