using System.Text.Json.Serialization;

namespace Signora.Windows.Models;

public sealed class Point3D
{
    [JsonPropertyName("x")] public double X { get; set; }
    [JsonPropertyName("y")] public double Y { get; set; }
    [JsonPropertyName("z")] public double Z { get; set; }
}

public sealed class HandData
{
    [JsonPropertyName("handedness")] public string Handedness { get; set; } = "Right";
    [JsonPropertyName("points")] public List<Point3D> Points { get; set; } = new();
}

public sealed class EngineStatus
{
    [JsonPropertyName("mode")] public string Mode { get; set; } = "isl";
    [JsonPropertyName("active_sign")] public string ActiveSign { get; set; } = "";
    [JsonPropertyName("confidence")] public double Confidence { get; set; }
    [JsonPropertyName("dwell")] public double Dwell { get; set; }
    [JsonPropertyName("transcript")] public string Transcript { get; set; } = "";
    [JsonPropertyName("sentence")] public string Sentence { get; set; } = "";
    [JsonPropertyName("fps")] public double Fps { get; set; }
    [JsonPropertyName("hands")] public List<HandData> Hands { get; set; } = new();
    [JsonPropertyName("pose")] public List<Point3D>? Pose { get; set; }
    [JsonPropertyName("anchor")] public string Anchor { get; set; } = "OPEN_SPACE";
    [JsonPropertyName("status")] public string Status { get; set; } = "idle";
    [JsonPropertyName("delegate")] public string Delegate { get; set; } = "";
    [JsonPropertyName("paused")] public bool Paused { get; set; }
    [JsonPropertyName("quality")] public string Quality { get; set; } = "high";
}
