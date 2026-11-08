using LibHac.Common;
using LibHac.Common.Keys;
using LibHac.Fs;
using LibHac.Tools.Fs;
using LibHac.Tools.FsSystem;
using LibHac.Tools.FsSystem.NcaUtils;
using Ryujinx.HLE.Loaders;
using System;
using System.Buffers.Binary;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using Path = System.IO.Path;

namespace Ryu.iOS.Runtime;

internal static class LoaderChecks
{
    private sealed class ChunkedStream(byte[] data) : MemoryStream(data)
    {
        public override int Read(Span<byte> buffer) => base.Read(buffer[..Math.Min(buffer.Length, 512)]);
        public override int Read(byte[] buffer, int offset, int count) => base.Read(buffer, offset, Math.Min(count, 512));
    }
    private static void U32(byte[] b, int at, uint v) => BinaryPrimitives.WriteUInt32LittleEndian(b.AsSpan(at), v);
    private static void U64(byte[] b, int at, ulong v) => BinaryPrimitives.WriteUInt64LittleEndian(b.AsSpan(at), v);
    private static byte[] Hfs(string name, byte[] contents)
    {
        byte[] bytes = new byte[512 + contents.Length];
        "HFS0"u8.CopyTo(bytes); U32(bytes, 4, 1); U32(bytes, 8, 512 - 16 - 64);
        U64(bytes, 24, (ulong)contents.Length); U32(bytes, 36, (uint)Math.Min(512, contents.Length));
        SHA256.HashData(contents.AsSpan(0, Math.Min(512, contents.Length))).CopyTo(bytes, 48);
        Encoding.UTF8.GetBytes(name).CopyTo(bytes, 80); contents.CopyTo(bytes, 512); return bytes;
    }
    private static byte[] Fixture()
    {
        // Authored, unencrypted header; no console keys or Nintendo content.
        byte[] nca = new byte[0xC00]; "NCA3"u8.CopyTo(nca.AsSpan(0x200));
        nca[0x204] = 1; nca[0x205] = 1; U64(nca, 0x208, (ulong)nca.Length); U64(nca, 0x210, 0x0100FFFF00000000);
        byte[] secure = Hfs("00000000000000000000000000000001.cnmt.nca", nca);
        byte[] root = Hfs("secure", secure);
        byte[] xci = new byte[0xF000 + root.Length]; "HEAD"u8.CopyTo(xci.AsSpan(0x100));
        U64(xci, 0x118, (ulong)(xci.Length / 512 - 1)); U64(xci, 0x130, 0xF000); U64(xci, 0x138, 512);
        SHA256.HashData(root.AsSpan(0, 512)).CopyTo(xci, 0x140); root.CopyTo(xci, 0xF000); return xci;
    }
    private static void ReadNca(Stream stream)
    {
        var keys = KeySet.CreateDefaultKeySet();
        var xci = new Xci(keys, stream.AsStorage(true));
        var secure = xci.OpenPartition(XciPartitionType.Secure);
        Nca nca = secure.GetNca(keys, "/00000000000000000000000000000001.cnmt.nca");
        if (nca.Header.TitleId != 0x0100FFFF00000000) throw new InvalidDataException("Fixture NCA header changed.");
    }
    internal static string Run(string directory)
    {
        byte[] fixture = Fixture();
        bool reproduced = false;
        try { using var shortRead = new ChunkedStream(fixture); ReadNca(shortRead); }
        catch (HorizonResultException e) when (ResultFs.OutOfRange.Includes(e.ResultValue)) { reproduced = true; }
        if (!reproduced) throw new InvalidOperationException("The unfixed short-read XCI control did not reproduce FS 2002-3005.");
        using (var fixedRead = new ReadOnlyGameStream(new ChunkedStream(fixture))) ReadNca(fixedRead);
        bool rejected = false;
        try { using var truncated = new ReadOnlyGameStream(new ChunkedStream(fixture[..^512])); ReadNca(truncated); }
        catch (HorizonResultException e) when (ResultFs.OutOfRange.Includes(e.ResultValue)) { rejected = true; }
        if (!rejected) throw new InvalidOperationException("A truncated XCI was accepted.");
        Directory.CreateDirectory(directory);
        string path = Path.Combine(directory, "authored-container.xci");
        File.WriteAllBytes(path, fixture);
        XciBounds.Check(path, KeySet.CreateDefaultKeySet());
        File.WriteAllBytes(path, fixture[..^512]);
        rejected = false;
        try { XciBounds.Check(path, KeySet.CreateDefaultKeySet()); } catch (ContentImports.SetupException) { rejected = true; }
        File.Delete(path);
        if (!rejected) throw new InvalidOperationException("XCI bounds check missed the truncated secure entry.");
        string log = Path.Combine(directory, "loader-journal.log");
        HorizonJournal.Begin(directory, "loader-journal.log");
        for (int i = 0; i < 80; i++) HorizonJournal.Write(new string('x', 1000));
        HorizonJournal.Write("Loader terminal reason retained"); HorizonJournal.Finish(false, new InvalidDataException("Authored loader failure"));
        string saved = File.ReadAllText(log);
        if (!saved.Contains("Loader terminal reason retained") || !saved.Contains("Authored loader failure") || !saved.Contains("RESULT FAIL") || new FileInfo(log).Length > 48 * 1024)
            throw new InvalidOperationException("Bounded journal lost terminal diagnostics.");
        return "PASS XCI short-read control reproduces 2002-3005\nPASS complete reads decode the authored NCA header\nPASS truncated XCI rejected with bounds\nPASS terminal loader diagnostics survive log rollover";
    }
}
