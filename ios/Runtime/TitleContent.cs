using LibHac.Common;
using LibHac.Fs;
using LibHac.Fs.Fsa;
using LibHac.FsSystem;
using LibHac.Ncm;
using LibHac.Ns;
using LibHac.Tools.Fs;
using LibHac.Tools.FsSystem;
using LibHac.Tools.FsSystem.NcaUtils;
using Ryujinx.Common.Configuration;
using Ryujinx.Common.Memory;
using Ryujinx.HLE.Loaders;
using Ryujinx.HLE.Loaders.Processes.Extensions;
using System;
using System.IO;
using System.Linq;
using System.Text.Json.Nodes;
using ContentType = LibHac.Ncm.ContentType;
using Path = System.IO.Path;

namespace Ryu.iOS.Runtime;

internal static class TitleContent
{
    internal static T Open<T>(string path, Func<IFileSystem, T> use)
    {
        using var stream = new ReadOnlyGameStream(path);
        using var storage = stream.AsStorage();
        IFileSystem fs;
        if (Path.GetExtension(path).Equals(".xci", StringComparison.OrdinalIgnoreCase))
        {
            XciBounds.Check(path, ServiceBootstrap.FileSystem.KeySet);
            fs = new Xci(ServiceBootstrap.FileSystem.KeySet, storage).OpenPartition(XciPartitionType.Secure);
        }
        else
        {
            var partition = new PartitionFileSystem();
            partition.Initialize(storage).ThrowIfFailure(); fs = partition;
        }
        using (fs) { ServiceBootstrap.FileSystem.ImportTickets(fs); return use(fs); }
    }
    private static BlitStruct<ApplicationControlProperty> Control(Nca nca)
    {
        var result = new BlitStruct<ApplicationControlProperty>(1);
        using var fs = nca.OpenFileSystem(NcaSectionType.Data, IntegrityCheckLevel.ErrorOnInvalid);
        using UniqueRef<IFile> file = new();
        fs.OpenFile(ref file.Ref, "/control.nacp".ToU8Span(), OpenMode.Read).ThrowIfFailure();
        file.Get.Read(out long count, 0, result.ByteSpan, ReadOption.None).ThrowIfFailure();
        if (count != result.ByteSpan.Length) throw new InvalidDataException("Incomplete control.nacp.");
        return result;
    }
    internal static JsonObject Inspect(string root, string program)
    {
        ServiceBootstrap.Initialize(root);
        string extension = Path.GetExtension(program).ToLowerInvariant();
        if (extension is not (".xci" or ".nsp")) return new() { ["titles"] = new JsonArray(), ["format"] = extension, ["size"] = new FileInfo(program).Length };
        ServiceBootstrap.FileSystem.ReloadKeySet();
        return Open(program, fs =>
        {
            var titles = new JsonArray();
            foreach (var (id, content) in fs.GetContentData(ContentMetaType.Application, ServiceBootstrap.FileSystem, IntegrityCheckLevel.ErrorOnInvalid))
            {
                Nca control = content.GetNcaByType(ServiceBootstrap.FileSystem.KeySet, ContentType.Control);
                var title = new JsonObject { ["titleId"] = (id & ~0x1FFFUL).ToString("x16"), ["programId"] = id.ToString("x16"), ["versionNumber"] = content.Version.Version };
                if (control != null)
                {
                    var data = Control(control);
                    int language = NativeSettings.Load(root, program).IntLanguage();
                    if ((uint)language >= (uint)data.Value.Title.Length || data.Value.Title[language].NameString.IsEmpty()) language = 0;
                    foreach (var candidate in data.Value.Title.ToArray())
                        if (data.Value.Title[language].NameString.IsEmpty() && !candidate.NameString.IsEmpty()) { title["name"] = candidate.NameString.ToString(); title["publisher"] = candidate.PublisherString.ToString(); break; }
                    title["name"] ??= data.Value.Title[language].NameString.ToString();
                    title["publisher"] ??= data.Value.Title[language].PublisherString.ToString();
                    title["version"] = data.Value.DisplayVersionString.ToString();
                    using var controlFs = control.OpenFileSystem(NcaSectionType.Data, IntegrityCheckLevel.ErrorOnInvalid);
                    var icons = controlFs.EnumerateEntries("/", "icon_*.dat").ToArray();
                    var chosen = icons.FirstOrDefault(x => x.Name == "icon_" + NativeSettings.Load(root, program).Text("SystemLanguage") + ".dat");
                    if (chosen.Name == null && icons.Length > 0) chosen = icons[0];
                    if (chosen.Name != null)
                    {
                        using UniqueRef<IFile> icon = new();
                        controlFs.OpenFile(ref icon.Ref, chosen.FullPath.ToU8Span(), OpenMode.Read).ThrowIfFailure();
                        icon.Get.GetSize(out long size).ThrowIfFailure();
                        if (size is > 0 and <= 1024 * 1024)
                        { byte[] image = new byte[(int)size]; icon.Get.Read(out long read, 0, image, ReadOption.None).ThrowIfFailure(); if (read == size) title["icon"] = Convert.ToBase64String(image); }
                    }
                }
                titles.Add((JsonNode)title);
            }
            if (titles.Count == 0) throw new InvalidDataException("No base application metadata was found. Select a base game, not an update or DLC package.");
            return new JsonObject { ["titles"] = titles, ["format"] = extension, ["size"] = new FileInfo(program).Length };
        });
    }
    internal static string BaseId(string root, string program) => Inspect(root, program)["titles"]!.AsArray().FirstOrDefault()?["titleId"]?.GetValue<string>() ?? throw new ArgumentException("This operation requires a base NSP/XCI title.");
    internal static string DataPath(string titleId, string name) => Path.Combine(AppDataManager.GamesDirPath, titleId, name);
    internal static JsonObject Updates(string id) => File.Exists(DataPath(id, "updates.json")) ? JsonNode.Parse(File.ReadAllText(DataPath(id, "updates.json")))!.AsObject() : new() { ["selected"] = "", ["paths"] = new JsonArray() };
    internal static JsonArray Dlc(string id) => File.Exists(DataPath(id, "dlc.json")) ? JsonNode.Parse(File.ReadAllText(DataPath(id, "dlc.json")))!.AsArray() : new();
    internal static JsonObject State(string root, string program)
    {
        var metadata = Inspect(root, program);
        string id = metadata["titles"]!.AsArray().FirstOrDefault()?["titleId"]?.GetValue<string>();
        if (id == null) return new() { ["metadata"] = metadata, ["updates"] = new JsonArray(), ["dlc"] = new JsonArray() };
        var saved = Updates(id); var updates = new JsonArray();
        foreach (var value in saved["paths"]!.AsArray())
        {
            string path = value!.GetValue<string>();
            updates.Add((JsonNode)new JsonObject { ["path"] = path, ["name"] = Path.GetFileName(path), ["selected"] = saved["selected"]!.GetValue<string>() == path, ["available"] = File.Exists(path) });
        }
        var dlc = new JsonArray();
        foreach (var container in Dlc(id)) foreach (var item in container!["dlc_nca_list"]!.AsArray())
            dlc.Add((JsonNode)new JsonObject { ["container"] = container["path"]!.DeepClone(), ["path"] = item!["path"]!.DeepClone(), ["titleId"] = item["title_id"]!.GetValue<ulong>().ToString("x16"), ["enabled"] = item["is_enabled"]!.DeepClone() });
        return new() { ["metadata"] = metadata, ["updates"] = updates, ["dlc"] = dlc };
    }
    internal static JsonObject Add(string root, string program, string source, bool update)
    {
        string id = BaseId(root, program);
        OwnedFiles.RequireWithin(root, source);
        int found = Open(source, fs =>
        {
            int count = 0;
            if (update)
            {
                foreach (var (_, content) in fs.GetContentData(ContentMetaType.Patch, ServiceBootstrap.FileSystem, IntegrityCheckLevel.ErrorOnInvalid))
                {
                    if ((content.ApplicationId & ~0x1FFFUL).ToString("x16") != id) continue;
                    var patch = content.GetNcaByType(ServiceBootstrap.FileSystem.KeySet, ContentType.Program);
                    var control = content.GetNcaByType(ServiceBootstrap.FileSystem.KeySet, ContentType.Control);
                    if (patch == null || control == null) throw new InvalidDataException("The update is missing program or control content.");
                    _ = Control(control);
                    count++;
                }
                if (count > 0)
                {
                    var state = Updates(id);
                    if (!state["paths"]!.AsArray().Any(x => x!.GetValue<string>() == source)) state["paths"]!.AsArray().Add((JsonNode)JsonValue.Create(source));
                    state["selected"] = source;
                    NativeSettings.AtomicJson(DataPath(id, "updates.json"), state);
                }
            }
            else
            {
                var items = new JsonArray();
                foreach (var entry in fs.EnumerateEntries("/", "*.nca"))
                {
                    using UniqueRef<IFile> file = new();
                    fs.OpenFile(ref file.Ref, entry.FullPath.ToU8Span(), OpenMode.Read).ThrowIfFailure();
                    Nca nca = new(ServiceBootstrap.FileSystem.KeySet, file.Get.AsStorage());
                    if (nca.Header.ContentType != NcaContentType.PublicData || (nca.Header.TitleId & ~0x1FFFUL).ToString("x16") != id) continue;
                    items.Add((JsonNode)new JsonObject { ["path"] = entry.FullPath, ["title_id"] = nca.Header.TitleId, ["is_enabled"] = true }); count++;
                }
                if (count > 0)
                {
                    var state = Dlc(id);
                    if (state.Any(x => x!["path"]!.GetValue<string>() == source)) throw new ArgumentException("This DLC container is already registered.");
                    state.Add((JsonNode)new JsonObject { ["path"] = source, ["dlc_nca_list"] = items });
                    NativeSettings.AtomicJson(DataPath(id, "dlc.json"), state);
                }
            }
            return count;
        });
        if (found == 0) throw new InvalidDataException(update ? "No update for this title was found in the selected container." : "No DLC for this title was found in the selected container.");
        return State(root, program);
    }
    internal static JsonObject Change(string root, string program, JsonObject request)
    {
        string id = BaseId(root, program), operation = request["operation"]!.GetValue<string>();
        if (operation.StartsWith("updates.", StringComparison.Ordinal))
        {
            var state = Updates(id); string path = request["path"]!.GetValue<string>();
            if (path != "" && !state["paths"]!.AsArray().Any(x => x!.GetValue<string>() == path)) throw new ArgumentException("Unknown update.");
            if (operation == "updates.remove") { var item = state["paths"]!.AsArray().FirstOrDefault(x => x!.GetValue<string>() == path); if (item != null) state["paths"]!.AsArray().Remove(item); if (state["selected"]!.GetValue<string>() == path) state["selected"] = ""; }
            else state["selected"] = path;
            NativeSettings.AtomicJson(DataPath(id, "updates.json"), state);
        }
        else
        {
            var state = Dlc(id); string container = request["container"]?.GetValue<string>();
            foreach (var entry in state.ToArray())
            {
                if (container != null && entry!["path"]!.GetValue<string>() != container) continue;
                if (operation == "dlc.remove") state.Remove(entry);
                else foreach (var item in entry!["dlc_nca_list"]!.AsArray())
                    if (request["titleId"] == null || item!["title_id"]!.GetValue<ulong>().ToString("x16") == request["titleId"]!.GetValue<string>()) item!["is_enabled"] = request["enabled"]!.GetValue<bool>();
            }
            NativeSettings.AtomicJson(DataPath(id, "dlc.json"), state);
        }
        return State(root, program);
    }
}

internal static class SettingsLanguage
{
    internal static int IntLanguage(this NativeSettings settings) => (int)settings.Choice<Ryujinx.HLE.HOS.SystemState.SystemLanguage>("SystemLanguage");
}
