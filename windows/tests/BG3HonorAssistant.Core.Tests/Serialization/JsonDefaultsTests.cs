using System.Text.Json;
using BG3HonorAssistant.Core.Models;
using BG3HonorAssistant.Core.Serialization;

namespace BG3HonorAssistant.Core.Tests.Serialization;

public sealed class JsonDefaultsTests
{
    [Fact]
    public void UsesSwiftCompatibleCamelCaseEnumValues()
    {
        var json = JsonSerializer.Serialize(
            CheckpointDisposition.CaughtUp,
            JsonDefaults.Create());

        Assert.Equal("\"caughtUp\"", json);
        Assert.Equal(
            CheckpointDisposition.CaughtUp,
            JsonSerializer.Deserialize<CheckpointDisposition>(json, JsonDefaults.Create()));
    }

    [Theory]
    [InlineData("0", "2001-01-01T00:00:00+00:00")]
    [InlineData("-978307200", "1970-01-01T00:00:00+00:00")]
    [InlineData("86400.5", "2001-01-02T00:00:00.5000000+00:00")]
    public void ReadsSwiftReferenceDateNumbers(string json, string expected)
    {
        var value = JsonSerializer.Deserialize<DateTimeOffset>(
            json,
            JsonDefaults.Create());

        Assert.Equal(DateTimeOffset.Parse(expected), value);
    }

    [Fact]
    public void WritesSwiftCompatibleReferenceDateNumber()
    {
        var value = new DateTimeOffset(
            2001,
            1,
            2,
            0,
            0,
            0,
            TimeSpan.Zero);

        Assert.Equal(
            "86400",
            JsonSerializer.Serialize(value, JsonDefaults.Create()));
    }

    [Fact]
    public void AcceptsIsoDateAsDefensiveWindowsMigrationInput()
    {
        var value = JsonSerializer.Deserialize<DateTimeOffset>(
            "\"2026-07-25T19:30:00-07:00\"",
            JsonDefaults.Create());

        Assert.Equal(
            new DateTimeOffset(
                2026,
                7,
                25,
                19,
                30,
                0,
                TimeSpan.FromHours(-7)),
            value);
    }
}
