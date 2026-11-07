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
    public const uint AbiVersion = 1;

    [UnmanagedCallersOnly(EntryPoint = "ryu_core_abi_version")]
    public static uint GetAbiVersion() => AbiVersion;

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
            ConfigureDarwinLibraries();
            var pool = new PreparedCodePool(writable, executable, capacity, beginWrite, publish);
            JitMemoryAllocator.PreparedCodeAllocator = pool.Reserve;
            string path = Marshal.PtrToStringUTF8((nint)directory) ?? throw new ArgumentException("Missing directory");
            WriteReport(report, reportCapacity, HorizonProbe.Run(path));
            return 0;
        }
        catch (Exception error)
        {
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
