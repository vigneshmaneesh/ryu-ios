using Ryujinx.Common.Configuration;
using Ryujinx.HLE.FileSystem;
using LibHac.Common;
using LibHac.Common.Keys;
using LibHac.Tools.Fs;
using System;
using System.IO;
using System.IO.Compression;
using System.Text.RegularExpressions;

namespace Ryu.iOS.Runtime;

internal static class ContentImports
{
    internal sealed class SetupException(string message) : Exception(message);
    private static string SystemContents(string root) => Path.Combine(root, "bis", "system", "Contents");
    private static void DeleteOwned(string root, string path)
    {
        string relative = Path.GetRelativePath(Path.GetFullPath(root), Path.GetFullPath(path));
        if (relative == "." || relative == ".." || relative.StartsWith(".." + Path.DirectorySeparatorChar) || Path.IsPathRooted(relative))
            throw new InvalidOperationException("Refusing to change storage outside the emulator directory.");
        if (Directory.Exists(path)) Directory.Delete(path, true);
    }
    internal static void RecoverFirmware(string root)
    {
        string contents = SystemContents(root), installed = Path.Combine(contents, "registered"), backup = Path.Combine(contents, "ryu-backup");
        string pending = Path.Combine(contents, "ryu-install.pending");
        if (Directory.Exists(backup))
        {
            if (File.Exists(pending) || !Directory.Exists(installed))
            {
                DeleteOwned(root, installed); Directory.Move(backup, installed);
            }
            else DeleteOwned(root, backup);
        }
        if (File.Exists(pending)) File.Delete(pending);
        DeleteOwned(root, Path.Combine(contents, "temp"));
    }
    internal static string Status(string root)
    {
        ServiceBootstrap.Initialize(root);
        bool keys = File.Exists(Path.Combine(AppDataManager.KeysDirPath, "prod.keys"));
        string version;
        try { version = ServiceBootstrap.Content.GetCurrentFirmwareVersion()?.VersionString ?? "Not installed"; }
        catch { version = "Unavailable — check your prod.keys"; }
        return $"prod.keys: {(keys ? "Imported" : "Not imported")}\nFirmware: {version}";
    }
    internal static string ImportKeys(string source, string root)
    {
        ServiceBootstrap.Initialize(root);
        string name = Path.GetFileName(source);
        if (name == "key_retail.bin")
        {
            if (new FileInfo(source).Length != 160) throw new InvalidDataException("key_retail.bin must contain 160 bytes.");
            byte[] bytes = File.ReadAllBytes(source);
            if (bytes.Length != 160) throw new InvalidDataException("key_retail.bin must contain 160 bytes.");
            _ = Ryujinx.HLE.HOS.Services.Nfc.AmiiboDecryption.AmiiboMasterKey.FromCombinedBin(bytes);
            string destination = Path.Combine(AppDataManager.KeysDirPath, name), temporary = destination + ".tmp";
            File.WriteAllBytes(temporary, bytes); File.Move(temporary, destination, true);
            return "Imported amiibo key file.\n" + Status(root);
        }
        if (name is not ("prod.keys" or "title.keys")) throw new ArgumentException("Select prod.keys or title.keys with its original filename.");
        if (new FileInfo(source).Length > 4 * 1024 * 1024) throw new ArgumentException("The key file is unexpectedly large.");
        string staging = Path.Combine(root, "key-import-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(staging);
        try
        {
            // The upstream validator runs before any existing key file is replaced.
            ContentManager.InstallKeys(source, staging);
            string validated = Path.Combine(staging, name), destination = Path.Combine(AppDataManager.KeysDirPath, name), backup = Path.Combine(staging, "previous.keys");
            var candidate = KeySet.CreateDefaultKeySet();
            ExternalKeyReader.ReadKeyFile(candidate, name == "prod.keys" ? validated : null, null, name == "title.keys" ? validated : null, null, null);
            if (name == "prod.keys" && candidate.HeaderKey.IsZeros()) throw new InvalidDataException("Missing header key.");
            bool existed = File.Exists(destination);
            if (existed) File.Copy(destination, backup);
            try { File.Move(validated, destination, true); ServiceBootstrap.FileSystem.ReloadKeySet(); }
            catch {
                if (existed) File.Move(backup, destination, true); else File.Delete(destination);
                ServiceBootstrap.FileSystem.ReloadKeySet(); throw;
            }
            return $"Imported {name}.\n" + Status(root);
        }
        finally { DeleteOwned(root, staging); }
    }
    internal static string InstallFirmware(string source, string root)
    {
        ServiceBootstrap.Initialize(root);
        RecoverFirmware(root);
        if (Path.GetExtension(source) is not (".zip" or ".xci")) throw new ArgumentException("Select a firmware ZIP or an XCI containing a firmware update.");
        if (Path.GetExtension(source) == ".zip")
        {
            using var zip = ZipFile.OpenRead(source);
            foreach (var entry in zip.Entries)
            {
                string name = entry.FullName;
                if (name.EndsWith(".nca", StringComparison.Ordinal) || name.EndsWith(".nca/00", StringComparison.Ordinal))
                {
                    string last = name.EndsWith("/00", StringComparison.Ordinal) ? Path.GetFileName(name[..^3]) : Path.GetFileName(name);
                    if (!Regex.IsMatch(last, "^[0-9a-fA-F]{32}(\\.cnmt)?\\.nca$")) throw new InvalidDataException("Firmware contains an invalid archive name.");
                }
            }
        }
        var version = ServiceBootstrap.Content.VerifyFirmwarePackage(source) ?? throw new InvalidDataException("No valid firmware version found in the selected package.");
        string contents = SystemContents(root), installed = Path.Combine(contents, "registered"), backup = Path.Combine(contents, "ryu-backup");
        string pending = Path.Combine(contents, "ryu-install.pending");
        Directory.CreateDirectory(contents);
        // Keep the previous firmware until the new, verified set is fully installed.
        using (var journal = new FileStream(pending, FileMode.Create, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
        { journal.WriteByte(1); journal.Flush(true); }
        if (Directory.Exists(installed)) Directory.Move(installed, backup);
        try
        {
            ServiceBootstrap.Content.InstallFirmware(source);
            File.Delete(pending); // Commit; any remaining backup is safe to remove.
        }
        catch
        {
            RecoverFirmware(root); ServiceBootstrap.Content.LoadEntries(); throw;
        }
        DeleteOwned(root, backup);
        return $"Installed firmware {version.VersionString}.\n" + Status(root);
    }
    internal static void RequireGameSystem()
    {
        if (!File.Exists(Path.Combine(AppDataManager.KeysDirPath, "prod.keys")))
            throw new SetupException("Import prod.keys in System files before launching an NSP or XCI game.");
        ServiceBootstrap.FileSystem.ReloadKeySet();
        try {
            if (ServiceBootstrap.Content.GetCurrentFirmwareVersion() == null)
                throw new SetupException("Install firmware in System files before launching this game.");
        }
        catch (SetupException) { throw; }
        catch { throw new SetupException("The installed firmware could not be read. Check your prod.keys and firmware in System files."); }
    }
}
