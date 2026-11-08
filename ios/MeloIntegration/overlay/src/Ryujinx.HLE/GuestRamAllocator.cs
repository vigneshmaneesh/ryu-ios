using Ryujinx.Common.Configuration;
using Ryujinx.Memory;
using System;

namespace Ryujinx.HLE;

public static class GuestRamAllocator
{
    public static MemoryBlock Create(ulong size, MemoryManagerMode mode, bool isIOS)
    {
        // KernelContext.CommitMemory makes allocated guest pages accessible.
        // Keep iOS's non-mirrored backing, but reserve it lazily rather than
        // mapping the whole guest RAM range read/write at startup.
        MemoryAllocationFlags flags = isIOS || mode == MemoryManagerMode.SoftwarePageTable
            ? MemoryAllocationFlags.Reserve
            : MemoryAllocationFlags.Reserve | MemoryAllocationFlags.Mirrorable;
        Console.WriteLine($"[Memory] Reserving {size / (1024 * 1024)} MiB guest RAM; mode={mode}; flags={flags}; iOS={isIOS}.");
        try
        {
            MemoryBlock memory = new(size, flags);
            Console.WriteLine("[Memory] Guest RAM reserved; kernel pages will be committed as needed.");
            return memory;
        }
        catch (Exception error)
        {
            throw new InvalidOperationException($"Guest RAM reservation failed: {size / (1024 * 1024)} MiB, {mode}, {flags}. {error.Message}", error);
        }
    }
}
