using Ryu.iOS.Runtime;
using System;
using System.IO;

string directory = Path.Combine(AppContext.BaseDirectory, "kernel-check-data");
Console.WriteLine(HorizonProbe.Run(directory));
Console.WriteLine(HorizonProbe.Run(directory));
