using Ryujinx.HLE.HOS.Kernel.Process;
using Ryujinx.HLE.HOS.Services.Hid;
using System;
using System.Runtime.InteropServices;

namespace Ryujinx.HLE.HOS.Tamper;

public static class AotCheatChecks
{
    // Executes real Atmosphere source through the parser, compiler, register
    // arithmetic, key conditional and memory operands, including narrow writes.
    public static string Run()
    {
        foreach (byte width in new byte[] { 1, 2, 4, 8 })
        {
            var memory = new ProbeMemory();
            var compiler = new AtmosphereCompiler(0x1000, 0x2000, 0x3000, 0x4000, memory);
            ulong constant = width == 8 ? 0xFEDCBA9876543210UL : 0xDEADBEEFUL;
            string value = width == 8 ? "FEDCBA98 76543210" : "DEADBEEF";
            var program = compiler.Compile("native-aot-fixture", ["40010000 00000000 00000004", "71010000 00000001", "80000001", $"0{width}010000 00000010 {value}", "20000000"])
                ?? throw new InvalidOperationException("Atmosphere fixture failed to compile.");
            program.IsEnabled = true;
            program.Execute(0);
            if (memory.Bytes.AsSpan().IndexOfAnyExcept((byte)0) >= 0) throw new InvalidOperationException("Key conditional executed without input.");
            program.Execute(ControllerKeys.A);
            ulong actual = width switch { 1 => memory.ReadMemory<byte>(0x1015), 2 => memory.ReadMemory<ushort>(0x1015), 4 => memory.ReadMemory<uint>(0x1015), _ => memory.ReadMemory<ulong>(0x1015) };
            ulong mask = width == 8 ? ulong.MaxValue : (1UL << (width * 8)) - 1;
            if (actual != (constant & mask)) throw new InvalidOperationException("Atmosphere write, arithmetic or width conversion failed.");
        }
        return "PASS AOT Atmosphere compiler / key conditional / register arithmetic / 8–64-bit memory writes";
    }
    private sealed class ProbeMemory : ITamperedProcess
    {
        internal readonly byte[] Bytes = new byte[256];
        public ProcessState State => ProcessState.Started;
        public bool TamperedCodeMemory { get; set; }
        public T ReadMemory<T>(ulong va) where T : unmanaged => MemoryMarshal.Read<T>(Bytes.AsSpan(checked((int)(va - 0x1000))));
        public void WriteMemory<T>(ulong va, T value) where T : unmanaged => MemoryMarshal.Write(Bytes.AsSpan(checked((int)(va - 0x1000))), in value);
        public void PauseProcess() { }
        public void ResumeProcess() { }
    }
}
