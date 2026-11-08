using System;
using System.Runtime.CompilerServices;

namespace Ryujinx.HLE.HOS.Tamper;

// Atmosphere VM operands are unsigned 8/16/32/64-bit integers. Explicit casts
// preserve truncation/wraparound without the dynamic binder (unavailable in AOT).
internal static class TamperNumber
{
    internal static ulong Read<T>(T value) where T : unmanaged
    {
        if (typeof(T) == typeof(byte)) return Unsafe.As<T, byte>(ref value);
        if (typeof(T) == typeof(ushort)) return Unsafe.As<T, ushort>(ref value);
        if (typeof(T) == typeof(uint)) return Unsafe.As<T, uint>(ref value);
        if (typeof(T) == typeof(ulong)) return Unsafe.As<T, ulong>(ref value);
        throw new NotSupportedException("Invalid Atmosphere operand width.");
    }
    internal static T Cast<T>(ulong value) where T : unmanaged
    {
        T result = default;
        if (typeof(T) == typeof(byte)) Unsafe.As<T, byte>(ref result) = unchecked((byte)value);
        else if (typeof(T) == typeof(ushort)) Unsafe.As<T, ushort>(ref result) = unchecked((ushort)value);
        else if (typeof(T) == typeof(uint)) Unsafe.As<T, uint>(ref result) = unchecked((uint)value);
        else if (typeof(T) == typeof(ulong)) Unsafe.As<T, ulong>(ref result) = value;
        else throw new NotSupportedException("Invalid Atmosphere operand width.");
        return result;
    }
    internal static int Shift<T>(T value) where T : unmanaged => (int)(Read(value) & (typeof(T) == typeof(ulong) ? 63UL : 31UL));
}
