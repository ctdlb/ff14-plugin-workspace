# ocornut / Dear ImGui（Omar Cornut）调研笔记

调研时间 2026-10-25。上游源码用本机只读克隆 `E:\FF14Dev\KnowledgeBase\imgui`（`--depth 1`，HEAD `4be0b47e`，2026-10-16，`IMGUI_VERSION "1.93.1 WIP"`，`imgui.h:32-33`）；C# 侧对照**本机真实绑定** `Dalamud.Bindings.ImGui`（运行时 `%APPDATA%\XIVLauncherCN\addon\Hooks\dev\Dalamud.Bindings.ImGui.dll`，1,226,752 字节，2026-10-21 12:43；源码 `E:\FF14Dev\KnowledgeBase\Dalamud\imgui\Dalamud.Bindings.ImGui\`，HexaGen 生成 + `Custom/` 手写）。

只读调研：未编译、未改任何已有文件。标「推测」「未确认」的不许当结论。已有 [OtterGui.md](../OtterGui.md) 讲「封装库替你把哪些事做对了」，本篇只讲「上游要求你自己写对什么」，不重复。

**C# 侧前提**：本机用 `using Dalamud.Bindings.ImGui;`（**不是** `ImGuiNET`），向量类型是 `System.Numerics.Vector2/Vector4`；所有字符串参数接受 `ImU8String`（`string` 有隐式转换，`ImU8String.cs:170-182`），但**没有 C 的 printf 风格重载**——`Text` 只有 `Text(ImU8String)`（`Custom/ImGui.Text.cs:244`），所以 C++ 的 `Text("%d", n)` 一律改插值 `ImGui.Text($"x{n}")`。

## ① 一句话定位

对 C# 插件作者，上游 ImGui 只有三件事要记：

1. **每帧重跑**：UI 就是你这一帧执行到的语句序列，没有控件对象、没有事件回调——"if your code doesn't run the UI is gone"（`imgui.cpp:207`）。跨帧状态只能放你自己的字段/配置。
2. **身份是 ID，不是变量**：控件靠「ID 栈 + 标签」算出的 hash 认人（`imgui.cpp:9426-9436`）；ID 撞了就是两个控件共用一个状态，而本机绑定不会提示。
3. **成对性有三种，规则不一样**：`Push*/Pop*` 必须配对；`Begin/BeginChild` **无论返回什么都得 `End/EndChild`**（`imgui.h:442-446`、`:464-468`）；`BeginTable` 反过来，**只有返回 true 才 `EndTable`**（`imgui.h:918`）。

还有一条本机绑定专属：**本机绑定比上游旧**，没有 `ImGuiChildFlags`、`SeparatorText`、`SetItemTooltip/BeginItemTooltip`、`ImGuiStyle.FontSizeBase`（`Dalamud.Bindings.ImGui` 源码 grep 0 命中，DLL 二进制字符串同样 0 命中），`BeginChild` 仍是老签名 `(string, Vector2, bool border, flags)`（`Generated/Functions/Functions.000.cs:1714`）。抄网上 1.90+ 的 C# 示例会 CS0117 / CS1501。确切版本号**未确认**。

## ② 七个问题

### Q1 ID 机制：`##`、`###`、`PushID`、`GetID`

**机制**：交互控件（Button/Checkbox/InputText/表格行…）必须有唯一 ID，ID = hash(当前 ID 栈 + 标签)。C++ 侧实现：`ImGuiWindow::GetID`（`imgui.cpp:9426-9436`）——`ImGuiID seed = IDStack.back();` 再拿这个 seed 去 hash 标签。只读控件（`Text`/`Separator`）不需要 ID。

**冲突的后果**（`docs/FAQ.md:449-456`）：同窗口两个 `Button("OK")` 会共用一个控件状态，点哪个都触发第一个；`Button("")` 会和父窗口本身的 ID 撞（空标签 == 用父控件标签，`docs/FAQ.md:286`）。

**三种解冲突手段**：

| 手段 | 可见标签 | 进 ID 的部分 | 行号 | 用在哪 |
| --- | --- | --- | --- | --- |
| `##suffix` | `##` 之前 | 整串（含 `##` 之后） | `imgui.h` 无专门说明；`docs/FAQ.md:288-294`、`:300-321` | 固定数量、标签相同的控件 |
| `###suffix` | `###` 之前 | **`###` 之后**（可见部分不进 ID） | `docs/FAQ.md:294`、`:368-403` | 标签会变（动画 FPS、开始/停止按钮）、状态不能丢 |
| `PushID()/PopID()` | 不变 | 额外压一层前缀/整数/指针 | `imgui.h:616-624`；`docs/FAQ.md:326-357`、`:474-513` | 循环、动态列表 |

- `GetID(...)`（`imgui.h:621-624`，绑定 `Generated/Functions/Functions.001.cs:339`）返回 `uint`：需要自己算 key 时用（`ImGuiStorage` 存自定义数据、`OpenPopup`/`IsPopupOpen` 传显式 ID），日常画控件不需要。
- 查冲突工具：C++ 是 `ShowIDStackToolWindow()`（`docs/FAQ.md:418`）；C# 绑定里没有（同上，旧版），只能靠 `###`/`PushID` 的纪律。
- 重复 ID 在 1.91+ 有 `ImGuiItemFlags_AllowDuplicateId` 与调试高亮（`imgui.h:1260`），本机绑定没有这个 flag —— 撞了静默出诡异行为。

**同一个循环里生成多个按钮的正确写法**（本机绑定可直接用）：

```csharp
using Dalamud.Bindings.ImGui;

foreach (var (index, entry) in this.entries.Select((e, i) => (i, e)))
{
    ImGui.PushID(index);                    // imgui.h:619；绑定 ImGui.PushID(int)
    if (ImGui.Button("删除"))
        Remove(entry);
    ImGui.SameLine();
    ImGui.Text(entry.Name);
    ImGui.PopID();                          // imgui.h:620；必须与 PushID 成对
}
```

固定数量、标签不同时 `##` 更省事；标签要变时用 `###`（状态才不丢）：

```csharp
ImGui.Button("写入配置##write");                                  // FAQ:300-321
ImGui.Button(this.running ? "停止###toggle" : "开始###toggle");    // FAQ:368-403
```

**不要**拿「可变的显示文字」当唯一 ID 却不加 `###`：树的展开状态、焦点都挂在 ID 上（`docs/FAQ.md:524-529`），文字一变状态就重置。

### Q2 立即模式的状态陷阱

**为什么**：`imgui.cpp:207` —— 每帧重跑一遍你的绘制代码。于是：

- 方法里的**局部变量每帧归零**，想跨帧保存就必须放字段/配置；
- 控件的内部状态（按住、编辑中、树展开、焦点）存在 ImGui 内部，按 ID 索引，不在你的对象里；
- 代码**顺序决定可见性**：先改状态再画，后面的控件这一帧立刻看到新值；画在前面的控件看不到。

所以「在 `if (ImGui.Button(...))` 里改状态」本身没问题，错误的是下面两种期待：

```csharp
// 对：状态在字段里；同一帧后面的 Text 立刻能读到
if (ImGui.Button("开始"))
    this.running = true;
ImGui.Text(this.running ? "运行中" : "已停止");

// 错：局部变量每帧重置，永远不显示「运行中」
bool running = false;
if (ImGui.Button("开始")) running = true;
if (running) ImGui.Text("运行中");
```

- `Button` 默认在「控件上按下并在控件上松开」的那一帧返回 true，**不是**「按下过一次」的持久标志；持续按住要用 `IsItemActive()`。
- 别指望返回值跨帧保持；需要「点一次执行一次」就在 if 里做，需要「持续生效」就读字段。

**`IsItem*` 系列**（只看**上一个**提交的控件，`imgui.h:1023-1031`）：

| 函数 | 行号 | 用途 |
| --- | --- | --- |
| `IsItemHovered()` | `imgui.h:1023` | 悬停提示；注意弹窗挡住时返回 false |
| `IsItemActive()` | `imgui.h:1024` | 正被按住/正在编辑（连续为真） |
| `IsItemEdited()` | `imgui.h:1028` | 这一帧值变了 |
| `IsItemDeactivated()` | `imgui.h:1030` | 这一帧刚失去激活 |
| `IsItemDeactivatedAfterEdit()` | `imgui.h:1031` | 这一帧刚结束编辑且值变过 → **写盘/撤销/校验的正确时机** |

`IsItemDeactivatedAfterEdit` 有已知假阳性：`Combo`/`ListBox`/`Selectable` 点已选中项也返回 true（`imgui.h:1031` 注释原文）。

```csharp
ImGui.SetNextItemWidth(160f);
ImGui.InputText("##nick", ref this.nick, 64);
if (ImGui.IsItemDeactivatedAfterEdit())        // 绑定 Custom/Generated/Generated/Functions/ImGui.gen.cs:2273
    this.config.Save();                        // 别每帧写盘
```

**Begin/End 配对**（最容易写错的一条）：

```csharp
ImGui.SetNextWindowSize(new Vector2(480, 320), ImGuiCond.FirstUseEver);
if (ImGui.Begin("我的设置", ref this.visible))   // 绑定 Begin(string, ref bool, flags) Functions.000.cs:1350
{
    // 内容
}
ImGui.End();                                     // 返回 false 也必须 End（imgui.h:442-446）
```

`imgui_demo.cpp:10049-10053` 就是官方写法：`if (!Begin(...)) { End(); return; }`。`BeginChild` 同理（`imgui.h:464-468`），但 `BeginTable` 必须写进 if（`imgui.h:918`）。

### Q3 布局：表格、SameLine、Child、SetNextItemWidth

**表格**（`imgui.h:896-916` 给了调用流）：

```csharp
if (ImGui.BeginTable("##settings", 2, ImGuiTableFlags.SizingStretchProp | ImGuiTableFlags.RowBg))
{
    ImGui.TableSetupColumn("项", ImGuiTableColumnFlags.WidthFixed, 160f);   // imgui.h:932
    ImGui.TableSetupColumn("值", ImGuiTableColumnFlags.WidthStretch);        // imgui.h:2138-2139
    foreach (var row in rows)
    {
        ImGui.TableNextRow();                        // imgui.h:919
        ImGui.TableSetColumnIndex(0);                // imgui.h:921；第一列也要显式进入
        ImGui.TextUnformatted(row.Label);
        ImGui.TableSetColumnIndex(1);
        row.DrawEditor();
    }
    ImGui.EndTable();                                // 只有 BeginTable 返回 true 才调（imgui.h:918）
}
```

- 枚举成员在本机绑定里**不带前缀**：`ImGuiTableFlags.SizingStretchProp`（`Generated/Enums/ImGuiTableFlags.cs:130`）、`ImGuiTableFlags.RowBg`（`:60`）、`ImGuiTableColumnFlags.WidthFixed/WidthStretch`（`Generated/Enums/ImGuiTableColumnFlags.cs:45`/`:40`）。
- `SizingFixedFit`（`imgui.h:2102`，= 1<<13）列宽贴合内容；`SizingStretchProp`（`:2104`，= 3<<13）按内容比例拉伸；`SizingStretchSame`（`:2105`）等分。
- **默认策略**（`imgui.h:2057-2077`）：`ScrollX` 开或宿主窗口 `AlwaysAutoResize` → `FixedFit`；否则 `StretchSame`。想「前几列固定、最后一列吃满」的常见设置页布局，就显式混用 Fixed + Stretch（`:2068` 说这是典型用法）。
- 第一列也**必须** `TableSetColumnIndex(0)` 或 `TableNextColumn()`，否则文字不显示（`imgui.h:910`、`:915`）。

**左列表 + 右详情 + 底部按钮**（抄 `imgui_demo.cpp:9731-9792`，改成老签名）：

```csharp
ImGui.SetNextWindowSize(new Vector2(720, 420), ImGuiCond.FirstUseEver);
if (ImGui.Begin("词条", ref this.visible))
{
    ImGui.BeginChild("##list", new Vector2(180, 0), true);      // 宽 180，高 = 父剩余（imgui.h:458-461）
    for (var i = 0; i < items.Count; i++)
        if (ImGui.Selectable(items[i].Name, i == this.selected))  // Custom/ImGui.Widgets.cs:517
            this.selected = i;
    ImGui.EndChild();                                            // 返回值忽略也必须 EndChild

    ImGui.SameLine();
    ImGui.BeginChild("##detail", new Vector2(0, -ImGui.GetFrameHeightWithSpacing()), true); // 底部留一行（imgui_demo.cpp:9765）
    ImGui.TextWrapped(items[this.selected].Description);
    ImGui.EndChild();

    if (ImGui.Button("保存")) this.config.Save();
}
ImGui.End();
```

Child 尺寸语义（`imgui.h:458-461`）：`0` = 用父窗口该轴剩余空间；`>0` = 固定像素；`<0` = 距右/下边界留多少。`AutoResizeX + AutoResizeY` 同时开会破坏滚动区，不推荐（`:462-463`）。滚动不需要额外参数——子窗口内容超高就自带滚动条。

**一行放多个控件**：

```csharp
ImGui.SetNextItemWidth(120f);                       // imgui.h:555；<0 表示右对齐留边
ImGui.InputInt("##count", ref this.count);          // Custom/ImGui.InputScalar.cs:98
ImGui.SameLine();                                    // imgui.h:591
if (ImGui.Button("重置")) this.count = 0;
```

`SameLine(offset_from_start_x, spacing)` 的 `spacing` 传 `-1` 表示用 `style.ItemSpacing.x`。

### Q4 窗口位置/尺寸与 `ImGuiCond`

```csharp
ImGui.SetNextWindowSize(new Vector2(520, 360), ImGuiCond.FirstUseEver);      // imgui.h:488；某轴填 0 = 该轴自动适配
ImGui.SetNextWindowPos(new Vector2(200, 200), ImGuiCond.Appearing, new Vector2(0.5f, 0.5f)); // imgui.h:487；pivot 0.5 = 该点居中
```

`ImGuiCond` 枚举（`imgui.h:2043-2051`）：

| 值 | 行号 | 含义 | 用在哪 |
| --- | --- | --- | --- |
| `None` / `Always` | `:2045-2046` | 每次都设 | 需要每帧强制的尺寸（注意会覆盖用户拖动） |
| `Once` | `:2047` | 每次进程只成功一次 | 首次布局 |
| `FirstUseEver` | `:2048` | **没有持久化记录**时才设（窗口在 ini 里没有条目） | 默认窗口大小、默认位置 |
| `Appearing` | `:2049` | 每次重新出现时设（隐藏后再显示） | 弹窗居中、重新摆位 |

坑：`FirstUseEver` 依赖窗口状态持久化（ini）。Dalamud 下 `imgui.ini` 落在哪、每个插件窗口是否独立记忆——**未确认**。稳妥做法：要「用户拖过的尺寸」就自己存配置并用 `Once` 只设一次，或者干脆不设让 ImGui 自己记；不要用 `Always` 每帧覆盖用户拖动。

### Q5 常见坑（症状 → 正确做法）

| 症状 | 正确做法（行号） |
| --- | --- |
| 长文本把窗口撑爆、右边被裁 | `ImGui.TextWrapped(text)`（`imgui.h:635`，等价 `PushTextWrapPos(0)+Text+Pop`）；要指定宽度用 `PushTextWrapPos(w)/PopTextWrapPos()`（`:557-558`）。**自动宽度窗口里只有一行文本时 TextWrapped 无效**（`:635` 注释），先 `SetNextWindowSize` 给宽度 |
| 设置页分区标题带缩进、右边多出折叠箭头 | 分区用 `CollapsingHeader`（`imgui.h:768`：不缩进、不 Push ID、不用 `TreePop`）；真树形才用 `TreeNode`（`:754`，会隐式 PushID，`docs/FAQ.md:514-517`），且 true 时 `TreePop()` |
| InputText 输不进长文本 / 中文被截断 | 绑定是 `ref string`（`Custom/ImGui.Manual.cs:123-138`），默认上限 `ImU8String.AllocFreeBufferSize = 512` 字节（`ImU8String.cs:13`）→ 显式传 maxLength；回车提交加 `ImGuiInputTextFlags.EnterReturnsTrue`（`imgui.h:1302`），但更好的时机是 `IsItemDeactivatedAfterEdit()` |
| Combo 选了不生效 / 越界崩 | `Combo` 返回 true 时把 index 写回**配置**（真实写法：`TextToTalkCN/src/TextToTalk/UI/Components.cs:56-63`）；列表变短先 clamp；每帧重建 `string[]` 会分配，用 `items_separated_by_zeros` 版（`Custom/ImGui.ComboAndList.cs:19`）或 `ReadOnlySpan<string>` 版（`:37`） |
| 颜色编辑改了没保存 / 循环里两个色块联动 | `ColorEdit4` 的 label 就是 ID → 循环里 `PushID`；值类型 `Vector4` 分量 0..1（`imgui.h:747`；绑定 `Generated/Functions/Functions.072.cs:1256`）。要大色板用 `ColorPicker4`（`imgui.h:749`） |
| 抄来的 C# 示例编译不过 | 本机绑定没有 1.90+ 的 `ImGuiChildFlags` / `SeparatorText` / `SetItemTooltip`（见 ①） |

补充两条与 C# 相关的：

- **Text 不做格式化**：`ImGui.Text("{}")` 原样显示；`ImGui.Text("a" + b)` 或插值。
- **每帧别做重活**：绘制函数每帧跑；写盘、网络、`Save()` 放在按钮或 `IsItemDeactivatedAfterEdit()` 里。

### Q6 样式：只 Push，不全局改

`ImGuiStyle` 结构在 `imgui.h:2330`，与我们相关的字段：

| 字段 | 行号 | `ImGuiStyleVar` 成员 | 影响 |
| --- | --- | --- | --- |
| `ItemSpacing` | `imgui.h:2354` | `ImGuiStyleVar.ItemSpacing`（`:1876`） | 控件之间横竖间距，调紧凑最有效 |
| `FramePadding` | `imgui.h:2351` | `FramePadding`（`:1873`） | 输入框/按钮内边距，直接改控件高度 |
| `WindowRounding` | `imgui.h:2341` | `WindowRounding`（`:1865`） | 窗口圆角；设 0 得方角 |
| `ChildRounding` | `imgui.h:2347` | `ChildRounding`（`:1869`） | 子窗口圆角 |
| `ScrollbarSize` | `imgui.h:2360` | `ScrollbarSize`（`:1880`） | 滚动条宽/高 |
| `CellPadding` | `imgui.h:2356` | `CellPadding` | 表格单元格内边距（`CellPadding.x` 全表锁定） |
| `GrabMinSize` | `imgui.h:2363` | `GrabMinSize`（`:1883`） | 滑块抓手上限 |

正确写法——**只包住自己的窗口内容**：

```csharp
ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, new Vector2(8f, 3f));   // 绑定 ImGui.gen.cs:1281（浮点是 :1277）
ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, new Vector2(4f, 2f));
// ... 自己的控件 ...
ImGui.PopStyleVar(2);                                                  // imgui.h:548，数量要配对
```

**为什么不能全局改**：

1. `GetStyle()` 返回的是**全局单例**，头文件注释直接写 "Always use PushStyleColor(), PushStyleVar() to modify style mid-frame!"（`imgui.h:413`）；`PushStyleVar` 注释同样强调「after NewFrame 之后必须用 Push 而不是直接改」（`:544-545`）。
2. Dalamud 是所有插件共用一个 ImGui context：`ImGui.GetStyle().WindowRounding = 0` 会把**别人的窗口**一起改掉，包括游戏内其他插件的设置页。
3. Dalamud 自己维护全局样式模型（`Dalamud/Interface/Style/StyleModel.cs:19`，`:47 GetFromCurrent()`），用户在 Dalamud 设置里可以整体换样式——**推测**你的全局写入会在下次样式切换时被覆盖，还会和用户选择打架。
4. 读 `GetStyle()` 没问题，本机插件就在读：`TextToTalkCN/src/TextToTalk/Backends/Azure/AzureBackendUI.cs:157`、`:176`。

结论：**值用 `GetStyle()` 读，改一律 `PushStyleVar/PopStyleVar`**；窗口级圆角这类整窗外观，改 `ImGuiStyleVar.WindowRounding` 包住整个窗口而不是改结构体。

### Q7 上游最值得读的三篇（以及一篇不值得读的）

| 文档 | 规模 | 为什么 |
| --- | --- | --- |
| `docs/FAQ.md` | 964 行 | 前 530 行几乎全是我们的高频 bug：ID/标签（`:285-294`、`:326-403`、`:409-529`）、空标签（`:359-365`）、动态标签 `###`（`:368-403`）。读它=读完「为什么我的控件互相串」。 |
| `imgui.cpp` 顶部注释 | `:44-103` 索引 + `:204-239` READ FIRST + `:390` API BREAKING CHANGES | 唯一解释「为什么 API 长这样」的地方；`:207`（每帧重跑）与 `:390`（升级会断什么）直接影响我们的写法与升级决策。 |
| `imgui_demo.cpp` | 11,552 行 | `ShowDemoWindow()`（`:346`）是整个库的活文档。三个范例直接能抄：`ShowExampleAppLayout`（`:9731`，左列表+右详情+底部按钮）、`ShowExampleAppLongText`（`:10046`，长文本容器怎么摆）、`ShowExampleAppSimpleOverlay`（`:10234`，悬浮窗）。 |

**`docs/BACKENDS.md` 对我们没用**：它讲后端要提供输入事件、纹理、索引三角形（`docs/BACKENDS.md:20-40`），Dalamud 早就做好了。真正该补的是**本机绑定源码** `Dalamud.Bindings.ImGui/Custom/`——我们踩的坑一半来自绑定与上游的版本差（比如 `InputText` 的 `ref string` 上限、没有 `ImGuiChildFlags`）。

## ③ 今晚就能改掉的三个写法

1. **循环里的控件没隔离 ID** → 每个迭代 `ImGui.PushID(i)` … `ImGui.PopID()`（或标签加 `##i`）。
   判据：改前在一个列表里连点两行，第二行没反应或第一行被触发；改后各点各的。依据 `imgui.h:616-620`、`docs/FAQ.md:326-357`。
2. **直接改 `ImGui.GetStyle()`** → 换成 `PushStyleVar/PopStyleVar` 包住自己窗口的内容。
   判据：同时开两个插件窗口对比，改前两个一起变，改后只有自己的变。依据 `imgui.h:413`、`:544-548`。
3. **`End()` 写在 `if (Begin())` 里面** → 把 `End()` 提到 if 外；`BeginTable` 相反，`EndTable()` 留在 if 内。
   判据：`imgui.h:442-446`、`:464-468`、`:918`。不改的症状是窗口栈错位：后面的控件画进别人的窗口，或 debug 构建里报 assert。

## ④ 可信度标注

| 结论类型 | 依据 | 等级 |
| --- | --- | --- |
| 上游行号（`imgui.h` / `imgui.cpp` / `docs/FAQ.md` / `imgui_demo.cpp`） | 本机 clone 实读，HEAD `4be0b47e`，1.93.1 WIP | 源码实证（库会更新，用前照行号再确认） |
| C# 绑定签名与行号 | `E:\FF14Dev\KnowledgeBase\Dalamud\imgui\Dalamud.Bindings.ImGui\` 源码实读 + 运行时 DLL 字符串核对 | 源码实证，**仅对本机这份绑定成立** |
| 本机绑定缺 1.90+ API | 枚举/函数在绑定源码 grep 0 命中，DLL 二进制字符串同样 0 命中 | 实证；**具体版本号未确认**（不是 1.93） |
| Dalamud 会覆盖全局样式 | 从 `StyleModel` 的存在推断 | **推测** |
| `imgui.ini` 在 Dalamud 下的持久化 / `FirstUseEver` 实际行为 | 未查 | **未确认** |
| 示例代码 | 逐条对照本机绑定签名，**未编译**（本次要求只读） | 未编译验证 |

未查清：① 本机绑定对应的 ImGui 确切版本；② Dalamud 是否持久化窗口布局（影响 `FirstUseEver`/`Appearing`）；③ 那三个 1.90+ API 会不会在下次 Dalamud 升级后出现（影响写法能否简化）。
