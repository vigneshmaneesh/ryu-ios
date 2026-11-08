using Ryujinx.Common.Configuration;
using Ryujinx.Memory;
using System;

namespace Ryujinx.HLE;

public static class GuestRamAllocator
{
    public static MemoryBlock Create(ulong size, MemoryManagerMode mode, bool isIOS)
    {
        // Match the supplied MeloNX Switch constructor exactly. Keep the
        // startup diagnostics and ownership rollback around the stock policy.
        MemoryAllocationFlags flags = isIOS || mode == MemoryManagerMode.SoftwarePageTable
            ? MemoryAllocationFlags.None
            : MemoryAllocationFlags.Reserve | MemoryAllocationFlags.Mirrorable;
        Console.WriteLine($"[Memory] Reserving {size / (1024 * 1024)} MiB guest RAM; mode={mode}; flags={flags}; iOS={isIOS}.");
        try
        {
            MemoryBlock memory = new(size, flags);
            Console.WriteLine("[Memory] Guest RAM ready; stock MeloNX allocation policy.");
            return memory;
        }
        catch (Exception error)
        {
            throw new InvalidOperationException($"Guest RAM reservation failed: {size / (1024 * 1024)} MiB, {mode}, {flags}. {error.Message}", error);
        }
    }
}
