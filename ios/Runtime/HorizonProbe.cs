using Ryu.iOS.HorizonChecks;
using Ryujinx.Audio.Backends.Dummy;
using Ryujinx.Common.Logging;
using Ryujinx.HLE;
using System;
using System.IO;
using System.Threading;

namespace Ryu.iOS.Runtime;

public static class HorizonProbe
{
    public static string Run(string directory)
    {
        ServiceBootstrap.Initialize(directory);
        using var reached = new ManualResetEventSlim();
        void Observe(object sender, LogEventArgs entry)
        {
            if (entry.Message.Contains(KernelHomebrew.Marker, StringComparison.Ordinal)) reached.Set();
        }
        Logger.Updated += Observe;
        Switch device = null;
        try
        {
            var renderer = new NoGraphicsRenderer();
            var configuration = ServiceBootstrap.KernelProbeConfiguration(renderer, new DummyHardwareDeviceDriver());
            string executable = Path.Combine(directory, "kernel-probe.nro");
            File.WriteAllBytes(executable, KernelHomebrew.Create());
            device = new Switch(configuration);
            if (!device.LoadProgram(executable)) throw new InvalidOperationException("The real NRO loader rejected the probe.");
            // The real CPU waits for this gate even when homebrew makes no GPU calls.
            device.Gpu.InitializeShaderCache(CancellationToken.None);
            if (!reached.Wait(TimeSpan.FromSeconds(20))) throw new TimeoutException("Horizon did not emit the heap-success marker.");
            var deadline = DateTime.UtcNow.AddSeconds(10);
            while (device.Processes.ActiveApplication != null && DateTime.UtcNow < deadline) Thread.Sleep(10);
            if (device.Processes.ActiveApplication != null) throw new TimeoutException("Guest process did not exit.");
            return "PASS real Horizon kernel and NRO loader\nPASS SetHeapSize / OutputDebugString / ExitProcess\nBundled homebrew completed. No emulated graphics tested.";
        }
        finally
        {
            if (device != null)
            {
                device.Gpu.HostInitalized.Set();
                device.Gpu.InitializeShaderCache(CancellationToken.None);
                device.Dispose();
                device.DisposeGpu();
            }
            Logger.Updated -= Observe;
        }
    }
}
