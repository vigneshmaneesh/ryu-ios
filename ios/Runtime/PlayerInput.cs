using Ryujinx.HLE;
using Ryujinx.HLE.HOS.Services.Hid;
using Ryujinx.HLE.HOS.Services.Hid.Types.SharedMemory.TouchScreen;
using System;

namespace Ryu.iOS.Runtime;

// UI threads publish snapshots; only the emulation worker writes HID memory.
internal static class PlayerInput
{
    private static readonly object Gate = new();
    private static GamepadInput _pad;
    private static bool _touch, _paused;
    private static uint _x, _y;
    internal static bool Paused { get { lock (Gate) return _paused; } set { lock (Gate) _paused = value; } }
    internal static void Set(ulong buttons, int lx, int ly, int rx, int ry)
    {
        lock (Gate) _pad = new GamepadInput { PlayerId = PlayerIndex.Player1, Buttons = (ControllerKeys)buttons,
            LStick = new() { Dx = Math.Clamp(lx, -32767, 32767), Dy = Math.Clamp(ly, -32767, 32767) },
            RStick = new() { Dx = Math.Clamp(rx, -32767, 32767), Dy = Math.Clamp(ry, -32767, 32767) } };
    }
    internal static void Touch(bool down, int x, int y)
    {
        lock (Gate) { _touch = down; _x = (uint)Math.Clamp(x, 0, 1279); _y = (uint)Math.Clamp(y, 0, 719); }
    }
    internal static void Reset() { lock (Gate) { _pad = default; _touch = false; _paused = false; } }
    internal sealed class Writer
    {
        private readonly GamepadInput[] _states = new GamepadInput[1];
        private bool _wasTouching;
        private uint _lastX, _lastY;
        internal Writer(Switch device) => device.Hid.Npads.Configure(new ControllerConfig { Player = PlayerIndex.Player1, Type = ControllerType.ProController });
        internal void Update(Switch device)
        {
            bool touching; uint x, y;
            lock (Gate) { _states[0] = _pad; touching = _touch; x = _x; y = _y; }
            _states[0].Buttons |= device.Hid.UpdateStickButtons(_states[0].LStick, _states[0].RStick);
            device.Hid.Npads.Update(_states);
            if (touching || _wasTouching)
            {
                device.Hid.Touchscreen.Update(new TouchPoint { X = touching ? x : _lastX, Y = touching ? y : _lastY,
                    DiameterX = 10, DiameterY = 10, Attribute = !touching ? TouchAttribute.End : _wasTouching ? TouchAttribute.None : TouchAttribute.Start });
            }
            else device.Hid.Touchscreen.Update();
            _wasTouching = touching; _lastX = x; _lastY = y;
        }
    }
}
