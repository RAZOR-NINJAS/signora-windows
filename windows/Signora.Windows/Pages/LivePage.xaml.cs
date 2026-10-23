using System.Diagnostics;
using System.Numerics;
using Microsoft.Graphics.Canvas;
using Microsoft.Graphics.Canvas.UI.Xaml;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Signora.Windows.Models;
using Signora.Windows.Services;
using Windows.Foundation;
using Windows.Storage.Streams;
using Windows.UI;

namespace Signora.Windows.Pages;

public sealed partial class LivePage : Page
{
    private static readonly (int A, int B)[] HandConnections =
    {
        (0, 1), (1, 2), (2, 3), (3, 4),
        (0, 5), (5, 6), (6, 7), (7, 8),
        (5, 9), (9, 10), (10, 11), (11, 12),
        (9, 13), (13, 14), (14, 15), (15, 16),
        (13, 17), (17, 18), (18, 19), (19, 20),
        (0, 17),
    };

    private static readonly (int A, int B)[] PoseConnections =
    {
        (11, 12), (11, 13), (13, 15), (12, 14), (14, 16),
        (11, 23), (12, 24), (23, 24),
        (23, 25), (25, 27), (24, 26), (26, 28),
        (27, 29), (29, 31), (28, 30), (30, 32),
    };

    private readonly SettingsStore _settings = new();
    private readonly EngineClient _engine;
    private readonly SemaphoreSlim _decodeLock = new(1, 1);

    private CanvasBitmap? _frame;
    private byte[]? _pendingFrame;
    private EngineStatus? _lastStatus;
    private bool _loaded;
    private bool _starting;
    private bool _suppressModeChange;

    private static readonly string EngineLogPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Signora",
        "engine.log");

    public LivePage()
    {
        InitializeComponent();

        _engine = new EngineClient(_settings);
        _engine.FrameReady += OnFrameReady;
        _engine.StatusChanged += OnStatusChanged;
        _engine.Log += OnEngineLog;
        _engine.EngineExited += OnEngineExited;

        Loaded += LivePage_Loaded;
        Unloaded += LivePage_Unloaded;
    }

    private async void LivePage_Loaded(object sender, RoutedEventArgs e)
    {
        if (_loaded)
        {
            return;
        }

        _loaded = true;
        _suppressModeChange = true;
        ModeBox.SelectedIndex = _settings.Data.Mode switch
        {
            "asl" => 1,
            "body" => 2,
            _ => 0,
        };
        _suppressModeChange = false;

        await StartEngineAsync();
    }

    private async void LivePage_Unloaded(object sender, RoutedEventArgs e)
    {
        _engine.FrameReady -= OnFrameReady;
        _engine.StatusChanged -= OnStatusChanged;
        _engine.Log -= OnEngineLog;
        _engine.EngineExited -= OnEngineExited;

        await _engine.DisposeAsync();

        _frame?.Dispose();
        _frame = null;

        VideoCanvas.RemoveFromVisualTree();
    }

    private async Task StartEngineAsync()
    {
        if (_starting)
        {
            return;
        }

        _starting = true;
        StartStopButton.IsEnabled = false;
        WaitingPanel.Visibility = Visibility.Visible;
        WaitingText.Text = "Starting Signora engine and opening the camera...";

        try
        {
            string mode = (ModeBox.SelectedItem as ComboBoxItem)?.Tag?.ToString() ?? "isl";
            _settings.Data.Mode = mode;
            _settings.Save();

            bool started = false;
            try
            {
                started = await _engine.StartAsync(mode);
            }
            catch (Exception ex)
            {
                WaitingText.Text = $"Engine error: {ex.Message}";
            }

            if (started)
            {
                WaitingPanel.Visibility = Visibility.Collapsed;
                StartStopButton.Content = "Stop";
            }
            else
            {
                string detail = string.IsNullOrWhiteSpace(_engine.LastLog)
                    ? "Engine failed to start. Run Pixel-Install.cmd again."
                    : $"Engine: {_engine.LastLog}";
                WaitingText.Text =
                    $"{detail}{Environment.NewLine}{Environment.NewLine}" +
                    $"Camera index {_settings.Data.CameraIndex} did not work. " +
                    $"Open Settings and try 1, 2 or 3.{Environment.NewLine}" +
                    $"Log: {EngineLogPath}";
                StartStopButton.Content = "Start";
            }
        }
        finally
        {
            _starting = false;
            StartStopButton.IsEnabled = true;
        }
    }

    private async Task StopEngineAsync()
    {
        try
        {
            await _engine.StopAsync();
        }
        catch (Exception ex)
        {
            Debug.WriteLine(ex);
        }

        WaitingPanel.Visibility = Visibility.Visible;
        WaitingText.Text = "Engine stopped.";
        StartStopButton.Content = "Start";
        TranscriptText.Text = "";
        SignText.Text = "—";
        ConfidenceBar.Value = 0;
        DwellBar.Value = 0;
        FpsText.Text = "0 fps";
    }

    private async void StartStopButton_Click(object sender, RoutedEventArgs e)
    {
        if (_engine.IsRunning)
        {
            await StopEngineAsync();
        }
        else
        {
            await StartEngineAsync();
        }
    }

    private async void ModeBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_loaded || _suppressModeChange)
        {
            return;
        }

        if (_engine.IsRunning)
        {
            await _engine.StopAsync();
        }

        await StartEngineAsync();
    }

    private void OnFrameReady(byte[] jpeg)
    {
        _pendingFrame = jpeg;
        DispatcherQueue.TryEnqueue(() => _ = DecodePendingFrameAsync());
    }

    private async Task DecodePendingFrameAsync()
    {
        byte[]? jpeg = Interlocked.Exchange(ref _pendingFrame, null);
        if (jpeg is null || !VideoCanvas.ReadyToDraw)
        {
            return;
        }

        if (!await _decodeLock.WaitAsync(0))
        {
            return;
        }

        try
        {
            using var stream = new InMemoryRandomAccessStream();
            using (var writer = new DataWriter(stream.GetOutputStreamAt(0)))
            {
                writer.WriteBytes(jpeg);
                await writer.StoreAsync();
                await writer.FlushAsync();
                writer.DetachStream();
            }

            stream.Seek(0);
            CanvasBitmap bitmap = await CanvasBitmap.LoadAsync(VideoCanvas, stream);

            CanvasBitmap? old = _frame;
            _frame = bitmap;
            old?.Dispose();

            VideoCanvas.Invalidate();
        }
        catch (Exception ex)
        {
            Debug.WriteLine(ex);
        }
        finally
        {
            _decodeLock.Release();
        }
    }

    private void OnStatusChanged(EngineStatus status)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            _lastStatus = status;

            TranscriptText.Text = status.Transcript;
            SignText.Text = string.IsNullOrWhiteSpace(status.ActiveSign) ? "—" : status.ActiveSign;
            ConfidenceBar.Value = status.Confidence;
            DwellBar.Value = status.Dwell;
            FpsText.Text = $"{status.Fps:0.0} fps";
            DwellText.Text = status.Dwell > 0
                ? $"Hold {status.Dwell * 100:0}%"
                : "Hold to confirm";
            EngineStatusText.Text =
                $"{status.Status} · {status.Delegate} · {status.Quality}";

            VideoCanvas.Invalidate();
        });
    }

    private void OnEngineLog(string message)
    {
        Debug.WriteLine(message);
        if (_lastStatus is null)
        {
            DispatcherQueue.TryEnqueue(() => EngineStatusText.Text = message);
        }
    }

    private void OnEngineExited()
    {
        // The engine can die long after StartAsync returned (camera unplugged,
        // device claimed by another app). Surface it instead of freezing on the
        // last frame with no explanation.
        DispatcherQueue.TryEnqueue(() =>
        {
            StartStopButton.Content = "Start";
            StartStopButton.IsEnabled = true;
            WaitingPanel.Visibility = Visibility.Visible;

            string detail = string.IsNullOrWhiteSpace(_engine.LastLog)
                ? "The engine stopped unexpectedly."
                : _engine.LastLog;
            WaitingText.Text =
                $"{detail}{Environment.NewLine}{Environment.NewLine}" +
                $"Press Start to retry.{Environment.NewLine}Log: {EngineLogPath}";

            TranscriptText.Text = "";
            SignText.Text = "—";
            ConfidenceBar.Value = 0;
            DwellBar.Value = 0;
            FpsText.Text = "0 fps";
        });
    }

    private async void Space_Click(object sender, RoutedEventArgs e)
    {
        await _engine.SendCommandAsync(new { action = "space" });
    }

    private async void Backspace_Click(object sender, RoutedEventArgs e)
    {
        await _engine.SendCommandAsync(new { action = "backspace" });
    }

    private async void Clear_Click(object sender, RoutedEventArgs e)
    {
        await _engine.SendCommandAsync(new { action = "clear" });
    }

    private async void Speak_Click(object sender, RoutedEventArgs e)
    {
        await _engine.SendCommandAsync(new { action = "speak" });
    }

    private void VideoCanvas_Draw(CanvasControl sender, CanvasDrawEventArgs args)
    {
        CanvasDrawingSession ds = args.DrawingSession;
        ds.Clear(Color.FromArgb(255, 11, 15, 25));

        double width = sender.ActualWidth;
        double height = sender.ActualHeight;

        if (_frame is null)
        {
            ds.DrawText("Waiting for camera…", 24f, 24f, Color.FromArgb(255, 148, 163, 184));
            return;
        }

        double frameWidth = _frame.Size.Width;
        double frameHeight = _frame.Size.Height;
        double scale = Math.Min(width / frameWidth, height / frameHeight);
        double drawWidth = frameWidth * scale;
        double drawHeight = frameHeight * scale;
        double x = (width - drawWidth) / 2.0;
        double y = (height - drawHeight) / 2.0;

        var destination = new Rect(x, y, drawWidth, drawHeight);
        var source = new Rect(0, 0, frameWidth, frameHeight);
        ds.DrawImage(_frame, destination, source);

        DrawOverlay(ds, _lastStatus, x, y, drawWidth, drawHeight);
    }

    private static void DrawOverlay(
        CanvasDrawingSession ds,
        EngineStatus? status,
        double x,
        double y,
        double width,
        double height)
    {
        if (status is null)
        {
            return;
        }

        if (status.Mode == "body" && status.Pose is { Count: >= 25 })
        {
            Color poseColor = Color.FromArgb(150, 56, 189, 248);

            foreach ((int a, int b) in PoseConnections)
            {
                if (a >= status.Pose.Count || b >= status.Pose.Count)
                {
                    continue;
                }

                ds.DrawLine(
                    ToScreen(status.Pose[a], x, y, width, height),
                    ToScreen(status.Pose[b], x, y, width, height),
                    poseColor,
                    2f);
            }

            foreach (int index in new[] { 0, 11, 12, 13, 14, 15, 16, 23, 24 })
            {
                if (index >= status.Pose.Count)
                {
                    continue;
                }

                ds.FillCircle(
                    ToScreen(status.Pose[index], x, y, width, height),
                    3.5f,
                    poseColor);
            }
        }

        foreach (HandData hand in status.Hands)
        {
            if (hand.Points.Count < 21)
            {
                continue;
            }

            Color handColor = hand.Handedness.Equals("Left", StringComparison.OrdinalIgnoreCase)
                ? Color.FromArgb(255, 244, 114, 182)
                : Color.FromArgb(255, 52, 211, 153);

            foreach ((int a, int b) in HandConnections)
            {
                if (a >= hand.Points.Count || b >= hand.Points.Count)
                {
                    continue;
                }

                ds.DrawLine(
                    ToScreen(hand.Points[a], x, y, width, height),
                    ToScreen(hand.Points[b], x, y, width, height),
                    handColor,
                    2.5f);
            }

            for (int i = 0; i < hand.Points.Count; i++)
            {
                float radius = i is 4 or 8 or 12 or 16 or 20 ? 4.5f : 2.5f;
                ds.FillCircle(
                    ToScreen(hand.Points[i], x, y, width, height),
                    radius,
                    handColor);
            }
        }
    }

    private static Vector2 ToScreen(Point3D point, double x, double y, double width, double height)
    {
        return new Vector2(
            (float)(x + point.X * width),
            (float)(y + point.Y * height));
    }
}
