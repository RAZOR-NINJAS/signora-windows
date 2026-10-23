using Microsoft.UI.Xaml;

namespace Signora.Windows;

public partial class App : Application
{
    public static Window? RootWindow { get; private set; }

    public App()
    {
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        RootWindow = new MainWindow();
        RootWindow.Activate();
    }
}
