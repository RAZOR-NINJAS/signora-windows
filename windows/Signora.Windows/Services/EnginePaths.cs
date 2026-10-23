namespace Signora.Windows.Services;

/// <summary>
/// Resolves the Python engine and data locations for both a repo checkout and a
/// stock-machine install under %LOCALAPPDATA%\Signora.
/// </summary>
public static class EnginePaths
{
    public static string Root { get; } = ResolveRoot();
    public static string Python { get; } = ResolvePython(Root);
    public static string DataSpatial => Path.Combine(Root, "data", "isl_spatial");
    public static string Scripts => Path.Combine(Root, "scripts");
    public static string Src => Path.Combine(Root, "src");

    private static string ResolveRoot()
    {
        string? env = Environment.GetEnvironmentVariable("SIGNORA_ROOT");
        if (!string.IsNullOrWhiteSpace(env) && Directory.Exists(env))
        {
            return env;
        }

        string marker = Path.Combine(AppContext.BaseDirectory, "signora-root.txt");
        if (File.Exists(marker))
        {
            string saved = File.ReadAllText(marker).Trim();
            if (!string.IsNullOrWhiteSpace(saved) && Directory.Exists(saved))
            {
                return saved;
            }
        }

        var starts = new[]
        {
            AppContext.BaseDirectory,
            Directory.GetCurrentDirectory(),
            Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Signora"),
        };

        foreach (string start in starts)
        {
            DirectoryInfo? dir = new(start);
            while (dir is not null)
            {
                if (File.Exists(Path.Combine(dir.FullName, "pyproject.toml")))
                {
                    return dir.FullName;
                }
                dir = dir.Parent;
            }
        }

        return AppContext.BaseDirectory;
    }

    private static string ResolvePython(string root)
    {
        string? env = Environment.GetEnvironmentVariable("SIGNORA_PYTHON");
        if (!string.IsNullOrWhiteSpace(env) && File.Exists(env))
        {
            return env;
        }

        var candidates = new[]
        {
            Path.Combine(root, ".venv", "Scripts", "python.exe"),
            Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Signora", ".venv", "Scripts", "python.exe"),
            Path.Combine(root, ".venv", "bin", "python"),
        };

        foreach (string candidate in candidates)
        {
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        return "python.exe";
    }
}
