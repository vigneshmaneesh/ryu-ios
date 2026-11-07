using Ryu.iOS.Runtime;
using System;
using System.IO;

foreach (uint seed in new uint[] { 0, 42, uint.MaxValue, 0x12345678 })
{
    Console.WriteLine($"Seed {seed}:");
    Console.WriteLine(CpuChecks.Run(seed));
}
var directory = Path.Combine(AppContext.BaseDirectory, "service-check-data");
Console.WriteLine(ServiceBootstrap.Initialize(directory));
Console.WriteLine(ServiceBootstrap.Initialize(directory));
