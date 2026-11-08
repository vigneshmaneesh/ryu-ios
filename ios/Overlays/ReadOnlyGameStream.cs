using System;
using System.IO;

namespace Ryujinx.HLE.Loaders;

// LibHac StreamStorage treats a short Stream.Read as an out-of-range error.
// Fill each requested buffer, while preserving true EOF and read-only access.
public sealed class ReadOnlyGameStream : Stream
{
    private readonly Stream _inner;
    private readonly bool _leaveOpen;
    private readonly string _name;
    public ReadOnlyGameStream(string path) : this(new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read), false, Path.GetFileName(path)) { }
    public ReadOnlyGameStream(Stream inner, bool leaveOpen = false, string name = "container")
    { _inner = inner; _leaveOpen = leaveOpen; _name = name; }
    public override bool CanRead => _inner.CanRead;
    public override bool CanSeek => _inner.CanSeek;
    public override bool CanWrite => false;
    public override long Length => _inner.Length;
    public override long Position { get => _inner.Position; set => _inner.Position = value; }
    public override int Read(byte[] buffer, int offset, int count) => Read(buffer.AsSpan(offset, count));
    public override int Read(Span<byte> buffer)
    {
        long start = Position;
        int total = 0;
        while (total < buffer.Length)
        {
            int count = _inner.Read(buffer[total..]);
            if (count == 0)
            {
                StartupDiagnostics.Write($"Unexpected end of {_name}: offset 0x{start:X}, requested {buffer.Length}, received {total}, file size {Length}");
                break;
            }
            total += count;
        }
        return total;
    }
    public override long Seek(long offset, SeekOrigin origin) => _inner.Seek(offset, origin);
    public override void Flush() { }
    public override void SetLength(long value) => throw new NotSupportedException("Game inputs are read-only.");
    public override void Write(byte[] b, int o, int c) => throw new NotSupportedException("Game inputs are read-only.");
    protected override void Dispose(bool disposing) { if (disposing && !_leaveOpen) _inner.Dispose(); base.Dispose(disposing); }
}
