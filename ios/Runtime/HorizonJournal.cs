using Ryujinx.Common.Logging;
using System;
using System.IO;
using System.Text;
using System.Runtime.InteropServices;
using System.Collections.Generic;

namespace Ryu.iOS.Runtime;

// Kept in app storage and flushed at checkpoints, so a native crash or process
// termination still leaves the last completed stage visible after relaunch.
internal static class HorizonJournal
{
    private const int Limit = 48 * 1024;
    private static readonly object Gate = new();
    private static FileStream _stream;
    private static bool _hooked;
    private static int _written;
    private static readonly Queue<byte[]> Recent = new();

    internal static void Begin(string directory, string filename = "horizon-last-run.log", string workload = "Horizon homebrew")
    {
        lock (Gate)
        {
            Directory.CreateDirectory(directory);
            _stream?.Dispose();
            _stream = new FileStream(Path.Combine(directory, filename), FileMode.Create,
                FileAccess.Write, FileShare.Read, 4096, FileOptions.WriteThrough);
            _written = 0;
            Recent.Clear();
            if (!_hooked)
            {
                AppDomain.CurrentDomain.UnhandledException += (_, args) =>
                    Write("UNHANDLED " + (args.ExceptionObject is Exception exception ? exception.ToString() : "Unknown exception"));
                _hooked = true;
            }
            Write("START " + workload + "; " + System.Runtime.InteropServices.RuntimeInformation.OSDescription);
            if (OperatingSystem.IsIOS() || OperatingSystem.IsMacOS())
                Write("Host thread stack: " + GetStackSize(GetCurrentThread()) + " bytes");
        }
    }

    [DllImport("/usr/lib/libSystem.B.dylib", EntryPoint = "pthread_self")]
    private static extern nuint GetCurrentThread();
    [DllImport("/usr/lib/libSystem.B.dylib", EntryPoint = "pthread_get_stacksize_np")]
    private static extern nuint GetStackSize(nuint thread);

    internal static void Write(string message)
    {
        lock (Gate)
        {
            if (_stream == null) return;
            try
            {
                string line = DateTime.UtcNow.ToString("HH:mm:ss.fff") + " " + message + "\n";
                byte[] data = Encoding.UTF8.GetBytes(line);
                if (data.Length > Limit - 256) data = Encoding.UTF8.GetBytes("[Long entry trimmed] " + line[^Math.Min(line.Length, 8000)..]);
                bool trim = false;
                while (_written + data.Length > Limit - 128 && Recent.TryDequeue(out var old)) { _written -= old.Length; trim = true; }
                Recent.Enqueue(data);
                _written += data.Length;
                if (trim)
                {
                    _stream.SetLength(0); _stream.Position = 0;
                    _stream.Write("[Older trace entries trimmed; latest events follow]\n"u8);
                    foreach (var entry in Recent) _stream.Write(entry);
                }
                else _stream.Write(data);
                _stream.Flush(flushToDisk: true);
            }
            catch (IOException) { } // Diagnostics must not replace the original failure.
            catch (ObjectDisposedException) { }
        }
    }

    internal static void Observe(object sender, LogEventArgs entry)
    {
        if (entry.Level is LogLevel.Error or LogLevel.Warning ||
            entry.Message.Contains("RYU_KERNEL_PROBE:", StringComparison.Ordinal) || entry.Message.Contains("RYU_PLAY:", StringComparison.Ordinal))
            Write("LOG " + entry.Message);
    }

    internal static void Finish(bool passed, Exception error = null)
    {
        lock (Gate)
        {
            if (error != null) Write(error.ToString());
            Write(passed ? "RESULT PASS" : "RESULT FAIL");
            _stream?.Dispose();
            _stream = null;
        }
    }
}
