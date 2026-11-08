using Ryujinx.HLE;
using Ryujinx.HLE.HOS.Applets;
using Ryujinx.HLE.HOS.Services.Account.Acc;
using Ryujinx.HLE.HOS.Services.Am.AppletOE.ApplicationProxyService.ApplicationProxy.Types;
using Ryujinx.HLE.UI;
using Ryujinx.Common.Configuration.Hid;
using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading;
using System.Threading.Tasks;
using System.Linq;

namespace Ryu.iOS.Runtime;

internal sealed record AppletChoice(string Id, string Name);
internal sealed record AppletPrompt(int Id, int Kind, string Title, string Message, string Initial, int Maximum, int Minimum, AppletChoice[] Choices);
[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
[JsonSerializable(typeof(AppletPrompt))]
internal partial class AppletJson : JsonSerializerContext;

internal sealed unsafe class NativeHostUi : IHostUIHandler
{
    private readonly NativeSettings _settings;
    internal NativeHostUi(NativeSettings settings = null) => _settings = settings;
    public bool UsesNativeKeyboard => true;
    private sealed class Request(AppletPrompt prompt)
    {
        internal readonly AppletPrompt Prompt = prompt;
        internal readonly ManualResetEventSlim Done = new();
        internal bool Accepted;
        internal string Text;
    }
    private static readonly object Gate = new();
    private static readonly Queue<Request> Requests = new();
    private static int _nextId;
    private static bool _active;
    private static delegate* unmanaged<int> _cancelled;
    internal static bool HasPendingPrompt { get { lock (Gate) return Requests.Count > 0; } }
    internal static void Begin(delegate* unmanaged<int> cancelled) { lock (Gate) { _cancelled = cancelled; _active = true; } }
    internal static void End()
    {
        lock (Gate) { _active = false; _cancelled = null; while (Requests.TryDequeue(out var r)) r.Done.Set(); }
    }
    internal static string Poll() { lock (Gate) return Requests.TryPeek(out var r) ? JsonSerializer.Serialize(r.Prompt, AppletJson.Default.AppletPrompt) : ""; }
    internal static void Answer(int id, bool accepted, string text)
    {
        lock (Gate) if (Requests.TryPeek(out var r) && r.Prompt.Id == id) {
            Requests.Dequeue(); r.Accepted = accepted; r.Text = text; r.Done.Set();
        }
    }
    private static bool Ask(int kind, string title, string message, string initial, int maximum, out string text, int minimum = 0, AppletChoice[] choices = null)
    {
        Request r;
        lock (Gate) {
            text = initial ?? "";
            if (!_active) return false;
            static string Bound(string s, int length) => s.Length > length ? s[..length] : s;
            int limit = Math.Clamp(maximum <= 0 ? 1024 : maximum, 1, 1024);
            r = new Request(new AppletPrompt(++_nextId, kind, Bound(title ?? "Game", 128), Bound(message ?? "", 2048), Bound(text, limit), limit, Math.Clamp(minimum, 0, limit), choices ?? []));
            Requests.Enqueue(r);
        }
        while (!r.Done.Wait(100)) {
            lock (Gate) if (!_active || (_cancelled != null && _cancelled() != 0)) { End(); break; }
        }
        text = r.Text ?? initial ?? "";
        // Answer/End remove requests while holding Gate before the waiter disposes.
        lock (Gate) r.Done.Dispose();
        return r.Accepted;
    }
    public bool DisplayInputDialog(SoftwareKeyboardUIArgs args, out string text) => Ask(1, args.HeaderText, (args.SubtitleText ?? "") + "\n" + (args.GuideText ?? ""), args.InitialText, args.StringLengthMax, out text, args.StringLengthMin);
    public bool DisplayMessageDialog(string title, string message) => Ask(0, title, message, "", 0, out _);
    public bool DisplayMessageDialog(ControllerAppletUIArgs args)
    {
        if (_settings?.Bool("IgnoreApplet") == true) return false;
        var options = new List<AppletChoice>();
        foreach (var type in new[] { Ryujinx.HLE.HOS.Services.Hid.ControllerType.ProController, Ryujinx.HLE.HOS.Services.Hid.ControllerType.JoyconPair, Ryujinx.HLE.HOS.Services.Hid.ControllerType.JoyconLeft, Ryujinx.HLE.HOS.Services.Hid.ControllerType.JoyconRight, Ryujinx.HLE.HOS.Services.Hid.ControllerType.Handheld })
        {
            if ((args.SupportedStyles & type) == 0 || (args.IsDocked && type == Ryujinx.HLE.HOS.Services.Hid.ControllerType.Handheld)) continue;
            for (int count = Math.Clamp(args.PlayerCountMin, 1, 8); count <= Math.Clamp(args.PlayerCountMax, 1, 8); count++)
            {
                if (type == Ryujinx.HLE.HOS.Services.Hid.ControllerType.Handheld && count != 1) continue;
                options.Add(new AppletChoice($"{(int)type}:{count}", $"{count} × {type}"));
            }
        }
        return Ask(3, "Controller setup", "Choose a supported controller arrangement. Connected devices and touch controls use these player slots.", "", 64, out _, choices: options.ToArray()) && PlayerInput.WaitUntilApplied(1000);
    }
    public bool DisplayCabinetDialog(out string text) => Ask(1, "Amiibo name", "Enter a name", "", 40, out text);
    public void DisplayCabinetMessageDialog() => DisplayMessageDialog("Amiibo", "Open Amiibo in the in-game menu while the game is searching for a tag.");
    public bool DisplayErrorAppletDialog(string title, string message, string[] buttons, (uint Module, uint Description)? code = null)
    {
        bool accepted = Ask(4, title, message, "", 16, out string answer, choices: buttons.Select((b, i) => new AppletChoice(i.ToString(), b)).ToArray());
        return accepted && int.TryParse(answer, out int selected) && selected != buttons.Length - 1;
    }
    public void ExecuteProgram(Switch device, ProgramSpecifyKind kind, ulong value) {
        device.Configuration.UserChannelPersistence.ExecuteProgram(kind, value);
        HorizonJournal.Write($"Title requested program transition: {kind} {value}");
        if (device.Processes.ActiveApplication is { } process) device.RequestApplicationExit(process.ProcessId);
    }
    public UserProfile ShowPlayerSelectDialog()
    {
        var accounts = ServiceBootstrap.Accounts;
        if (_settings?.Bool("SkipUserProfiles") == true) return accounts.LastOpenedUser;
        var users = accounts.GetAllUsers().ToArray();
        return Ask(2, "Choose a profile", "Select the user for this game.", accounts.LastOpenedUser.UserId.ToString(), 32, out string selected, choices: users.Select(u => new AppletChoice(u.UserId.ToString(), u.Name)).ToArray()) ? users.FirstOrDefault(u => u.UserId.ToString() == selected) : null;
    }
    public IHostUITheme HostUITheme { get; } = new Theme();
    public void TakeScreenshot() => SessionCommands.Enqueue(0, 0, "");
    public IDynamicTextInputHandler CreateDynamicTextInputHandler() => new TextInput();
    private sealed class Theme : IHostUITheme {
        public string FontFamily => "Arial";
        public ThemeColor DefaultBackgroundColor => new(1, 0.08f, 0.08f, 0.1f);
        public ThemeColor DefaultForegroundColor => new(1, 1, 1, 1);
        public ThemeColor DefaultBorderColor => new(1, 0.3f, 0.3f, 0.3f);
        public ThemeColor SelectionBackgroundColor => new(1, 0, 0.65f, 0.7f);
        public ThemeColor SelectionForegroundColor => new(1, 1, 1, 1);
    }
    private sealed class TextInput : IDynamicTextInputHandler {
        public event DynamicTextChangedHandler TextChangedEvent;
        public event KeyPressedHandler KeyPressedEvent;
        public event KeyReleasedHandler KeyReleasedEvent;
        private bool _enabled, _disposed;
        private string _text = "";
        private int _busy;
        public bool TextProcessingEnabled {
            get => Volatile.Read(ref _enabled);
            set {
                Volatile.Write(ref _enabled, value);
                if (value && !_disposed && Interlocked.CompareExchange(ref _busy, 1, 0) == 0) Task.Run(() => {
                    try {
                        if (Ask(1, "Game keyboard", "Enter text", _text, 1024, out var result) && !_disposed && TextProcessingEnabled) {
                            _text = result; TextChangedEvent?.Invoke(result, result.Length, result.Length, false);
                            KeyPressedEvent?.Invoke(Key.Enter); KeyReleasedEvent?.Invoke(Key.Enter);
                        }
                    } finally { Volatile.Write(ref _busy, 0); }
                });
            }
        }
        public void SetText(string text, int cursor) => _text = text ?? "";
        public void SetText(string text, int begin, int end) => SetText(text, begin);
        public void Dispose() { _disposed = true; _enabled = false; }
    }
}
