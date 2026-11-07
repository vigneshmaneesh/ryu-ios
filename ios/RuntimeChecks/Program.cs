using Ryu.iOS.Runtime;
using System;

foreach (uint seed in new uint[] { 0, 42, uint.MaxValue, 0x12345678 })
{
    Console.WriteLine($"Seed {seed}:");
    Console.WriteLine(CpuChecks.Run(seed));
}
