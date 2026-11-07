using Ryujinx.Audio.Backends.Dummy;
using Ryujinx.Common.Logging;
using Ryujinx.Common.Configuration;
using Ryujinx.Graphics.GAL;
using Ryujinx.Graphics.Vulkan;
using Ryujinx.HLE;
using Silk.NET.Vulkan;
using System;
using Stopwatch = System.Diagnostics.Stopwatch;
using System.IO;
using System.Threading;

namespace Ryu.iOS.Runtime;

internal static unsafe class HomebrewSession
{
    internal static string Run(string library, nint layer, int width, int height,
        delegate* unmanaged<nint, nint, ulong*, int> createSurface, delegate* unmanaged<int> cancelled,
        string program, string directory, Action<ulong> updateFrames)
    {
        if (!File.Exists(program) || !program.EndsWith(".nro", StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException("Select an existing NRO homebrew executable.");
        HorizonJournal.Write("Mounting filesystem and account services");
        ServiceBootstrap.Initialize(directory);
        GraphicsBindings.Configure(library);
        using Vk api = GraphicsBindings.CreateApi();
        VulkanRenderer renderer = null;
        Switch device = null;
        bool gpuReady = false;
        Logger.Updated += HorizonJournal.Observe;
        StartupDiagnostics.Checkpoint = HorizonJournal.Write;
        try
        {
            renderer = new VulkanRenderer(api, (instance, _) =>
            {
                ulong surface;
                int result = createSurface(instance.Handle, layer, &surface);
                if (result != 0 || surface == 0) throw new InvalidOperationException($"Metal surface failed: {result}.");
                return new SurfaceKHR(surface);
            }, () => ["VK_KHR_surface", "VK_EXT_metal_surface"], "");
            HorizonJournal.Write("Constructing Switch with the real Vulkan renderer");
            device = new Switch(ServiceBootstrap.KernelProbeConfiguration(renderer, new DummyHardwareDeviceDriver()));
            HorizonJournal.Write("Initializing Vulkan and the GPU thread");
            renderer.Initialize(GraphicsDebugLevel.None);
            renderer.Window.SetSize(width, height);
            renderer.Window.ChangeVSyncMode(device.VSyncMode);
            device.Gpu.SetGpuThread();
            HorizonJournal.Write("Loading guest NRO: " + Path.GetFileName(program));
            if (!device.LoadProgram(program)) throw new InvalidOperationException("The NRO loader rejected this homebrew.");
            device.Gpu.InitializeShaderCache(CancellationToken.None);
            gpuReady = true;
            HorizonJournal.Write("CPU and GPU ready; processing the guest command stream");
            var boot = Stopwatch.StartNew();
            bool firstFrame = false;
            bool stopped = false;
            while (device.Processes.ActiveApplication != null)
            {
                if (cancelled != null && cancelled() != 0) { stopped = true; break; }
                if (device.WaitFifo()) device.ProcessFrame();
                while (device.ConsumeFrameAvailable())
                {
                    device.PresentFrame(static () => { });
                    updateFrames(renderer.PresentedFrames);
                    if (!firstFrame && renderer.PresentedFrames > 0)
                    {
                        firstFrame = true;
                        HorizonJournal.Write("FIRST GUEST FRAME: emulated GPU output presented to Metal");
                    }
                }
                if (!firstFrame && boot.Elapsed > TimeSpan.FromSeconds(60))
                    throw new TimeoutException("Homebrew has not produced a guest frame within 60 seconds. Share the saved log.");
            }
            if (!stopped && !firstFrame) throw new InvalidOperationException("Homebrew exited without presenting a frame.");
            HorizonJournal.Write($"Guest {(stopped ? "stopped" : "exited")}; {renderer.PresentedFrames} frames; starting teardown");
            return $"{(stopped ? "Stopped" : "Completed")} {Path.GetFileName(program)}\nGuest GPU frames: {renderer.PresentedFrames}\nCPU, Horizon, GPU command processing, shader translation and Metal presentation were active.\nAudio and touch/controller input are not connected yet.";
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
                HorizonJournal.Write("Stopping Horizon processes");
                device.Dispose();
                HorizonJournal.Write("Disposing GPU resources");
                device.DisposeGpu();
                HorizonJournal.Write("Homebrew session teardown complete");
            }
            else renderer?.Dispose();
            StartupDiagnostics.Checkpoint = null;
            Logger.Updated -= HorizonJournal.Observe;
        }
    }
}
