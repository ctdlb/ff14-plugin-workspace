using System;
using System.Numerics;
using Dalamud.Game.Command;
using Dalamud.IoC;
using Dalamud.Plugin;
using Dalamud.Plugin.Services;
using FFXIVClientStructs.FFXIV.Component.GUI;
using KamiToolKit;
using KamiToolKit.BaseTypes;
using KamiToolKit.Enums;
using KamiToolKit.Nodes;

namespace KamiDemo;

/// <summary>演示插件入口。</summary>
public sealed class Plugin : IDalamudPlugin
{
    /// <summary>插件名。</summary>
    public string Name => "Kami 原生界面演示";

    /// <summary>命令管理器。</summary>
    [PluginService]
    public static ICommandManager CommandManager { get; private set; } = null!;

    /// <summary>插件接口。</summary>
    [PluginService]
    public static IDalamudPluginInterface PluginInterface { get; private set; } = null!;

    private readonly DemoWindow window;
    private readonly TtsPreviewWindow ttsPreview;

    /// <summary>初始化插件。</summary>
    public Plugin()
    {
        // 必须最先调用，KamiToolKit 需要它接管原生节点的生命周期
        KamiToolKitLibrary.InitializeAsync(PluginInterface, "KamiDemo").GetAwaiter().GetResult();

        this.window = new DemoWindow
        {
            InternalName = "KamiDemoWindow",
            Title = "原生界面演示",
            Size = new Vector2(520.0f, 360.0f),
        };

        this.ttsPreview = new TtsPreviewWindow
        {
            InternalName = "KamiTtsPreview",
            Title = "TextToTalk 设置（原生界面预览）",
            Size = new Vector2(720.0f, 430.0f),
        };

        CommandManager.AddHandler("/kamidemo", new CommandInfo(this.OnCommand)
        {
            HelpMessage = "打开或关闭原生界面演示窗口",
        });

        CommandManager.AddHandler("/kamitts", new CommandInfo((_, _) => this.ttsPreview.Toggle())
        {
            HelpMessage = "打开或关闭 TextToTalk 设置的原生界面预览",
        });

        PluginInterface.UiBuilder.OpenMainUi += this.window.Toggle;
        PluginInterface.UiBuilder.OpenConfigUi += this.window.Toggle;

        this.window.Open();
        this.ttsPreview.Open();
    }

    /// <summary>卸载插件。</summary>
    public void Dispose()
    {
        PluginInterface.UiBuilder.OpenMainUi -= this.window.Toggle;
        PluginInterface.UiBuilder.OpenConfigUi -= this.window.Toggle;
        CommandManager.RemoveHandler("/kamidemo");
        CommandManager.RemoveHandler("/kamitts");

        // 关掉窗口并把节点从游戏里摘掉
        this.window.Dispose();
        this.ttsPreview.Dispose();

        // 兜底清理可能漏掉的节点
        KamiToolKitLibrary.Dispose();
    }

    private void OnCommand(string command, string arguments) => this.window.Toggle();
}

/// <summary>原生窗口本体。</summary>
public class DemoWindow : NativeAddon
{
    private TextNode? counterText;
    private int clicks;

    /// <inheritdoc/>
    protected override unsafe void OnSetup(AtkUnitBase* addon, Span<AtkValue> atkValues)
    {
        var start = this.ContentStartPosition;
        var width = this.ContentSize.X;

        var title = new TextNode
        {
            Position = start,
            Size = new Vector2(width, 28.0f),
            FontType = FontType.Jupiter,
            FontSize = 20,
            TextFlags = TextFlags.AutoAdjustNodeSize,
            String = "这个窗口是游戏原生界面",
        };
        title.AttachNode(this);

        var description = new TextNode
        {
            Position = start + new Vector2(0.0f, 34.0f),
            Size = new Vector2(width, 56.0f),
            FontSize = 14,
            LineSpacing = 18,
            TextFlags = TextFlags.WordWrap | TextFlags.MultiLine,
            String = "按钮、勾选框、文字全部来自游戏自己的界面组件，所以字体、渐变底色和点击音效都和原生窗口完全一致。",
        };
        description.AttachNode(this);

        this.counterText = new TextNode
        {
            Position = start + new Vector2(0.0f, 100.0f),
            Size = new Vector2(width, 24.0f),
            FontSize = 14,
            TextFlags = TextFlags.AutoAdjustNodeSize,
            String = "按钮点击：0 次",
        };
        this.counterText.AttachNode(this);

        var button = new TextButtonNode
        {
            Position = start + new Vector2(0.0f, 132.0f),
            Size = new Vector2(220.0f, 32.0f),
            String = "点我 +1",
            OnClick = () =>
            {
                this.clicks++;
                if (this.counterText is not null)
                {
                    this.counterText.String = $"按钮点击：{this.clicks} 次";
                }
            },
        };
        button.AttachNode(this);

        var checkbox = new CheckboxNode
        {
            Position = start + new Vector2(0.0f, 178.0f),
            Size = new Vector2(300.0f, 24.0f),
            IsChecked = true,
            String = "这是一个原生勾选框",
        };
        checkbox.AttachNode(this);

        var closeButton = new TextButtonNode
        {
            Position = start + new Vector2(0.0f, 222.0f),
            Size = new Vector2(220.0f, 32.0f),
            String = "关闭窗口",
            OnClick = this.Close,
        };
        closeButton.AttachNode(this);
    }
}
