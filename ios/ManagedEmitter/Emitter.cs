using System;
using System.Runtime.InteropServices;
using Ryujinx.Cpu.LightningJit;
using Ryujinx.Cpu.LightningJit.CodeGen;
using Ryujinx.Cpu.LightningJit.CodeGen.Arm64;

namespace Ryujinx.iOS;

public static class Emitter
{
    // C ABI: copies a dynamically emitted f(a, b) = a + b + bias into caller-owned RW memory.
    // No exceptions or managed references may cross the native boundary.
    [UnmanagedCallersOnly(EntryPoint = "ryu_emit_add")]
    public static unsafe int EmitAdd(byte* destination, nuint capacity, uint bias)
    {
        try
        {
            byte[] code = BuildAdd(bias);
            if (destination == null || capacity < (nuint)code.Length)
            {
                return -1;
            }

            code.CopyTo(new Span<byte>(destination, code.Length));
            return code.Length;
        }
        catch
        {
            return -2;
        }
    }

    public static byte[] BuildAdd(uint bias)
    {
        CodeWriter writer = new();
        Assembler assembler = new(writer);
        Operand x0 = new(0, RegisterType.Integer, OperandType.I64);
        Operand x1 = new(1, RegisterType.Integer, OperandType.I64);
        Operand x2 = new(2, RegisterType.Integer, OperandType.I64);
        assembler.Add(x0, x0, x1);
        assembler.Movz(x2, (int)(bias & 0xffff), 0);
        if ((bias >> 16) != 0)
        {
            assembler.Movk(x2, (int)(bias >> 16), 1);
        }
        assembler.Add(x0, x0, x2);
        assembler.Ret();
        return writer.AsByteSpan().ToArray();
    }
}
