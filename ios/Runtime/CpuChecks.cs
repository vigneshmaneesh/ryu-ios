using Ryujinx.Cpu;
using Ryujinx.Cpu.Jit;
using Ryujinx.Memory;
using System;
using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using System.Threading;
using CpuMemory = Ryujinx.Cpu.Jit.MemoryManager;

namespace Ryu.iOS.Runtime;

// Uses the entire upstream CPU, real software page tables, dispatcher and cache.
// These embedded programs are platform conformance tests, not Horizon homebrew.
public static class CpuChecks
{
    private const ulong Entry = 0x1000, Callee = 0x2000, Data = 0x8000;
    private static readonly TimeSpan Timeout = TimeSpan.FromSeconds(20);

    public static string Run(uint seed)
    {
        DispatchAndMapping(seed);
        Interrupt();
        ConcurrentContexts(seed);
        return "PASS production dispatcher / BL / RET / SVC\n" +
               "PASS translation cache invalidation\n" +
               "PASS software page tables / remap / tracking\n" +
               "PASS cooperative interrupt / stop\n" +
               "PASS two guest threads / TLS isolation\n" +
               "Production CPU: 5 groups passed.";
    }

    private static TickSource Clock() => new(19_200_000) { TickScalar = 100 };

    private sealed class Machine : IDisposable
    {
        public readonly MemoryBlock Backing = new(0x20000);
        public readonly CpuMemory Memory;
        public readonly ICpuContext Cpu;
        public Machine()
        {
            Memory = new CpuMemory(Backing, 1UL << 20);
            Memory.IncrementReferenceCount();
            Memory.Map(0, 0, 0x10000, MemoryMapFlags.None);
            Cpu = new JitEngine(Clock()).CreateCpuContext(Memory, true);
            Cpu.PrepareCodeRange(Entry, 0x3000);
        }
        public void Program(ulong address, params uint[] instructions) =>
            Memory.Write(address, MemoryMarshal.AsBytes(instructions.AsSpan()));
        public void Dispose()
        {
            Cpu.Dispose();
            Memory.DecrementReferenceCount();
            Backing.Dispose();
        }
    }

    private static uint Svc(int number) => 0xd4000001u | ((uint)number << 5);
    private static uint Bl(ulong pc, ulong target) => 0x94000000u | ((uint)((long)(target - pc) >> 2) & 0x03ffffff);
    private static uint MovZ(int register, uint value) => 0xd2800000u | ((value & 0xffff) << 5) | (uint)register;
    private static uint MovKHigh(int register, uint value) => 0xf2a00000u | ((value >> 16) << 5) | (uint)register;
    private static void Require(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }

    private static void DispatchAndMapping(uint seed)
    {
        using var machine = new Machine();
        var memory = machine.Memory;
        var cpu = machine.Cpu;
        void CalleeValue(uint value) => machine.Program(Callee, MovZ(0, value), MovKHigh(0, value),
            0x8b010000, 0xd65f03c0); // ADD x0,x0,x1; RET
        CalleeValue(seed);
        // Calls must go through production stubs; SVC 1 replaces an already cached callee.
        machine.Program(Entry, Bl(Entry, Callee), Svc(1), Bl(Entry + 8, Callee), Svc(2),
            0xf9400062, Svc(3), 0xf9400062, Svc(4), Svc(0), 0x14000000); // LDR x2,[x3]
        memory.Write<ulong>(Data, 0x123456789abcdef0);
        machine.Backing.Write<ulong>(0x18000, 0xfedcba9876543210);
        int stage = 0;
        Exception failure = null;
        using var context = cpu.CreateExecutionContext(new ExceptionCallbacks(
            supervisorCallback: (thread, pc, number) =>
            {
                try
                {
                    switch (number)
                    {
                        case 1:
                            Require(stage++ == 0 && thread.GetX(0) == (ulong)seed + 22, "Initial dispatched call result");
                            CalleeValue(unchecked(seed + 1));
                            cpu.InvalidateCacheRegion(Callee, 16);
                            break;
                        case 2:
                            Require(stage++ == 1 && thread.GetX(0) == (ulong)unchecked(seed + 1) + 22, "Stale cached translation after invalidation");
                            break;
                        case 3:
                            Require(stage++ == 2 && thread.GetX(2) == 0x123456789abcdef0, "Initial guest page mapping");
                            memory.Unmap(Data, 0x1000);
                            Require(!memory.IsMapped(Data), "Page remains mapped after unmap");
                            memory.Map(Data, 0x18000, 0x1000, MemoryMapFlags.None);
                            break;
                        case 4:
                            Require(stage++ == 3 && thread.GetX(2) == 0xfedcba9876543210, "Guest reads stale page after remap");
                            memory.SignalMemoryTracking(Data, 8, false);
                            break;
                        case 0:
                            Require(stage == 4, "Guest stopped before completing dispatcher checks");
                            thread.StopRunning();
                            break;
                        default: throw new InvalidOperationException($"Unexpected SVC {number} at {pc:x}");
                    }
                }
                catch (Exception error) { failure = error; thread.StopRunning(); }
            }, undefinedCallback: (thread, pc, op) =>
            { failure = new InvalidOperationException($"Undefined {op:x8} at {pc:x}"); thread.StopRunning(); }));
        context.SetX(1, 22);
        context.SetX(3, Data);
        RunBounded(cpu, context, Entry);
        if (failure != null) throw failure;
        Require(stage == 4, "Dispatcher test did not reach all stages");
    }

    private static void Interrupt()
    {
        using var machine = new Machine();
        machine.Program(Entry, Svc(1), 0x91000400, 0x17ffffff); // ADD x0,x0,#1; B -4
        using var started = new ManualResetEventSlim();
        int interrupts = 0;
        using var context = machine.Cpu.CreateExecutionContext(new ExceptionCallbacks(
            supervisorCallback: (thread, pc, number) => started.Set(),
            interruptCallback: thread => { Interlocked.Increment(ref interrupts); thread.StopRunning(); }));
        Exception failure = null;
        var worker = new Thread(() =>
        {
            try { machine.Cpu.Execute(context, Entry); }
            catch (Exception error) { failure = error; started.Set(); }
        }) { IsBackground = true, Name = "Ryu.iOS.InterruptCheck" };
        worker.Start();
        bool didStart = started.Wait(Timeout);
        context.RequestInterrupt();
        if (!didStart) context.StopRunning();
        if (!worker.Join(Timeout)) Environment.FailFast("CPU failed to stop after interrupt; refusing to free active guest memory.");
        if (failure != null) throw failure;
        Require(didStart && interrupts == 1 && !context.Running, "Guest interrupt/stop failed");
    }

    private static void ConcurrentContexts(uint seed)
    {
        using var machine = new Machine();
        machine.Program(Entry, Svc(1), 0xd53bd040, Svc(0), 0x14000000); // MRS x0,TPIDR_EL0
        using var rendezvous = new CountdownEvent(2);
        var failures = new ConcurrentQueue<Exception>();
        var contexts = new IExecutionContext[2];
        var workers = new Thread[2];
        for (int i = 0; i < 2; i++)
        {
            int index = i;
            contexts[i] = machine.Cpu.CreateExecutionContext(new ExceptionCallbacks(supervisorCallback: (context, pc, number) =>
            {
                try
                {
                    if (number == 1)
                    {
                        rendezvous.Signal();
                        Require(rendezvous.Wait(Timeout), "Second guest thread did not enter the dispatcher");
                    }
                    else
                    {
                        Require(context.GetX(0) == (ulong)seed + (ulong)index + 1, "Guest TLS leaked across threads");
                        context.StopRunning();
                    }
                }
                catch (Exception error) { failures.Enqueue(error); context.StopRunning(); }
            }));
            contexts[i].TpidrEl0 = (long)seed + i + 1;
            workers[i] = new Thread(() =>
            {
                try { machine.Cpu.Execute(contexts[index], Entry); }
                catch (Exception error) { failures.Enqueue(error); }
            }) { IsBackground = true, Name = $"Ryu.iOS.GuestCheck.{i}" };
        }
        try
        {
            foreach (var thread in workers) thread.Start();
            foreach (var thread in workers)
                if (!thread.Join(Timeout))
                {
                    foreach (var context in contexts) context.StopRunning();
                    foreach (var remaining in workers)
                        if (!remaining.Join(Timeout)) Environment.FailFast("Guest thread did not stop; active mappings retained.");
                    throw new TimeoutException("Concurrent CPU test timed out");
                }
            if (failures.TryDequeue(out var failure)) throw failure;
        }
        finally { foreach (var context in contexts) context.Dispose(); }
    }

    private static void RunBounded(ICpuContext cpu, IExecutionContext context, ulong entry)
    {
        int timedOut = 0;
        using var watchdog = new Timer(_ => { Interlocked.Exchange(ref timedOut, 1); context.StopRunning(); }, null, Timeout, System.Threading.Timeout.InfiniteTimeSpan);
        cpu.Execute(context, entry);
        Require(Volatile.Read(ref timedOut) == 0, "Guest execution timed out");
    }
}
