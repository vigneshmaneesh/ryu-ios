using ARMeilleure.Common;
using ARMeilleure.Memory;
using System;

namespace Ryujinx.Cpu;

public static class ArmAddressTableFactory
{
    public static IAddressTable<ulong> Create(MemoryManagerType memoryType, bool for64Bits, bool isIOS)
    {
        // The flat 64-bit sparse table reserves 1 TiB and depends on demand-fault
        // mappings. MeloNX deliberately excluded iOS before upstream moved the
        // selection into the CPU contexts. Preserve that platform restriction.
        bool sparse = !isIOS && memoryType is not MemoryManagerType.SoftwareMmu
                                             and not MemoryManagerType.SoftwarePageTable;
        if (sparse)
        {
            return SparseAddressTable<ulong>.CreateForArm(for64Bits);
        }

        Console.WriteLine($"[CPU] Creating multi-level {(for64Bits ? "A64" : "A32")} code lookup table ({memoryType}; iOS={isIOS}).");
        return AddressTable<ulong>.CreateForArm(for64Bits);
    }
}
