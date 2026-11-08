"""Inventory the pinned desktop surface; generate the native settings contract.

Only entries in WIRED are editable. Merely discovering a desktop property does
not make it an implemented iOS feature. Run after prepare_core.py.
"""
import json
import re
from pathlib import Path

IOS = Path(__file__).resolve().parents[1]
SRC = IOS / "build/upstream/src"
CONFIG = SRC / "Ryujinx/Systems/Configuration/ConfigurationFileFormat.cs"

# key: (section, default, optional min/max). Values match the actual core adapter.
WIRED = {
    "BackendThreading": ("Graphics", "Auto"),
    "ResScale": ("Graphics", 1, -1, 4),
    "ResScaleCustom": ("Graphics", 1.0, 0.25, 8),
    "MaxAnisotropy": ("Graphics", -1.0, -1, 16),
    "AspectRatio": ("Graphics", "Fixed16x9"),
    "AntiAliasing": ("Graphics", "None"),
    "ScalingFilter": ("Graphics", "Bilinear"),
    "ScalingFilterLevel": ("Graphics", 80, 0, 100),
    "VSyncMode": ("Graphics", "Switch"),
    "EnableCustomVSyncInterval": ("Graphics", False),
    "CustomVSyncInterval": ("Graphics", 120, 1, 1000),
    "EnableShaderCache": ("Graphics", True),
    "EnableTextureRecompression": ("Graphics", False),
    "EnableMacroHLE": ("Graphics", True),
    "EnableColorSpacePassthrough": ("Graphics", False),
    "GraphicsShadersDumpPath": ("Graphics", ""),
    "SystemLanguage": ("System", "AmericanEnglish"),
    "SystemRegion": ("System", "USA"),
    "SystemTimeZone": ("System", "UTC"),
    "SystemTimeOffset": ("System", 0, -3153600000, 3153600000),
    "MatchSystemTime": ("System", True),
    "DockedMode": ("System", False),
    "DramSize": ("System", "MemoryConfiguration4GiB"),
    "EnablePtc": ("CPU", True),
    "EnableLowPowerPtc": ("CPU", False),
    "TickScalar": ("CPU", 100, 1, 1000),
    "GCLowLatency": ("CPU", False),
    "EnableInternetAccess": ("Network", False),
    "MultiplayerMode": ("Network", "Disabled"),
    "MultiplayerLanInterfaceId": ("Network", "0"),
    "MultiplayerDisableP2p": ("Network", False),
    "MultiplayerLdnPassphrase": ("Network", ""),
    "LdnServer": ("Network", ""),
    "EnableFsIntegrityChecks": ("System", True),
    "FsGlobalAccessLogMode": ("Logging", 0, 0, 3),
    "IgnoreMissingServices": ("Debug", False),
    "EnableGdbStub": ("Debug", False),
    "GdbStubPort": ("Debug", 55555, 1024, 65535),
    "DebuggerSuspendOnStart": ("Debug", False),
    "AudioVolume": ("Audio", 1.0, 0, 1),
    "EnableKeyboard": ("Input", False),
    "EnableMouse": ("Input", False),
    "EnableFileLog": ("Logging", True),
    "LoggingEnableDebug": ("Logging", False),
    "LoggingEnableStub": ("Logging", False),
    "LoggingEnableInfo": ("Logging", True),
    "LoggingEnableWarn": ("Logging", True),
    "LoggingEnableError": ("Logging", True),
    "LoggingEnableTrace": ("Logging", False),
    "LoggingEnableGuest": ("Logging", True),
    "LoggingEnableFsAccessLog": ("Logging", False),
    "LoggingEnableNetLog": ("Logging", False),
    "LoggingGraphicsDebugLevel": ("Logging", "None"),
}

PLATFORM = {
    "MemoryManagerMode": "Software page tables are required by this non-jailbroken iOS JIT port.",
    "UseHypervisor": "Hypervisor execution is unavailable to a sideloaded iOS application.",
    "GraphicsBackend": "Vulkan through bundled MoltenVK/Metal; desktop OpenGL is unavailable on iOS.",
    "PreferredGpu": "iOS selects the device's integrated Apple GPU.",
    "EnableHardwareAcceleration": "SwiftUI/UIKit always use the system compositor.",
    "LoggingEnableAvalonia": "The native iOS frontend does not contain Avalonia.",
    "RememberWindowState": "UIKit manages iPhone/iPad window placement.",
    "WindowStartup": "UIKit manages iPhone/iPad window placement.",
    "ShowTitleBar": "Native navigation and the in-game HUD replace desktop window chrome.",
    "EnableDiscordIntegration": "Desktop Discord RPC is unavailable in the iOS application sandbox.",
    "CheckUpdatesOnStart": "IPA updates must be installed through the user's sideloading application.",
    "UpdateCheckerType": "IPA updates must be installed through the user's sideloading application.",
    "Version": "Native settings use a separately versioned schema.",
    "EnableVsync": "Legacy migrated property; VSyncMode is the current control.",
}


def enum_choices(type_name):
    for path in SRC.rglob(type_name + ".cs"):
        source = path.read_text(encoding="utf-8-sig")
        match = re.search(r"enum\s+" + type_name + r"\b[^\{]*\{([^}]+)\}", source)
        if match:
            body = re.sub(r"//[^\n]*|/\*.*?\*/|\[[^]]*\]", "", match[1], flags=re.S)
            return [m[0] for item in body.split(",") if (m := re.findall(r"^\s*(\w+)", item)) and m[0] not in ("Min", "Max")]
    return []


def main():
    source = CONFIG.read_text(encoding="utf-8-sig")
    settings, schema = [], []
    pattern = r"(?:///[^\n]*\n\s*)*public\s+([\w<>\[\], ]+?)\s+(\w+)\s*\{\s*get;\s*set;\s*\}"
    for match in re.finditer(pattern, source):
        typ, key = match[1], match[2]
        description = re.sub(r"\s+", " ", re.sub(r"<[^>]*>|///", "", match[0].split("public")[0])).strip()
        entry = dict(key=key, type=typ, description=description, source=str(CONFIG.relative_to(IOS / "build/upstream")).replace("\\", "/"))
        entry["status"] = "runtime-wired" if key in WIRED else "platform" if key in PLATFORM else "pending"
        if key in PLATFORM:
            entry["note"] = PLATFORM[key]
        settings.append(entry)
        if key not in WIRED:
            continue
        section, default, *bounds = WIRED[key]
        field = dict(key=key, title=re.sub(r"(?<=[a-z0-9])(?=[A-Z])", " ", key), section=section, description=description, default=default,
                     kind="bool" if typ == "bool" else "number" if typ in ("float", "long", "int", "ushort") else "string", integer=typ in ("long", "int", "ushort"))
        choices = enum_choices(typ)
        if choices:
            field.update(kind="enum", choices=choices)
        if bounds:
            field.update(minimum=bounds[0], maximum=bounds[1])
        schema.append(field)
    commands = []
    ui = SRC / "Ryujinx/UI"
    for path in sorted(ui.rglob("*.axaml")):
        text = path.read_text(encoding="utf-8-sig")
        for command in sorted(set(re.findall(r'Command="\{Binding\s+([\w.]+)', text) + re.findall(r'(?:Click|Tapped)="([\w]+)"', text))):
            commands.append(dict(command=command, source=str(path.relative_to(SRC)).replace("\\", "/"), status="pending"))
    lock = json.loads((IOS / "upstream.lock.json").read_text(encoding="utf-8-sig"))
    manifest = dict(upstream=lock, configurationVersion=73, settings=settings, commands=commands)
    (IOS / "parity-inventory.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    (IOS / "Runtime/settings-schema.json").write_text(json.dumps(schema, indent=2) + "\n", encoding="utf-8")
    print(f"Audited {len(settings)} upstream properties and {len(commands)} UI command occurrences; {len(schema)} runtime controls.")


if __name__ == "__main__":
    main()
