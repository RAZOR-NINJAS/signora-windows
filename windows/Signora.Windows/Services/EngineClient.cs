using System.Diagnostics;
using System.Net.Http.Json;
using Signora.Windows.Models;

namespace Signora.Windows.Services;

/// <summary>
/// Owns the local Python engine process and consumes its MJPEG/status API.
/// The frontend never touches the camera directly, so MediaPipe and the model
/// stay in one process while the UI renders a native overlay.
/// </summary>
public sealed class EngineClient : IAsyncDisposable
{
    private readonly HttpClient _http = new()
    {
        Timeout = Timeout.InfiniteTimeSpan,
    };

    private readonly SettingsStore _settings;
    private readonly int _port;

    private Process? _process;
    private CancellationTokenSource? _cts;
    private Task? _videoTask;
    private Task? _statusTask;

    /// <summary>Most recent engine output line, for surfacing failures in the UI.</summary>
    public string LastLog { get; private set; } = "";

    private static readonly object LogGate = new();
    private static readonly string LogFile = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Signora",
        "engine.log");

    public EngineClient(SettingsStore settings, int port = 8899)
    {
        _settings = settings;
        _port = port;
    }

    public event Action<byte[]>? FrameReady;
    public event Action<EngineStatus>? StatusChanged;
    public event Action<string>? Log;

    public bool IsRunning
    {
        get
        {
            try
            {
                return _process is { HasExited: false };
            }
            catch
            {
                return false;
            }
        }
    }

    public string BaseUrl => $"http://127.0.0.1:{_port}";

    public async Task<bool> StartAsync(string mode, CancellationToken ct = default)
    {
        if (IsRunning)
        {
            await StopAsync();
        }

        if (!File.Exists(EnginePaths.Python) && Path.IsPathRooted(EnginePaths.Python))
        {
            Record($"Python engine not found: {EnginePaths.Python}");
            return false;
        }

        _cts = new CancellationTokenSource();

        LastLog = "";
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(LogFile)!);
            File.WriteAllText(LogFile, "");
        }
        catch
        {
            // Logging is diagnostic only; never block startup on it.
        }

        var psi = new ProcessStartInfo
        {
            FileName = EnginePaths.Python,
            WorkingDirectory = EnginePaths.Root,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };

        psi.ArgumentList.Add("-m");
        psi.ArgumentList.Add("signora.cli");
        psi.ArgumentList.Add("native");
        psi.ArgumentList.Add("--mode");
        psi.ArgumentList.Add(mode);
        psi.ArgumentList.Add("--source");
        psi.ArgumentList.Add(_settings.Data.CameraIndex.ToString());
        psi.ArgumentList.Add("--port");
        psi.ArgumentList.Add(_port.ToString());
        psi.ArgumentList.Add("--dwell");
        psi.ArgumentList.Add(_settings.Data.DwellMs.ToString());
        psi.ArgumentList.Add("--threshold");
        psi.ArgumentList.Add(_settings.Data.Threshold.ToString("0.00", System.Globalization.CultureInfo.InvariantCulture));

        if (!_settings.Data.Tts)
        {
            psi.ArgumentList.Add("--no-tts");
        }

        if (!_settings.Data.Mirror)
        {
            psi.ArgumentList.Add("--no-mirror");
        }

        psi.Environment["PYTHONPATH"] = EnginePaths.Src;
        psi.Environment["PYTHONUTF8"] = "1";
        psi.Environment["SIGNORA_QUALITY"] = _settings.Data.Quality;

        _process = new Process
        {
            StartInfo = psi,
            EnableRaisingEvents = true,
        };
        _process.OutputDataReceived += (_, e) =>
        {
            if (!string.IsNullOrWhiteSpace(e.Data))
            {
                Record(e.Data);
            }
        };
        _process.ErrorDataReceived += (_, e) =>
        {
            if (!string.IsNullOrWhiteSpace(e.Data))
            {
                Record(e.Data);
            }
        };
        _process.Exited += (_, _) => Record("Engine process exited.");

        try
        {
            if (!_process.Start())
            {
                Record("Could not start the Python engine.");
                ResetProcess();
                return false;
            }
        }
        catch (Exception ex)
        {
            Record($"Could not start the Python engine: {ex.Message}");
            ResetProcess();
            return false;
        }

        _process.BeginOutputReadLine();
        _process.BeginErrorReadLine();

        for (int attempt = 0; attempt < 240; attempt++)
        {
            if (ct.IsCancellationRequested)
            {
                await StopAsync();
                return false;
            }

            Process? process = _process;
            CancellationTokenSource? cts = _cts;
            if (process is null || cts is null || cts.IsCancellationRequested)
            {
                return false;
            }

            bool exited;
            try
            {
                exited = process.HasExited;
            }
            catch
            {
                return false;
            }

            if (exited)
            {
                Record($"Engine exited during startup (code {process.ExitCode}).");
                await StopAsync();
                return false;
            }

            try
            {
                // Bound each probe: a half-open socket must not stall startup.
                using var probe = CancellationTokenSource.CreateLinkedTokenSource(ct);
                probe.CancelAfter(TimeSpan.FromSeconds(3));
                using var response = await _http.GetAsync($"{BaseUrl}/api/health", probe.Token);
                if (response.IsSuccessStatusCode)
                {
                    CancellationToken token = cts.Token;
                    _videoTask = Task.Run(() => ReadVideoAsync(token), CancellationToken.None);
                    _statusTask = Task.Run(() => PollStatusAsync(token), CancellationToken.None);
                    return true;
                }
            }
            catch
            {
                // Engine still booting.
            }

            try
            {
                await Task.Delay(250, ct);
            }
            catch (OperationCanceledException)
            {
                await StopAsync();
                return false;
            }
        }

        Record("Engine did not become ready in time.");
        await StopAsync();
        return false;
    }

    private void Record(string line)
    {
        LastLog = line;
        try
        {
            lock (LogGate)
            {
                File.AppendAllText(LogFile, $"[{DateTimeOffset.Now:HH:mm:ss}] {line}{Environment.NewLine}");
            }
        }
        catch
        {
            // Ignore log write failures.
        }

        Log?.Invoke(line);
    }

    private void ResetProcess()
    {
        _process?.Dispose();
        _process = null;
        _cts?.Dispose();
        _cts = null;
    }

    public async Task StopAsync()
    {
        try
        {
            _cts?.Cancel();
        }
        catch
        {
            // Ignore.
        }

        try
        {
            if (_process is { HasExited: false })
            {
                _process.Kill(entireProcessTree: true);
            }
        }
        catch
        {
            // Process may already be gone.
        }

        if (_videoTask is not null)
        {
            try { await _videoTask; } catch { /* Ignore. */ }
            _videoTask = null;
        }

        if (_statusTask is not null)
        {
            try { await _statusTask; } catch { /* Ignore. */ }
            _statusTask = null;
        }

        _process?.Dispose();
        _process = null;

        _cts?.Dispose();
        _cts = null;
    }

    public async Task SendCommandAsync(object command, CancellationToken ct = default)
    {
        if (!IsRunning)
        {
            return;
        }

        try
        {
            using var response = await _http.PostAsJsonAsync($"{BaseUrl}/api/command", command, ct);
            response.EnsureSuccessStatusCode();
        }
        catch (Exception ex)
        {
            Record($"Command failed: {ex.Message}");
        }
    }

    private async Task ReadVideoAsync(CancellationToken ct)
    {
        try
        {
            using var response = await _http.GetAsync(
                $"{BaseUrl}/video",
                HttpCompletionOption.ResponseHeadersRead,
                ct);
            response.EnsureSuccessStatusCode();

            await using Stream stream = await response.Content.ReadAsStreamAsync(ct);
            byte[] buffer = new byte[64 * 1024];
            using var frame = new MemoryStream(512 * 1024);

            int previous = -1;
            bool inFrame = false;

            while (!ct.IsCancellationRequested)
            {
                int read = await stream.ReadAsync(buffer, ct);
                if (read <= 0)
                {
                    break;
                }

                for (int i = 0; i < read; i++)
                {
                    byte b = buffer[i];

                    if (!inFrame)
                    {
                        if (previous == 0xFF && b == 0xD8)
                        {
                            frame.SetLength(0);
                            frame.WriteByte(0xFF);
                            frame.WriteByte(0xD8);
                            inFrame = true;
                        }
                    }
                    else
                    {
                        frame.WriteByte(b);
                        if (previous == 0xFF && b == 0xD9)
                        {
                            FrameReady?.Invoke(frame.ToArray());
                            inFrame = false;
                        }
                    }

                    previous = b;
                }
            }
        }
        catch (OperationCanceledException)
        {
            // Normal shutdown.
        }
        catch (Exception ex)
        {
            Record($"Video stream stopped: {ex.Message}");
        }
    }

    private async Task PollStatusAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            try
            {
                EngineStatus? status = await _http.GetFromJsonAsync<EngineStatus>(
                    $"{BaseUrl}/api/status",
                    ct);

                if (status is not null)
                {
                    StatusChanged?.Invoke(status);
                }
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch
            {
                // Engine restarting or transient socket issue.
            }

            try
            {
                await Task.Delay(100, ct);
            }
            catch
            {
                break;
            }
        }
    }

    public async ValueTask DisposeAsync()
    {
        await StopAsync();
        _http.Dispose();
    }
}
