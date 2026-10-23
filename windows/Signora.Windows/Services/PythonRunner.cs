using System.Diagnostics;

namespace Signora.Windows.Services;

/// <summary>
/// Runs short-lived Python maintenance tasks (training, imports) while streaming
/// their output into the native UI instead of opening a console window.
/// </summary>
public sealed class PythonRunner
{
    public event Action<string>? Output;

    public async Task<int> RunAsync(
        IEnumerable<string> arguments,
        CancellationToken ct = default)
    {
        var psi = new ProcessStartInfo
        {
            FileName = EnginePaths.Python,
            WorkingDirectory = EnginePaths.Root,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };

        foreach (string argument in arguments)
        {
            psi.ArgumentList.Add(argument);
        }

        psi.Environment["PYTHONPATH"] = EnginePaths.Src;
        psi.Environment["PYTHONUTF8"] = "1";

        using var process = new Process
        {
            StartInfo = psi,
            EnableRaisingEvents = true,
        };

        process.OutputDataReceived += (_, e) =>
        {
            if (!string.IsNullOrWhiteSpace(e.Data))
            {
                Output?.Invoke(e.Data);
            }
        };
        process.ErrorDataReceived += (_, e) =>
        {
            if (!string.IsNullOrWhiteSpace(e.Data))
            {
                Output?.Invoke(e.Data);
            }
        };

        try
        {
            if (!process.Start())
            {
                Output?.Invoke("Could not start Python.");
                return -1;
            }
        }
        catch (Exception ex)
        {
            Output?.Invoke($"Could not start Python: {ex.Message}");
            return -1;
        }

        process.BeginOutputReadLine();
        process.BeginErrorReadLine();

        try
        {
            await process.WaitForExitAsync(ct);
        }
        catch (OperationCanceledException)
        {
            try { process.Kill(entireProcessTree: true); } catch { /* Ignore. */ }
            return -1;
        }

        return process.ExitCode;
    }
}
