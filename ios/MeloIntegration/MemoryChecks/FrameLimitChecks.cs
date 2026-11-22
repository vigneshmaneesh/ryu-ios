using System;
using System.Diagnostics;
using System.Reflection;
using Ryujinx.HLE;

static class FrameLimitChecks
{
    public static void Run()
    {
        var composer = typeof(PerformanceStatistics).Assembly.GetType(
            "Ryujinx.HLE.HOS.Services.SurfaceFlinger.SurfaceFlinger", throwOnError: true)!;
        const BindingFlags staticFlags = BindingFlags.Static | BindingFlags.NonPublic;
        var intervalFor = composer.GetMethod("GetFrameInterval", staticFlags)!;
        var remainderFor = composer.GetMethod("GetTimingRemainder", staticFlags)!;

        var interval = (long)intervalFor.Invoke(null, [1L, true])!;
        if (interval * 60 < Stopwatch.Frequency || (interval - 1) * 60 >= Stopwatch.Frequency ||
            (long)intervalFor.Invoke(null, [interval * 2, true])! != interval * 2 ||
            (long)intervalFor.Invoke(null, [1L, false])! != 1)
        {
            throw new Exception("The optional limit changed a slower interval or failed to cap a fast one.");
        }

        long delayedTick = interval * 5 + interval / 2;
        if ((long)remainderFor.Invoke(null, [delayedTick, interval, true])! != 0 ||
            (long)remainderFor.Invoke(null, [delayedTick, interval, false])! != interval * 3)
        {
            throw new Exception("A late tick can catch up with a capped frame, or normal Switch pacing changed.");
        }

        const BindingFlags instanceFlags = BindingFlags.Instance | BindingFlags.NonPublic;
        var statistics = new PerformanceStatistics(null);
        using var timer = (System.Timers.Timer)typeof(PerformanceStatistics)
            .GetField("_resetTimer", instanceFlags)!.GetValue(statistics)!;
        timer.Stop();
        var sample = typeof(PerformanceStatistics).GetMethod("CalculateFrameRate", instanceFlags)!;

        long frameTime = Stopwatch.Frequency * 3600;
        statistics.RecordGameFrameTime(frameTime);
        for (int i = 0; i < 60; i++)
        {
            frameTime += interval;
            statistics.RecordGameFrameTime(frameTime);
        }
        statistics.RecordGameFrameTime(frameTime); // A duplicate must not create a transient overshoot.
        sample.Invoke(statistics, [0]);
        if (Math.Abs(statistics.GetGameFrameRate() - 60) > 0.001)
        {
            throw new Exception("Reported capped FPS does not match the paced timestamps.");
        }

        long slowerInterval = (Stopwatch.Frequency + 39) / 40;
        for (int i = 0; i < 40; i++)
        {
            frameTime += slowerInterval;
            statistics.RecordGameFrameTime(frameTime);
        }
        sample.Invoke(statistics, [0]);
        if (Math.Abs(statistics.GetGameFrameRate() - 40) > 0.001)
        {
            throw new Exception("Reported FPS hid a slowdown with the limiter enabled.");
        }

        Console.WriteLine("PASS Switch VSync limiter uses a 60 FPS interval, skips catch-up bursts and reports actual slower frames.");
    }
}
