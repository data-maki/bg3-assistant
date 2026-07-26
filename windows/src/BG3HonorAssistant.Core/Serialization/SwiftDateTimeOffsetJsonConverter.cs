using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace BG3HonorAssistant.Core.Serialization;

/// <summary>
/// Swift's default JSONEncoder/JSONDecoder representation for Date is a
/// floating-point count of seconds from 2001-01-01T00:00:00Z. ISO text is
/// accepted as a defensive Windows migration input, while writes preserve the
/// Swift representation used by the macOS behavioral oracle.
/// </summary>
public sealed class SwiftDateTimeOffsetJsonConverter : JsonConverter<DateTimeOffset>
{
    private static readonly DateTimeOffset ReferenceDate =
        new(2001, 1, 1, 0, 0, 0, TimeSpan.Zero);

    public override DateTimeOffset Read(
        ref Utf8JsonReader reader,
        Type typeToConvert,
        JsonSerializerOptions options)
    {
        _ = typeToConvert;
        _ = options;
        if (reader.TokenType == JsonTokenType.Number)
        {
            var seconds = reader.GetDouble();
            if (!double.IsFinite(seconds))
            {
                throw new JsonException("A Swift date must be finite.");
            }

            try
            {
                return ReferenceDate.AddSeconds(seconds);
            }
            catch (ArgumentOutOfRangeException exception)
            {
                throw new JsonException(
                    "A Swift date was outside the supported range.",
                    exception);
            }
        }

        if (reader.TokenType == JsonTokenType.String &&
            DateTimeOffset.TryParse(
                reader.GetString(),
                CultureInfo.InvariantCulture,
                DateTimeStyles.RoundtripKind,
                out var parsed))
        {
            return parsed;
        }

        throw new JsonException(
            "Expected a Swift reference-date number or ISO-8601 timestamp.");
    }

    public override void Write(
        Utf8JsonWriter writer,
        DateTimeOffset value,
        JsonSerializerOptions options)
    {
        _ = options;
        writer.WriteNumberValue(
            (value.ToUniversalTime() - ReferenceDate).TotalSeconds);
    }
}
