using System.Threading;

namespace Ryujinx.Common.Callbacks
{
    public static class UpscalerTelemetry
    {
        private static string _status = "Waiting for renderer";
        public static string Status => Volatile.Read(ref _status);
        public static void Report(string status) => Volatile.Write(ref _status, status);
    }
}
