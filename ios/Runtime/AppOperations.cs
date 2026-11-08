using System;
using System.IO;
using System.Text.Json.Nodes;

namespace Ryu.iOS.Runtime;

// Idle-only management operations. The same core/native busy lease protects
// settings, profiles and title content from mutation during a running game.
internal static class AppOperations
{
    internal static JsonObject Execute(string root, JsonObject request)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(root);
        if (!Path.IsPathFullyQualified(root)) throw new ArgumentException("An absolute app data folder is required.");
        root = Path.GetFullPath(root);
        if (root == Path.GetPathRoot(root)) throw new ArgumentException("An app data folder is required.");
        Directory.CreateDirectory(root);
        string operation = request["operation"]?.GetValue<string>() ?? throw new ArgumentException("Missing operation.");
        string program = request["program"]?.GetValue<string>();
        return operation switch
        {
            "settings.get" => NativeSettings.Get(root, program),
            "settings.save" => NativeSettings.Save(root, program, request["changes"]!.AsObject(), false),
            "settings.reset" => NativeSettings.Save(root, program, new(), true),
            "title.inspect" => TitleContent.Inspect(root, program),
            "title.content" => TitleContent.State(root, program),
            "updates.add" => TitleContent.Add(root, program, request["source"]!.GetValue<string>(), true),
            "dlc.add" => TitleContent.Add(root, program, request["source"]!.GetValue<string>(), false),
            "updates.select" or "updates.remove" or "dlc.enable" or "dlc.remove" => TitleContent.Change(root, program, request),
            "profiles.list" or "profiles.add" or "profiles.rename" or "profiles.select" or "profiles.image" or "profiles.delete" => ProfileManager.Manage(root, request),
            "mods.list" or "mods.import" or "mods.enable" or "mods.remove" or "cheats.import" or "cheats.enable" => ModManager.Manage(root, program, request),
            "saves.list" or "saves.export" or "saves.restore" or "saves.delete" => SaveManager.Manage(root, program, request),
            _ => throw new ArgumentException("Unknown app operation: " + operation),
        };
    }
}
