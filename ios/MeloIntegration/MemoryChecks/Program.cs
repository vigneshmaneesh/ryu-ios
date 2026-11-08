using ARMeilleure.Common;
using ARMeilleure.Memory;
using Ryujinx.Cpu;
using System;

int configurations = 0, lookups = 0;
foreach (MemoryManagerType type in Enum.GetValues<MemoryManagerType>())
foreach (bool for64Bits in new[] { false, true })
{
    // Exercise the production factory used by both CPU backends under iOS's
    // platform choice, including the host-tracked mode that reserved 1 TiB.
    using IAddressTable<ulong> table = ArmAddressTableFactory.Create(type, for64Bits, isIOS: true);
    if (table.TableType != AddressTableType.Default || table.Levels.Length <= 1)
        throw new Exception("iOS selected the flat sparse table.");
    table.Fill = 0x12345678;
    if (table.Base == 0) throw new Exception("Missing table root.");
    ulong[] addresses = for64Bits
        ? [0, 0x1000, 0x8000000, 0x100000000, 0x7ffffff000]
        : [0, 0x1000, 0x8000000, 0xffff0000, 0xfffff000];
    for (int i = 0; i < addresses.Length; i++)
    {
        if (table.GetValue(addresses[i]) != 0x12345678) throw new Exception("Unmapped slot lost its dispatcher fallback.");
        table.GetValue(addresses[i]) = (ulong)(0x100 + i);
        lookups++;
    }
    for (int i = 0; i < addresses.Length; i++)
        if (table.GetValue(addresses[i]) != (ulong)(0x100 + i))
            throw new Exception("Distant guest addresses aliased another translation.");
    table.GetValue(addresses[2]) = table.Fill;
    if (table.GetValue(addresses[2]) != table.Fill || table.GetValue(addresses[1]) != 0x101)
        throw new Exception("Translation invalidation affected another slot.");
    table.SignalCodeRange(addresses[1], 0x1000);
    configurations++;
}
Console.WriteLine($"PASS iOS CPU tables: {configurations} memory-mode/CPU-width configurations; {lookups} distant mappings, default dispatch, isolation and invalidation; no flat sparse reservation.");
