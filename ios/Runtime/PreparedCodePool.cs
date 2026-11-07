using ARMeilleure.Memory;
using System;
using System.Collections.Generic;

namespace Ryu.iOS.Runtime;

// One process-owned virtual allocation, prepared before StikDebug detaches.
// The upstream cache owns subregion leases; physical pages are touched on demand.
internal sealed unsafe class PreparedCodePool
{
    private readonly nint _rw, _rx;
    private readonly ulong _size;
    private readonly delegate* unmanaged<void> _begin;
    private readonly delegate* unmanaged<nint, nuint, void> _publish;
    private readonly List<(ulong Offset, ulong Size)> _free = [];
    private readonly object _gate = new();
    public PreparedCodePool(nint rw, nint rx, nuint size, delegate* unmanaged<void> begin,
        delegate* unmanaged<nint, nuint, void> publish)
    {
        if (rw == 0 || rx == 0 || size == 0 || begin == null || publish == null)
            throw new ArgumentException("Prepared RX/RW regions and callbacks are required.");
        _rw = rw; _rx = rx; _size = size; _begin = begin; _publish = publish;
        _free.Add((0, _size));
    }
    public IJitMemoryBlock Reserve(ulong size)
    {
        if (size == 0 || size > _size) throw new OutOfMemoryException("Prepared JIT pool capacity exceeded.");
        lock (_gate)
        {
            for (int i = 0; i < _free.Count; i++)
            {
                var range = _free[i];
                if (range.Size < size) continue;
                _free.RemoveAt(i);
                if (range.Size > size) _free.Insert(i, (range.Offset + size, range.Size - size));
                return new Lease(this, range.Offset, size);
            }
        }
        throw new OutOfMemoryException("Prepared JIT pool exhausted; restart to prepare a larger pool.");
    }
    private void Release(ulong offset, ulong size)
    {
        lock (_gate)
        {
            _free.Add((offset, size));
            _free.Sort((a, b) => a.Offset.CompareTo(b.Offset));
            for (int i = _free.Count - 2; i >= 0; i--)
                if (_free[i].Offset + _free[i].Size == _free[i + 1].Offset)
                {
                    _free[i] = (_free[i].Offset, _free[i].Size + _free[i + 1].Size);
                    _free.RemoveAt(i + 1);
                }
        }
    }
    private sealed class Lease(PreparedCodePool pool, ulong offset, ulong size) : IPreparedJitMemoryBlock
    {
        private bool _disposed;
        public nint Pointer => pool._rx + checked((nint)offset);
        private void Check(ulong start, ulong length)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            if (start > size || length > size - start) throw new ArgumentOutOfRangeException(nameof(length));
        }
        public void Write(ulong start, ReadOnlySpan<byte> code)
        {
            Check(start, (ulong)code.Length);
            pool._begin();
            try { code.CopyTo(new Span<byte>((void*)(pool._rw + checked((nint)(offset + start))), code.Length)); }
            finally { pool._publish(Pointer + checked((nint)start), (nuint)code.Length); }
        }
        public void Commit(ulong start, ulong length) => Check(start, length);
        public void MapAsRw(ulong start, ulong length) => Check(start, length);
        public void MapAsRx(ulong start, ulong length) => Check(start, length);
        public void MapAsRwx(ulong start, ulong length) => throw new PlatformNotSupportedException("Use the prepared writable alias.");
        public void Dispose()
        {
            lock (pool._gate)
            {
                if (_disposed) return;
                _disposed = true;
                pool.Release(offset, size);
            }
        }
    }
}
