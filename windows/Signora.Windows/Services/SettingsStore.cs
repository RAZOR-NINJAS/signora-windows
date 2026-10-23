using System.Text.Json;

namespace Signora.Windows.Services;

public sealed class SettingsData
{
    public string Mode { get; set; } = "isl";
    public string Quality { get; set; } = "high";
    public int CameraIndex { get; set; }
    public bool Mirror { get; set; } = true;
    public bool Tts { get; set; } = true;
    public int DwellMs { get; set; } = 400;
    public double Threshold { get; set; } = 0.52;
}

/// <summary>
/// Portable per-user settings stored as JSON under %LOCALAPPDATA%\Signora.
/// Deliberately avoids ApplicationData so unpackaged builds behave identically.
/// </summary>
public sealed class SettingsStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
    };

    private readonly string _path;

    public SettingsData Data { get; private set; }

    public SettingsStore()
    {
        string dir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Signora");
        Directory.CreateDirectory(dir);
        _path = Path.Combine(dir, "settings.json");
        Data = Load();
    }

    public void Save()
    {
        try
        {
            File.WriteAllText(_path, JsonSerializer.Serialize(Data, JsonOptions));
        }
        catch
        {
            // Settings are best-effort; never block the UI.
        }
    }

    private SettingsData Load()
    {
        try
        {
            if (File.Exists(_path))
            {
                var loaded = JsonSerializer.Deserialize<SettingsData>(File.ReadAllText(_path));
                if (loaded is not null)
                {
                    return loaded;
                }
            }
        }
        catch
        {
            // Fall through to defaults.
        }

        return new SettingsData();
    }
}
