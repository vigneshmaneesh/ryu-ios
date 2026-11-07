using Ryujinx.Common.Configuration;
using Ryujinx.Common;
using Ryujinx.Common.Logging;
using Ryujinx.Graphics.GAL;
using Ryujinx.Graphics.Vulkan;
using Silk.NET.Vulkan;
using System;
using System.Threading;
using GalFormat = Ryujinx.Graphics.GAL.Format;

namespace Ryu.iOS.Runtime;

// Production renderer conformance. This drives GAL directly, not a guest GPU
// command stream, and must not be described as game/homebrew graphics support.
internal static unsafe class GraphicsProbe
{
    private const int Width = 256;
    private const int Height = 144;

    internal static string Run(string library, nint layer, int surfaceWidth, int surfaceHeight,
        delegate* unmanaged<nint, nint, ulong*, int> createSurface, delegate* unmanaged<int> cancelled)
    {
        GraphicsBindings.Configure(library);
        Logger.Updated += HorizonJournal.Observe;
        try
        {
            HorizonJournal.Write("Loading Silk.NET bindings and production VulkanRenderer");
            using Vk api = GraphicsBindings.CreateApi();
            using var renderer = new VulkanRenderer(api, (instance, _) =>
            {
                ulong surface;
                int result = createSurface(instance.Handle, layer, &surface);
                if (result != 0 || surface == 0) throw new InvalidOperationException($"Metal surface creation failed: {result}.");
                HorizonJournal.Write("Metal surface created");
                return new SurfaceKHR(surface);
            }, () => ["VK_KHR_surface", "VK_EXT_metal_surface"], "");

            HorizonJournal.Write("Initializing production renderer, capabilities, resources and swapchain");
            renderer.Initialize(GraphicsDebugLevel.None);
            renderer.Window.SetSize(surfaceWidth, surfaceHeight);
            renderer.Window.ChangeVSyncMode(VSyncMode.Switch);
            HardwareInfo hardware = renderer.GetHardwareInfo();
            HorizonJournal.Write($"Renderer initialized: {hardware.GpuModel}; {hardware.GpuDriver}");
            ITexture target = renderer.CreateTexture(new TextureCreateInfo(Width, Height, 1, 1, 1,
                1, 1, 4, GalFormat.R8G8B8A8Unorm, DepthStencilMode.Depth, Target.Texture2D,
                SwizzleComponent.Red, SwizzleComponent.Green, SwizzleComponent.Blue, SwizzleComponent.Alpha));
            try
            {
                renderer.Pipeline.SetRenderTargetColorMasks([0xf]);
                renderer.Pipeline.SetRenderTargets([target], null);
                ColorF[] colors = [new(1, 0, 0, 1), new(0, 1, 0, 1), new(0, 0, 1, 1), new(1, 1, 1, 1)];
                for (int index = 0; index < colors.Length; index++)
                {
                    renderer.Pipeline.SetScissors([new Rectangle<int>((index & 1) * Width / 2,
                        (index >> 1) * Height / 2, Width / 2, Height / 2)]);
                    renderer.Pipeline.ClearRenderTargetColor(0, 0, 1, 0xf, colors[index]);
                }
                HorizonJournal.Write("Four scissored quadrant clears submitted through upstream GAL pipeline");
                using (PinnedSpan<byte> pixels = target.GetData()) Verify(pixels.Get());
                HorizonJournal.Write($"PASS production render target: all {Width * Height} RGBA pixels verified");

                // A bounded display test with the actual helper shader, swapchain
                // acquire/present and fences. UI cancellation is checked per frame.
                ImageCrop crop = new(0, 0, 0, 0, false, false, true, 16, 9);
                int frames = 0;
                for (; frames < 120; frames++)
                {
                    if (cancelled != null && cancelled() != 0) throw new OperationCanceledException("Renderer display test cancelled.");
                    renderer.PreFrame();
                    renderer.Window.Present(target, crop, static () => { });
                    Thread.Sleep(16);
                }
                if (renderer.PresentedFrames != (ulong)frames)
                    throw new InvalidOperationException($"Only {renderer.PresentedFrames} of {frames} frames were presented.");
                HorizonJournal.Write($"PASS upstream presentation: {frames} frames accepted by the swapchain");
                renderer.Pipeline.SetRenderTargets([], null);
                return $"PASS production VulkanRenderer: {hardware.GpuModel}\nPASS {Width * Height} rendered pixels\nPASS {frames} frame submissions to Metal surface\nExpected display: red, green, blue and white quadrants.\nHost renderer test; no guest GPU commands executed.";
            }
            finally
            {
                target.Release();
                HorizonJournal.Write("Render target released; disposing production renderer");
            }
        }
        finally
        {
            Logger.Updated -= HorizonJournal.Observe;
            HorizonJournal.Write("Graphics renderer scope exited");
        }
    }

    private static void Verify(ReadOnlySpan<byte> pixels)
    {
        if (pixels.Length != Width * Height * 4) throw new InvalidOperationException($"Unexpected pixel count: {pixels.Length} bytes.");
        ReadOnlySpan<uint> colors = [0xff0000ff, 0xff00ff00, 0xffff0000, 0xffffffff];
        for (int y = 0; y < Height; y++)
        for (int x = 0; x < Width; x++)
        {
            uint expected = colors[(x >= Width / 2 ? 1 : 0) + (y >= Height / 2 ? 2 : 0)];
            int at = (y * Width + x) * 4;
            uint actual = (uint)(pixels[at] | pixels[at + 1] << 8 | pixels[at + 2] << 16 | pixels[at + 3] << 24);
            if (actual != expected) throw new InvalidOperationException($"Renderer pixel ({x},{y}): 0x{actual:x8}, expected 0x{expected:x8}.");
        }
    }
}
