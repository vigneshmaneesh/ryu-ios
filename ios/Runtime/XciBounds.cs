using LibHac.Common;
using LibHac.Common.Keys;
using LibHac.Fs;
using LibHac.Fs.Fsa;
using LibHac.Tools.Fs;
using LibHac.Tools.FsSystem;
using Ryujinx.HLE.Loaders;
using System;
using System.IO;

namespace Ryu.iOS.Runtime;

internal static class XciBounds
{
    internal static void Check(string path, KeySet keys)
    {
        using var stream = new ReadOnlyGameStream(path);
        var xci = new Xci(keys, stream.AsStorage(true));
        if (!xci.HasPartition(XciPartitionType.Secure)) throw new ContentImports.SetupException("The XCI has no secure game partition. Import a complete base-game XCI.");
        using var root = xci.OpenPartition(XciPartitionType.Root);
        root.GetFileBaseOffset(out long secureRelative, "/secure"u8).ThrowIfFailure();
        long secureStart = checked((xci.Header.HasInitialData ? 0x1000 : 0) + xci.Header.RootPartitionOffset + secureRelative);
        using var secure = xci.OpenPartition(XciPartitionType.Secure);
        int count = 0;
        foreach (var entry in secure.EnumerateEntries("/", "*"))
        {
            if (entry.Type != DirectoryEntryType.File) continue;
            secure.GetFileBaseOffset(out long relative, entry.FullPath.ToU8Span()).ThrowIfFailure();
            long start = checked(secureStart + relative);
            if (entry.Size < 0 || start < 0 || start > stream.Length || entry.Size > stream.Length - start)
                throw new ContentImports.SetupException($"The imported XCI is incomplete or has an invalid file table. Entry {entry.Name} requires bytes 0x{start:X}–0x{checked(start + entry.Size):X}; the file contains {stream.Length} bytes. Reimport the complete XCI.");
            HorizonJournal.Write($"XCI entry {entry.Name}: offset 0x{start:X}, size {entry.Size}");
            count++;
        }
        HorizonJournal.Write($"XCI bounds passed: {count} secure files within {stream.Length} bytes");
    }
}
