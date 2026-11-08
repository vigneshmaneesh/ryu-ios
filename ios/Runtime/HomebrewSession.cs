using Ryujinx.Audio.Backends.Dummy;
using Ryujinx.Audio.Integration;
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
        IHardwareDeviceDriver audio = null;
        bool gpuReady = false;
        long requestedExit = 0;
        ulong audioBefore = AppleAudioDriver.Available ? AppleAudioDriver.Counter(0, 2) : 0;
        int guestSawInput = 0, guestSawTouch = 0, guestScored = 0;
        void ObserveInput(object sender, LogEventArgs entry) {
            if (entry.Message.Contains("RYU_PLAY: input", StringComparison.Ordinal)) Volatile.Write(ref guestSawInput, 1);
            if (entry.Message.Contains("RYU_PLAY: touch", StringComparison.Ordinal)) Volatile.Write(ref guestSawTouch, 1);
            if (entry.Message.Contains("RYU_PLAY: target collected", StringComparison.Ordinal)) Volatile.Write(ref guestScored, 1);
        }
        Logger.Updated += ObserveInput;
        void RequestExit(ulong pid) => Volatile.Write(ref requestedExit, unchecked((long)pid));
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
            audio = AppleAudioDriver.Available ? new AppleAudioDriver() : new DummyHardwareDeviceDriver();
            device = new Switch(ServiceBootstrap.KernelProbeConfiguration(renderer, audio));
            var input = new PlayerInput.Writer(device);
            HorizonJournal.Write(AppleAudioDriver.Available ? "Native Apple AudioQueue output and player-one HID connected" : "Audio callbacks unavailable; using silent backend");
            device.ApplicationExitRequested += RequestExit;
            HorizonJournal.Write("Initializing Vulkan and the GPU thread");
            renderer.Initialize(GraphicsDebugLevel.None);
            renderer.Window.SetSize(width, height);
            renderer.Window.ChangeVSyncMode(device.VSyncMode);
            device.Gpu.SetGpuThread();
            HorizonJournal.Write("Loading guest NRO: " + Path.GetFileName(program));
            if (!device.LoadProgram(program)) throw new InvalidOperationException("The NRO loader rejected this homebrew.");
            ulong applicationPid = device.Processes.ActiveApplication?.ProcessId ?? 0;
            device.Gpu.InitializeShaderCache(CancellationToken.None);
            gpuReady = true;
            HorizonJournal.Write("CPU and GPU ready; processing the guest command stream");
            var boot = Stopwatch.StartNew();
            bool firstFrame = false;
            bool stopped = false;
            long nextInput = 0;
            while (device.Processes.ActiveApplication != null)
            {
                if (unchecked((ulong)Volatile.Read(ref requestedExit)) == applicationPid)
                {
                    HorizonJournal.Write("Guest requested application exit through applet AM");
                    break;
                }
                if (cancelled != null && cancelled() != 0) { stopped = true; break; }
                bool paused = PlayerInput.Paused;
                if (paused != device.System.IsPaused) { device.System.TogglePauseEmulation(paused); HorizonJournal.Write(paused ? "Game paused" : "Game resumed"); }
                if (paused) { boot.Stop(); Thread.Sleep(8); continue; }
                boot.Start();
                if (boot.ElapsedMilliseconds >= nextInput) { input.Update(device); nextInput = boot.ElapsedMilliseconds + 8; }
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
            ulong audioFrames = AppleAudioDriver.Available ? AppleAudioDriver.Counter(0, 2) - audioBefore : 0;
            return $"{(stopped ? "Stopped" : "Completed")} {Path.GetFileName(program)}\nGuest GPU frames: {renderer.PresentedFrames}\nApple audio frames consumed: {audioFrames}\nPlayer-one controller and touchscreen connected.\n" + (Volatile.Read(ref guestSawInput) != 0 ? "Guest confirmed input.\n" : "") + (Volatile.Read(ref guestSawTouch) != 0 ? "Guest confirmed touch.\n" : "") + (Volatile.Read(ref guestScored) != 0 ? "Guest collected target.\n" : "") + "Commercial game compatibility is still being developed.";
        }
        finally
        {
            if (device != null)
            {
                device.ApplicationExitRequested -= RequestExit;
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
            else { audio?.Dispose(); renderer?.Dispose(); }
            StartupDiagnostics.Checkpoint = null;
            Logger.Updated -= HorizonJournal.Observe;
            Logger.Updated -= ObserveInput;
            PlayerInput.Reset();
        }
    }
}
