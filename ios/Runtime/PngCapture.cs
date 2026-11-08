using Ryujinx.Graphics.GAL;
using System;
using System.Buffers.Binary;
using System.IO;
using System.IO.Compression;
using System.Text;

namespace Ryu.iOS.Runtime;

// NativeAOT screenshot export without desktop Skia native dependencies.
internal static class PngCapture
{
    internal static void Write(string path, ScreenCaptureImageInfo image)
    {
        if (image.Width <= 0 || image.Height <= 0 || (long)image.Width * image.Height > 16 * 1024 * 1024 || image.Data.Length != checked(image.Width * image.Height * 4)) throw new InvalidDataException("Unsupported screenshot dimensions.");
        using var compressed = new MemoryStream();
        using (var zlib = new ZLibStream(compressed, CompressionLevel.Fastest, true))
        {
            byte[] row = new byte[image.Width * 4 + 1];
            for (int y = 0; y < image.Height; y++)
            {
                int sy = image.FlipY ? image.Height - 1 - y : y;
                for (int x = 0; x < image.Width; x++)
                {
                    int sx = image.FlipX ? image.Width - 1 - x : x, source = (sy * image.Width + sx) * 4, target = 1 + x * 4;
                    row[target] = image.Data[source + (image.IsBgra ? 2 : 0)]; row[target + 1] = image.Data[source + 1]; row[target + 2] = image.Data[source + (image.IsBgra ? 0 : 2)]; row[target + 3] = image.Data[source + 3];
                }
                zlib.Write(row);
            }
        }
        using var output = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.Read);
        output.Write(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 });
        Span<byte> header = stackalloc byte[13]; header.Clear(); BinaryPrimitives.WriteInt32BigEndian(header, image.Width); BinaryPrimitives.WriteInt32BigEndian(header[4..], image.Height); header[8] = 8; header[9] = 6;
        Chunk(output, "IHDR", header); Chunk(output, "IDAT", compressed.GetBuffer().AsSpan(0, (int)compressed.Length)); Chunk(output, "IEND", []); output.Flush(true);
    }
    private static void Chunk(Stream stream, string type, ReadOnlySpan<byte> data)
    {
        Span<byte> word = stackalloc byte[4]; BinaryPrimitives.WriteInt32BigEndian(word, data.Length); stream.Write(word);
        byte[] name = Encoding.ASCII.GetBytes(type); stream.Write(name); stream.Write(data);
        uint crc = uint.MaxValue;
        foreach (byte value in name) crc = Update(crc, value);
        foreach (byte value in data) crc = Update(crc, value);
        BinaryPrimitives.WriteUInt32BigEndian(word, ~crc); stream.Write(word);
    }
    private static uint Update(uint crc, byte value) { crc ^= value; for (int i = 0; i < 8; i++) crc = (crc >> 1) ^ ((crc & 1) != 0 ? 0xedb88320U : 0); return crc; }
}
