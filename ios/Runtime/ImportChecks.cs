using Ryujinx.Common.Configuration;
using System;
using System.IO;

namespace Ryu.iOS.Runtime;

internal static class ImportChecks
{
    internal static string Run(string directory)
    {
        ServiceBootstrap.Initialize(directory);
        string key = Path.Combine(AppDataManager.KeysDirPath, "prod.keys");
        if (File.Exists(key)) throw new InvalidOperationException("Import checks require a clean disposable data directory.");
        string temporary = Path.Combine(directory, "import-regression");
        Directory.CreateDirectory(temporary);
        string bad = Path.Combine(temporary, "prod.keys");
        File.WriteAllText(bad, "header_key = " + new string('0', 64));
        const string previous = "preserve-existing-file";
        File.WriteAllText(key, previous);
        try
        {
            bool rejected = false;
            try { ContentImports.ImportKeys(bad, directory); } catch { rejected = true; }
            if (!rejected || File.ReadAllText(key) != previous) throw new InvalidOperationException("Invalid keys replaced the existing file.");
        }
        finally { File.Delete(key); File.Delete(bad); }
        string contents = Path.Combine(temporary, "bis", "system", "Contents");
        string current = Path.Combine(contents, "registered"), backup = Path.Combine(contents, "ryu-backup"), pending = Path.Combine(contents, "ryu-install.pending");
        Directory.CreateDirectory(current); Directory.CreateDirectory(backup);
        File.WriteAllText(Path.Combine(current, "new"), "uncommitted");
        File.WriteAllText(Path.Combine(backup, "old"), "accepted");
        File.WriteAllText(pending, "1");
        ContentImports.RecoverFirmware(temporary);
        if (!File.Exists(Path.Combine(current, "old")) || File.Exists(Path.Combine(current, "new")) || File.Exists(pending))
            throw new InvalidOperationException("Interrupted firmware installation did not restore the previous set.");
        Directory.CreateDirectory(backup);
        File.WriteAllText(Path.Combine(backup, "stale"), "old backup");
        ContentImports.RecoverFirmware(temporary);
        if (!File.Exists(Path.Combine(current, "old")) || Directory.Exists(backup)) throw new InvalidOperationException("Committed firmware recovery failed.");
        File.Delete(Path.Combine(current, "old"));
        bool needsSetup = false;
        try { ContentImports.RequireGameSystem(); } catch (ContentImports.SetupException) { needsSetup = true; }
        if (!needsSetup) throw new InvalidOperationException("Commercial game preflight did not report missing system files.");
        return "PASS invalid keys preserve the installed file\nPASS interrupted/committed firmware recovery\nPASS commercial-game setup preflight";
    }
}
