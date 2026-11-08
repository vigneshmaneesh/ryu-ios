using Ryujinx.HLE;
using Ryujinx.HLE.HOS.Services.Hid;
using Ryujinx.HLE.HOS.Services.Hid.Types.SharedMemory.TouchScreen;
using System;
using System.Collections.Generic;
using System.Numerics;

namespace Ryu.iOS.Runtime;

// UI threads publish snapshots; only the emulation worker writes HID memory.
internal static class PlayerInput
{
    private static readonly object Gate = new();
    private static readonly GamepadInput[] Pads = new GamepadInput[8];
    private static readonly bool[] Connected = [true, false, false, false, false, false, false, false];
    private static readonly ControllerType[] Types = [ControllerType.ProController, ControllerType.ProController, ControllerType.ProController, ControllerType.ProController, ControllerType.ProController, ControllerType.ProController, ControllerType.ProController, ControllerType.ProController];
    private static readonly SixAxisInput[] Motion = new SixAxisInput[8];
    private static readonly bool[] HasMotion = new bool[8];
    private static readonly (VibrationValue Left, VibrationValue Right)[] Rumble = new (VibrationValue, VibrationValue)[8];
    private static readonly bool[] Touches = new bool[16];
    private static readonly uint[] TouchX = new uint[16], TouchY = new uint[16];
    private static readonly ulong[] Keys = new ulong[4];
    private static int _modifiers, _mouseX, _mouseY, _scrollX, _scrollY, _revision;
    private static uint _mouseButtons;
    private static bool _mouseConnected, _paused;
    internal static bool Paused { get { lock (Gate) return _paused; } set { lock (Gate) _paused = value; } }
    internal static void Set(ulong buttons, int lx, int ly, int rx, int ry)
    {
        SetPlayer(0, true, ControllerType.ProController, buttons, lx, ly, rx, ry);
    }
    internal static void SetPlayer(int player, bool connected, ControllerType type, ulong buttons, int lx, int ly, int rx, int ry)
    {
        if ((uint)player >= 8 || type is not (ControllerType.ProController or ControllerType.Handheld or ControllerType.JoyconPair or ControllerType.JoyconLeft or ControllerType.JoyconRight) || (type == ControllerType.Handheld && player != 0)) return;
        lock (Gate)
        {
          if (Connected[player] != connected || Types[player] != type) _revision++;
          Connected[player] = connected; Types[player] = type;
          Pads[player] = new GamepadInput { PlayerId = type == ControllerType.Handheld ? PlayerIndex.Handheld : (PlayerIndex)player, Buttons = (ControllerKeys)buttons,
            LStick = new() { Dx = Math.Clamp(lx, -32767, 32767), Dy = Math.Clamp(ly, -32767, 32767) },
            RStick = new() { Dx = Math.Clamp(rx, -32767, 32767), Dy = Math.Clamp(ry, -32767, 32767) } };
        }
    }
    internal static void Touch(bool down, int x, int y) => TouchFinger(0, down, x, y);
    internal static void TouchFinger(int finger, bool down, int x, int y)
    {
        if ((uint)finger >= 16) return;
        lock (Gate) { Touches[finger] = down; TouchX[finger] = (uint)Math.Clamp(x, 0, 1279); TouchY[finger] = (uint)Math.Clamp(y, 0, 719); }
    }
    internal static void SetMotion(int player, ReadOnlySpan<float> values)
    {
        if ((uint)player >= 8 || values.Length != 18) return;
        foreach (float value in values) if (!float.IsFinite(value)) return;
        lock (Gate) { Motion[player] = new() { Accelerometer = new Vector3(values[0], values[1], values[2]), Gyroscope = new Vector3(values[3], values[4], values[5]), Rotation = new Vector3(values[6], values[7], values[8]), Orientation = values[9..].ToArray() }; HasMotion[player] = true; }
    }
    internal static void Keyboard(ulong a, ulong b, ulong c, ulong d, int modifiers) { lock (Gate) { Keys[0] = a; Keys[1] = b; Keys[2] = c; Keys[3] = d; _modifiers = modifiers; } }
    internal static void Mouse(int x, int y, uint buttons, int scrollX, int scrollY, bool connected) { lock (Gate) { _mouseX = Math.Clamp(x, 0, 1279); _mouseY = Math.Clamp(y, 0, 719); _mouseButtons = buttons; _scrollX += scrollX; _scrollY += scrollY; _mouseConnected = connected; } }
    internal static void ReadRumble(int player, Span<float> destination)
    {
        if ((uint)player >= 8 || destination.Length < 8) return;
        lock (Gate) { var (l, r) = Rumble[player]; destination[0] = l.AmplitudeLow; destination[1] = l.FrequencyLow; destination[2] = l.AmplitudeHigh; destination[3] = l.FrequencyHigh; destination[4] = r.AmplitudeLow; destination[5] = r.FrequencyLow; destination[6] = r.AmplitudeHigh; destination[7] = r.FrequencyHigh; }
    }
    internal static void Reset()
    {
        lock (Gate) { Array.Clear(Pads); Array.Clear(Connected); Connected[0] = true; Array.Fill(Types, ControllerType.ProController); Array.Clear(HasMotion); Array.Clear(Rumble); Array.Clear(Touches); Array.Clear(Keys); _paused = false; _modifiers = 0; _mouseButtons = 0; _mouseConnected = false; _scrollX = _scrollY = 0; _revision++; }
    }
    internal sealed class Writer
    {
        private readonly List<GamepadInput> _states = new(8);
        private readonly List<SixAxisInput> _motion = new(16);
        private readonly bool[] _wasTouching = new bool[16];
        private readonly TouchPoint[] _points = new TouchPoint[16];
        private readonly ulong[] _keys = new ulong[4];
        private readonly NativeSettings _settings;
        private int _configurationRevision = -1;
        internal Writer(Switch device, NativeSettings settings = null)
        {
            _settings = settings;
            device.Hid.Npads.Configure(new ControllerConfig { Player = PlayerIndex.Player1, Type = ControllerType.ProController });
            device.Hid.Keyboard.Active = settings?.Bool("EnableKeyboard") ?? false;
            device.Hid.Mouse.Active = settings?.Bool("EnableMouse") ?? false;
        }
        internal void Update(Switch device)
        {
            int touchCount = 0;
            lock (Gate)
            {
                if (_configurationRevision != _revision)
                {
                    var config = new List<ControllerConfig>();
                    for (int i = 0; i < 8; i++) if (Connected[i]) config.Add(new() { Player = (PlayerIndex)i, Type = Types[i] });
                    device.Hid.Npads.Configure(config.ToArray()); _configurationRevision = _revision;
                }
                _states.Clear(); _motion.Clear();
                for (int i = 0; i < 8; i++) if (Connected[i])
                {
                    var pad = Pads[i]; pad.PlayerId = Types[i] == ControllerType.Handheld ? PlayerIndex.Handheld : (PlayerIndex)i;
                    pad.Buttons |= device.Hid.UpdateStickButtons(pad.LStick, pad.RStick); _states.Add(pad);
                    if (HasMotion[i]) { var motion = Motion[i]; motion.PlayerId = pad.PlayerId; _motion.Add(motion); if (Types[i] == ControllerType.JoyconPair) _motion.Add(motion); }
                }
                for (int i = 0; i < 16; i++)
                {
                    if (Touches[i] || _wasTouching[i]) _points[touchCount++] = new() { FingerId = (uint)i, X = TouchX[i], Y = TouchY[i], DiameterX = 10, DiameterY = 10, Attribute = !Touches[i] ? TouchAttribute.End : _wasTouching[i] ? TouchAttribute.None : TouchAttribute.Start };
                    _wasTouching[i] = Touches[i];
                }
                Keys.CopyTo(_keys, 0); device.Hid.Keyboard.Update(new() { Keys = _keys, Modifier = _modifiers });
                device.Hid.Mouse.Update(_mouseX, _mouseY, _mouseButtons, _scrollX, _scrollY, _mouseConnected); _scrollX = _scrollY = 0;
            }
            device.Hid.Npads.Update(_states);
            device.Hid.Npads.UpdateSixAxis(_motion);
            device.Hid.Touchscreen.Update(_points.AsSpan(0, touchCount));
            foreach (var state in _states)
            {
                var queue = device.Hid.Npads.GetRumbleQueue(state.PlayerId);
                (VibrationValue, VibrationValue) last = default; bool any = false;
                while (queue.TryDequeue(out var value)) { last = value; any = true; }
                if (any) lock (Gate) Rumble[state.PlayerId == PlayerIndex.Handheld ? 0 : (int)state.PlayerId] = last;
            }
        }
    }
}
