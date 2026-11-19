using System;
using System.Reflection;
using Ryujinx.Graphics.GAL;
using Ryujinx.Graphics.Gpu;
using Ryujinx.Graphics.Texture;
using Ryujinx.Memory.Range;

static class TextureScaleChecks
{
    public static void Run()
    {
        // Exercise the production cache decision and resize guard without a GPU.
        var assembly = typeof(GraphicsConfig).Assembly;
        const string ns = "Ryujinx.Graphics.Gpu.Image.";
        var cache = assembly.GetType(ns + "TextureCache", throwOnError: true)!;
        var info = assembly.GetType(ns + "TextureInfo", throwOnError: true)!;
        var texture = assembly.GetType(ns + "Texture", throwOnError: true)!;
        var format = assembly.GetType(ns + "FormatInfo", throwOnError: true)!;
        var rgba = format.GetProperty("Default")!.GetValue(null);
        var classify = cache.GetMethod("IsUpscaleCompatible", BindingFlags.NonPublic | BindingFlags.Static)!;
        var setScale = texture.GetMethod("SetScale")!;
        var scaleFactor = texture.GetProperty("ScaleFactor")!;
        var scaleMode = texture.GetProperty("ScaleMode")!;

        object Info(int width, int height, int levels) => Activator.CreateInstance(info,
            0UL, width, height, 1, levels, 1, 1, 0, false, 1, 1, 1, Target.Texture2D, rgba,
            DepthStencilMode.Depth, SwizzleComponent.Red, SwizzleComponent.Green,
            SwizzleComponent.Blue, SwizzleComponent.Alpha)!;

        // At 1/3 scale, the 86-pixel host texture could only hold 7 of the 8
        // requested levels. A regular game frame should still downscale.
        object mipInfo = Info(256, 128, 8);
        object frameInfo = Info(1280, 720, 1);
        float previousScale = GraphicsConfig.ResScale;
        try
        {
            foreach (float scale in new[] { 1f / 3, 0.5f, 1f / 1.3f })
            {
                GraphicsConfig.ResScale = scale;
                foreach (bool withUpscale in new[] { false, true })
                {
                    var mipMode = classify.Invoke(null, [mipInfo, withUpscale])!;
                    var frameMode = classify.Invoke(null, [frameInfo, withUpscale])!;
                    if (mipMode.ToString() != "Blacklisted" ||
                        frameMode.ToString() != (withUpscale ? "Scaled" : "Eligible"))
                    {
                        throw new Exception($"Incorrect mip or frame scaling policy at {scale}.");
                    }
                }
            }

            GraphicsConfig.ResScale = 2f;
            var originalMipMode = classify.Invoke(null, [mipInfo, true])!;
            if (originalMipMode.ToString() != "Undesired")
            {
                throw new Exception("The above-native texture policy changed.");
            }

            // If scaling is requested directly on mip storage, it should stay
            // at 1x without attempting to allocate a new host texture.
            var mipTexture = Activator.CreateInstance(texture, null, null,
                mipInfo, default(SizeInfo), default(MultiRange), originalMipMode)!;
            setScale.Invoke(mipTexture, [1f / 3]);
            if ((float)scaleFactor.GetValue(mipTexture)! != 1f ||
                scaleMode.GetValue(mipTexture)!.ToString() != "Blacklisted")
            {
                throw new Exception("A direct scale request discarded the native mip range.");
            }

            // A one-level view must also respect the wider range of its storage.
            var mipView = Activator.CreateInstance(texture, null, null,
                Info(2, 1, 1), default(SizeInfo), default(MultiRange), originalMipMode)!;
            texture.GetField("_viewStorage", BindingFlags.NonPublic | BindingFlags.Instance)!.SetValue(mipView, mipTexture);
            setScale.Invoke(mipView, [0.5f]);
            if ((float)scaleFactor.GetValue(mipTexture)! != 1f ||
                scaleMode.GetValue(mipView)!.ToString() != "Blacklisted")
            {
                throw new Exception("A single-level view could downscale mipmapped storage.");
            }
        }
        finally
        {
            GraphicsConfig.ResScale = previousScale;
        }

        Console.WriteLine("PASS mipmapped storage stays native at sub-native scales and single-level framebuffers can still downscale.");
    }
}
