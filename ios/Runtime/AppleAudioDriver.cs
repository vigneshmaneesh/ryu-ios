using Ryujinx.Audio.Backends.Common;
using Ryujinx.Audio.Common;
using Ryujinx.Audio.Integration;
using Ryujinx.Memory;
using System;
using System.Collections.Generic;
using System.Threading;
using static Ryujinx.Audio.Integration.IHardwareDeviceDriver;

namespace Ryu.iOS.Runtime;

// Native callbacks copy PCM into AudioQueue-owned buffers. No managed code runs
// on the realtime completion thread; this driver polls completed sequence IDs.
internal sealed unsafe class AppleAudioDriver : IHardwareDeviceDriver
{
    internal static delegate* unmanaged<uint, uint, nint> Open;
    internal static delegate* unmanaged<nint, byte*, nuint, ulong, int> Enqueue;
    internal static delegate* unmanaged<nint, int, float, int> Control;
    internal static delegate* unmanaged<nint, int, ulong> Counter;
    internal static delegate* unmanaged<nint, void> Close;
    internal static bool Available => Open != null && Enqueue != null && Control != null && Counter != null && Close != null;
    private readonly object _gate = new();
    private readonly List<Session> _sessions = [];
    private readonly ManualResetEvent _update = new(false), _pause = new(true);
    private readonly Timer _timer;
    private float _volume = 1;
    private bool _disposed;
    public static bool IsSupported => Available;
    public AppleAudioDriver() => _timer = new Timer(_ => Poll(), null, 5, 5);
    public float Volume { get { lock (_gate) return _volume; } set { lock (_gate) { _volume = Math.Clamp(value, 0, 1); foreach (var s in _sessions) s.RefreshVolume(); } } }
    private void Poll()
    {
        lock (_gate) { if (_disposed) return; foreach (var s in _sessions) if (s.Poll()) _update.Set(); }
    }
    public IHardwareDeviceSession OpenDeviceSession(Direction direction, IVirtualMemoryManager memory, SampleFormat format, uint rate, uint channels)
    {
        if (direction != Direction.Output || !SupportsSampleFormat(format) || !SupportsSampleRate(rate) || !SupportsChannelCount(channels))
            throw new NotSupportedException("Apple audio requires 48 kHz PCM16 output, mono or stereo.");
        lock (_gate)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            var session = new Session(this, memory, rate == 0 ? 48000u : rate, channels == 0 ? 2u : channels);
            _sessions.Add(session); return session;
        }
    }
    public ManualResetEvent GetUpdateRequiredEvent() => _update;
    public ManualResetEvent GetPauseEvent() => _pause;
    public bool SupportsDirection(Direction d) => d == Direction.Output;
    public bool SupportsSampleRate(uint r) => r is 0 or 48000;
    public bool SupportsSampleFormat(SampleFormat f) => f == SampleFormat.PcmInt16;
    public bool SupportsChannelCount(uint c) => c is 0 or 1 or 2;
    public void Dispose()
    {
        lock (_gate) { if (_disposed) return; _disposed = true; _timer.Dispose(); foreach (var s in _sessions) s.Dispose(); _sessions.Clear(); _pause.Dispose(); }
        // The upstream audio update loop owns/disposes _update, matching its drivers.
    }
    private sealed class Session : HardwareDeviceSessionOutputBase
    {
        private readonly AppleAudioDriver _driver;
        private readonly object _gate = new();
        private readonly Dictionary<ulong, ulong> _tickets = [];
        private nint _handle;
        private ulong _sequence, _completed;
        private float _volume = 1;
        private bool _started, _nativeStarted;
        internal Session(AppleAudioDriver driver, IVirtualMemoryManager memory, uint rate, uint channels)
            : base(memory, SampleFormat.PcmInt16, rate, channels)
        {
            _driver = driver; _handle = Open(rate, channels);
            if (_handle == 0) throw new InvalidOperationException("Apple AudioQueue could not open an output device.");
        }
        internal bool Poll()
        {
            lock (_gate)
            {
                if (_handle == 0) return false;
                bool shouldPlay = _started && _driver._pause.WaitOne(0);
                if (shouldPlay != _nativeStarted) { Check(Control(_handle, shouldPlay ? 1 : 0, 0)); _nativeStarted = shouldPlay; }
                ulong done = Counter(_handle, 1); bool changed = done != _completed; _completed = done; return changed;
            }
        }
        private static void Check(int code) { if (code != 0) throw new InvalidOperationException($"Apple AudioQueue error {code}."); }
        internal void RefreshVolume() { lock (_gate) { if (_handle != 0) Check(Control(_handle, 2, _volume * _driver._volume)); } }
        public override void QueueBuffer(AudioBuffer buffer)
        {
            lock (_gate)
            {
                if (_handle == 0) return;
                ulong ticket = ++_sequence;
                fixed (byte* data = buffer.Data) Check(Enqueue(_handle, data, (nuint)buffer.Data.Length, ticket));
                _tickets[buffer.BufferTag] = ticket;
            }
        }
        public override bool WasBufferFullyConsumed(AudioBuffer b) { lock (_gate) return _handle == 0 || !_tickets.TryGetValue(b.BufferTag, out ulong ticket) || Counter(_handle, 1) >= ticket; }
        public override void UnregisterBuffer(AudioBuffer b) { lock (_gate) _tickets.Remove(b.BufferTag); }
        public override ulong GetPlayedSampleCount() { lock (_gate) return _handle == 0 ? 0 : Counter(_handle, 0); }
        public override void SetVolume(float v) { lock (_gate) _volume = Math.Clamp(v, 0, 1); RefreshVolume(); }
        public override float GetVolume() { lock (_gate) return _volume; }
        public override void Start() { lock (_gate) _started = true; Poll(); }
        public override void Stop() { lock (_gate) _started = false; Poll(); }
        public override void PrepareToClose() => Stop();
        public override void Dispose() { lock (_gate) { if (_handle != 0) { Close(_handle); _handle = 0; _tickets.Clear(); } } }
    }
}
