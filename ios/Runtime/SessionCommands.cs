using Ryujinx.Common.Configuration;
using Ryujinx.Graphics.GAL;
using Ryujinx.Graphics.Gpu;
using Ryujinx.HLE;
using Ryujinx.HLE.HOS.Services.Nfc.AmiiboDecryption;
using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace Ryu.iOS.Runtime;

internal static class SessionCommands
{
    private static readonly object Gate = new();
    private static readonly Queue<(int Command, double Value, string Text)> Pending = new();
    private static bool _active, _amiibo;
    private static string _screenshot = "", _error = "", _title = "";
    private static float _volume;
    private static int _vsync;
    internal static void Begin() { lock (Gate) { Pending.Clear(); _active = true; _screenshot = _error = _title = ""; } }
    internal static void End() { lock (Gate) { _active = false; Pending.Clear(); } }
    // Called by UI/hotkeys; device and renderer access remains on the GPU worker.
    internal static int Enqueue(int command, double value, string text)
    {
        if (command is < 0 or > 6 || !double.IsFinite(value) || (text?.Length ?? 0) > 2048) return -1;
        lock (Gate) { if (!_active || Pending.Count >= 32) return -2; Pending.Enqueue((command, value, text ?? "")); return 0; }
    }
    internal static string Poll()
    {
        lock (Gate) return new JsonObject { ["active"] = _active, ["screenshot"] = _screenshot, ["error"] = _error, ["amiiboSearching"] = _amiibo, ["titleId"] = _title, ["volume"] = _volume, ["vsync"] = _vsync }.ToJsonString();
    }
    internal static void Capture(string root, ScreenCaptureImageInfo info)
    {
        try
        {
            string folder = Path.Combine(root, "Screenshots"); Directory.CreateDirectory(folder);
            string path = Path.Combine(folder, $"Ryu-{DateTime.UtcNow:yyyyMMdd-HHmmss}-{Guid.NewGuid():N}.png");
            PngCapture.Write(path, info);
            lock (Gate) { _screenshot = path; _error = ""; }
        }
        catch (Exception error) { lock (Gate) _error = "Screenshot: " + error.Message; }
    }
    internal static void Update(Switch device, IRenderer renderer, string root)
    {
        while (true)
        {
            (int Command, double Value, string Text) request;
            lock (Gate) { if (!Pending.TryDequeue(out request)) break; }
            try
            {
                switch (request.Command)
                {
                    case 0: device.Gpu.Renderer.Screenshot(); break;
                    case 1: device.SetVolume((float)Math.Clamp(request.Value, 0, 1)); break;
                    case 2:
                        device.VSyncMode = (VSyncMode)Math.Clamp((int)request.Value, 0, 2); device.UpdateVSyncInterval();
                        device.Gpu.Renderer.BackgroundContextAction(() => renderer.Window.ChangeVSyncMode(device.VSyncMode)); break;
                    case 3: device.System.ChangeDockedModeState(request.Value != 0); break;
                    case 4: GraphicsConfig.ResScale = (float)Math.Clamp(request.Value, 0.25, 8); break;
                    case 5:
                        if (!Regex.IsMatch(request.Text, "^[0-9a-fA-F]{16}$")) throw new ArgumentException("An amiibo ID must contain 16 hexadecimal digits.");
                        if (!device.System.SearchingForAmiibo(out int id)) throw new InvalidOperationException("The game is not currently searching for an amiibo.");
                        device.System.ScanAmiibo(id, request.Text.ToLowerInvariant(), request.Value != 0); break;
                    case 6:
                        string path = OwnedFiles.RequireWithin(root, request.Text);
                        if (!AmiiboBinReader.HasAmiiboKeyFile) throw new InvalidOperationException("Import your key_retail.bin in System files before scanning an amiibo dump.");
                        if (new FileInfo(path).Length is not (532 or 540)) throw new InvalidDataException("Use a 532- or 540-byte amiibo dump.");
                        if (!device.System.SearchingForAmiibo(out _)) throw new InvalidOperationException("The game is not currently searching for an amiibo.");
                        device.System.ScanAmiiboFromBin(path); break;
                }
                lock (Gate) _error = "";
            }
            catch (Exception error) { lock (Gate) _error = error.Message; }
        }
        lock (Gate) { _amiibo = device.System.SearchingForAmiibo(out _); _volume = device.GetVolume(); _vsync = (int)device.VSyncMode; _title = device.Processes.ActiveApplication?.ProgramIdText ?? ""; }
    }
}
