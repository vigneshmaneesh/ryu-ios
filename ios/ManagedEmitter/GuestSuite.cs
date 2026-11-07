using ARMeilleure.Memory;
using Ryujinx.Cpu.LightningJit;
using Ryujinx.Cpu.LightningJit.Arm64;
using Ryujinx.Cpu.LightningJit.State;
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace Ryujinx.iOS;

public static unsafe class GuestSuite
{
    private const ulong ReturnAddress = 0xdeadbeef;
    // Raw guest instruction words are decoded and translated by the upstream compiler.
    // None of these functions is called directly as host code.
    private static readonly uint[][] Programs = [
        [0x8b010000, 0xd65f03c0], // ADD X0,X0,X1; RET
        [0xd2800000, 0xb4000081, 0x8b010000, 0xf1000421, 0x54ffffc1, 0xd65f03c0], // triangular sum loop
        [0xf9400022, 0x8b020000, 0xf9000420, 0xd65f03c0], // LDR; ADD; STR; RET
        [0xaa0003f2, 0x8b01025d, 0xaa1d03e0, 0xd65f03c0], // guest X18/X29 remapping
        [0xd4000841, 0x8b010000, 0xd65f03c0], // SVC #0x42; ADD; RET
        [0xd53bd040, 0xd53bd061, 0x8b010000, 0xd65f03c0], // guest TLS register reads
    ];
    private static readonly string[] Names = ["ADD/overflow", "branches/loop", "guest memory", "reserved registers", "managed SVC callback", "guest TLS"];

    [UnmanagedCallersOnly(EntryPoint = "ryu_guest_suite")]
    public static int Run(nint writable, nint executable, nuint capacity,
        delegate* unmanaged<void> beginWrite, delegate* unmanaged<nint, nuint, void> publish,
        uint seed, byte* report, nuint reportCapacity)
    {
        try
        {
            if (RuntimeInformation.ProcessArchitecture != Architecture.Arm64)
                throw new PlatformNotSupportedException("Guest execution requires an ARM64 host.");
            IosMemoryAllocator allocator = new(writable, executable, capacity, beginWrite, publish);
            using IosMemoryAllocator.CodeBlock code = (IosMemoryAllocator.CodeBlock)allocator.Reserve((ulong)capacity);
            StringBuilder messages = new();
            int total = 0;
            for (int programIndex = 0; programIndex < Programs.Length; programIndex++)
            {
                using GuestMemory memory = new();
                memory.LoadProgram(Programs[programIndex]);
                CompiledFunction compiled = A64Compiler.Compile(CpuPresets.CortexA57, memory,
                    GuestMemory.CodeAddress, null, 0, Architecture.Arm64);
                if (compiled.GuestCodeLength != Programs[programIndex].Length * 4)
                    throw new InvalidOperationException($"{Names[programIndex]} did not translate the whole program.");
                code.Write(compiled.Code);

                int cases = programIndex == 1 ? 5 : 4;
                for (int test = 0; test < cases; test++)
                {
                    using NativeContext context = new(allocator);
                    (ulong a, ulong b) = test switch {
                        0 => (20UL, 22UL), 1 => (ulong.MaxValue, 1UL),
                        2 => (0UL, 0UL), _ => ((ulong)seed, (ulong)uint.MaxValue)
                    };
                    context.SetX(0, a);
                    context.SetX(1, b);
                    context.SetX(30, ReturnAddress);
                    ulong expected;
                    switch (programIndex)
                    {
                        case 1:
                            b = new ulong[] { 0, 1, 2, 10, 64 }[test];
                            context.SetX(1, b);
                            expected = b * (b + 1) / 2;
                            break;
                        case 2:
                            context.SetX(1, GuestMemory.DataAddress);
                            memory.Write(GuestMemory.DataAddress, b);
                            memory.Write(GuestMemory.DataAddress + 8, 0xccccccccccccccccUL);
                            expected = unchecked(a + b);
                            break;
                        case 4: expected = unchecked(a + b + 7); break;
                        case 5:
                            context.SetTpidrEl0(unchecked((long)a));
                            context.SetTpidrroEl0(unchecked((long)b));
                            expected = unchecked(a + b);
                            break;
                        default: expected = unchecked(a + b); break;
                    }
                    NativeInterface.Begin(context);
                    try
                    {
                        ulong next = ((delegate* unmanaged<nint, ulong>)code.Pointer)(context.BasePtr);
                        if (NativeInterface.Fault != null) throw new InvalidOperationException(NativeInterface.Fault);
                        if (next != ReturnAddress) throw new InvalidOperationException($"Wrong guest return address in {Names[programIndex]}.");
                        if (context.GetX(0) != expected)
                            throw new InvalidOperationException($"{Names[programIndex]} case {test}: expected {expected}, got {context.GetX(0)}.");
                        if (programIndex == 2 && memory.Read<ulong>(GuestMemory.DataAddress + 8) != expected)
                            throw new InvalidOperationException("Translated guest store returned the wrong value.");
                        if (programIndex == 3 && (context.GetX(18) != a || context.GetX(29) != expected))
                            throw new InvalidOperationException("Reserved guest register was not preserved.");
                        if (programIndex == 4 && (NativeInterface.SupervisorCalls != 1 || context.GetX(2) != 0x12345678))
                            throw new InvalidOperationException("Managed callback or guest register reload failed.");
                        memory.VerifyGuards();
                        total++;
                    }
                    finally { NativeInterface.End(); }
                }
                messages.AppendLine($"PASS {Names[programIndex]}: {cases} cases");
            }
            messages.Append($"Guest translation: {total} cases passed.");
            WriteReport(report, reportCapacity, messages.ToString());
            return 0;
        }
        catch (Exception exception)
        {
            WriteReport(report, reportCapacity, $"Guest translation failed: {exception.GetType().Name}: {exception.Message}");
            return -1;
        }
    }

    // Host-independent validation: run the real decoder/compiler and check boundaries.
    public static int ValidateTranslations()
    {
        int count = 0;
        using GuestMemory memory = new();
        foreach (uint[] program in Programs)
        {
            memory.LoadProgram(program);
            CompiledFunction compiled = A64Compiler.Compile(CpuPresets.CortexA57, memory, GuestMemory.CodeAddress, null, 0, Architecture.Arm64);
            if (compiled.Code.Length == 0 || (compiled.Code.Length & 3) != 0 || compiled.GuestCodeLength != program.Length * 4)
                throw new InvalidOperationException("Incomplete guest compilation.");
            memory.VerifyGuards();
            count++;
        }
        memory.Write(GuestMemory.Size - 8, ulong.MaxValue);
        if (memory.Read<ulong>(GuestMemory.Size - 8) != ulong.MaxValue) throw new Exception("Last mapped value failed.");
        count++;
        try { memory.Read<ulong>(GuestMemory.Size - 7); throw new Exception("Out-of-range read was accepted."); }
        catch (ArgumentOutOfRangeException) { count++; }
        try { memory.Write(ulong.MaxValue, 1UL); throw new Exception("Overflowing guest address was accepted."); }
        catch (ArgumentOutOfRangeException) { count++; }
        return count;
    }

    private static void WriteReport(byte* output, nuint capacity, string message)
    {
        if (output == null || capacity == 0) return;
        byte[] bytes = Encoding.UTF8.GetBytes(message);
        int count = (int)Math.Min((nuint)bytes.Length, capacity - 1);
        bytes.AsSpan(0, count).CopyTo(new Span<byte>(output, count));
        output[count] = 0;
    }
}
