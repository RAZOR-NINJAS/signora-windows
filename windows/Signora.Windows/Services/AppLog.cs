namespace Signora.Windows.Services;

/// <summary>
/// Append-only UI log for failures that would otherwise disappear silently
/// (navigation faults, page construction errors). Lives next to engine.log so a
/// single folder holds everything needed to diagnose a run.
/// </summary>
public static class AppLog
{
    private static readonly object Gate = new();

    private static string LogFile => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Signora",
        "ui.log");

    public static void Write(string source, Exception exception)
    {
        try
        {
            string directory = Path.GetDirectoryName(LogFile)!;
            Directory.CreateDirectory(directory);
            lock (Gate)
            {
                File.AppendAllText(
                    LogFile,
                    $"[{DateTimeOffset.Now:O}] {source}{Environment.NewLine}{exception}{Environment.NewLine}{Environment.NewLine}");
            }
        }
        catch
        {
            // Diagnostics must never take the app down.
        }
    }
}
