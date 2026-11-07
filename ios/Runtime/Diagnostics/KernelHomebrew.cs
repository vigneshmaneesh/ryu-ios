using System;
using System.Buffers.Binary;
using System.Text;

namespace Ryu.iOS.HorizonChecks;

// An authored, redistributable NRO; no Nintendo code, keys or firmware included.
// The guest sets a 2 MiB heap, emits a marker through real SVC 0x27, then exits.
internal static class KernelHomebrew
{
    public const string Marker = "RYU_KERNEL_PROBE: heap=ok";
    public static byte[] Create()
    {
        byte[] nro = new byte[0x3038];
        void Word(int offset, uint value) => BinaryPrimitives.WriteUInt32LittleEndian(nro.AsSpan(offset), value);
        Word(0, 0x14000020); // B 0x80, skipping NRO metadata.
        "NRO0"u8.CopyTo(nro.AsSpan(0x10));
        Word(0x18, 0x3000); // Executable size excluding assets.
        Word(0x20, 0); Word(0x24, 0x1000); // Text file offset and size.
        Word(0x28, 0x1000); Word(0x2c, 0x1000); // Read-only segment.
        Word(0x30, 0x2000); Word(0x34, 0x1000); // Data segment.
        Word(0x38, 0x1000); // BSS.
        Word(0x80, 0xd2a00401); // MOVZ x1,#0x20,LSL#16 (2 MiB).
        Word(0x84, 0xd4000021); // SVC SetHeapSize.
        Word(0x88, 0xb5000080); // CBNZ x0,0x98: failure skips success marker.
        Word(0x8c, 0x10007ba0); // ADR x0,0x1000.
        Word(0x90, 0xd2800001u | ((uint)Encoding.ASCII.GetByteCount(Marker) << 5));
        Word(0x94, 0xd40004e1); // SVC OutputDebugString.
        Word(0x98, 0xd40000e1); // SVC ExitProcess.
        Word(0x9c, 0x14000000); // Never fall into data if an exit is broken.
        Encoding.ASCII.GetBytes(Marker).CopyTo(nro, 0x1000);
        "ASET"u8.CopyTo(nro.AsSpan(0x3000)); // Empty optional icon/NACP/RomFS.
        return nro;
    }
}
