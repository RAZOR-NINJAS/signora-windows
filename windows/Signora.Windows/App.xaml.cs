using System.Runtime.InteropServices;
using Microsoft.UI.Xaml;

namespace Signora.Windows;

public partial class App : Application
{
    public static Window? RootWindow { get; private set; }

    public App()
    {
        AppDomain.CurrentDomain.UnhandledException += (_, e) =>
            Report(e.ExceptionObject as Exception, "AppDomain");

        UnhandledException += (_, e) => Report(e.Exception, "Xaml");

        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        try
        {
            RootWindow = new MainWindow();
            RootWindow.Activate();
        }
        catch (Exception ex)
        {
            Report(ex, "Launch");
            throw;
        }
    }

    private static void Report(Exception? ex, string source)
    {
        if (ex is null)
        {
            return;
        }

        string directory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Signora");
        string path = Path.Combine(directory, "startup-error.log");

        try
        {
            Directory.CreateDirectory(directory);
            File.AppendAllText(
                path,
                $"[{DateTimeOffset.Now:O}] {source}{Environment.NewLine}{ex}{Environment.NewLine}{Environment.NewLine}");
        }
        catch
        {
            // Nothing useful to do if the log cannot be written.
        }

        try
        {
            MessageBoxW(IntPtr.Zero, $"{source}: {ex.Message}{Environment.NewLine}{Environment.NewLine}{path}", "Signora", 0x10);
        }
        catch
        {
            // No window station available.
        }
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int MessageBoxW(IntPtr hWnd, string text, string caption, uint type);
}
