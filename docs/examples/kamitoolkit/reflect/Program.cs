// 打印 KamiToolKit 里各控件的真实属性签名。
// 用法：dotnet run --project reflect.csproj
// 输出目录里要有 KamiToolKit.dll（由 csproj 的 PackageReference 负责复制）。

using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.Loader;

var baseDir = AppContext.BaseDirectory;
var dev = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
    @"XIVLauncherCN\addon\Hooks\dev");

// KamiToolKit 依赖 Dalamud / Lumina / FFXIVClientStructs，这些在 Dalamud dev 目录里，挂个解析器
AssemblyLoadContext.Default.Resolving += (ctx, name) =>
{
    foreach (var dir in new[] { baseDir, dev })
    {
        var candidate = Path.Combine(dir, name.Name + ".dll");
        if (File.Exists(candidate)) return ctx.LoadFromAssemblyPath(candidate);
    }

    return null;
};

var asm = Assembly.LoadFrom(Path.Combine(baseDir, "KamiToolKit.dll"));

Type[] types;
try
{
    types = asm.GetTypes();
}
catch (ReflectionTypeLoadException ex)
{
    types = ex.Types.Where(t => t is not null).ToArray()!;
}

var focus = new[]
{
    "SliderNode", "CheckboxNode", "TextButtonNode", "TextInputNode", "TabBarNode",
    "StringDropDownNode", "TextNode", "EnumDropDownNode`1", "VerticalListNode", "ScrollingAreaNode`1",
};

var interestingNames = new[]
{
    "Value", "Min", "Max", "Step", "OnValueChanged", "IsChecked", "OnClick", "String",
    "Options", "SelectedOption", "OnOptionSelected", "MaxListOptions", "MaxCharacters",
    "FontSize", "PlaceholderString", "FitContents", "ContentHeight", "ScrollSpeed", "AddTab",
};

foreach (var name in focus)
{
    var type = types.FirstOrDefault(x => x.Name == name);
    if (type is null)
    {
        Console.WriteLine($"== {name} 未找到");
        continue;
    }

    Console.WriteLine($"== {type.FullName} : {type.BaseType?.Name}");

    foreach (var property in type.GetProperties(BindingFlags.Public | BindingFlags.Instance)
                 .Where(p => interestingNames.Contains(p.Name))
                 .OrderBy(p => p.Name))
    {
        Console.WriteLine($"  P {property.PropertyType} {property.Name}");
    }

    foreach (var method in type.GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly)
                 .Where(m => interestingNames.Contains(m.Name))
                 .OrderBy(m => m.Name))
    {
        Console.WriteLine($"  M {method.Name}({string.Join(", ", method.GetParameters().Select(p => p.ParameterType.Name + " " + p.Name))})");
    }
}
