using Ryujinx.Graphics.Vulkan;
using Silk.NET.Core.Loader;
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;

namespace Ryu.iOS.Runtime;

// Silk's iOS library name is __Internal. Resolve that name, including on cloned
// Vulkan contexts, to the actual signed framework instead of the desktop loader.
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
        if (PathResolver.Default is not DefaultPathResolver resolver)
            throw new InvalidOperationException("Unexpected Vulkan library resolver.");
        resolver.Resolvers.Insert(0, Resolve);
        NativeLibrary.SetDllImportResolver(typeof(VulkanRenderer).Assembly,
            (name, assembly, search) => name is "libMoltenVK.dylib" or "libvulkan.dylib" ? _library : 0);
    }

    private static IEnumerable<string> Resolve(string name)
    {
        string file = Path.GetFileName(name);
        return file is "__Internal" or "libvulkan.dylib" or "libMoltenVK.dylib" ? [_path] : [];
    }
}
