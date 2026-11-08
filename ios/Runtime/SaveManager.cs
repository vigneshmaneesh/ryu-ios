using LibHac.Common;
using LibHac.Fs;
using LibHac.Fs.Shim;
using LibHac.Ncm;
using Ryujinx.HLE.FileSystem;
using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text.Json.Nodes;
using Path = System.IO.Path;

namespace Ryu.iOS.Runtime;

internal static class SaveManager
{
    private static IEnumerable<SaveDataInfo> Entries(string root)
    {
        ServiceBootstrap.Initialize(root);
        SaveDataFilter filter = SaveDataFilter.Make(programId: default, saveType: default, userId: default, saveDataId: default, index: default);
        using UniqueRef<SaveDataIterator> iterator = new();
        ServiceBootstrap.Client.Fs.OpenSaveDataIterator(ref iterator.Ref, SaveDataSpaceId.User, in filter).ThrowIfFailure();
        var entries = new List<SaveDataInfo>();
        SaveDataInfo[] buffer = new SaveDataInfo[16];
        while (true)
        {
            iterator.Get.ReadSaveDataInfo(out long count, buffer).ThrowIfFailure();
            if (count == 0) break;
            for (int i = 0; i < count; i++) if (buffer[i].ProgramId.Value != 0) entries.Add(buffer[i]);
        }
        return entries;
    }
    private static string Folder(ulong id) => Path.Combine(VirtualFileSystem.GetNandPath(), "user", "save", id.ToString("x16"));
    private static string Payload(string folder) => Directory.Exists(Path.Combine(folder, "0")) ? Path.Combine(folder, "0") : Directory.Exists(Path.Combine(folder, "1")) ? Path.Combine(folder, "1") : folder;
    internal static JsonObject List(string root, string program = null)
    {
        string title = string.IsNullOrEmpty(program) ? null : TitleContent.BaseId(root, program);
        var result = new JsonArray();
        foreach (var info in Entries(root))
        {
            if (title != null && (info.ProgramId.Value & ~0x1FFFUL).ToString("x16") != title) continue;
            if (info.Type == SaveDataType.Account && info.UserId != ServiceBootstrap.Accounts.LastOpenedUser.UserId.ToLibHac()) continue;
            string folder = Folder(info.SaveDataId);
            long size = Directory.Exists(folder) ? Directory.EnumerateFiles(folder, "*", SearchOption.AllDirectories).Sum(p => new FileInfo(p).Length) : 0;
            result.Add(new JsonObject { ["id"] = info.SaveDataId.ToString("x16"), ["titleId"] = info.ProgramId.Value.ToString("x16"), ["type"] = info.Type.ToString(), ["size"] = size });
        }
        return new() { ["saves"] = result, ["profile"] = ServiceBootstrap.Accounts.LastOpenedUser.Name };
    }
    internal static JsonObject Manage(string root, string program, JsonObject request)
    {
        string operation = request["operation"]!.GetValue<string>();
        if (operation == "saves.list") return List(root, program);
        ulong id = Convert.ToUInt64(request["id"]!.GetValue<string>(), 16);
        var info = Entries(root).SingleOrDefault(x => x.SaveDataId == id);
        if (info.SaveDataId != id || id == 0 || (info.Type == SaveDataType.Account && info.UserId != ServiceBootstrap.Accounts.LastOpenedUser.UserId.ToLibHac())) throw new ArgumentException("Unknown save for the selected profile.");
        string folder = OwnedFiles.RequireWithin(root, Folder(id));
        if (operation == "saves.export")
        {
            string exports = Path.Combine(root, "Exports"); Directory.CreateDirectory(exports);
            string destination = Path.Combine(exports, $"{info.ProgramId.Value:x16}-{info.Type}-{DateTime.UtcNow:yyyyMMdd-HHmmss}-{Guid.NewGuid():N}.zip");
            ZipFile.CreateFromDirectory(Payload(folder), destination, CompressionLevel.Fastest, false);
            return new() { ["export"] = destination };
        }
        if (operation == "saves.delete")
        {
            if (request["confirmed"]?.GetValue<bool>() != true) throw new ArgumentException("Save deletion requires confirmation.");
            ServiceBootstrap.Client.Fs.DeleteSaveData(SaveDataSpaceId.User, id).ThrowIfFailure();
        }
        else if (operation == "saves.restore") Restore(root, folder, OwnedFiles.RequireWithin(root, request["source"]!.GetValue<string>()));
        else throw new ArgumentException("Unknown save operation.");
        return List(root, program);
    }
    private static void Restore(string root, string folder, string source)
    {
        string transactions = Path.Combine(root, "save-transactions"), token = Guid.NewGuid().ToString("N");
        Directory.CreateDirectory(transactions);
        string stage = Path.Combine(transactions, token + ".new"), backup = Path.Combine(transactions, token + ".old"), pending = Path.Combine(transactions, token + ".json");
        Directory.CreateDirectory(stage);
        try
        {
            CopyTree(root, folder, stage);
            // Preserve LibHac's extra data but replace both journal snapshots so
            // its next mount cannot select stale working data over the restore.
            OwnedFiles.Delete(root, Path.Combine(stage, "0")); OwnedFiles.Delete(root, Path.Combine(stage, "1"));
            string payload = Path.Combine(stage, "0"); Directory.CreateDirectory(payload);
            OwnedFiles.ExtractZip(source, payload);
            NativeSettings.AtomicJson(pending, new JsonObject { ["folder"] = folder, ["backup"] = backup, ["stage"] = stage });
            Directory.Move(folder, backup);
            Directory.Move(stage, folder);
            File.Delete(pending); // Commit point; old data can now be discarded.
            OwnedFiles.Delete(root, backup);
        }
        catch { Recover(root); throw; }
        finally { if (Directory.Exists(stage)) OwnedFiles.Delete(root, stage); }
    }
    private static void CopyTree(string root, string source, string destination)
    {
        OwnedFiles.RequireWithin(root, source);
        foreach (string directory in Directory.GetDirectories(source)) { OwnedFiles.RequireWithin(root, directory); string target = Path.Combine(destination, Path.GetFileName(directory)); Directory.CreateDirectory(target); CopyTree(root, directory, target); }
        foreach (string file in Directory.GetFiles(source)) { OwnedFiles.RequireWithin(root, file); File.Copy(file, Path.Combine(destination, Path.GetFileName(file))); }
    }
    internal static void Recover(string root)
    {
        string transactions = Path.Combine(root, "save-transactions");
        if (!Directory.Exists(transactions)) return;
        foreach (string file in Directory.GetFiles(transactions, "*.json"))
        {
            var record = JsonNode.Parse(File.ReadAllText(file))!.AsObject();
            string folder = OwnedFiles.RequireWithin(root, record["folder"]!.GetValue<string>()), backup = OwnedFiles.RequireWithin(transactions, record["backup"]!.GetValue<string>()), stage = OwnedFiles.RequireWithin(transactions, record["stage"]!.GetValue<string>());
            if (Directory.Exists(backup)) { if (Directory.Exists(folder)) OwnedFiles.Delete(root, folder); Directory.Move(backup, folder); }
            if (Directory.Exists(stage)) OwnedFiles.Delete(root, stage);
            File.Delete(file);
        }
        // Files left after the commit point contain obsolete backup data only.
        foreach (string directory in Directory.GetDirectories(transactions)) OwnedFiles.Delete(transactions, directory);
    }
}
