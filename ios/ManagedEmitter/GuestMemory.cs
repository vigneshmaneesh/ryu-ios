using ARMeilleure.Memory;
using System;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace Ryujinx.iOS;

// Small, contiguous guest address space for embedded CPU conformance programs.
// This is not the Switch's production address-space or page-fault implementation.
internal sealed unsafe class GuestMemory : IMemoryManager, IDisposable
{
    public const int Size = 1 << 16;
    public const ulong CodeAddress = 0x1000;
    public const ulong DataAddress = 0x8000;
    private const int GuardSize = 32;
    private nint _allocation;
    public int AddressSpaceBits => 16;
    public nint PageTablePointer => _allocation + GuardSize;
    public MemoryManagerType Type => MemoryManagerType.HostMapped;
    public event Action<ulong, ulong> UnmapEvent { add { } remove { } }

    public GuestMemory()
    {
        _allocation = (nint)NativeMemory.AlignedAlloc(Size + 2 * GuardSize, 16);
        if (_allocation == 0) throw new OutOfMemoryException();
        new Span<byte>((void*)_allocation, Size + 2 * GuardSize).Fill(0xa5);
        new Span<byte>((void*)PageTablePointer, Size).Clear();
    }
    public void LoadProgram(ReadOnlySpan<uint> instructions)
    {
        int length = checked(instructions.Length * sizeof(uint));
        CheckRange(CodeAddress, (ulong)length);
        MemoryMarshal.AsBytes(instructions).CopyTo(new Span<byte>((void*)(PageTablePointer + (nint)CodeAddress), length));
    }
    private void CheckRange(ulong address, ulong size)
    {
        ObjectDisposedException.ThrowIf(_allocation == 0, this);
        if (address > Size || size > Size - address) throw new ArgumentOutOfRangeException(nameof(address), "Guest access is outside the mapped address space.");
    }
    public T Read<T>(ulong va) where T : unmanaged
    {
        CheckRange(va, (ulong)Unsafe.SizeOf<T>());
        return Unsafe.ReadUnaligned<T>((void*)(PageTablePointer + (nint)va));
    }
    public T ReadTracked<T>(ulong va) where T : unmanaged => Read<T>(va);
    public void Write<T>(ulong va, T value) where T : unmanaged
    {
        CheckRange(va, (ulong)Unsafe.SizeOf<T>());
        Unsafe.WriteUnaligned((void*)(PageTablePointer + (nint)va), value);
    }
    public ReadOnlySpan<byte> GetSpan(ulong va, int size, bool tracked = false)
    {
        if (size < 0) throw new ArgumentOutOfRangeException(nameof(size));
        CheckRange(va, (ulong)size);
        return new ReadOnlySpan<byte>((void*)(PageTablePointer + (nint)va), size);
    }
    public ref T GetRef<T>(ulong va) where T : unmanaged
    {
        CheckRange(va, (ulong)Unsafe.SizeOf<T>());
        return ref Unsafe.AsRef<T>((void*)(PageTablePointer + (nint)va));
    }
    public bool IsMapped(ulong va) => _allocation != 0 && va < Size;
    public void SignalMemoryTracking(ulong va, ulong size, bool write, bool precise = false, int? exemptId = null) => CheckRange(va, size);
    public void VerifyGuards()
    {
        ObjectDisposedException.ThrowIf(_allocation == 0, this);
        for (int index = 0; index < GuardSize; index++)
            if (((byte*)_allocation)[index] != 0xa5 || ((byte*)PageTablePointer)[Size + index] != 0xa5)
                throw new InvalidOperationException("Guest memory guard was modified.");
    }
    public void Dispose()
    {
        if (_allocation != 0) { NativeMemory.AlignedFree((void*)_allocation); _allocation = 0; }
    }
}
