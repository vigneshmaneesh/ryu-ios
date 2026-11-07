using Ryujinx.Common.Logging;
using System;
using System.IO;
using System.Text;

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

    internal static void Begin(string directory)
    {
        lock (Gate)
        {
            Directory.CreateDirectory(directory);
            _stream?.Dispose();
            _stream = new FileStream(Path.Combine(directory, "horizon-last-run.log"), FileMode.Create,
                FileAccess.Write, FileShare.Read, 4096, FileOptions.WriteThrough);
            _written = 0;
            if (!_hooked)
            {
                AppDomain.CurrentDomain.UnhandledException += (_, args) =>
                    Write("UNHANDLED " + (args.ExceptionObject is Exception exception ? exception.ToString() : "Unknown exception"));
                _hooked = true;
            }
            Write("START Horizon homebrew; " + System.Runtime.InteropServices.RuntimeInformation.OSDescription);
        }
    }

    internal static void Write(string message)
    {
        lock (Gate)
        {
            if (_stream == null) return;
            try
            {
                string line = DateTime.UtcNow.ToString("HH:mm:ss.fff") + " " + message + "\n";
                byte[] data = Encoding.UTF8.GetBytes(line);
                if (_written + data.Length > Limit) return;
                _stream.Write(data);
                _stream.Flush(flushToDisk: true);
                _written += data.Length;
            }
            catch (IOException) { } // Diagnostics must not replace the original failure.
            catch (ObjectDisposedException) { }
        }
    }

    internal static void Observe(object sender, LogEventArgs entry)
    {
        if (entry.Level is LogLevel.Error or LogLevel.Warning ||
            entry.Message.Contains("RYU_KERNEL_PROBE:", StringComparison.Ordinal))
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
