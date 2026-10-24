using System;
using System.Collections.Generic;
using Dalamud.Game.Addon.Lifecycle;
using Dalamud.Game.Addon.Lifecycle.AddonArgTypes;
using Dalamud.Game.Command;
using Dalamud.Plugin;
using Dalamud.Plugin.Services;
using FFXIVClientStructs.FFXIV.Component.GUI;

namespace HoverProbe;

/// <summary>
/// 只读探针：不修改任何节点，只在几个时间点记录 ItemDetail 的窗口高 / 九宫格高 / 提示行位置。
/// 用来判断「谁在什么时候把布局改回去了」。
/// </summary>
public sealed class HoverProbePlugin : IDalamudPlugin {
    public string Name => "HoverProbe";

    private const string Command = "/hoverprobe";

    private static readonly string[] AddonNames = ["ItemDetail"];

    private readonly IAddonLifecycle.AddonEventDelegate onPreRequestedUpdate;
    private readonly IAddonLifecycle.AddonEventDelegate onPostRequestedUpdate;
    private readonly IAddonLifecycle.AddonEventDelegate onPostUpdate;
    private readonly IAddonLifecycle.AddonEventDelegate onPreDraw;

    private bool logging;

    // 每帧采样（Framework.Update）：判断值是「写一次就不动」还是「每帧都被写一遍」
    private int tickWinH = -1;
    private int tickHintY = -1;
    private ulong tickHovered;
    private int tickSameFrames;
    private DateTime tickLastLog = DateTime.MinValue;

    public HoverProbePlugin(IDalamudPluginInterface pluginInterface) {
        pluginInterface.Create<Service>();

        onPreRequestedUpdate = (_, args) => { unsafe { Dump("PreRequestedUpdate", (AtkUnitBase*)args.Addon.Address); } };
        onPostRequestedUpdate = (_, args) => { unsafe { Dump("PostRequestedUpdate", (AtkUnitBase*)args.Addon.Address); } };
        onPostUpdate = (_, args) => { unsafe { Dump("PostUpdate", (AtkUnitBase*)args.Addon.Address); } };
        onPreDraw = (_, args) => { unsafe { Dump("PreDraw", (AtkUnitBase*)args.Addon.Address); } };

        Service.AddonLifecycle.RegisterListener(AddonEvent.PreRequestedUpdate, AddonNames, onPreRequestedUpdate);
        Service.AddonLifecycle.RegisterListener(AddonEvent.PostRequestedUpdate, AddonNames, onPostRequestedUpdate);
        Service.AddonLifecycle.RegisterListener(AddonEvent.PostUpdate, AddonNames, onPostUpdate);
        Service.AddonLifecycle.RegisterListener(AddonEvent.PreDraw, AddonNames, onPreDraw);

        Service.Framework.Update += OnFrameworkUpdate;

        Service.CommandManager.AddHandler(Command, new CommandInfo(OnCommand) {
            HelpMessage = "开/关布局探针日志。",
        });

        logging = true;
        Service.PluginLog.Warning("[PROBE] HoverProbe 已加载，默认开始记录（/hoverprobe 可开关）");
    }

    private unsafe void OnFrameworkUpdate(IFramework framework) {
        if (!logging)
            return;

        var addonPtr = Service.GameGui.GetAddonByName("ItemDetail", 1);
        if (addonPtr.IsNull) {
            tickWinH = -1;
            tickHintY = -1;
            return;
        }

        var addon = (AtkUnitBase*)addonPtr.Address;
        if (addon == null || !addon->IsVisible) {
            tickWinH = -1;
            tickHintY = -1;
            return;
        }

        var window = addon->WindowNode;
        if (window == null)
            return;

        var winH = (int)window->AtkResNode.Height;
        var hint = addon->GetNodeById(2);
        var hintY = hint == null ? -1 : (int)hint->Y;
        var hovered = Service.GameGui.HoveredItem;

        if (winH == tickWinH && hintY == tickHintY && hovered == tickHovered) {
            tickSameFrames++;
            if ((DateTime.UtcNow - tickLastLog).TotalSeconds >= 2) {
                Service.PluginLog.Warning($"[PROBE] Tick 不变 win={winH} hint={hintY} 连续={tickSameFrames} 帧");
                tickLastLog = DateTime.UtcNow;
            }
            return;
        }

        Service.PluginLog.Warning(
            $"[PROBE] Tick 变化 hovered={hovered} win={winH} hint={hintY} (上一帧 win={tickWinH} hint={tickHintY}) 持续了 {tickSameFrames} 帧");
        tickWinH = winH;
        tickHintY = hintY;
        tickHovered = hovered;
        tickSameFrames = 0;
        tickLastLog = DateTime.UtcNow;
    }

    private void OnCommand(string command, string args) {
        logging = !logging;
        Service.ChatGui.Print($"[HoverProbe] 日志已{(logging ? "开启" : "关闭")}");
    }

    private unsafe void Dump(string phase, AtkUnitBase* addon) {
        if (!logging || addon == null || !addon->IsVisible)
            return;

        var window = addon->WindowNode;
        var winH = window == null ? 0 : (int)window->AtkResNode.Height;
        var winW = window == null ? 0 : (int)window->AtkResNode.Width;

        var nineGridH = -1;
        if (window != null && window->Component != null) {
            var root = window->Component->UldManager.RootNode;
            for (var n = root; n != null; n = n->PrevSiblingNode) {
                if (n->Type == NodeType.NineGrid) {
                    nineGridH = (int)n->Height;
                    break;
                }
            }
        }

        var hint = addon->GetNodeById(2);
        var hintY = hint == null ? -1 : (int)hint->Y;
        var addonH = (int)addon->RootNode->Height;

        Service.PluginLog.Warning(
            $"[PROBE] {phase} hovered={Service.GameGui.HoveredItem} win={winW}x{winH} nineGridH={nineGridH} rootH={addonH} hintY={hintY}");
    }

    public void Dispose() {
        Service.Framework.Update -= OnFrameworkUpdate;
        Service.AddonLifecycle.UnregisterListener(AddonEvent.PreRequestedUpdate, AddonNames, onPreRequestedUpdate);
        Service.AddonLifecycle.UnregisterListener(AddonEvent.PostRequestedUpdate, AddonNames, onPostRequestedUpdate);
        Service.AddonLifecycle.UnregisterListener(AddonEvent.PostUpdate, AddonNames, onPostUpdate);
        Service.AddonLifecycle.UnregisterListener(AddonEvent.PreDraw, AddonNames, onPreDraw);
        Service.CommandManager.RemoveHandler(Command);
    }
}
