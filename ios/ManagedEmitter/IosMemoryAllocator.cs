using ARMeilleure.Memory;
using System;
using System.Runtime.InteropServices;

namespace Ryujinx.iOS;

// Executable regions are prepared by the native StikDebug coordinator before this
// allocator exists. The RX pointer never changes; all writes use its distinct RW alias.
internal sealed unsafe class IosMemoryAllocator : IJitMemoryAllocator
{
    private readonly nint _writable;
    private readonly nint _executable;
    private readonly nuint _capacity;
    private readonly delegate* unmanaged<void> _beginWrite;
    private readonly delegate* unmanaged<nint, nuint, void> _publish;
    private bool _reserved;

    public IosMemoryAllocator(nint writable, nint executable, nuint capacity,
        delegate* unmanaged<void> beginWrite, delegate* unmanaged<nint, nuint, void> publish)
    {
        if (writable == 0 || executable == 0 || capacity == 0 || beginWrite == null || publish == null)
            throw new ArgumentException("Prepared code region and callbacks are required.");
        _writable = writable;
        _executable = executable;
        _capacity = capacity;
        _beginWrite = beginWrite;
        _publish = publish;
    }

    public IJitMemoryBlock Allocate(ulong size) => new DataBlock(size);

    public IJitMemoryBlock Reserve(ulong size)
    {
        if (_reserved) throw new InvalidOperationException("The prepared code region is already reserved.");
        if (size == 0 || size > _capacity) throw new ArgumentOutOfRangeException(nameof(size));
        _reserved = true;
        return new CodeBlock(_writable, _executable, (nuint)size, _beginWrite, _publish);
    }

    internal sealed class CodeBlock : IJitMemoryBlock
    {
        private readonly nint _writable;
        private readonly nuint _size;
        private readonly delegate* unmanaged<void> _beginWrite;
        private readonly delegate* unmanaged<nint, nuint, void> _publish;
        private bool _disposed;
        public nint Pointer { get; }

        internal CodeBlock(nint writable, nint executable, nuint size,
            delegate* unmanaged<void> beginWrite, delegate* unmanaged<nint, nuint, void> publish)
        {
            _writable = writable;
            Pointer = executable;
            _size = size;
            _beginWrite = beginWrite;
            _publish = publish;
        }

        public void Write(ReadOnlySpan<byte> code)
        {
            CheckRange(0, (ulong)code.Length);
            _beginWrite();
            try { code.CopyTo(new Span<byte>((void*)_writable, code.Length)); }
            finally { _publish(Pointer, (nuint)code.Length); }
        }

        public void Commit(ulong offset, ulong size) => CheckRange(offset, size);
        public void MapAsRw(ulong offset, ulong size) => CheckRange(offset, size);
        public void MapAsRx(ulong offset, ulong size) => CheckRange(offset, size);
        public void MapAsRwx(ulong offset, ulong size) => throw new PlatformNotSupportedException("Use separate RW and RX aliases on iOS.");
        private void CheckRange(ulong offset, ulong size)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            if (offset > _size || size > _size - offset) throw new ArgumentOutOfRangeException(nameof(size));
        }
        // The native process coordinator owns these mappings and reuses them on reruns.
        public void Dispose() => _disposed = true;
    }

    internal sealed class DataBlock : IJitMemoryBlock
    {
        private readonly ulong _size;
        private nint _pointer;
        public nint Pointer => _pointer;
        public DataBlock(ulong size)
        {
            if (size == 0 || size > int.MaxValue) throw new ArgumentOutOfRangeException(nameof(size));
            _size = size;
            _pointer = (nint)NativeMemory.AlignedAlloc((nuint)((size + 15) & ~15UL), 16);
            if (_pointer == 0) throw new OutOfMemoryException();
            NativeMemory.Clear((void*)_pointer, (nuint)size);
        }
        public void Commit(ulong offset, ulong size) => CheckRange(offset, size);
        public void MapAsRw(ulong offset, ulong size) => CheckRange(offset, size);
        public void MapAsRx(ulong offset, ulong size) => throw new PlatformNotSupportedException("Data allocations are not executable.");
        public void MapAsRwx(ulong offset, ulong size) => throw new PlatformNotSupportedException("Data allocations are not executable.");
        private void CheckRange(ulong offset, ulong size)
        {
            ObjectDisposedException.ThrowIf(_pointer == 0, this);
            if (offset > _size || size > _size - offset) throw new ArgumentOutOfRangeException(nameof(size));
        }
        public void Dispose()
        {
            if (_pointer != 0) { NativeMemory.AlignedFree((void*)_pointer); _pointer = 0; }
        }
    }
}
