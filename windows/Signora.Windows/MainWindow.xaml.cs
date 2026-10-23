using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Signora.Windows.Pages;
using Signora.Windows.Services;

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
            NavigateTo("live");
        }
    }

    private void Nav_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.SelectedItem is NavigationViewItem item)
        {
            NavigateTo(item.Tag?.ToString());
        }
    }

    private void Nav_ItemInvoked(NavigationView sender, NavigationViewItemInvokedEventArgs args)
    {
        if (args.InvokedItemContainer is NavigationViewItem item)
        {
            NavigateTo(item.Tag?.ToString());
        }
    }

    private void NavigateTo(string? tag)
    {
        Type page = tag switch
        {
            "train" => typeof(TrainPage),
            "settings" => typeof(SettingsPage),
            _ => typeof(LivePage),
        };

        if (ContentFrame.CurrentSourcePageType == page)
        {
            return;
        }

        try
        {
            ContentFrame.Navigate(page);
        }
        catch (Exception ex)
        {
            // A broken page must not take the whole window down; log and stay put.
            AppLog.Write($"navigate:{page.Name}", ex);
        }
    }
}
