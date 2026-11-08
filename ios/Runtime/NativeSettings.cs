using ARMeilleure;
using LibHac.Tools.FsSystem;
using Ryujinx.Common.Configuration;
using Ryujinx.Common.Configuration.Multiplayer;
using Ryujinx.Common.Logging;
using Ryujinx.Common.Logging.Targets;
using Ryujinx.Graphics.GAL;
using Ryujinx.Graphics.Gpu;
using Ryujinx.HLE;
using Ryujinx.HLE.HOS.SystemState;
using Ryujinx.Audio.Integration;
using System;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Ryu.iOS.Runtime;

// Deliberately uses a JSON DOM and explicit assignments: no reflection setters,
// dynamic code generation or object-typed serialization in the NativeAOT core.
internal sealed class NativeSettings
{
    internal static readonly JsonArray Schema = LoadSchema();
    private readonly JsonObject _values;
    private NativeSettings(JsonObject values) => _values = values;
    internal bool Bool(string key) => _values[key]!.GetValue<bool>();
    internal string Text(string key) => _values[key]!.GetValue<string>();
    internal double Number(string key) => _values[key]!.GetValue<double>();
    internal int Int(string key) => checked((int)Number(key));
    internal T Choice<T>(string key) where T : struct, Enum => Enum.Parse<T>(Text(key));
    internal static string Scope(string program) => string.IsNullOrEmpty(program) ? "global" : Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(Path.GetFullPath(program))));
    internal static string PathFor(string root, string program) => Path.Combine(root, "settings", Scope(program) + ".json");
    private static JsonArray LoadSchema()
    {
        using var stream = typeof(NativeSettings).Assembly.GetManifestResourceStream("Ryu.SettingsSchema") ?? throw new InvalidOperationException("Missing settings contract.");
        return JsonNode.Parse(stream)!.AsArray();
    }
    private static JsonObject Defaults()
    {
        var result = new JsonObject();
        foreach (var field in Schema) result[field!["key"]!.GetValue<string>()] = field["default"]!.DeepClone();
        return result;
    }
    private static JsonObject Read(string path)
    {
        if (!File.Exists(path)) return new();
        if (new FileInfo(path).Length > 1024 * 1024) throw new InvalidDataException("Settings exceed 1 MiB.");
        var saved = JsonNode.Parse(File.ReadAllText(path))!.AsObject();
        if (saved["version"]?.GetValue<int>() != 1) throw new InvalidDataException("Unsupported native settings version.");
        return saved["values"]!.AsObject();
    }
    internal static NativeSettings Load(string root, string program = null)
    {
        var result = Defaults();
        Merge(result, Read(PathFor(root, null)));
        if (!string.IsNullOrEmpty(program)) Merge(result, Read(PathFor(root, program)));
        return new(result);
    }
    private static void Merge(JsonObject destination, JsonObject changes)
    {
        foreach (var pair in changes)
        {
            var field = Schema.FirstOrDefault(f => f!["key"]!.GetValue<string>() == pair.Key);
            if (field == null) throw new ArgumentException("Unknown or unavailable setting: " + pair.Key);
            var value = pair.Value ?? throw new ArgumentException("A setting cannot be null.");
            string kind = field["kind"]!.GetValue<string>();
            try
            {
                if (kind == "bool") _ = value.GetValue<bool>();
                else if (kind == "number")
                {
                    double number = value.GetValue<double>();
                    if (!double.IsFinite(number) || number < field["minimum"]!.GetValue<double>() || number > field["maximum"]!.GetValue<double>() ||
                        (field["integer"]!.GetValue<bool>() && number != Math.Truncate(number)) || (pair.Key == "ResScale" && number == 0)) throw new ArgumentOutOfRangeException(pair.Key);
                }
                else
                {
                    string text = value.GetValue<string>();
                    if (text.Length > 1024) throw new ArgumentException("Setting text is too long.");
                    if (kind == "enum" && !field["choices"]!.AsArray().Any(x => x!.GetValue<string>() == text)) throw new ArgumentException("Unknown option.");
                    if (pair.Key == "GraphicsShadersDumpPath" && text != "" && (Path.IsPathRooted(text) || text.Split('/', '\\').Any(p => p is ".." or "."))) throw new ArgumentException("Use a relative folder inside shader dumps.");
                    if (pair.Key == "SystemTimeZone")
                    {
                        // Firmware supplies additional Nintendo locations. Reject path traversal;
                        // the time service validates availability when it mounts that firmware.
                        if (string.IsNullOrWhiteSpace(text) || text.Contains("..", StringComparison.Ordinal) || text.StartsWith('/') || text.Contains('\\')) throw new ArgumentException("Invalid time zone.");
                    }
                }
            }
            catch (InvalidOperationException) { throw new ArgumentException("Wrong setting type: " + pair.Key); }
            destination[pair.Key] = value.DeepClone();
        }
    }
    internal static JsonObject Get(string root, string program)
    {
        return new() { ["scope"] = Scope(program), ["schema"] = Schema.DeepClone(), ["values"] = Load(root, program)._values.DeepClone(), ["overrides"] = Read(PathFor(root, program)).DeepClone() };
    }
    internal static JsonObject Save(string root, string program, JsonObject changes, bool reset)
    {
        string path = PathFor(root, program);
        if (reset) { if (File.Exists(path)) File.Delete(path); }
        else
        {
            var values = Read(path);
            Merge(values, changes);
            AtomicJson(path, new JsonObject { ["version"] = 1, ["values"] = values });
        }
        return Get(root, program);
    }
    internal static void AtomicJson(string path, JsonNode json)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        string staging = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            using (var stream = new FileStream(staging, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            { using var writer = new Utf8JsonWriter(stream); json.WriteTo(writer); writer.Flush(); stream.Flush(true); }
            File.Move(staging, path, true);
        }
        finally { if (File.Exists(staging)) File.Delete(staging); }
    }
    internal void ApplyGraphics(string root)
    {
        GraphicsConfig.ResScale = (float)(Int("ResScale") == -1 ? Number("ResScaleCustom") : Number("ResScale"));
        GraphicsConfig.MaxAnisotropy = (float)Number("MaxAnisotropy");
        GraphicsConfig.EnableShaderCache = Bool("EnableShaderCache");
        GraphicsConfig.EnableTextureRecompression = Bool("EnableTextureRecompression");
        GraphicsConfig.EnableMacroHLE = Bool("EnableMacroHLE");
        GraphicsConfig.EnableColorSpacePassthrough = Bool("EnableColorSpacePassthrough");
        GraphicsConfig.ShadersDumpPath = Text("GraphicsShadersDumpPath") is { Length: > 0 } dump ? Path.Combine(root, "shader-dumps", dump) : null;
        if (GraphicsConfig.ShadersDumpPath != null) Directory.CreateDirectory(GraphicsConfig.ShadersDumpPath);
        Optimizations.LowPower = Bool("EnableLowPowerPtc");
        System.Runtime.GCSettings.LatencyMode = Bool("GCLowLatency") ? System.Runtime.GCLatencyMode.SustainedLowLatency : System.Runtime.GCLatencyMode.Interactive;
        (string key, LogLevel level)[] levels = [("Debug", LogLevel.Debug), ("Stub", LogLevel.Stub), ("Info", LogLevel.Info), ("Warn", LogLevel.Warning), ("Error", LogLevel.Error), ("Trace", LogLevel.Trace), ("Guest", LogLevel.Guest), ("FsAccessLog", LogLevel.AccessLog), ("NetLog", LogLevel.NetLog)];
        foreach (var (key, level) in levels) Logger.SetEnable(level, Bool("LoggingEnable" + key));
    }
    internal void ApplyWindow(IWindow window)
    {
        window.SetAntiAliasing(Choice<AntiAliasing>("AntiAliasing"));
        window.SetScalingFilter(Choice<ScalingFilter>("ScalingFilter"));
        window.SetScalingFilterLevel(Int("ScalingFilterLevel"));
        window.SetColorSpacePassthrough(Bool("EnableColorSpacePassthrough"));
    }
    internal HleConfiguration Configure(IRenderer renderer, IHardwareDeviceDriver audio) => new(
        Choice<MemoryConfiguration>("DramSize"), Choice<SystemLanguage>("SystemLanguage"), Choice<RegionCode>("SystemRegion"),
        Choice<VSyncMode>("VSyncMode") == VSyncMode.Custom && !Bool("EnableCustomVSyncInterval") ? VSyncMode.Switch : Choice<VSyncMode>("VSyncMode"),
        Bool("DockedMode"), Bool("EnablePtc"), (long)Number("TickScalar"), Bool("EnableInternetAccess"),
        Bool("EnableFsIntegrityChecks") ? IntegrityCheckLevel.ErrorOnInvalid : IntegrityCheckLevel.None, Int("FsGlobalAccessLogMode"),
        Bool("MatchSystemTime") ? 0 : (long)Number("SystemTimeOffset"), Text("SystemTimeZone"), MemoryManagerMode.SoftwarePageTable,
        Bool("IgnoreMissingServices"), Choice<AspectRatio>("AspectRatio"), (float)Number("AudioVolume"), false,
        Text("MultiplayerLanInterfaceId"), Choice<MultiplayerMode>("MultiplayerMode"), Bool("MultiplayerDisableP2p"),
        Text("MultiplayerLdnPassphrase"), string.IsNullOrEmpty(Text("LdnServer")) ? Ryujinx.Common.SharedConstants.DefaultLanPlayHost : Text("LdnServer"), Bool("EnableGdbStub"), (ushort)Int("GdbStubPort"), Bool("DebuggerSuspendOnStart"), Int("CustomVSyncInterval"));
    internal IDisposable StartLog(string root) => new SessionLog(root, Bool("EnableFileLog"));
    private sealed class SessionLog : IDisposable
    {
        private readonly bool _enabled;
        internal SessionLog(string root, bool enabled)
        {
            _enabled = enabled;
            if (enabled)
            {
                string directory = Path.Combine(root, "Logs"); Directory.CreateDirectory(directory);
                foreach (var old in new DirectoryInfo(directory).GetFiles("Ryu-*.log").OrderByDescending(x => x.LastWriteTimeUtc).Skip(2)) old.Delete();
                // NativeAOT shared libraries have no managed entry assembly.
                // Upstream PrepareLogFile queries that assembly for its version.
                string path = Path.Combine(directory, $"Ryu-{DateTime.UtcNow:yyyyMMdd-HHmmss}-{Guid.NewGuid():N}.log");
                Logger.AddTarget(new AsyncLogTargetWrapper(new FileLogTarget("ios-session", new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.Read)), 1000));
            }
        }
        public void Dispose() { if (_enabled) { Logger.Flush(); Logger.RemoveTarget("ios-session"); } }
    }
}
