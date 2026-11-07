using Ryu.iOS.Runtime;
using System;
using System.IO;

string directory = Path.Combine(AppContext.BaseDirectory, "kernel-check-data");
if (args.Length == 2 && args[0] == "--journal-interrupt")
{
    HorizonJournal.Begin(Path.GetFullPath(args[1]));
    HorizonJournal.Write("Interrupted-run persistence checkpoint");
    Environment.Exit(73); // No orderly Finish/Dispose, matching an interrupted run.
}
for (int run = 0; run < 2; run++)
{
    HorizonJournal.Begin(directory);
    try
    {
        Console.WriteLine(HorizonProbe.Run(directory));
        HorizonJournal.Finish(true);
    }
    catch (Exception error)
    {
        HorizonJournal.Finish(false, error);
        throw;
    }
    string trace = File.ReadAllText(Path.Combine(directory, "horizon-last-run.log"));
    if (!trace.Contains("RESULT PASS") || !trace.Contains("Kernel teardown complete"))
        throw new InvalidOperationException("The persisted trace did not include successful kernel teardown.");
}
