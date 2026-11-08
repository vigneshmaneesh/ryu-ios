using System;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text.Json.Nodes;
using System.Buffers.Binary;

namespace Ryu.iOS.Runtime;

public static class ParityChecks
{
    public static string Run(string directory)
    {
        string root = Path.Combine(directory, "parity-checks"), program = Path.Combine(root, "fixture.nro");
        Directory.CreateDirectory(root);
        NativeSettings.Save(root, null, new(), true); NativeSettings.Save(root, program, new(), true);
        NativeSettings.Save(root, null, JsonNode.Parse("{\"ResScale\":-1,\"ResScaleCustom\":1.5,\"AudioVolume\":0.5}")!.AsObject(), false);
        NativeSettings.Save(root, program, JsonNode.Parse("{\"ResScaleCustom\":2.25}")!.AsObject(), false);
        if (NativeSettings.Load(root).Number("ResScaleCustom") != 1.5 || NativeSettings.Load(root, program).Number("ResScaleCustom") != 2.25 || NativeSettings.Load(root, program).Number("AudioVolume") != 0.5) throw new InvalidOperationException("Settings scopes lost inheritance.");
        foreach (string bad in new[] { "{\"AudioVolume\":2}", "{\"ResScale\":0}", "{\"BackendThreading\":\"Unknown\"}", "{\"UseHypervisor\":true}", "{\"EnablePtc\":1}", "{\"GraphicsShadersDumpPath\":\"../escape\"}" })
        {
            string before = File.ReadAllText(NativeSettings.PathFor(root, program));
            bool rejected = false; try { NativeSettings.Save(root, program, JsonNode.Parse(bad)!.AsObject(), false); } catch (ArgumentException) { rejected = true; }
            if (!rejected || before != File.ReadAllText(NativeSettings.PathFor(root, program))) throw new InvalidOperationException("Invalid setting mutated a configuration file.");
        }
        NativeSettings.Save(root, program, new(), true);
        if (NativeSettings.Load(root, program).Number("ResScaleCustom") != 1.5) throw new InvalidOperationException("Reset did not restore global inheritance.");
        NativeSettings.Save(root, null, new(), true);
        // Also exercise the actual native bridge payload format with AOT-safe DOM serialization.
        string contract = AppOperations.Execute(root, JsonNode.Parse("{\"operation\":\"settings.get\"}")!.AsObject()).ToJsonString();
        if (JsonNode.Parse(contract)!["schema"]!.AsArray().Count != NativeSettings.Schema.Count) throw new InvalidOperationException("Settings contract was truncated.");
        string archive = Path.Combine(root, "unsafe.zip"), extraction = Path.Combine(root, "extracted");
        Directory.CreateDirectory(extraction);
        using (var zip = ZipFile.Open(archive, ZipArchiveMode.Create)) { using var writer = new StreamWriter(zip.CreateEntry("../escape.txt").Open()); writer.Write("escape"); }
        bool unsafeRejected = false; try { OwnedFiles.ExtractZip(archive, extraction); } catch (InvalidDataException) { unsafeRejected = true; }
        File.Delete(archive);
        if (!unsafeRejected || File.Exists(Path.Combine(root, "escape.txt"))) throw new InvalidOperationException("ZIP import escaped its staging directory.");
        ServiceBootstrap.Initialize(directory);
        var accounts = ServiceBootstrap.Accounts;
        var previous = accounts.LastOpenedUser.UserId;
        var beforeIds = accounts.GetAllUsers().Select(x => x.UserId).ToHashSet();
        ProfileManager.Manage(directory, JsonNode.Parse("{\"operation\":\"profiles.add\",\"name\":\"AOT fixture\"}")!.AsObject());
        var added = accounts.GetAllUsers().Single(x => !beforeIds.Contains(x.UserId)).UserId;
        try
        {
            ProfileManager.Manage(directory, new JsonObject { ["operation"] = "profiles.select", ["id"] = added.ToString() });
            ProfileManager.Manage(directory, new JsonObject { ["operation"] = "profiles.rename", ["id"] = added.ToString(), ["name"] = "AOT renamed" });
            var persisted = new Ryujinx.HLE.HOS.Services.Account.Acc.AccountManager(ServiceBootstrap.Client);
            if (persisted.LastOpenedUser.UserId != added || persisted.LastOpenedUser.Name != "AOT renamed") throw new InvalidOperationException("Account changes did not persist.");
            _ = SaveManager.List(directory).ToJsonString();
        }
        finally
        {
            ProfileManager.Manage(directory, new JsonObject { ["operation"] = "profiles.delete", ["id"] = added.ToString(), ["confirmed"] = true });
            accounts.OpenUser(previous);
        }
        string recovery = Path.Combine(root, "recovery"), transactions = Path.Combine(recovery, "save-transactions"), save = Path.Combine(recovery, "save"), old = Path.Combine(transactions, "test.old"), stage = Path.Combine(transactions, "test.new");
        Directory.CreateDirectory(save); Directory.CreateDirectory(old); Directory.CreateDirectory(stage);
        File.WriteAllText(Path.Combine(save, "new"), "uncommitted"); File.WriteAllText(Path.Combine(old, "old"), "accepted");
        NativeSettings.AtomicJson(Path.Combine(transactions, "test.json"), new JsonObject { ["folder"] = save, ["backup"] = old, ["stage"] = stage });
        SaveManager.Recover(recovery);
        if (!File.Exists(Path.Combine(save, "old")) || File.Exists(Path.Combine(save, "new")) || Directory.Exists(stage)) throw new InvalidOperationException("Interrupted save restore did not roll back.");
        OwnedFiles.Delete(root, recovery);
        string capture = Path.Combine(root, "pixel-fixture.png");
        PngCapture.Write(capture, new Ryujinx.Graphics.GAL.ScreenCaptureImageInfo(2, 2, true, [3,2,1,255, 6,5,4,255, 9,8,7,255, 12,11,10,255], true, true));
        byte[] png = File.ReadAllBytes(capture);
        using var deflated = new MemoryStream();
        for (int offset = 8; offset < png.Length;)
        {
            int count = BinaryPrimitives.ReadInt32BigEndian(png.AsSpan(offset, 4));
            if (System.Text.Encoding.ASCII.GetString(png, offset + 4, 4) == "IDAT") deflated.Write(png, offset + 8, count);
            offset += 12 + count;
        }
        deflated.Position = 0;
        using var decoded = new MemoryStream(); using (var zlib = new ZLibStream(deflated, CompressionMode.Decompress, true)) zlib.CopyTo(decoded);
        if (!decoded.ToArray().SequenceEqual(new byte[] { 0,10,11,12,255,7,8,9,255, 0,4,5,6,255,1,2,3,255 })) throw new InvalidOperationException("Screenshot export did not preserve channel order or flips.");
        File.Delete(capture);
        return "PASS persistent global/per-game settings, inheritance and reset\nPASS invalid settings preserve the previous configuration\nPASS AOT settings contract serialization\nPASS ZIP traversal rejection\nPASS real account creation/selection/rename/persistence/delete\nPASS real save-index enumeration and interrupted-restore recovery\nPASS PNG screenshot pixels / BGRA conversion / both flips\n" + Ryujinx.HLE.HOS.Tamper.AotCheatChecks.Run();
    }
}
