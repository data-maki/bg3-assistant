using BG3HonorAssistant.Infrastructure.Persistence;
using Microsoft.Data.Sqlite;

namespace BG3HonorAssistant.Infrastructure.Tests.Persistence;

public sealed class RunRepositoryTests : IDisposable
{
    private readonly string temporaryDirectory = Path.Combine(
        Path.GetTempPath(),
        "BG3HonorAssistant.Tests",
        Guid.NewGuid().ToString("N"));

    [Fact]
    public async Task SavesAndRestoresExactlyOneActiveRun()
    {
        var repository = CreateRepository();

        await repository.SaveAsync("run-a", "First", "guide-1", """{"id":"run-a","value":1}""");
        await repository.SaveAsync("run-b", "Second", "guide-1", """{"id":"run-b","value":2}""");

        var active = await repository.LoadActiveAsync();
        var all = await repository.ListAsync();

        Assert.NotNull(active);
        Assert.Equal("run-b", active.Id);
        Assert.Equal("""{"id":"run-b","value":2}""", active.SnapshotJson);
        Assert.Equal(2, all.Count);
        Assert.Single(all, run => run.IsActive);
    }

    [Fact]
    public async Task LoadsSwitchesAndDeletesRunsWithoutTouchingOtherSnapshots()
    {
        var repository = CreateRepository();
        await repository.SaveAsync(
            "run-a",
            "First",
            "guide-1",
            """{"id":"run-a","value":1}""");
        await repository.SaveAsync(
            "run-b",
            "Second",
            "guide-1",
            """{"id":"run-b","value":2}""");

        Assert.Equal("run-a", (await repository.LoadAsync("run-a"))?.Id);
        Assert.True(await repository.SetActiveAsync("run-a"));
        Assert.Equal("run-a", (await repository.LoadActiveAsync())?.Id);
        Assert.False(await repository.SetActiveAsync("missing"));
        Assert.Equal("run-a", (await repository.LoadActiveAsync())?.Id);

        Assert.True(await repository.SetActiveAsync("run-b"));
        Assert.True(await repository.DeleteAsync("run-a"));
        Assert.False(await repository.DeleteAsync("run-a"));
        Assert.Null(await repository.LoadAsync("run-a"));
        Assert.Equal("run-b", (await repository.LoadActiveAsync())?.Id);
    }

    [Fact]
    public async Task RetainsOnlyTwentyTransactionalRevisions()
    {
        var repository = CreateRepository();

        for (var revision = 1; revision <= 25; revision++)
        {
            await repository.SaveAsync(
                "run-a",
                "First",
                "guide-1",
                $$"""{"id":"run-a","revision":{{revision}}}""");
        }

        Assert.Equal(
            RunRepository.MaximumRevisionsPerRun,
            await repository.CountRevisionsAsync("run-a"));
        Assert.Contains(
            "\"revision\":25",
            (await repository.LoadActiveAsync())!.SnapshotJson,
            StringComparison.Ordinal);
    }

    [Fact]
    public async Task FallsBackToNewestValidRevisionWhenActiveSnapshotCannotDecode()
    {
        var repository = CreateRepository();
        await repository.SaveAsync(
            "run-a",
            "First",
            "guide-1",
            """{"id":"run-a","valid":true,"revision":1}""");
        await ReplaceActiveSnapshotAsync(
            repository.DatabasePath,
            """{"id":"run-a","valid":false}""");

        var recovered = await repository.LoadRecoverableActiveAsync(
            snapshot => snapshot.Contains("\"valid\":true", StringComparison.Ordinal));

        Assert.NotNull(recovered);
        Assert.Contains("\"revision\":1", recovered.SnapshotJson, StringComparison.Ordinal);
    }

    [Fact]
    public async Task PersistsJsonSettings()
    {
        var repository = CreateRepository();

        await repository.SetSettingAsync(
            "assistant",
            """{"overlayDensity":"focus","showWhileBg3Runs":true}""");

        Assert.Equal(
            """{"overlayDensity":"focus","showWhileBg3Runs":true}""",
            await repository.GetSettingAsync("assistant"));
    }

    [Fact]
    public async Task PersistsImportedBuildsInTheSameDatabase()
    {
        var repository = CreateRepository();
        const string buildJson =
            """{"id":"imported-monk","name":"Open Hand Monk","levels":[1,2,3]}""";

        await repository.SaveImportedBuildAsync(
            "imported-monk",
            "Open Hand Monk",
            buildJson);

        Assert.Equal(
            buildJson,
            await repository.GetImportedBuildJsonAsync("imported-monk"));
        Assert.Equal(
            [buildJson],
            await repository.ListImportedBuildJsonAsync());
        Assert.True(await repository.DeleteImportedBuildAsync("imported-monk"));
        Assert.Empty(await repository.ListImportedBuildJsonAsync());
        Assert.False(await repository.DeleteImportedBuildAsync("imported-monk"));
    }

    [Fact]
    public async Task MigratesVersionOneTransactionallyAndCreatesRecoveryCopy()
    {
        var repository = CreateRepository();
        await CreateVersionOneFixtureAsync(repository.DatabasePath, includeVersionTwoColumn: false);

        await repository.InitializeAsync();

        var active = await repository.LoadActiveAsync();
        var recoveryCopy = Assert.Single(repository.ListRecoveryCopies());
        Assert.Equal("legacy-run", active?.Id);
        Assert.True(File.Exists(recoveryCopy));
        Assert.Equal(1, await ReadSchemaVersionAsync(recoveryCopy));
        Assert.Equal(
            RunRepository.CurrentSchemaVersion,
            await ReadSchemaVersionAsync(repository.DatabasePath));
    }

    [Fact]
    public async Task FailedMigrationRollsBackAndLeavesRecoveryCopy()
    {
        var repository = CreateRepository();
        await CreateVersionOneFixtureAsync(repository.DatabasePath, includeVersionTwoColumn: true);

        await Assert.ThrowsAsync<SqliteException>(() => repository.InitializeAsync());

        var recoveryCopy = Assert.Single(repository.ListRecoveryCopies());
        Assert.Equal(1, await ReadSchemaVersionAsync(repository.DatabasePath));
        Assert.Equal(1, await ReadSchemaVersionAsync(recoveryCopy));
        Assert.Equal("legacy-run", await ReadOnlyRunIdAsync(repository.DatabasePath));
        Assert.Equal("legacy-run", await ReadOnlyRunIdAsync(recoveryCopy));
    }

    [Fact]
    public async Task CorruptDatabaseIsPreservedForExplicitRecovery()
    {
        var repository = CreateRepository();
        Directory.CreateDirectory(Path.GetDirectoryName(repository.DatabasePath)!);
        var corruptBytes = new byte[] { 0x42, 0x47, 0x33, 0x00, 0x7F, 0x01 };
        await File.WriteAllBytesAsync(repository.DatabasePath, corruptBytes);

        await Assert.ThrowsAsync<SqliteException>(() => repository.InitializeAsync());

        Assert.Equal(
            corruptBytes,
            await File.ReadAllBytesAsync(repository.DatabasePath));
        Assert.Empty(repository.ListRecoveryCopies());
    }

    [Fact]
    public async Task UsesPatchedSqliteBuild()
    {
        var repository = CreateRepository();

        var versionText = await repository.GetSqliteVersionAsync();
        var version = Version.Parse(versionText);

        Assert.True(
            version >= new Version(3, 50, 2),
            $"Expected SQLite 3.50.2 or newer, but loaded {version}.");
    }

    [Fact]
    public async Task RejectsInvalidSnapshotBeforeOpeningTransaction()
    {
        var repository = CreateRepository();

        await Assert.ThrowsAnyAsync<Exception>(() =>
            repository.SaveAsync("run-a", "First", "guide-1", "{invalid"));
        Assert.False(File.Exists(repository.DatabasePath));
    }

    public void Dispose()
    {
        if (Directory.Exists(temporaryDirectory))
        {
            Directory.Delete(temporaryDirectory, recursive: true);
        }

        GC.SuppressFinalize(this);
    }

    private RunRepository CreateRepository()
    {
        return new RunRepository(Path.Combine(temporaryDirectory, "state.sqlite3"));
    }

    private static async Task CreateVersionOneFixtureAsync(
        string databasePath,
        bool includeVersionTwoColumn)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(databasePath)!);
        await using var connection = new SqliteConnection(
            new SqliteConnectionStringBuilder
            {
                DataSource = databasePath,
                Mode = SqliteOpenMode.ReadWriteCreate,
                Pooling = false,
            }.ToString());
        await connection.OpenAsync();
        using var command = connection.CreateCommand();
        command.CommandText =
            $$"""
            CREATE TABLE schema_migrations(
                version INTEGER PRIMARY KEY,
                applied_at INTEGER NOT NULL
            );
            INSERT INTO schema_migrations(version, applied_at) VALUES(1, 0);
            CREATE TABLE runs(
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                guide_version TEXT NOT NULL,
                snapshot_json TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                is_active INTEGER NOT NULL DEFAULT 0
                {{(includeVersionTwoColumn ? ", last_opened_at INTEGER" : string.Empty)}}
            );
            INSERT INTO runs(
                id, name, guide_version, snapshot_json, created_at, updated_at, is_active)
            VALUES(
                'legacy-run', 'Legacy', 'guide-1', '{"id":"legacy-run"}', 1, 1, 1);
            CREATE TABLE run_revisions(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                run_id TEXT NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
                revision INTEGER NOT NULL,
                snapshot_json TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                UNIQUE(run_id, revision)
            );
            CREATE TABLE settings(
                key TEXT PRIMARY KEY,
                value_json TEXT NOT NULL
            );
            CREATE TABLE imported_builds(
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                build_json TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            );
            """;
        await command.ExecuteNonQueryAsync();
    }

    private static async Task<int> ReadSchemaVersionAsync(string databasePath)
    {
        await using var connection = new SqliteConnection(
            new SqliteConnectionStringBuilder
            {
                DataSource = databasePath,
                Mode = SqliteOpenMode.ReadOnly,
                Pooling = false,
            }.ToString());
        await connection.OpenAsync();
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT MAX(version) FROM schema_migrations;";
        return Convert.ToInt32(await command.ExecuteScalarAsync());
    }

    private static async Task ReplaceActiveSnapshotAsync(
        string databasePath,
        string snapshot)
    {
        await using var connection = new SqliteConnection(
            new SqliteConnectionStringBuilder
            {
                DataSource = databasePath,
                Mode = SqliteOpenMode.ReadWrite,
                Pooling = false,
            }.ToString());
        await connection.OpenAsync();
        using var command = connection.CreateCommand();
        command.CommandText =
            "UPDATE runs SET snapshot_json = $snapshot WHERE is_active = 1;";
        command.Parameters.AddWithValue("$snapshot", snapshot);
        await command.ExecuteNonQueryAsync();
    }

    private static async Task<string?> ReadOnlyRunIdAsync(string databasePath)
    {
        await using var connection = new SqliteConnection(
            new SqliteConnectionStringBuilder
            {
                DataSource = databasePath,
                Mode = SqliteOpenMode.ReadOnly,
                Pooling = false,
            }.ToString());
        await connection.OpenAsync();
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT id FROM runs LIMIT 1;";
        return await command.ExecuteScalarAsync() as string;
    }
}
