using Ryujinx.Cpu.Jit;
using Ryujinx.Memory;
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace Ryu.iOS.Runtime;

public static unsafe class CoreApi
{
    private static int _busy;
    private static int _resolverReady;
    private static long _guestFrames;
    public const uint AbiVersion = 1;

    [UnmanagedCallersOnly(EntryPoint = "ryu_core_input_set")]
    public static void SetInput(ulong buttons, int lx, int ly, int rx, int ry) => PlayerInput.Set(buttons, lx, ly, rx, ry);
    [UnmanagedCallersOnly(EntryPoint = "ryu_core_touch_set")]
    public static void SetTouch(int down, int x, int y) => PlayerInput.Touch(down != 0, x, y);
    [UnmanagedCallersOnly(EntryPoint = "ryu_core_input_reset")]
    public static void ResetInput() => PlayerInput.Reset();
    [UnmanagedCallersOnly(EntryPoint = "ryu_core_pause")]
    public static void Pause(int paused) => PlayerInput.Paused = paused != 0;
    [UnmanagedCallersOnly(EntryPoint = "ryu_core_audio_configure")]
    public static int ConfigureAudio(delegate* unmanaged<uint, uint, nint> open,
        delegate* unmanaged<nint, byte*, nuint, ulong, int> enqueue,
        delegate* unmanaged<nint, int, float, int> control,
        delegate* unmanaged<nint, int, ulong> counter, delegate* unmanaged<nint, void> close)
    {
        if (Interlocked.CompareExchange(ref _busy, 1, 0) != 0) return -2;
        try { AppleAudioDriver.Open = open; AppleAudioDriver.Enqueue = enqueue; AppleAudioDriver.Control = control; AppleAudioDriver.Counter = counter; AppleAudioDriver.Close = close; return 0; }
        finally { Volatile.Write(ref _busy, 0); }
    }

    [UnmanagedCallersOnly(EntryPoint = "ryu_core_abi_version")]
    public static uint GetAbiVersion() => AbiVersion;

    [UnmanagedCallersOnly(EntryPoint = "ryu_core_guest_frames")]
    public static ulong GetGuestFrames() => (ulong)Volatile.Read(ref _guestFrames);

    [UnmanagedCallersOnly(EntryPoint = "ryu_core_homebrew_run")]
    public static int RunHomebrew(nint writable, nint executable, nuint capacity,
        delegate* unmanaged<void> beginWrite, delegate* unmanaged<nint, nuint, void> publish,
        byte* library, nint layer, int width, int height,
        delegate* unmanaged<nint, nint, ulong*, int> createSurface, delegate* unmanaged<int> cancelled,
        byte* program, byte* directory, byte* report, nuint reportCapacity)
    {
        if (library == null || layer == 0 || createSurface == null || program == null || directory == null ||
            width <= 0 || height <= 0 || report == null || reportCapacity < 2 || reportCapacity > int.MaxValue) return -1;
        report[0] = 0;
        if (Interlocked.CompareExchange(ref _busy, 1, 0) != 0) return -2;
        Volatile.Write(ref _guestFrames, 0);
        try
        {
            string path = Marshal.PtrToStringUTF8((nint)directory);
            HorizonJournal.Begin(path, "guest-last-run.log", "guest homebrew graphics");
            ConfigureDarwinLibraries();
            var pool = new PreparedCodePool(writable, executable, capacity, beginWrite, publish);
            JitMemoryAllocator.PreparedCodeAllocator = pool.Reserve;
            string result = HomebrewSession.Run(Marshal.PtrToStringUTF8((nint)library), layer, width, height,
                createSurface, cancelled, Marshal.PtrToStringUTF8((nint)program), path,
                frames => Volatile.Write(ref _guestFrames, (long)frames));
            WriteReport(report, reportCapacity, result);
            HorizonJournal.Finish(true);
            return 0;
        }
        catch (Exception error)
        {
            HorizonJournal.Finish(false, error);
            WriteReport(report, reportCapacity, $"FAIL homebrew {error.GetType().Name}: {error.Message}");
            return -3;
        }
        finally
        {
            JitMemoryAllocator.PreparedCodeAllocator = null;
            Volatile.Write(ref _busy, 0);
        }
    }

    [UnmanagedCallersOnly(EntryPoint = "ryu_core_graphics_check")]
    public static int CheckGraphics(byte* library, nint layer, int width, int height,
        delegate* unmanaged<nint, nint, ulong*, int> createSurface, delegate* unmanaged<int> cancelled,
        byte* directory, byte* report, nuint reportCapacity)
    {
        if (library == null || layer == 0 || createSurface == null || width <= 0 || height <= 0 ||
            directory == null || report == null || reportCapacity < 2 || reportCapacity > int.MaxValue) return -1;
        report[0] = 0;
        if (Interlocked.CompareExchange(ref _busy, 1, 0) != 0) return -2;
        try
        {
            string path = Marshal.PtrToStringUTF8((nint)directory) ?? throw new ArgumentException("Missing directory");
            HorizonJournal.Begin(path, "graphics-last-run.log", "upstream Vulkan renderer");
            ConfigureDarwinLibraries();
            string result = GraphicsProbe.Run(Marshal.PtrToStringUTF8((nint)library), layer, width, height, createSurface, cancelled);
            WriteReport(report, reportCapacity, result);
            HorizonJournal.Finish(true);
            return 0;
        }
        catch (OperationCanceledException error)
        {
            HorizonJournal.Finish(false, error);
            WriteReport(report, reportCapacity, error.Message);
            return 1;
        }
        catch (Exception error)
        {
            HorizonJournal.Finish(false, error);
            WriteReport(report, reportCapacity, $"FAIL graphics {error.GetType().Name}: {error.Message}");
            return -3;
        }
        finally { Volatile.Write(ref _busy, 0); }
    }

    // Real iOS BCL/NativeAOT startup regression. No executable guest memory or
    // debugger is needed to exercise the constructor that crashed on devices.
    [UnmanagedCallersOnly(EntryPoint = "ryu_core_startup_check")]
    public static int CheckStartup(byte* directory, byte* report, nuint reportCapacity)
    {
        if (directory == null || report == null || reportCapacity < 2 || reportCapacity > int.MaxValue) return -1;
        report[0] = 0;
        if (Interlocked.CompareExchange(ref _busy, 1, 0) != 0) return -2;
        try
        {
            string path = Marshal.PtrToStringUTF8((nint)directory) ?? throw new ArgumentException("Missing directory");
            HorizonJournal.Begin(path);
            ConfigureDarwinLibraries();
            WriteReport(report, reportCapacity, HorizonProbe.Run(path, loadGuest: false));
            HorizonJournal.Finish(true);
            return 0;
        }
        catch (Exception error)
        {
            HorizonJournal.Finish(false, error);
            WriteReport(report, reportCapacity, $"FAIL startup {error.GetType().Name}: {error.Message}");
            return -3;
        }
        finally { Volatile.Write(ref _busy, 0); }
    }

    [UnmanagedCallersOnly(EntryPoint = "ryu_core_horizon_check")]
    public static int CheckHorizon(nint writable, nint executable, nuint capacity,
        delegate* unmanaged<void> beginWrite, delegate* unmanaged<nint, nuint, void> publish,
        byte* directory, byte* report, nuint reportCapacity)
    {
        if (directory == null || report == null || reportCapacity < 2 || reportCapacity > int.MaxValue) return -1;
        report[0] = 0;
        if (Interlocked.CompareExchange(ref _busy, 1, 0) != 0) return -2;
        try
        {
            string path = Marshal.PtrToStringUTF8((nint)directory) ?? throw new ArgumentException("Missing directory");
            HorizonJournal.Begin(path);
            HorizonJournal.Write("Configuring native libraries and prepared JIT allocator");
            ConfigureDarwinLibraries();
            var pool = new PreparedCodePool(writable, executable, capacity, beginWrite, publish);
            JitMemoryAllocator.PreparedCodeAllocator = pool.Reserve;
            WriteReport(report, reportCapacity, HorizonProbe.Run(path));
            HorizonJournal.Finish(true);
            return 0;
        }
        catch (Exception error)
        {
            HorizonJournal.Finish(false, error);
            WriteReport(report, reportCapacity, $"FAIL Horizon {error.GetType().Name}: {error.Message}");
            return -3;
        }
        finally
        {
            JitMemoryAllocator.PreparedCodeAllocator = null;
            Volatile.Write(ref _busy, 0);
        }
    }

    [UnmanagedCallersOnly(EntryPoint = "ryu_core_services_check")]
    public static int CheckServices(byte* directory, byte* report, nuint reportCapacity)
    {
        if (directory == null || report == null || reportCapacity < 2 || reportCapacity > int.MaxValue) return -1;
        report[0] = 0;
        if (Interlocked.CompareExchange(ref _busy, 1, 0) != 0) return -2;
        try
        {
            ConfigureDarwinLibraries();
            string path = Marshal.PtrToStringUTF8((nint)directory) ?? throw new ArgumentException("Missing directory");
            WriteReport(report, reportCapacity, ServiceBootstrap.Initialize(path));
            // Reproduce the mobile logging path before any guest runs. Flush also
            // catches failures confined to the async logger thread in simulator CI.
            Ryujinx.Common.Logging.Logger.Warning?.PrintMsg(Ryujinx.Common.Logging.LogClass.Application, "Ryu platform logger check");
            Ryujinx.Common.Logging.Logger.Flush();
            return 0;
        }
        catch (Exception error)
        {
            WriteReport(report, reportCapacity, $"FAIL services {error.GetType().Name}: {error.Message}");
            return -3;
        }
        finally { Volatile.Write(ref _busy, 0); }
    }

    [UnmanagedCallersOnly(EntryPoint = "ryu_core_check")]
    public static int Check(nint writable, nint executable, nuint capacity,
        delegate* unmanaged<void> beginWrite, delegate* unmanaged<nint, nuint, void> publish,
        uint seed, byte* report, nuint reportCapacity)
    {
        if (report == null || reportCapacity < 2 || reportCapacity > int.MaxValue) return -1;
        report[0] = 0;
        if (Interlocked.CompareExchange(ref _busy, 1, 0) != 0) return -2;
        try
        {
            ConfigureDarwinLibraries();
            var pool = new PreparedCodePool(writable, executable, capacity, beginWrite, publish);
            JitMemoryAllocator.PreparedCodeAllocator = pool.Reserve;
            string result = CpuChecks.Run(seed);
            WriteReport(report, reportCapacity, result);
            return 0;
        }
        catch (Exception error)
        {
            WriteReport(report, reportCapacity, $"FAIL {error.GetType().Name}: {error.Message}");
            return -3;
        }
        finally
        {
            JitMemoryAllocator.PreparedCodeAllocator = null;
            Volatile.Write(ref _busy, 0);
        }
    }

    private static void WriteReport(byte* report, nuint capacity, string message)
    {
        var output = new Span<byte>(report, checked((int)capacity));
        var encoder = Encoding.UTF8.GetEncoder();
        encoder.Convert(message.AsSpan(), output[..^1], true, out _, out int used, out _);
        output[used] = 0;
    }

    private static void ConfigureDarwinLibraries()
    {
        if (!OperatingSystem.IsIOS() || Interlocked.Exchange(ref _resolverReady, 1) != 0) return;
        DllImportResolver resolve = (name, assembly, search) =>
            name is "libc" or "libSystem.dylib" ? NativeLibrary.Load("/usr/lib/libSystem.B.dylib") : 0;
        NativeLibrary.SetDllImportResolver(typeof(MemoryBlock).Assembly, resolve);
        NativeLibrary.SetDllImportResolver(typeof(ARMeilleure.Memory.IMemoryManager).Assembly, resolve);
        NativeLibrary.SetDllImportResolver(typeof(Ryujinx.Common.Configuration.AppDataManager).Assembly, resolve);
        NativeLibrary.SetDllImportResolver(typeof(Ryujinx.Cpu.ICpuContext).Assembly, resolve);
        NativeLibrary.SetDllImportResolver(typeof(Ryujinx.HLE.Switch).Assembly, resolve);
    }
}
