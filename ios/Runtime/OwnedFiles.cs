using System;
using System.IO;
using System.IO.Compression;
using System.Linq;

namespace Ryu.iOS.Runtime;

internal static class OwnedFiles
{
    internal static string RequireWithin(string root, string path)
    {
        root = Path.TrimEndingDirectorySeparator(Path.GetFullPath(root)); path = Path.GetFullPath(path);
        string relative = Path.GetRelativePath(root, path);
        if (relative == "." || relative == ".." || relative.StartsWith(".." + Path.DirectorySeparatorChar, StringComparison.Ordinal) || Path.IsPathRooted(relative)) throw new ArgumentException("The path must stay inside this app's data folder.");
        string current = root;
        foreach (string part in relative.Split(Path.DirectorySeparatorChar))
        {
            current = Path.Combine(current, part);
            if ((File.Exists(current) || Directory.Exists(current)) && (File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0) throw new ArgumentException("Symbolic links are not accepted here.");
        }
        return path;
    }
    internal static void ExtractZip(string source, string destination, long maximum = 8L * 1024 * 1024 * 1024)
    {
        using var archive = ZipFile.OpenRead(source);
        long total = 0;
        if (archive.Entries.Count > 100000) throw new InvalidDataException("Archive contains too many entries.");
        foreach (var entry in archive.Entries)
        {
            if (entry.FullName.Contains('\\') || entry.FullName.Contains(':') || entry.FullName.StartsWith('/') || entry.FullName.Split('/').Any(p => p is ".." or ".") || ((entry.ExternalAttributes >> 16) & 0xF000) == 0xA000) throw new InvalidDataException("Archive contains an unsafe entry.");
            string path = RequireWithin(destination, Path.Combine(destination, entry.FullName));
            total = checked(total + entry.Length); if (total > maximum) throw new InvalidDataException("Archive exceeds the expanded size limit.");
            if (entry.FullName.EndsWith('/')) { Directory.CreateDirectory(path); continue; }
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            using var input = entry.Open(); using var output = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None);
            byte[] buffer = new byte[65536]; long written = 0; int read;
            while ((read = input.Read(buffer)) > 0) { written = checked(written + read); if (written > entry.Length) throw new InvalidDataException("Archive entry exceeds its declared size."); output.Write(buffer, 0, read); }
            if (written != entry.Length) throw new InvalidDataException("Archive entry is truncated.");
        }
    }
    internal static void Delete(string root, string path) { RequireWithin(root, path); if (Directory.Exists(path)) Directory.Delete(path, true); else if (File.Exists(path)) File.Delete(path); }
}
