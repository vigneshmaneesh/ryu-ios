using System;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text.Json.Nodes;

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
        return "PASS persistent global/per-game settings, inheritance and reset\nPASS invalid settings preserve the previous configuration\nPASS AOT settings contract serialization\nPASS ZIP traversal rejection\n" + Ryujinx.HLE.HOS.Tamper.AotCheatChecks.Run();
    }
}
