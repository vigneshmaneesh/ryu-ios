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
    public static string Run(string directory, bool loadGuest = true)
    {
        HorizonJournal.Write("Initializing filesystem/account services");
        ServiceBootstrap.Initialize(directory);
        HorizonJournal.Write("Services ready; installing logging observer");
        using var reached = new ManualResetEventSlim();
        void Observe(object sender, LogEventArgs entry)
        {
            if (entry.Message.Contains(KernelHomebrew.Marker, StringComparison.Ordinal)) reached.Set();
        }
        Logger.Updated += Observe;
        Logger.Updated += HorizonJournal.Observe;
        StartupDiagnostics.Checkpoint = HorizonJournal.Write;
        Switch device = null;
        bool gpuReady = false;
        try
        {
            var renderer = new NoGraphicsRenderer();
            var configuration = ServiceBootstrap.KernelProbeConfiguration(renderer, new DummyHardwareDeviceDriver());
            string executable = Path.Combine(directory, "kernel-probe.nro");
            File.WriteAllBytes(executable, KernelHomebrew.Create());
            HorizonJournal.Write("Constructing Switch: RAM, kernel, scheduler and service threads");
            device = new Switch(configuration);
            if (!loadGuest)
            {
                // Match ProcessLoaderHelper: constructor return does not imply
                // that asynchronous service registration has finished. Closing
                // SM first would abort services still inside SmApi.Initialize.
                HorizonJournal.Write("Waiting for all generated service registrations");
                StartupDiagnostics.WaitServicesReady(device);
                HorizonJournal.Write("All generated service registrations ready");
                HorizonJournal.Write("Kernel construction check completed; no guest executed");
                return "PASS real Horizon kernel construction / services / HID / teardown";
            }
            HorizonJournal.Write("Kernel/services constructed; loading authored NRO");
            if (!device.LoadProgram(executable)) throw new InvalidOperationException("The real NRO loader rejected the probe.");
            HorizonJournal.Write("NRO loaded; initializing shader-cache readiness gate");
            // The real CPU waits for this gate even when homebrew makes no GPU calls.
            device.Gpu.InitializeShaderCache(CancellationToken.None);
            gpuReady = true;
            HorizonJournal.Write("Readiness gate open; waiting for guest SVC marker");
            if (!reached.Wait(TimeSpan.FromSeconds(20))) throw new TimeoutException("Horizon did not emit the heap-success marker.");
            HorizonJournal.Write("Guest heap/SVC marker received; waiting for process exit");
            var deadline = DateTime.UtcNow.AddSeconds(10);
            while (device.Processes.ActiveApplication != null && DateTime.UtcNow < deadline) Thread.Sleep(10);
            if (device.Processes.ActiveApplication != null) throw new TimeoutException("Guest process did not exit.");
            HorizonJournal.Write("Guest exiting; starting kernel teardown");
            return "PASS real Horizon kernel and NRO loader\nPASS SetHeapSize / OutputDebugString / ExitProcess\nBundled homebrew completed. No emulated graphics tested.";
        }
        finally
        {
            if (device != null)
            {
                if (!gpuReady)
                {
                    device.Gpu.HostInitalized.Set();
                    device.Gpu.InitializeShaderCache(CancellationToken.None);
                }
                device.Dispose();
                HorizonJournal.Write("Kernel teardown complete; disposing GPU bookkeeping");
                device.DisposeGpu();
                HorizonJournal.Write("GPU bookkeeping disposed");
            }
            Logger.Updated -= Observe;
            Logger.Updated -= HorizonJournal.Observe;
            StartupDiagnostics.Checkpoint = null;
        }
    }
}
