using Ryujinx.Common.Logging;
using System;
using System.Collections.Generic;

namespace Ryu.iOS.Runtime;

internal sealed class LoaderErrorCapture : IDisposable
{
    private readonly List<string> _errors = [];
    private readonly int _thread = Environment.CurrentManagedThreadId;
    internal LoaderErrorCapture() => Logger.Updated += Observe;
    private void Observe(object sender, LogEventArgs e)
    {
        if (e.Level != LogLevel.Error || Environment.CurrentManagedThreadId != _thread) return;
        if (_errors.Count == 4) _errors.RemoveAt(0);
        _errors.Add(e.Message.Length > 700 ? e.Message[..700] : e.Message);
    }
    internal string Failure => _errors.Count == 0 ? "The loader rejected this title without an error message. Share the saved loader trace." : string.Join("\n", _errors);
    public void Dispose() => Logger.Updated -= Observe;
}
