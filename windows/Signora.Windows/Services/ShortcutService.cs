using System.Runtime.InteropServices;

namespace Signora.Windows.Services;

/// <summary>
/// Keeps the Start Menu and desktop shortcuts pointing at the running build.
///
/// The installer creates these, but a moved folder, a skipped shortcut step, or
/// an old install left a stale or missing entry. Re-registering from the app
/// itself means one successful launch is enough to repair the Start Menu.
/// </summary>
public static class ShortcutService
{
    public static void Ensure()
    {
        try
        {
            string exe = Environment.ProcessPath ?? Path.Combine(
                AppContext.BaseDirectory,
                "Signora.Windows.exe");

            if (!File.Exists(exe))
            {
                return;
            }

            string appDir = Path.GetDirectoryName(exe) ?? AppContext.BaseDirectory;

            string programs = Environment.GetFolderPath(Environment.SpecialFolder.Programs);
            if (!string.IsNullOrWhiteSpace(programs))
            {
                Directory.CreateDirectory(programs);
                EnsureShortcut(Path.Combine(programs, "Signora.lnk"), exe, appDir);
            }

            string desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
            if (!string.IsNullOrWhiteSpace(desktop) && Directory.Exists(desktop))
            {
                EnsureShortcut(Path.Combine(desktop, "Signora.lnk"), exe, appDir);
            }
        }
        catch (Exception ex)
        {
            // Shortcut repair is best-effort; never block startup on it.
            AppLog.Write("shortcut", ex);
        }
    }

    private static void EnsureShortcut(string path, string exe, string workingDirectory)
    {
        object? shell = null;
        try
        {
            Type? shellType = Type.GetTypeFromProgID("WScript.Shell");
            if (shellType is null)
            {
                return;
            }

            shell = Activator.CreateInstance(shellType);
            if (shell is null)
            {
                return;
            }

            dynamic wsh = shell;
            dynamic shortcut = wsh.CreateShortcut(path);

            if (File.Exists(path))
            {
                object? rawTarget = shortcut.TargetPath;
                object? rawWorkdir = shortcut.WorkingDirectory;
                string? target = rawTarget as string;
                string? workdir = rawWorkdir as string;
                if (string.Equals(target, exe, StringComparison.OrdinalIgnoreCase) &&
                    string.Equals(workdir, workingDirectory, StringComparison.OrdinalIgnoreCase))
                {
                    return;
                }
            }

            shortcut.TargetPath = exe;
            shortcut.WorkingDirectory = workingDirectory;
            shortcut.IconLocation = $"{exe},0";
            shortcut.Description = "Signora - Offline Sign Language Recognition";
            shortcut.Save();
        }
        finally
        {
            if (shell is not null && Marshal.IsComObject(shell))
            {
                Marshal.ReleaseComObject(shell);
            }
        }
    }
}
