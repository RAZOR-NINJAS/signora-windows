using System.Diagnostics;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Signora.Windows.Services;
using Windows.Storage;
using Windows.Storage.Pickers;

namespace Signora.Windows.Pages;

public sealed partial class TrainPage : Page
{
    private bool _training;

    public TrainPage()
    {
        InitializeComponent();
        Loaded += (_, _) => RefreshDataInfo();
    }

    private void RefreshDataInfo()
    {
        DataPathText.Text = EnginePaths.DataSpatial;
        try
        {
            string[] files = Directory.Exists(EnginePaths.DataSpatial)
                ? Directory.GetFiles(EnginePaths.DataSpatial, "*.npy")
                : Array.Empty<string>();

            ClassCountText.Text = $"{files.Length} classes · model root {EnginePaths.Root}";
        }
        catch (Exception ex)
        {
            ClassCountText.Text = ex.Message;
        }
    }

    private void Refresh_Click(object sender, RoutedEventArgs e)
    {
        RefreshDataInfo();
    }

    private async void ImportButton_Click(object sender, RoutedEventArgs e)
    {
        if (App.RootWindow is null)
        {
            return;
        }

        var picker = new FolderPicker
        {
            SuggestedStartLocation = PickerLocationId.DocumentsLibrary,
        };
        picker.FileTypeFilter.Add("*");

        nint hwnd = WinRT.Interop.WindowNative.GetWindowHandle(App.RootWindow);
        WinRT.Interop.InitializeWithWindow.Initialize(picker, hwnd);

        StorageFolder? folder = await picker.PickSingleFolderAsync();
        if (folder is null)
        {
            return;
        }

        try
        {
            Directory.CreateDirectory(EnginePaths.DataSpatial);
            StorageFolder target = await StorageFolder.GetFolderFromPathAsync(EnginePaths.DataSpatial);

            int copied = 0;
            foreach (StorageFile file in await folder.GetFilesAsync())
            {
                if (!file.FileType.Equals(".npy", StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                await file.CopyAsync(target, file.Name, NameCollisionOption.ReplaceExisting);
                copied++;
            }

            AppendLog($"Imported {copied} .npy file(s) into {EnginePaths.DataSpatial}.");
            RefreshDataInfo();
        }
        catch (Exception ex)
        {
            AppendLog($"Import failed: {ex.Message}");
        }
    }

    private void OpenFolder_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Directory.CreateDirectory(EnginePaths.DataSpatial);
            Process.Start(new ProcessStartInfo
            {
                FileName = "explorer.exe",
                Arguments = $"\"{EnginePaths.DataSpatial}\"",
                UseShellExecute = true,
            });
        }
        catch (Exception ex)
        {
            AppendLog($"Could not open folder: {ex.Message}");
        }
    }

    private async void RetrainButton_Click(object sender, RoutedEventArgs e)
    {
        if (_training)
        {
            return;
        }

        _training = true;
        RetrainButton.IsEnabled = false;
        ImportButton.IsEnabled = false;
        TrainingRing.IsActive = true;
        TrainingStatusText.Text = "Training…";
        LogText.Text = "";

        var runner = new PythonRunner();
        runner.Output += line => DispatcherQueue.TryEnqueue(() => AppendLog(line));

        var arguments = new List<string> { "scripts/train_isl.py", "--spatial" };
        string exclude = ExcludeBox.Text.Trim();
        if (!string.IsNullOrWhiteSpace(exclude))
        {
            arguments.Add("--exclude");
            arguments.Add(exclude);
        }

        AppendLog($"Running: {EnginePaths.Python} {string.Join(' ', arguments)}");

        try
        {
            int exitCode = await runner.RunAsync(arguments);
            TrainingStatusText.Text = exitCode == 0 ? "Training complete" : $"Training failed ({exitCode})";
            AppendLog(exitCode == 0 ? "Training finished successfully." : $"Training exited with code {exitCode}.");
            RefreshDataInfo();
        }
        catch (Exception ex)
        {
            TrainingStatusText.Text = "Training failed";
            AppendLog(ex.Message);
        }
        finally
        {
            _training = false;
            RetrainButton.IsEnabled = true;
            ImportButton.IsEnabled = true;
            TrainingRing.IsActive = false;
        }
    }

    private void AppendLog(string line)
    {
        LogText.Text += line + Environment.NewLine;
        LogText.SelectionStart = LogText.Text.Length;
    }
}
