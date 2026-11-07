using Ryujinx.Common.Logging;
using Ryujinx.Common.Logging.Targets;
using System;
using System.Runtime.InteropServices;

internal static class Checks
{
    [UnmanagedCallersOnly(EntryPoint = "ryu_ios_logging_check")]
    public static int Run()
    {
        if (!OperatingSystem.IsIOS()) return 10;
        // Negative control: this must be the iOS BCL, where terminal colour is
        // unsupported, rather than the desktop console used by the Mac checks.
        try { Console.ForegroundColor = ConsoleColor.Yellow; return 11; }
        catch (PlatformNotSupportedException) { }

        Logger.Warning?.PrintMsg(LogClass.Application, "iOS async logger regression");
        Logger.Error?.PrintMsg(LogClass.Application, "iOS error logger regression");
        Logger.Flush();
        using var direct = new ConsoleLogTarget("iOS direct regression");
        direct.Log(null, new LogEventArgs(LogLevel.Warning, TimeSpan.Zero, "test", "iOS direct logger regression"));
        // Dispose is deliberately exercised too: ResetColor also throws on iOS.
        return 0;
    }
}
