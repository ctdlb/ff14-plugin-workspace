# Reatkact 学习笔记

> 调研对象：`E:\DeepSeek Harness\.tmp\study\Reatkact`（浅克隆 `--depth 1`，只有 1 条提交历史）。
> 只读调研：没编译、没改源码。推断写「推测」，没读到的写「未确认」。

## 1. 一句话定位

**把 React 渲染到游戏 ATK 界面上**——在游戏进程内嵌一个真 Node.js 运行时，用 `react-reconciler` 自建渲染器，把 React 树落到 KamiToolKit 的节点属性上。

- 仓库：<https://github.com/NotNite/Reatkact>
- LICENSE：**仓库里没有任何许可证文件**（`git ls-files` 无 `LICEN*` / `COPYING`）→ 默认「保留所有权利」，**不可直接抄代码**
- 规模：**11 个 `.cs` / 442 行**（C# 侧）；另有 4 个 TS 文件在 `js/reatkact/src/`，示例在 `js/hello-world/src/index.tsx`
- 最近提交：**2025-06-02** `be537df` `Rework prop application`
- 工程：`Dalamud.NET.Sdk/12.0.2`；NuGet `Microsoft.JavaScript.NodeApi 0.9.11` + `LibNode 20.1800.215`；子模块 `libs/KamiToolKit`（`.gitmodules` 指向 `MidoriKami/KamiToolKit`，**本机未初始化，目录为空**）

## 2. 核心 API / 目录地图

| 路径 | 行数 | 作用 |
| --- | --- | --- |
| `Reatkact/NodeRuntime.cs` | 155 | 起/复用 Node 运行时，注册桥接类型，加载 JS 模块 |
| `Reatkact/Bridge/BridgeAddon.cs` | 53 | JS 侧的「窗口」对象，内部包一个 `DynamicAddon` |
| `Reatkact/Bridge/IBridgeNode.cs` | 60 | 节点桥接基类，暴露 x/y/width/height |
| `Reatkact/Bridge/INodeControls.cs` | 32 | 增删子节点的统一接口 + `*Raw(object?)` 包装 |
| `Reatkact/Bridge/NodeIdCounter.cs` | 16 | 给节点补唯一 `NodeId` 的全局计数器 |
| `Reatkact/Bridge/Nodes/TextNode.cs` / `TextButtonNode.cs` | 22 / 11 | 仅有的两个元素 |
| `js/reatkact/src/{bridge,reconciler,index}.ts` | — | 渲染器本体（React host config） |

关键签名：

```csharp
// NodeRuntime.cs:19
public NodeRuntime(Configuration configuration, string? baseDir = null)
// NodeRuntime.cs:39  —— 手工反射注册桥接类型（源码生成器只管 native addon）
private void BindTypes()   // :58 JSValue.Global.SetProperty("ReatkactBridge", bridge)
// NodeRuntime.cs:69  —— 进程内单例 hack
private static NodeEmbeddingPlatform GetPlatform(Configuration configuration)
// NodeRuntime.cs:120
public void Start(string file)   // :127 取 default 导出的 init，:130 它必须返回 unload 函数
// NodeRuntime.cs:142
public void Dispose()            // :143-149 必须先调 unload，否则「游戏多半会死锁」

// BridgeAddon.cs:8
public class BridgeAddon(BridgeAddon.AddonOptions options) : NodeControlsBase, IDisposable
// BridgeAddon.cs:48
public struct AddonOptions { public required string Title; public float Width; public float Height; }
// BridgeAddon.cs:23
private class DynamicAddon : NativeAddon, INodeControls   // :27 InternalName = "Reatkact" —— 写死

// IBridgeNode.cs:15
public abstract class BridgeNodeBase<TN> : NodeControlsBase, IBridgeNode where TN : NodeBase, new()
// NodeIdCounter.cs:11
public static void EnsureNodeId(NodeBase node)  // node.NodeId == 0 → Interlocked.Increment
// SeStringExtensions.cs:8
public static SeString ParseMacroString(this string? str)  // ReadOnlySeString.FromMacroString → SeString.Parse
```

入口 `Plugin.cs:11` 构造插件时把 JS 入口路径**写死**成 `../../js/hello-world/dist/index.js`（`Plugin.cs:18-28`，旁边注释 `// FIXME: lol`）。

## 3. 它解决什么问题

Dalamud 插件 UI 传统上只能用 ImGui。这个项目证明另一条路：**用 React 写插件界面，渲染到 ATK**——不是 CEF（不背浏览器），而是 react-reconciler + `node-api-dotnet`，React 的 diff 结果直接写进 KTK 节点的 `X/Y/Width/Height/Text`。好处是「UI 用声明式写」，且渲染出来的是游戏原生节点，跟着游戏 UI 一起混。

## 4. 对我们的用处

**结论：没用，明确不建议引入。** 我们的目标是「往游戏原生 `ItemDetail` 里插自己的文本节点并撑高窗口」，这个库四条都不搭：

1. **它没有「往别人 addon 里插」的概念。** 节点只能挂进它自己 `new` 出来的 `DynamicAddon`（`BridgeAddon.cs:23-35`：`NativeController.AttachToAddon(child.Node, this)`）。要挂到 `ItemDetail->RootNode` 上，得先有 KTK 的 `AttachNode(AtkUnitBase*)`，而那个能力跟这个库无关。
2. **工程代价极高。** Node.js 运行时每进程只能起一次，作者的办法是把 handle 写进插件配置、用 `RuntimeHelpers.GetUninitializedObject` 复活单例（`NodeRuntime.cs:83-116`），注释写着 `this is terrible` 和 `Pray to god it doesn't crash I guess`；卸载顺序错了会死锁（`NodeRuntime.cs:143-149`）。
3. **功能极少。** 只有 `atkText` / `atkTextButton` 两个元素，无事件、无布局（README「Implemented features」自己说的）。
4. **作者自己劝退。** README 原文：`this is (of course) mostly for demonstration/shitpost points, please don't actually use this in your plugin`。且**没有 LICENSE**。

唯一可借的一条：`NodeIdCounter.cs:11-13` 说明**手写原生节点必须给唯一 `NodeId`**（KTK 侧只补 `NodeId == 0` 的），我们手搓节点时值得照这个思路自查一遍。

## 5. 坑 / 限制

- **无许可证文件** → 不能把代码搬进我们仓库。
- `libs/KamiToolKit` 是子模块且没 init（目录为空）→ 不解 submodule 直接编不了。
- `Dalamud.NET.Sdk/12.0.2`，与我们的 `Dalamud.CN.NET.Sdk/15.0.0` 差好几代。
- 构建顺序有硬要求：先 `cd js && pnpm i -r && pnpm run build`，再编 C#（README「Building JS code」）。
- 写死项一堆：插件目录（`Plugin.cs:18-28`）、`InternalName`（`BridgeAddon.cs:27`）、`Dispose` 实际上没人调（`BridgeAddon.cs:19` 注释 `FIXME this isn't actually called anywhere lol`）。
- 需要从插件目录 `runtimes/win-x64/native/libnode.dll` 加载原生库（`NodeRuntime.cs:70-76`）；LibNode 用的是 Node 20 的 fork。

## 6. 还没读透的部分

- `js/reatkact/src/reconciler.ts` 的 host config 未细读（`appendChild` / `insertBefore` / `removeChild` 怎么映射到桥接的 `*Raw` 方法），只看了 `bridge.ts` 的属性下发部分。
- `bridge.ts` 的 diff 策略（`if (nextProps.x !== prevProps?.x)` 逐个比较）只扫了前 40 行，完整属性表未列。
- Node.js 侧异常/GC 在游戏 CABI 下的实际行为**未确认**（作者也只留了一句「pray」）。
- 仓库是浅克隆，无法确认 `LICENSE` 是从来没提交过、还是早期删掉了 → 许可结论按「当前 HEAD 没有」记。
