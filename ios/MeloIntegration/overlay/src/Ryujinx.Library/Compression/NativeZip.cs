using System;
using System.IO;
using System.IO.Compression;
using System.Runtime.InteropServices;

namespace Ryujinx.Library 
{
    public static unsafe class ZipNative
    {
        [ThreadStatic]
        private static string? _lastError;

        [UnmanagedCallersOnly(EntryPoint = "zip_extract")]
        public static int ExtractZip(byte* zipPathUtf8, byte* destPathUtf8, int overwrite)
        {
            try
            {
                string zipPath = PtrToString(zipPathUtf8);
                string destPath = PtrToString(destPathUtf8);

                ExtractManaged(zipPath, destPath, overwrite != 0);

                return 0;
            }
            catch (Exception ex)
            {
                _lastError = ex.Message;
                return -99;
            }
        }

        [UnmanagedCallersOnly(EntryPoint = "zip_entry_count")]
        public static int GetEntryCount(byte* zipPathUtf8)
        {
            try
            {
                string zipPath = PtrToString(zipPathUtf8);
                using ZipArchive archive = ZipFile.OpenRead(zipPath);
                return archive.Entries.Count;
            }
            catch (Exception ex)
            {
                _lastError = ex.Message;
                return -1;
            }
        }

        [UnmanagedCallersOnly(EntryPoint = "zip_get_last_error")]
        public static IntPtr GetLastError()
        {
            string msg = _lastError ?? "No error";
            return Marshal.StringToCoTaskMemUTF8(msg);
        }

        [UnmanagedCallersOnly(EntryPoint = "zip_free_string")]
        public static void FreeString(IntPtr ptr)
        {
            if (ptr != IntPtr.Zero)
                Marshal.FreeCoTaskMem(ptr);
        }

        // Preflight every entry before writing. Refuse links and existing linked
        // parents, Windows/Unix absolute paths, prefix-sibling escapes and bombs.
        public static void ExtractManaged(string zipPath, string destPath, bool overwrite)
        {
            const long maxBytes = 32L * 1024 * 1024 * 1024;
            const int maxEntries = 100000;
            string root = Path.TrimEndingDirectorySeparator(Path.GetFullPath(destPath));
            using ZipArchive archive = ZipFile.OpenRead(zipPath);
            if (archive.Entries.Count > maxEntries) throw new InvalidDataException("Archive has too many entries.");
            long total = 0;
            foreach (ZipArchiveEntry entry in archive.Entries)
            {
                total = checked(total + entry.Length);
                if (total > maxBytes) throw new InvalidDataException("Archive exceeds extraction limit.");
                string name = entry.FullName.Replace('\\', '/');
                if (name.StartsWith('/') || name.Contains(':') || ((entry.ExternalAttributes >> 16) & 0xF000) == 0xA000)
                    throw new InvalidDataException("Unsafe archive entry: " + name);
                string target = Path.GetFullPath(Path.Combine(root, name));
                string relative = Path.GetRelativePath(root, target);
                if (relative == ".." || relative.StartsWith(".." + Path.DirectorySeparatorChar) || Path.IsPathRooted(relative))
                    throw new InvalidDataException("Archive entry escapes destination: " + name);
                RejectLinks(root, target);
            }
            Directory.CreateDirectory(root);
            foreach (ZipArchiveEntry entry in archive.Entries)
            {
                string target = Path.GetFullPath(Path.Combine(root, entry.FullName.Replace('\\', '/')));
                RejectLinks(root, target);
                if (string.IsNullOrEmpty(entry.Name)) { Directory.CreateDirectory(target); continue; }
                Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                using Stream input = entry.Open();
                using var output = new FileStream(target, overwrite ? FileMode.Create : FileMode.CreateNew, FileAccess.Write, FileShare.None);
                long remaining = entry.Length;
                byte[] buffer = new byte[81920];
                int read;
                while ((read = input.Read(buffer)) != 0)
                {
                    remaining -= read;
                    if (remaining < 0) throw new InvalidDataException("Archive size differs from its header.");
                    output.Write(buffer, 0, read);
                }
                if (remaining != 0) throw new InvalidDataException("Truncated archive entry.");
            }
        }

        private static void RejectLinks(string root, string target)
        {
            for (string? current = target; current != null; current = Path.GetDirectoryName(current))
            {
                if ((File.Exists(current) || Directory.Exists(current)) &&
                    (File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
                    throw new InvalidDataException("Linked extraction path: " + current);
                // System aliases above the selected root are not archive paths.
                if (current == root) break;
            }
        }

        private static string PtrToString(byte* ptr)
        {
            if (ptr == null) return string.Empty;
            return Marshal.PtrToStringUTF8((IntPtr)ptr) ?? string.Empty;
        }
    }
}
