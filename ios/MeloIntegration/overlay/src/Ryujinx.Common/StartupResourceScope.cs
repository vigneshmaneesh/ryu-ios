using System;
using System.Collections.Generic;

namespace Ryujinx.Common;

// A failed constructor/startup cannot rely on the normal shutdown path. Keep
// resources until ownership transfers, and unwind in reverse order on failure.
public sealed class StartupResourceScope : IDisposable
{
    private readonly List<IDisposable> _resources = [];
    private bool _completed;
    public T Track<T>(T resource) where T : IDisposable
    {
        if (_completed) throw new ObjectDisposedException(nameof(StartupResourceScope));
        _resources.Add(resource);
        return resource;
    }
    public void Commit() { _resources.Clear(); _completed = true; }
    public void Release(IDisposable resource) => _resources.Remove(resource);
    public void Defer(Action action) => Track(new CleanupAction(action));
    private sealed class CleanupAction(Action action) : IDisposable
    {
        public void Dispose() => action();
    }
    public void Dispose()
    {
        if (_completed) return;
        _completed = true;
        for (int i = _resources.Count - 1; i >= 0; i--)
        {
            try { _resources[i].Dispose(); }
            catch (ObjectDisposedException) { }
            catch (Exception error) { Console.WriteLine($"[Cleanup] {_resources[i].GetType().Name}: {error.Message}"); }
        }
        _resources.Clear();
    }
}
