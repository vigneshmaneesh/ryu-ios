using Ryujinx.Graphics.Vulkan;
using Silk.NET.Core.Contexts;
using Silk.NET.Vulkan;
using System;
using System.IO;
using System.Runtime.InteropServices;

namespace Ryu.iOS.Runtime;

// Silk's __Internal iOS loader asks NativeAOT to load a null library path. Bind
// commands directly from the retained signed framework, without that loader.
internal static class GraphicsBindings
{
    private static string _path;
    private static nint _library;

    internal static void Configure(string path)
    {
        path = Path.GetFullPath(path);
        if (_path != null)
        {
            if (_path != path) throw new InvalidOperationException("The graphics library cannot change during an app session.");
            return;
        }
        if (!File.Exists(path)) throw new FileNotFoundException("The bundled MoltenVK library is missing.", path);
        _library = NativeLibrary.Load(path);
        _path = path;
        NativeLibrary.SetDllImportResolver(typeof(VulkanRenderer).Assembly,
            (name, assembly, search) => name is "libMoltenVK.dylib" or "libvulkan.dylib" ? _library : 0);
    }

    internal static Vk CreateApi() => new(new LamdaNativeContext(name =>
        NativeLibrary.TryGetExport(_library, name, out nint address) ? address : 0));
}
