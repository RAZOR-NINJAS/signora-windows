using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Signora.Windows.Services;

namespace Signora.Windows.Pages;

public sealed partial class SettingsPage : Page
{
    private readonly SettingsStore _settings = new();
    private bool _loading;

    public SettingsPage()
    {
        InitializeComponent();
        Loaded += (_, _) =>
        {
            ApplyToControls();
            UpdatePaths();
        };
    }

    private void ApplyToControls()
    {
        _loading = true;

        ModeBox.SelectedIndex = _settings.Data.Mode switch
        {
            "asl" => 1,
            "body" => 2,
            _ => 0,
        };

        QualityBox.SelectedIndex = _settings.Data.Quality == "balanced" ? 1 : 0;
        CameraBox.Value = _settings.Data.CameraIndex;
        DwellSlider.Value = _settings.Data.DwellMs;
        ThresholdSlider.Value = _settings.Data.Threshold;
        MirrorSwitch.IsOn = _settings.Data.Mirror;
        TtsSwitch.IsOn = _settings.Data.Tts;

        _loading = false;
        UpdateValueLabels();
    }

    private void UpdatePaths()
    {
        EnginePathText.Text = $"Python: {EnginePaths.Python}";
        RootPathText.Text = $"Project root: {EnginePaths.Root}";
        DataPathText.Text = $"Spatial data: {EnginePaths.DataSpatial}";
    }

    private void UpdateValueLabels()
    {
        DwellValueText.Text = $"{DwellSlider.Value:0} ms";
        ThresholdValueText.Text = $"{ThresholdSlider.Value:0.00}";
    }

    private void Save()
    {
        if (_loading)
        {
            return;
        }

        _settings.Data.Mode = SelectedTag(ModeBox, "isl");
        _settings.Data.Quality = SelectedTag(QualityBox, "high");
        if (!double.IsNaN(CameraBox.Value))
        {
            _settings.Data.CameraIndex = (int)CameraBox.Value;
        }
        _settings.Data.DwellMs = (int)DwellSlider.Value;
        _settings.Data.Threshold = ThresholdSlider.Value;
        _settings.Data.Mirror = MirrorSwitch.IsOn;
        _settings.Data.Tts = TtsSwitch.IsOn;
        _settings.Save();

        UpdateValueLabels();
        SaveStatusText.Text = "Saved";
    }

    private static string SelectedTag(ComboBox box, string fallback)
    {
        return (box.SelectedItem as ComboBoxItem)?.Tag?.ToString() ?? fallback;
    }

    private void ModeBox_SelectionChanged(object sender, SelectionChangedEventArgs e) => Save();

    private void QualityBox_SelectionChanged(object sender, SelectionChangedEventArgs e) => Save();

    private void CameraBox_ValueChanged(NumberBox sender, NumberBoxValueChangedEventArgs args) => Save();

    private void DwellSlider_ValueChanged(object sender, RangeBaseValueChangedEventArgs e) => Save();

    private void ThresholdSlider_ValueChanged(object sender, RangeBaseValueChangedEventArgs e) => Save();

    private void MirrorSwitch_Toggled(object sender, RoutedEventArgs e) => Save();

    private void TtsSwitch_Toggled(object sender, RoutedEventArgs e) => Save();

    private void Reset_Click(object sender, RoutedEventArgs e)
    {
        _settings.Data.Mode = "isl";
        _settings.Data.Quality = "high";
        _settings.Data.CameraIndex = 0;
        _settings.Data.DwellMs = 400;
        _settings.Data.Threshold = 0.52;
        _settings.Data.Mirror = true;
        _settings.Data.Tts = true;
        _settings.Save();

        ApplyToControls();
        SaveStatusText.Text = "Reset to defaults";
    }
}
