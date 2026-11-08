using Ryujinx.Common.Configuration;
using Ryujinx.HLE.HOS;
using System;
using System.IO;
using System.Linq;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace Ryu.iOS.Runtime;

internal static class ModManager
{
    private static string Folder(string id) => Path.Combine(ModLoader.GetModsBasePath(), "contents", id);
    private static JsonObject Metadata(string id) => File.Exists(TitleContent.DataPath(id, "mods.json")) ? JsonNode.Parse(File.ReadAllText(TitleContent.DataPath(id, "mods.json")))!.AsObject() : new() { ["mods"] = new JsonArray() };
    internal static JsonObject State(string id)
    {
        string folder = Folder(id); Directory.CreateDirectory(folder);
        var metadata = Metadata(id); var mods = new JsonArray();
        foreach (string path in Directory.GetDirectories(folder).Where(p => Path.GetFileName(p) != "cheats"))
        {
            var saved = metadata["mods"]!.AsArray().FirstOrDefault(x => x!["path"]!.GetValue<string>() == path);
            mods.Add((JsonNode)new JsonObject { ["name"] = Path.GetFileName(path), ["path"] = path, ["enabled"] = saved?["enabled"]?.GetValue<bool>() ?? true });
        }
        var cache = new ModLoader.ModCache();
        ModLoader.QueryContentsDir(cache, new DirectoryInfo(Path.Combine(ModLoader.GetModsBasePath(), "contents")), Convert.ToUInt64(id, 16), []);
        string enabledPath = Path.Combine(folder, "cheats", "enabled.txt");
        string[] enabled = File.Exists(enabledPath) ? File.ReadAllLines(enabledPath) : [];
        var cheats = new JsonArray();
        foreach (var cheat in cache.Cheats)
        {
            string build = Path.GetFileNameWithoutExtension(cheat.Path.Name).ToUpperInvariant(), key = build + "-" + cheat.Name;
            cheats.Add((JsonNode)new JsonObject { ["name"] = cheat.Name, ["buildId"] = build, ["key"] = key, ["enabled"] = enabled.Contains(key), ["path"] = cheat.Path.FullName });
        }
        return new() { ["mods"] = mods, ["cheats"] = cheats, ["titleId"] = id };
    }
    internal static JsonObject Manage(string root, string program, JsonObject request)
    {
        string id = TitleContent.BaseId(root, program), folder = Folder(id), operation = request["operation"]!.GetValue<string>();
        Directory.CreateDirectory(folder);
        if (operation == "mods.import")
        {
            string source = OwnedFiles.RequireWithin(root, request["source"]!.GetValue<string>());
            if (!Path.GetExtension(source).Equals(".zip", StringComparison.OrdinalIgnoreCase)) throw new ArgumentException("Select a mod ZIP.");
            string name = Path.GetFileNameWithoutExtension(request["originalName"]!.GetValue<string>());
            if (name.Length is < 1 or > 80 || name.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0 || name is "." or ".." or "cheats" || name.Contains('/') || name.Contains('\\')) throw new ArgumentException("Use a simple mod ZIP filename.");
            string destination = OwnedFiles.RequireWithin(folder, Path.Combine(folder, name));
            if (Directory.Exists(destination)) throw new ArgumentException("A mod with that name is already installed. Remove it first to replace it.");
            string staging = Path.Combine(root, "mod-staging-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(staging);
            try
            {
                OwnedFiles.ExtractZip(source, staging);
                string content = staging;
                string atmosphere = Path.Combine(staging, "contents", id);
                if (Directory.Exists(atmosphere)) content = atmosphere;
                while (!HasContent(content) && Directory.GetFiles(content).Length == 0 && Directory.GetDirectories(content).Length == 1) content = Directory.GetDirectories(content)[0];
                if (!HasContent(content)) throw new InvalidDataException("The ZIP must contain romfs, exefs, romfs.bin, exefs.nsp or cheats for this title.");
                Directory.Move(content, destination);
            }
            finally { if (Directory.Exists(staging)) OwnedFiles.Delete(root, staging); }
        }
        else if (operation == "mods.enable" || operation == "mods.remove")
        {
            string path = request["path"]!.GetValue<string>();
            if (!State(id)["mods"]!.AsArray().Any(x => x!["path"]!.GetValue<string>() == path)) throw new ArgumentException("Unknown mod.");
            var metadata = Metadata(id); var mods = metadata["mods"]!.AsArray();
            var item = mods.FirstOrDefault(x => x!["path"]!.GetValue<string>() == path);
            if (item != null) mods.Remove(item);
            if (operation == "mods.remove") OwnedFiles.Delete(folder, path);
            else mods.Add((JsonNode)new JsonObject { ["name"] = Path.GetFileName(path), ["path"] = path, ["enabled"] = request["enabled"]!.GetValue<bool>() });
            NativeSettings.AtomicJson(TitleContent.DataPath(id, "mods.json"), metadata);
        }
        else if (operation == "cheats.import")
        {
            string source = OwnedFiles.RequireWithin(root, request["source"]!.GetValue<string>()), original = request["originalName"]!.GetValue<string>();
            if (!Regex.IsMatch(original, "^[0-9a-fA-F]{16}\\.txt$")) throw new ArgumentException("Keep the cheat file's 16-digit build ID filename (for example 0123456789ABCDEF.txt).");
            if (new FileInfo(source).Length > 4 * 1024 * 1024) throw new ArgumentException("Cheat files must be smaller than 4 MiB.");
            string text = File.ReadAllText(source);
            foreach (string line in text.Split('\n').Select(x => x.Trim()).Where(x => x.Length > 0))
                if (!Regex.IsMatch(line, "^(\\[[^\\]\\r\\n]+\\]|[0-9a-fA-F]{8}( +[0-9a-fA-F]{8})*)$")) throw new InvalidDataException("The cheat file contains a malformed instruction or section.");
            string destination = Path.Combine(folder, "cheats", original.ToUpperInvariant().Replace(".TXT", ".txt", StringComparison.Ordinal));
            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            string temporary = destination + ".tmp"; File.WriteAllText(temporary, text); File.Move(temporary, destination, true);
        }
        else if (operation == "cheats.enable")
        {
            string key = request["key"]!.GetValue<string>();
            if (!State(id)["cheats"]!.AsArray().Any(x => x!["key"]!.GetValue<string>() == key)) throw new ArgumentException("Unknown cheat.");
            string path = Path.Combine(folder, "cheats", "enabled.txt");
            var enabled = (File.Exists(path) ? File.ReadAllLines(path) : []).ToHashSet(StringComparer.Ordinal);
            if (request["enabled"]!.GetValue<bool>()) enabled.Add(key); else enabled.Remove(key);
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllLines(path + ".tmp", enabled); File.Move(path + ".tmp", path, true);
        }
        else if (operation != "mods.list") throw new ArgumentException("Unknown mod operation.");
        return State(id);
    }
    private static bool HasContent(string folder) => Directory.Exists(Path.Combine(folder, "romfs")) || Directory.Exists(Path.Combine(folder, "exefs")) || Directory.Exists(Path.Combine(folder, "cheats")) || File.Exists(Path.Combine(folder, "romfs.bin")) || File.Exists(Path.Combine(folder, "exefs.nsp"));
}
