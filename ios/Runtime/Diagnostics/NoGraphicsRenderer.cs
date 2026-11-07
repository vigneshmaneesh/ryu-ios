using Ryujinx.Common.Configuration;
using Ryujinx.Graphics.GAL;
using System;

namespace Ryu.iOS.HorizonChecks;

// Kernel/homebrew conformance only; any attempt to render fails explicitly.
// This diagnostic fixture is never used as the app's game renderer.
internal sealed class NoGraphicsRenderer : IRenderer
{
    public event EventHandler<ScreenCaptureImageInfo> ScreenCaptured { add { } remove { } }
    public bool PreferThreading => false;
    public IPipeline Pipeline => throw GraphicsAccess();
    public IWindow Window => throw GraphicsAccess();
    public uint ProgramCount => 0;
    private static NotSupportedException GraphicsAccess() => new("The kernel probe attempted a graphics operation.");
    public void BackgroundContextAction(Action action, bool alwaysBackground = false) => throw GraphicsAccess();
    public BufferHandle CreateBuffer(int size, BufferAccess access = BufferAccess.Default) => throw GraphicsAccess();
    public BufferHandle CreateBuffer(nint pointer, int size) => throw GraphicsAccess();
    public BufferHandle CreateBufferSparse(ReadOnlySpan<BufferRange> buffers) => throw GraphicsAccess();
    public IImageArray CreateImageArray(int size, bool isBuffer) => throw GraphicsAccess();
    public IProgram CreateProgram(ShaderSource[] shaders, ShaderInfo info) => throw GraphicsAccess();
    public ISampler CreateSampler(SamplerCreateInfo info) => throw GraphicsAccess();
    public ITexture CreateTexture(TextureCreateInfo info) => throw GraphicsAccess();
    public ITextureArray CreateTextureArray(int size, bool isBuffer) => throw GraphicsAccess();
    public bool PrepareHostMapping(nint address, ulong size) => false;
    public void CreateSync(ulong id, bool strict) => throw GraphicsAccess();
    public void DeleteBuffer(BufferHandle buffer)
    {
        if (buffer != BufferHandle.Null) throw GraphicsAccess();
    }
    public PinnedSpan<byte> GetBufferData(BufferHandle buffer, int offset, int size) => throw GraphicsAccess();
    public Capabilities GetCapabilities() => default;
    public ulong GetCurrentSync() => 0;
    public HardwareInfo GetHardwareInfo() => default;
    public IProgram LoadProgramBinary(byte[] binary, bool fragment, ShaderInfo info) => throw GraphicsAccess();
    public void SetBufferData(BufferHandle buffer, int offset, ReadOnlySpan<byte> data) => throw GraphicsAccess();
    public void UpdateCounters() => throw GraphicsAccess();
    public void PreFrame() => throw GraphicsAccess();
    public ICounterEvent ReportCounter(CounterType type, EventHandler<ulong> result, float divisor, bool hostReserved) => throw GraphicsAccess();
    public void ResetCounter(CounterType type) => throw GraphicsAccess();
    public void WaitSync(ulong id) => throw GraphicsAccess();
    public void Initialize(GraphicsDebugLevel level) { }
    public void SetInterruptAction(Action<Action> action) { }
    public void Screenshot() => throw GraphicsAccess();
    public void Dispose() { }
}
