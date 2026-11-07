using Ryujinx.Common.Configuration;
using Ryujinx.Common.Configuration.Multiplayer;
using Ryujinx.Audio.Integration;
using Ryujinx.Graphics.GAL;
using Ryujinx.HLE;
using Ryujinx.HLE.FileSystem;
using Ryujinx.HLE.HOS;
using Ryujinx.HLE.HOS.Services.Account.Acc;
using Ryujinx.HLE.HOS.SystemState;
using LibHac.Tools.FsSystem;
using Ryujinx.Memory;
using System;
using System.IO;

namespace Ryu.iOS.Runtime;

// Real LibHac filesystem/account services. Switch kernel/GPU construction is a
// separate lifecycle stage; this preflight does not claim to run a guest process.
public static class ServiceBootstrap
{
    private static readonly object Gate = new();
    private static string _root;
    private static VirtualFileSystem _fileSystem;
    private static LibHacHorizonManager _horizon;
    private static ContentManager _content;
    private static AccountManager _accounts;

    internal static HleConfiguration KernelProbeConfiguration(IRenderer renderer, IHardwareDeviceDriver audio)
    {
        lock (Gate)
        {
            if (_root == null) throw new InvalidOperationException("Initialize the filesystem first.");
            var configuration = new HleConfiguration(
                MemoryConfiguration.MemoryConfiguration4GiB, SystemLanguage.BritishEnglish, RegionCode.Europe,
                VSyncMode.Switch, false, false, 100, false, IntegrityCheckLevel.ErrorOnInvalid, 0, 0, "UTC",
                MemoryManagerMode.SoftwarePageTable, false, AspectRatio.Fixed16x9, 0, false, "",
                MultiplayerMode.Disabled, true, "", "", false, 0, false, 60);
            return configuration.Configure(_fileSystem, _horizon, _content, _accounts, new UserChannelPersistence(),
                renderer, audio, null);
        }
    }

    public static string Initialize(string directory)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(directory);
        if (!Path.IsPathFullyQualified(directory)) throw new ArgumentException("An absolute app data directory is required.");
        string root = Path.TrimEndingDirectorySeparator(Path.GetFullPath(directory));
        if (root == Path.GetPathRoot(root)) throw new ArgumentException("App data cannot be a filesystem root.");
        // Reserve Switch-sized virtual RAM without allocating 4 GiB of physical
        // memory. Only the first/last host pages are committed and checked.
        const ulong ramSize = 4UL * 1024 * 1024 * 1024;
        using (var ram = new MemoryBlock(ramSize, MemoryAllocationFlags.Reserve))
        {
            ulong page = MemoryBlock.GetPageSize();
            ram.Commit(0, page);
            ram.Commit(ramSize - page, page);
            ram.Write<ulong>(0, 0x0123456789abcdef);
            ram.Write<ulong>(ramSize - 8, 0xfedcba9876543210);
            if (ram.Read<ulong>(0) != 0x0123456789abcdef || ram.Read<ulong>(ramSize - 8) != 0xfedcba9876543210)
                throw new InvalidOperationException("Switch-sized RAM reservation aliased or corrupted.");
        }
        const string ramReport = "PASS 4 GiB virtual RAM / sparse page commits";
        lock (Gate)
        {
            if (_root != null)
            {
                if (_root != root) throw new InvalidOperationException("The emulator filesystem is already mounted at another directory.");
                return ramReport + "\nPASS filesystem/account services (existing session).";
            }
            Directory.CreateDirectory(root);
            AppDataManager.Initialize(root);
            if (Path.TrimEndingDirectorySeparator(AppDataManager.BaseDirPath) != root)
                throw new InvalidOperationException("The core did not select the app's data directory.");
            _fileSystem = VirtualFileSystem.CreateInstance();
            _horizon = new LibHacHorizonManager();
            _horizon.InitializeFsServer(_fileSystem);
            _horizon.InitializeArpServer();
            _horizon.InitializeBcatServer();
            _horizon.InitializeSystemClients();
            _content = new ContentManager(_fileSystem);
            _content.LoadEntries();
            _accounts = new AccountManager(_horizon.RyujinxClient);
            if (_accounts.LastOpenedUser == null)
                throw new InvalidOperationException("The default emulated account was not opened.");
            // Exercise the source-generated persistent profile format under AOT.
            var reloaded = new AccountManager(_horizon.RyujinxClient);
            if (reloaded.LastOpenedUser == null)
                throw new InvalidOperationException("The emulated account did not survive serialization.");
            _root = root;
            return ramReport + "\nPASS LibHac filesystem / ARP / BCAT services\nPASS emulated account persistence\nKernel, graphics and game boot remain separate milestones.";
        }
    }
}
