using Ryujinx.Cpu.LightningJit.State;
using System.Diagnostics;

namespace Ryujinx.Cpu.LightningJit;

// Harness adapter for the compiler's host-call contract. This intentionally does
// not implement Horizon services or substitute for the production NativeInterface.
internal static class NativeInterface
{
    [System.ThreadStatic] internal static NativeContext Context;
    [System.ThreadStatic] internal static int SupervisorCalls;
    [System.ThreadStatic] internal static int Synchronizations;
    [System.ThreadStatic] internal static string Fault;

    internal static void Begin(NativeContext context)
    {
        Context = context;
        SupervisorCalls = Synchronizations = 0;
        Fault = null;
        context.SetCounter(0);
        context.SetRunning(true);
    }
    internal static void End() => Context = null;

    public static void Break(ulong address, int encoding) => Fault = $"Unexpected guest breakpoint at 0x{address:x}.";
    public static void Undefined(ulong address, int encoding) => Fault = $"Undefined guest instruction 0x{encoding:x8} at 0x{address:x}.";
    public static void SupervisorCall(ulong address, int immediate)
    {
        if (Context == null) { Fault = "Callback has no active guest context."; return; }
        if (address != Ryujinx.iOS.GuestMemory.CodeAddress || immediate != 0x42)
        {
            Fault = $"Unexpected supervisor call {immediate} at 0x{address:x}.";
            return;
        }
        SupervisorCalls++;
        Context.SetX(0, unchecked(Context.GetX(0) + 7));
        Context.SetX(2, 0x12345678);
    }
    public static ulong GetCntpctEl0() => (ulong)Stopwatch.GetTimestamp();
    public static bool CheckSynchronization()
    {
        if (Context == null) { Fault = "Synchronization has no active guest context."; return false; }
        Synchronizations++;
        if (Synchronizations > 1024) Fault = "Guest program exceeded its synchronization budget.";
        Context.SetCounter(128);
        return Fault == null && Context.GetRunning();
    }
}
