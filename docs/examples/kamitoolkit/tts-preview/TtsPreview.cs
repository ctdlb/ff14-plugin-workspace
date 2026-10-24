using System.Collections.Generic;
using System.Numerics;
using FFXIVClientStructs.FFXIV.Component.GUI;
using KamiToolKit.BaseTypes;
using KamiToolKit.Enums;
using KamiToolKit.Nodes;

namespace KamiDemo;

/// <summary>用原生组件复刻 TextToTalk 设置窗口的样子，只看观感。</summary>
public class TtsPreviewWindow : NativeAddon
{
    private readonly List<NodeBase> tabSynthesis = [];
    private readonly List<NodeBase> tabPlayer = [];
    private readonly List<NodeBase> tabNpc = [];
    private readonly List<NodeBase> tabChannel = [];
    private readonly List<NodeBase> tabFilter = [];

    /// <inheritdoc/>
    protected override unsafe void OnSetup(AtkUnitBase* addon, System.Span<AtkValue> atkValues)
    {
        var start = this.ContentStartPosition;
        var width = this.ContentSize.X;

        var tabBar = new TabBarNode
        {
            Position = start,
            Size = new Vector2(width, 26.0f),
        };
        tabBar.AttachNode(this);

        var contentTop = start + new Vector2(0.0f, 36.0f);

        this.BuildSynthesisTab(contentTop, width);
        this.BuildPlayerTab(contentTop, width);
        this.BuildNpcTab(contentTop, width);
        this.BuildChannelTab(contentTop, width);
        this.BuildFilterTab(contentTop, width);

        tabBar.AddTab("语音合成设置", () => this.ShowTab(this.tabSynthesis));
        tabBar.AddTab("玩家语音", () => this.ShowTab(this.tabPlayer));
        tabBar.AddTab("NPC 语音", () => this.ShowTab(this.tabNpc));
        tabBar.AddTab("频道设置", () => this.ShowTab(this.tabChannel));
        tabBar.AddTab("触发器与排除", () => this.ShowTab(this.tabFilter));

        this.ShowTab(this.tabSynthesis);
    }

    private void ShowTab(List<NodeBase> tab)
    {
        foreach (var list in new[] { this.tabSynthesis, this.tabPlayer, this.tabNpc, this.tabChannel, this.tabFilter })
        {
            foreach (var node in list)
            {
                node.IsVisible = ReferenceEquals(list, tab);
            }
        }
    }

    private TextNode AddLabel(List<NodeBase> tab, Vector2 position, string text, uint fontSize = 14)
    {
        var node = new TextNode
        {
            Position = position,
            Size = new Vector2(680.0f, 22.0f),
            FontSize = fontSize,
            TextFlags = TextFlags.AutoAdjustNodeSize,
            String = text,
        };
        node.AttachNode(this);
        tab.Add(node);
        return node;
    }

    private void BuildSynthesisTab(Vector2 top, float width)
    {
        this.AddLabel(this.tabSynthesis, top, "语音后端（朗读用的引擎）");

        var backend = new StringDropDownNode
        {
            Position = top + new Vector2(0.0f, 26.0f),
            Size = new Vector2(300.0f, 28.0f),
            MaxListOptions = 8,
            Options =
            [
                "Edge TTS（免费在线）",
                "Azure（微软云）",
                "Google Cloud（谷歌云）",
                "Amazon Polly（亚马逊）",
                "Kokoro（本地离线）",
                "OpenAI",
                "ElevenLabs",
            ],
        };
        backend.AttachNode(this);
        this.tabSynthesis.Add(backend);

        this.AddLabel(this.tabSynthesis, top + new Vector2(340.0f, 0.0f), "音量");

        var volume = new SliderNode
        {
            Position = top + new Vector2(340.0f, 26.0f),
            Size = new Vector2(300.0f, 28.0f),
            Min = 0,
            Max = 100,
            Step = 1,
            Value = 100,
        };
        volume.AttachNode(this);
        this.tabSynthesis.Add(volume);

        var enabled = new CheckboxNode
        {
            Position = top + new Vector2(0.0f, 70.0f),
            Size = new Vector2(300.0f, 24.0f),
            IsChecked = true,
            String = "启用朗读",
        };
        enabled.AttachNode(this);
        this.tabSynthesis.Add(enabled);

        var preview = new TextButtonNode
        {
            Position = top + new Vector2(0.0f, 106.0f),
            Size = new Vector2(180.0f, 30.0f),
            String = "试听一句",
            OnClick = () => { },
        };
        preview.AttachNode(this);
        this.tabSynthesis.Add(preview);
    }

    private void BuildPlayerTab(Vector2 top, float width)
    {
        this.AddLabel(this.tabPlayer, top, "玩家语音（按角色名匹配）");

        var picker = new StringDropDownNode
        {
            Position = top + new Vector2(0.0f, 26.0f),
            Size = new Vector2(320.0f, 28.0f),
            MaxListOptions = 6,
            Options = ["默认语音", "晓晓（女声）", "云希（男声）", "Google 日语女声"],
        };
        picker.AttachNode(this);
        this.tabPlayer.Add(picker);

        var add = new TextButtonNode
        {
            Position = top + new Vector2(340.0f, 26.0f),
            Size = new Vector2(140.0f, 28.0f),
            String = "添加玩家",
            OnClick = () => { },
        };
        add.AttachNode(this);
        this.tabPlayer.Add(add);

        this.AddLabel(this.tabPlayer, top + new Vector2(0.0f, 70.0f), "这个页签原来是一张表格，原生版本准备用列表（ListItem）实现。");
    }

    private void BuildNpcTab(Vector2 top, float width)
    {
        this.AddLabel(this.tabNpc, top, "NPC 语音（按 NPC 名字匹配）");

        var picker = new StringDropDownNode
        {
            Position = top + new Vector2(0.0f, 26.0f),
            Size = new Vector2(320.0f, 28.0f),
            MaxListOptions = 6,
            Options = ["默认语音", "晓晓（女声）", "云希（男声）"],
        };
        picker.AttachNode(this);
        this.tabNpc.Add(picker);

        this.AddLabel(this.tabNpc, top + new Vector2(0.0f, 70.0f), "和玩家页同样的结构，只是一张更长的表。");
    }

    private void BuildChannelTab(Vector2 top, float width)
    {
        this.AddLabel(this.tabChannel, top, "要朗读哪些频道（勾选）");

        var options = new[] { "说话", "喊话", "小队", "团队", "小队频道", "系统信息", "NPC 对话" };
        for (var index = 0; index < options.Length; index++)
        {
            var checkbox = new CheckboxNode
            {
                Position = top + new Vector2((index % 3) * 220.0f, 30.0f + (index / 3) * 32.0f),
                Size = new Vector2(200.0f, 24.0f),
                IsChecked = index is 0 or 2 or 5 or 6,
                String = options[index],
            };
            checkbox.AttachNode(this);
            this.tabChannel.Add(checkbox);
        }
    }

    private void BuildFilterTab(Vector2 top, float width)
    {
        this.AddLabel(this.tabFilter, top, "触发器（正则，命中就朗读）");
        var trigger = new TextInputNode
        {
            Position = top + new Vector2(0.0f, 26.0f),
            Size = new Vector2(420.0f, 26.0f),
            String = "托托诺",
            MaxCharacters = 100,
        };
        trigger.AttachNode(this);
        this.tabFilter.Add(trigger);

        this.AddLabel(this.tabFilter, top + new Vector2(0.0f, 66.0f), "排除项（正则，命中就跳过）");
        var exclude = new TextInputNode
        {
            Position = top + new Vector2(0.0f, 92.0f),
            Size = new Vector2(420.0f, 26.0f),
            String = "^\\[.*\\]",
            MaxCharacters = 100,
        };
        exclude.AttachNode(this);
        this.tabFilter.Add(exclude);

        this.AddLabel(this.tabFilter, top + new Vector2(0.0f, 132.0f), "文本输入是原生控件，中文输入法和复制粘贴能不能用还需要实测。");
    }
}
