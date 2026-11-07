using System;
using System.Buffers.Binary;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using Ryujinx.iOS;

// Independent, CPU-neutral execution of the tiny ARM64 subset used by the probe.
// These checks run on Windows/Linux/macOS and never execute ARM64 on the host.
static ulong Evaluate(byte[] code, ulong a, ulong b)
{
    ulong[] registers = new ulong[32];
    registers[0] = a;
    registers[1] = b;
    for (int offset = 0; offset < code.Length; offset += 4)
    {
        uint instruction = BinaryPrimitives.ReadUInt32LittleEndian(code.AsSpan(offset, 4));
        int rd = (int)(instruction & 31);
        if (instruction == 0xd65f03c0)
        {
            if (offset != code.Length - 4) throw new Exception("Unexpected instructions after RET.");
            return registers[0];
        }
        if ((instruction & 0xffe0fc00) == 0x8b000000)
        {
            int rn = (int)((instruction >> 5) & 31);
            int rm = (int)((instruction >> 16) & 31);
            registers[rd] = unchecked(registers[rn] + registers[rm]);
        }
        else if ((instruction & 0xff800000) == 0xd2800000)
        {
            int shift = (int)((instruction >> 21) & 3) * 16;
            registers[rd] = ((instruction >> 5) & 0xffffUL) << shift;
        }
        else if ((instruction & 0xff800000) == 0xf2800000)
        {
            int shift = (int)((instruction >> 21) & 3) * 16;
            registers[rd] = (registers[rd] & ~(0xffffUL << shift)) | (((instruction >> 5) & 0xffffUL) << shift);
        }
        else throw new Exception($"Unexpected ARM64 instruction 0x{instruction:x8}.");
    }
    throw new Exception("Missing RET.");
}

uint[] biases = [0, 1, 42, 4095, 65535, 65536, 0x12345678, uint.MaxValue];
(ulong A, ulong B)[] inputs = [(0, 0), (20, 22), (ulong.MaxValue, 1), (0x1234567890abcdef, 0xfedcba0987654321)];
int checks = 0;
foreach (uint bias in biases)
{
    byte[] code = Emitter.BuildAdd(bias);
    foreach ((ulong a, ulong b) in inputs)
    {
        ulong expected = unchecked(a + b + bias);
        if (Evaluate(code, a, b) != expected) throw new Exception($"Failed bias={bias}, a={a}, b={b}.");
        checks++;
    }
}

// Exercise the actual exported C ABI, including bounds and null handling.
unsafe
{
    delegate* unmanaged<byte*, nuint, uint, int> emit = &Emitter.EmitAdd;
    byte* buffer = stackalloc byte[64];
    new Span<byte>(buffer, 64).Fill(0xcc);
    if (emit(null, 64, 42) != -1 || emit(buffer, 1, 42) != -1) throw new Exception("Invalid ABI bounds handling.");
    if (buffer[0] != 0xcc) throw new Exception("Short buffer was modified.");
    int count = emit(buffer, 64, 42);
    byte[] expected = Convert.FromHexString("0000018B420580D20000028BC0035FD6");
    if (count != expected.Length || !new ReadOnlySpan<byte>(buffer, count).SequenceEqual(expected))
        throw new Exception("Export differs from the expected ARM64 machine code.");
    if (buffer[count] != 0xcc) throw new Exception("Emitter wrote past the end of the code.");
    checks += 5;
}
Console.WriteLine($"PASS: {checks} ARM64 semantics and native ABI checks.");
