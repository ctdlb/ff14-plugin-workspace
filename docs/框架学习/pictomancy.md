# pictomancy 学习笔记（源码静态分析）

> 调研对象：`.tmp\study\ffxiv_pictomancy`（`git clone --depth 1`，只能看到 1 条提交）。只读调研（`git log`/`grep`/`wc`/`sed`），**未编译、未运行**。凡是推断都写「推测」，没读到的写「未确认」。

## 一句话定位

一个「在 3D 世界空间里画覆盖层」的库：接口手感像 ImGui（`AddLine`/`AddCircle`/`AddFan`/`AddSphere`…），但坐标是世界坐标、由库自己用 D3D11 投影并处理深度遮挡，另外还封装了游戏 VFX（Omen 地面预警圈、Lockon、读条连线）的创建。

- 仓库：<https://github.com/sourpuh/ffxiv_pictomancy>（NuGet 包名 `Pictomancy`）
- LICENSE 文件：`LICENSE`，正文是 **GNU AFFERO GPL v3**；`Pictomancy/Pictomancy.csproj` 显式写了 `<PackageLicenseExpression>AGPL-3.0-or-later</PackageLicenseExpression>`、`<Version>1.0.10</Version>`
- 规模：全部 **51 个 `.cs` / 6,523 行**；库本体 `Pictomancy/` = **48 文件 / 5,733 行**，示例工程 `PictomancyDemo/` = 790 行
- 最近提交：`70611d1` · `2026-06-13 13:38:42 -0700` · "1.0.10"

## 目录地图

| 目录 | 文件 / 行数 | 干什么 |
| --- | --- | --- |
| `Pictomancy/DXDraw/` | 21 / 3,948 | D3D11 管线：各图元 shader、`DXRenderer`、`RenderContext`、`SceneDepth`、裁剪区 |
| `Pictomancy/VfxDraw/` | 8 / 341 | VFX 数据结构与函数（`Vfx`、`VfxData`、`VfxInitData`、`VfxFunctions` 里 7 条 `ScanText` 签名） |
| `Pictomancy/ImGuiDraw/` | 2 / 129 | 把 `ImDrawList` 的顶点塞进 D3D 管线 |
| `Pictomancy/*.cs` | 17 文件 | 门面（`PctService`/`PctContext`/`PctDrawList`/`PctDrawHints`/`PctOptions`/`PctDxParams`）+ `VfxRenderer` + 原生节点胶水（`PctOverlayNode`、`TextureImageNode`） |

依赖（`.csproj`）：`SharpDX.Mathematics` / `SharpDX.D3DCompiler` / `SharpDX.Direct3D11` / `SharpDX.Direct2D1` **4.2.0**、`KamiToolKit 1.1.2`；SDK `Dalamud.NET.Sdk/15.0.0`，`AllowUnsafeBlocks`，`Use_DalamudPackager=false`。

## 核心 API

### 1. 生命周期：全局单例（不是 per-plugin 实例）

```csharp
// Pictomancy/PctService.cs:48
public static PctContext Initialize(IDalamudPluginInterface pluginInterface, PctOptions? options = null)
// Pictomancy/PctService.cs:92
public static void Dispose()
// Pictomancy/PctService.cs:149
public static PctDrawList? Draw(ImDrawListPtr? imguidrawlist = null, PctDrawHints? hints = null)
// Pictomancy/PctService.cs:134
public static PctDrawList GetDrawList()
```

`Initialize` 重复调用会抛 `InvalidOperationException`（"Pictomancy is already initialized. Dispose the existing PctContext before calling Initialize again."）；返回的 `PctContext` 是 `IDisposable`，`Dispose` 幂等。`Draw` 在渲染器不可用时返回 `null`（**必须判空**）；过场/黑屏默认整帧跳过（`:195 IsFaded`，由 `PctDrawHints.DrawInCutscene`/`DrawWhenFaded` 控制）。

### 2. 画布：一帧一个，用完必须 Dispose

```csharp
// Pictomancy/PctDrawList.cs:9
public class PctDrawList : IDisposable
// Pictomancy/PctDrawList.cs:76
public void Dispose()
// Pictomancy/PctDrawList.cs:66
public PctTexture DrawToTexture()
```

`Dispose()` 负责 EndFrame + 按 `AutoDraw` 输出，**每帧都要调**（用 `using var draw = PctService.Draw(...)`）。

### 3. 图元（世界坐标）

```csharp
// Pictomancy/PctDrawList.cs:224
public void AddLine(Vector3 start, Vector3 stop, float halfWidth, uint color, float thickness = 2, PctDxParams? p = null)
// Pictomancy/PctDrawList.cs:319
public void AddSphere(Vector3 origin, float radius, uint color, PctDxParams? p = null)
// Pictomancy/PctDrawList.cs:135
public void AddText(Vector3 position, uint color, string text, float scale = 1)
// Pictomancy/PctDrawList.cs:191
public void PathStroke(uint color, PctStrokeFlags flags = default, float thickness = 2f, PctDxParams? p = null)
```

其余同族：`AddQuad`/`AddQuadFilled`、`AddCircle`/`AddCircleFilled`/`AddArc`、`AddConeFilled`、`AddFan`/`AddFanFilled`、`AddImage`（`IDalamudTextureWrap`/`ImTextureID`/`nint` 三种重载）、`AddSprite`、`AddBillboard`、`AddDot`；裁剪用 `AddClipZone(Rectangle)` / `AddClipZone(Vector2 min, Vector2 max)`（`:157`/`:166`）。

> `AddText` 是**例外**：注释写明走 ImGui 画，不参与深度遮挡与自动裁剪（"not clipped"）。

### 4. 渲染提示与素材

```csharp
// Pictomancy/PctDrawHints.cs:21 / :34
public AutoDraw AutoDraw { get; init; } = AutoDraw.ImGuiOverlay;
public UIMask UIMask { get; init; } = UIMask.Default;
```

`AutoDraw`（`AutoDraw.cs`）：`None=0` 只产纹理 / `ImGuiOverlay=1` 同帧合成 / `NativeOverlay=2` 挂原生 overlay 节点、滞后 1 帧。`UIMask`（`UIMask.cs`）：`Default` / `None` / `BackbufferAlpha`（按背缓冲 alpha 遮住原生 UI，`NativeOverlay` 时自动禁用，注释说 O8 之类场景效果差）。

### 5. 投影遮挡参数

```csharp
// Pictomancy/PctDxParams.cs（record struct）
OccludedAlpha = 1f, OcclusionTolerance = 0.02f, FadeStart/FadeStop = +inf,
ProjectionHeight = 0f, FresnelSpread = 0.25f, FresnelIntensity = 0.5f, FresnelOpacity = 0.3f
```

### 6. 选项与容量上限

```csharp
// Pictomancy/PctOptions.cs:11 / :17 / :20
EnableDxRenderer = true, EnableKtkOutput = false, EnableVfxRenderer = true
```

缓冲上限 `MaxFans 2048`、`MaxTriangleVertices 1024*3`、`MaxStrokeSegments 2048*240/2`、`MaxClipZones 1024`、`MaxSpheres 256`、`MaxImages 256`、`MaxSprites 256`——超限**静默丢弃**（只有一次性告警）。

### 7. VFX 封装（Omen/Lockon/读条）

```csharp
// Pictomancy/VfxRenderer.cs:50
AddOmen(string id, string name, Vector3 origin, Vector3? scale = null, float rotation = 0, Vector4? color = null)
// Pictomancy/VfxDraw/Vfx.cs:15
public static Vfx Create(string path, Vector3 position, Vector3 size, float rotation, Vector4? color = null)
```

配套 `AddLockon`（`:65`）、`AddChanneling`（`:81`）、`AddCommon`（`:96`）、`AddCustom`（`:112`）。

## 它解决什么问题

**「我要在世界里画一块跟着目标走、被墙挡住会变淡、被 UI 挡住会消失的东西」**——DrawList 自己做世界→屏幕投影、深度测试、相机后方裁剪、UI 区域裁剪；调用方只给世界坐标和颜色。另一半是 VFX 数据调用式的玩法特效（地面圆形预警 = Omen、锁定标记 = Lockon、读条连线 = Channeling），省去自己拼 VFX 路径与 `VfxInitData`。

## 对我们的用处

**结论：没有能直接用的东西，一行都用不上。** 它的全部输出都是世界空间 3D 图元；我们要的是「往游戏原生 `ItemDetail` 的 ATK 节点树里插文本节点、改 `WindowNode`/九宫格/RootNode 把窗口撑高」，两个层次完全不重叠：

- 它自己也不碰 ATK 文本节点，也不改任何窗口尺寸：全库 `AddNode` 只有 **1 处**（`Pictomancy/PctService.cs:67 _overlayController.AddNode(_overlayNode)`），且是往**全屏 overlay** 上挂一张纹理。
- 它唯一沾原生节点的两处（`Pictomancy/PctOverlayNode.cs` 的 `internal unsafe class PctOverlayNode : OverlayNode`、`Pictomancy/TextureImageNode.cs` 的 `public unsafe class TextureImageNode : SimpleImageNode` + `SetTexture(Texture* texture)` 写 `asset->AtkTexture.KernelTexture`）**都是 KamiToolKit 的 API**，pictomancy 只是使用者。
- **真正对口我们需求的是它依赖的 KamiToolKit**（我们已有 `docs\框架学习\KamiToolKit-深读.md`），不是 pictomancy 本身。
- 唯一勉强算「思路可借」的两点（**都只是思路，别引依赖**）：`Pictomancy/PctService.cs:186 IsResolutionScaled` 展示了怎么判断「渲染分辨率 ≠ 屏幕分辨率」（缩放窗口时自绘坐标会错位，我们画屏幕坐标文字时会碰到同类问题）；`PctDrawHints.UIMask = BackbufferAlpha` 说明「用背缓冲 alpha 识别 UI 像素」这条思路可行（代价：要额外读 RTV，且在 `NativeOverlay` 下不可用）。

## 坑 / 限制

- **许可证：AGPL-3.0-or-later（比 GPL 更狠）**。抄代码不行；**只要引用它的 NuGet 包并分发插件，整个插件就落在 AGPL 下**（须以 AGPL 提供源码；AGPL §13 的网络条款对本地插件无实际影响，但分发义务照样成立）。真要用的前提是愿意把插件开源成 AGPL——**推测**：AGPL 对「动态链接算不算衍生」在插件场景基本按「算」处理，稳妥按「引用即传染」。
- **另有版权上的隐性风险**：它的 VFX 部分靠 7 条 `ScanText` 手扫签名（`Pictomancy/VfxDraw/VfxFunctions.cs:38-44`），游戏更新即可能全废；它的图形管线重度依赖私有细节（`Device.Instance()->D3D11Forwarder`、`RenderTargetManager` 深度缓冲、背缓冲 RTV），版本一换最先坏的就是这些。
- **依赖 SharpDX 4.2.0**（已被托管代码淘汰的绑定）与 **KamiToolKit 1.1.2**——后者是我们的既有依赖，版本要对齐，否则 `OverlayNode`/`SimpleImageNode` 的类型会撞（**推测**：同一 KTK 版本下没问题，跨版本可能编译失败，**未确认**）。
- **全局单例**：`PctService` 用 7 个 `[PluginService]` 静态字段（`Pictomancy/PctService.cs:18-24`），`Initialize` 只能调一次；两个插件同时用会有一个抛异常。
- **每帧必须 `Dispose`**，忘了就漏 GPU 资源；`Draw()` 返回 `null` 必须判空。
- **静默降级**：shader 编译失败只打日志（`"[Pictomancy] Failed to compile fan shader; starting in degraded mode."`）并置 `FanDegraded`/`StrokeDegraded`，画面缺东西但功能不报错——排错时得看日志。
- **容量上限硬编码**，超了直接丢图元，不抛异常。
- 彩蛋：`Pictomancy/GaolbreakHeartbeatReader.cs` 读 IPC 键 `"Gaolbreak.Heartbeat.v1"`，检测到该插件存活就关掉 `BackbufferAlpha` 遮罩。

## 还没读透的部分

- `Pictomancy/DXDraw/` 21 文件 / 3,948 行的 shader 与管线实现（`Stroke.cs` 368 行、`TriFill.cs`、`FanFill.cs`、`Image.cs`、`Sprite.cs`、`Sphere.cs` 各一，只看了入口）。
- `ProjectedTriFill`/`ProjectedFanFill` 的投影与近平面裁剪数学。
- `Pictomancy/ImGuiDraw/` 的 `ImGuiRenderer`（129 行）。
- `UIMask.BackbufferAlpha` 的具体判定与它和 `NativeOverlay` 的互斥条件。
- `VfxDraw/VfxInitData.cs` 与 `Vfx` 的变换矩阵更新时机。
- 示例工程 `PictomancyDemo/VfxTab`（VFX 那一页怎么用）与 `DemoWindow.DrawWorld` 的完整调用链。
