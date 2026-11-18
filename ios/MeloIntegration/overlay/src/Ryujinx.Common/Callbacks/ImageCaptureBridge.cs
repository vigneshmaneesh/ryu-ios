using System;
using System.Runtime.InteropServices;

namespace Ryujinx.Common.Callbacks
{
    // The callback consumes/copies all borrowed data before returning.
    // Result reports local image creation, independently of Photos authorization.
    public static class ImageCaptureBridge
    {
        public const int MaxImageBytes = 64 * 1024 * 1024;

        [StructLayout(LayoutKind.Sequential)]
        private struct Request
        {
            public nint Pixels;
            public nint FilePath;
            public int Width;
            public int Height;
            public int ByteLength;
            public int Flags;
            public int Result;
        }

        public static unsafe bool Export(byte[] pixels, int width, int height, bool bgra = false,
            bool flipX = false, bool flipY = false, string filePath = null)
        {
            long required = (long)width * height * 4;
            if (width <= 0 || height <= 0 || width > 8192 || height > 8192 ||
                required > MaxImageBytes || pixels == null || pixels.Length < required)
            {
                return false;
            }

            nint path = filePath == null ? 0 : Marshal.StringToCoTaskMemUTF8(filePath);
            try
            {
                fixed (byte* data = pixels)
                {
                    Request request = new()
                    {
                        Pixels = (nint)data,
                        FilePath = path,
                        Width = width,
                        Height = height,
                        ByteLength = (int)required,
                        Flags = (bgra ? 1 : 0) | (flipX ? 2 : 0) | (flipY ? 4 : 0),
                    };
                    return CallbackRegistry.Invoke("ExportImageCapture", (nint)(&request), sizeof(Request)) &&
                        request.Result == 1;
                }
            }
            finally
            {
                if (path != 0)
                {
                    Marshal.FreeCoTaskMem(path);
                }
            }
        }
    }
}
