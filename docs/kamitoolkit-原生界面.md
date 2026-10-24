# KamiToolKit：用游戏原生界面写卫月插件

记录 2026-10 做 Sonar CN / TextToTalkCN 时验证过的东西。目标是以后想给插件换原生界面时，直接照这份文档开工，不用重新摸索。

## 它是什么

KamiToolKit 是「游戏自己的界面组件」的 C# 封装。用它画出来的窗口，字体、渐变、按钮音效、下拉展开动画都和游戏原生窗口一致，而不是 ImGui 那种「浮在游戏上面的工具窗口」。

| 项目 | 值 |
|---|---|
| NuGet 包名 | `KamiToolKit` |
| 验证过的版本 | `2.2.65` |
| 上游仓库 | `https://github.com/MidoriKami/KamiToolKit` |
| 国服二次开发分支 | `https://github.com/Dalamud-DailyRoutines/KamiToolKit`（多了同步版 `Initialize`，控件名也不同，别混用） |
| 官方示例 | `https://github.com/MidoriKami/KamiToolKitDemo` |
| 包内目标框架 | `net10.0-windows7.0` |

## 开工前必须改的两处

### 1. 目标框架

包只提供 `net10.0-windows7.0`。项目写 `net10.0` 会直接还原失败：

```
error NU1202: 包 KamiToolKit 2.2.65 与 net10.0 不兼容
```

```xml
<TargetFramework>net10.0-windows7.0</TargetFramework>
```

### 2. 引用包

```xml
<PackageReference Include="KamiToolKit" Version="2.2.65" />
```

不需要额外引用 FFXIVClientStructs 或 Lumina——Dalamud SDK 已经给了。

## 最小可用骨架

```csharp
using System;
using System.Numerics;
using FFXIVClientStructs.FFXIV.Component.GUI;
using KamiToolKit;
using KamiToolKit.BaseTypes;
using KamiToolKit.Nodes;

public class MyWindow : NativeAddon
{
    protected override unsafe void OnSetup(AtkUnitBase* addon, Span<AtkValue> atkValues)
    {
        var text = new TextNode
        {
            Position = this.ContentStartPosition,
            Size = new Vector2(400.0f, 24.0f),
            FontSize = 14,                       // uint！
            String = "你好，原生界面",
        };
        text.AttachNode(this);

        var button = new TextButtonNode
        {
            Position = this.ContentStartPosition + new Vector2(0.0f, 40.0f),
            Size = new Vector2(180.0f, 30.0f),
            String = "点我",
            OnClick = () => { },
        };
        button.AttachNode(this);
    }
}
```

初始化与销毁（插件构造 / 卸载时各一次）：

```csharp
// 2.2.65 只有异步版本，没有同步 Initialize
KamiToolKitLibrary.InitializeAsync(pluginInterface, "MyPlugin").GetAwaiter().GetResult();

// 卸载
myWindow.Dispose();
KamiToolKitLibrary.Dispose();
```

窗口本体：

```csharp
var window = new MyWindow
{
    InternalName = "MyPluginMain",   // 窗口内部名，全局唯一
    Title = "我的插件设置",
    Size = new Vector2(720.0f, 460.0f),
};
window.Toggle();   // 或 Open() / Close()
```

## 控件清单（2.2.65 实测签名）

| 控件 | 关键属性 | 备注 |
|---|---|---|
| `TextNode` | `String`、`FontSize`(**uint**)、`LineSpacing`、`TextFlags`、`AlignmentType` | 中文正常显示 |
| `TextButtonNode` | `String`、`OnClick`(**Action**)、`IsChecked` | |
| `CheckboxNode` | `String`、`IsChecked`、`OnClick`(**Action\<bool\>**，参数是新状态) | 回调参数是新勾选状态，不用自己取反 |
| `SliderNode` | `Min`/`Max`/`Step`/`Value`（全是 **int**）、`OnValueChanged`(**Action\<int\>**) | 小数要自己换算成整数百分比 |
| `StringDropDownNode` | `Options`(List\<string\>)、`SelectedOption`(**string**)、`MaxListOptions`、`OnOptionSelected`(Action\<string\>) | **没有** `SelectedIndex` |
| `TextInputNode` | `String`、`MaxCharacters`、`PlaceholderString` | 中文输入法支持未验证 |
| `TabBarNode` | `AddTab(string, Action)`、`SelectTab`、`EnableTab`/`DisableTab` | 切页不会自动隐藏内容，要自己切 `IsVisible` |
| `ScrollingAreaNode<T>` | 容器 | 长列表用 |
| `VerticalListNode` | `FitContents` | 自动排版 |
| `TreeListCategoryNode` | `AddCategoryNode`/`AddHeader`/`AddNode` | 折叠分组 |

所有节点通用的：`Position`、`Size`、`IsVisible`、`IsEnabled`、`Alpha`、`Color`，挂载用 `node.AttachNode(this)` 或 `node.AttachNode(parentNode)`。

**注意**：`String` 类型其实是 `Lumina.Text.ReadOnly.ReadOnlySeString`，赋值时写字符串字面量会自动转换。

## 窗口尺寸：三个参数决定背景

背景（窗口框）大小不是直接设的，而是三个参数组合出来。下面这组数值来自已删除的 `PriceInsight-CN`，保留作参考：

| 参数 | 作用 | 实测值 |
|---|---|---|
| `WindowWidth` | 窗口宽度 | 400 |
| `ContentTopOffset` | 顶部预留（标题栏 + 页签占位） | 65 |
| `BottomPadding` | 内容排完后底部多留的高度 | 39 |

计算方式：

```
窗口高度 = ContentTopOffset + 内容实际高度 + BottomPadding
         = 65 + 316 + 39 = 420
```

内容高度 316 不是参数，而是按行累加算出来的（行高 28、行间距 6、分组间距 14、分组标题 32、勾选框 34、下拉框 60）。加控件才会变，所以做一个 `FitSize` 计算属性把它统一起来：

```csharp
public static Vector2 FitSize => new(WindowWidth, ContentTopOffset + content + BottomPadding);
// 使用：Size = NativeConfigWindow.FitSize;   // 只在构造时生效
```

| 坑 | 说明 |
|---|---|
| `Size` 只在**构造时**生效 | 在 `OnSetup` 里调 `SetWindowSize`，`OnShow` 里补救，都会被初始化流程覆盖 |
| `ContentSize` 只读 | 由库算（`Size` − 标题栏 − `2 × ContentPadding`），改不了内容起点 |
| 高度给太大排版会崩 | 试过 1000：标题被页签盖住、行与行重叠（控件坐标是固定像素，引擎对超大窗口会另做缩放） |
| 位置与留白要分开调 | 内容整体下移改 `ContentTopOffset`；只想底部多留白改 `BottomPadding`。二者都计入窗口总高 |

**调试办法**：写一个临时命令（如 `/piui width|offset|pad <值>`）改静态字段后重建窗口，比每次改代码编译快得多；发布前记得删掉。

这组参数曾在 `PriceInsight-CN` 与 `MarketQuery` 上各实测一次（两个插件均已删除，结论保留）：`ContentTopOffset` 只影响窗口高度、不移动内容起点（内容由库自己锚定），所以「内容下移」和「底部留白」必须分开调。

## 踩过的坑

| 现象 | 原因 | 解法 |
|---|---|---|
| `CS0115: 没有找到适合的方法来重写` | `OnSetup` 参数签名不对 | 必须是 `OnSetup(AtkUnitBase* addon, Span<AtkValue> atkValues)` |
| `CS0117: InitializeAsync 不存在` / `Initialize 不存在` | 上游只有异步版 | `InitializeAsync(...).GetAwaiter().GetResult()` |
| `CS0266: 无法将 int 隐式转换为 uint` | `FontSize` 是 uint | 写 `14u` 或声明 `uint fontSize` |
| `CS0117: SelectedIndex 未定义` | 下拉框没有这个属性 | 用 `SelectedOption = "当前值"` |
| `CS1593: 委托 Action<bool> 未采用 0 个参数` | 勾选框回调带参 | `OnClick = checkedState => { ... }` |
| `CS0266: 无法将 float 转换为 int` | 滑块 `Value` 是 int | 值域改成整数百分比 |
| 窗口一闪而过 / 节点不显示 | 没初始化库 | 插件构造里先 `KamiToolKitLibrary.InitializeAsync` |

## 查 API 的办法

包里的 XML 文档不全（下拉框、滑块的成员都没有注释）。要么读上游源码，要么用反射打一份签名出来：

```
docs/examples/kamitoolkit/reflect/     ← 现成的反射小工程
```

思路：把 `AssemblyLoadContext.Default.Resolving` 指到 Dalamud dev 目录和插件目录，再 `Assembly.LoadFrom("KamiToolKit.dll")` 遍历 `GetProperties` / `GetMethods`。直接加载会报缺 `Lumina`、`FFXIVClientStructs`，必须挂解析器。

## 示例工程

```
docs/examples/kamitoolkit/
├── demo/            ← 最小演示插件（一个窗口、按钮、勾选框）
├── tts-preview/     ← 五页签设置窗口样张（页签 + 下拉 + 滑块 + 输入框）
└── reflect/         ← 反射打印 KamiToolKit 类型的控制台小工程
```

示例都只含源码，编译时补自己的 `Dalamud.NET.Sdk` 引用即可。

## 什么时候别用它

- **要嵌入 ImGui 内容**：原生窗口和 ImGui 是两套绘制系统，塞不进去，只能并排放或者做跳转
- **改动风险高、旧界面已经能用**：TextToTalkCN 试过一次，原生外壳做出来了，但玩家语音/NPC 语音是动态表格，加上中文输入法未验证，最终放弃、保留 ImGui
- **只想要一个设置页**：ImGui 的 `WindowSystem` 更省事，跨版本也更稳
- **要往游戏「已有的」addon 里插节点**（如 `ItemDetail`、`ContextMenu`）：`NativeAddon` 是**新建自己的窗口**，`AttachNode` 只能挂在自己这套自建窗口上，插不进别人的 addon。这类需求得直接操作 `AtkResNode` 的兄弟链，见 `插件开发坑.md` 第 4 节「插节点的标准写法」
