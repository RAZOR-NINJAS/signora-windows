using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Signora.Windows.Pages;

namespace Signora.Windows;

public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        Title = "Signora";
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);

        // Mica only exists on Windows 11; on Windows 10 the assignment throws.
        if (MicaController.IsSupported())
        {
            SystemBackdrop = new MicaBackdrop();
        }

        Nav.SelectedItem = Nav.MenuItems[0];
        if (ContentFrame.CurrentSourcePageType is null)
        {
            ContentFrame.Navigate(typeof(LivePage));
        }
    }

    private void Nav_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.SelectedItem is not NavigationViewItem item)
        {
            return;
        }

        Type page = item.Tag switch
        {
            "train" => typeof(TrainPage),
            "settings" => typeof(SettingsPage),
            _ => typeof(LivePage),
        };

        if (ContentFrame.CurrentSourcePageType != page)
        {
            ContentFrame.Navigate(page);
        }
    }
}
