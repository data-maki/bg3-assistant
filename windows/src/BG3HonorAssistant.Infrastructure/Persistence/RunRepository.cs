using System.Text.Json;
using Microsoft.Data.Sqlite;

namespace BG3HonorAssistant.Infrastructure.Persistence;

public sealed class RunRepository
{
    public const int MaximumRevisionsPerRun = 20;
    public const int CurrentSchemaVersion = 3;

    private readonly string databasePath;
    private readonly TimeProvider timeProvider;

    public RunRepository(string databasePath, TimeProvider? timeProvider = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(databasePath);
        this.databasePath = Path.GetFullPath(databasePath);
        this.timeProvider = timeProvider ?? TimeProvider.System;
    }

    public string DatabasePath => databasePath;

    public IReadOnlyList<string> ListRecoveryCopies()
    {
        var directory = Path.GetDirectoryName(databasePath);
        if (string.IsNullOrEmpty(directory) || !Directory.Exists(directory))
        {
            return [];
        }

        var filename = Path.GetFileName(databasePath);
        return Directory
            .EnumerateFiles(
                directory,
                $"{filename}.pre-migration-*.bak",
                SearchOption.TopDirectoryOnly)
            .OrderBy(path => path, StringComparer.Ordinal)
            .ToArray();
    }

    public async Task InitializeAsync(CancellationToken cancellationToken = default)
    {
        var directory = Path.GetDirectoryName(databasePath);
        if (!string.IsNullOrEmpty(directory))
        {
            Directory.CreateDirectory(directory);
        }

        await using var connection = await OpenConnectionAsync(cancellationToken);
        await MigrateAsync(connection, cancellationToken);
    }

    public async Task SaveAsync(
        string id,
        string name,
        string guideVersion,
        string snapshotJson,
        bool makeActive = true,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(id);
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        ArgumentNullException.ThrowIfNull(guideVersion);
        ValidateJson(snapshotJson);

        await using var connection = await OpenInitializedConnectionAsync(cancellationToken);
        using var transaction = connection.BeginTransaction(deferred: false);
        var now = timeProvider.GetUtcNow().ToUnixTimeMilliseconds();

        if (makeActive)
        {
            await ExecuteAsync(
                connection,
                transaction,
                "UPDATE runs SET is_active = 0 WHERE is_active = 1;",
                cancellationToken);
        }

        using (var upsert = connection.CreateCommand())
        {
            upsert.Transaction = transaction;
            upsert.CommandText =
                """
                INSERT INTO runs(
                    id, name, guide_version, snapshot_json, created_at, updated_at, is_active)
                VALUES(
                    $id, $name, $guideVersion, $snapshot, $now, $now, $isActive)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name,
                    guide_version = excluded.guide_version,
                    snapshot_json = excluded.snapshot_json,
                    updated_at = excluded.updated_at,
                    is_active = excluded.is_active;
                """;
            upsert.Parameters.AddWithValue("$id", id);
            upsert.Parameters.AddWithValue("$name", name);
            upsert.Parameters.AddWithValue("$guideVersion", guideVersion);
            upsert.Parameters.AddWithValue("$snapshot", snapshotJson);
            upsert.Parameters.AddWithValue("$now", now);
            upsert.Parameters.AddWithValue("$isActive", makeActive ? 1 : 0);
            await upsert.ExecuteNonQueryAsync(cancellationToken);
        }

        long revision;
        using (var nextRevision = connection.CreateCommand())
        {
            nextRevision.Transaction = transaction;
            nextRevision.CommandText =
                "SELECT COALESCE(MAX(revision), 0) + 1 FROM run_revisions WHERE run_id = $id;";
            nextRevision.Parameters.AddWithValue("$id", id);
            revision = (long)(await nextRevision.ExecuteScalarAsync(cancellationToken) ?? 1L);
        }

        using (var insertRevision = connection.CreateCommand())
        {
            insertRevision.Transaction = transaction;
            insertRevision.CommandText =
                """
                INSERT INTO run_revisions(run_id, revision, snapshot_json, created_at)
                VALUES($id, $revision, $snapshot, $now);
                """;
            insertRevision.Parameters.AddWithValue("$id", id);
            insertRevision.Parameters.AddWithValue("$revision", revision);
            insertRevision.Parameters.AddWithValue("$snapshot", snapshotJson);
            insertRevision.Parameters.AddWithValue("$now", now);
            await insertRevision.ExecuteNonQueryAsync(cancellationToken);
        }

        using (var prune = connection.CreateCommand())
        {
            prune.Transaction = transaction;
            prune.CommandText =
                """
                DELETE FROM run_revisions
                WHERE run_id = $id
                  AND revision NOT IN (
                    SELECT revision
                    FROM run_revisions
                    WHERE run_id = $id
                    ORDER BY revision DESC
                    LIMIT $limit
                  );
                """;
            prune.Parameters.AddWithValue("$id", id);
            prune.Parameters.AddWithValue("$limit", MaximumRevisionsPerRun);
            await prune.ExecuteNonQueryAsync(cancellationToken);
        }

        transaction.Commit();
    }

    public async Task<SavedRun?> LoadActiveAsync(CancellationToken cancellationToken = default)
    {
        await using var connection = await OpenInitializedConnectionAsync(cancellationToken);
        using var command = connection.CreateCommand();
        command.CommandText =
            """
            SELECT id, name, guide_version, snapshot_json, created_at, updated_at, is_active
            FROM runs
            WHERE is_active = 1
            ORDER BY updated_at DESC
            LIMIT 1;
            """;
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        return await reader.ReadAsync(cancellationToken) ? ReadRun(reader) : null;
    }

    public async Task<SavedRun?> LoadAsync(
        string id,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(id);
        await using var connection = await OpenInitializedConnectionAsync(cancellationToken);
        using var command = connection.CreateCommand();
        command.CommandText =
            """
            SELECT id, name, guide_version, snapshot_json, created_at, updated_at, is_active
            FROM runs
            WHERE id = $id
            LIMIT 1;
            """;
        command.Parameters.AddWithValue("$id", id);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        return await reader.ReadAsync(cancellationToken) ? ReadRun(reader) : null;
    }

    public async Task<SavedRun?> LoadRecoverableActiveAsync(
        Func<string, bool> snapshotIsValid,
        CancellationToken cancellationToken = default) =>
        (await LoadRecoverableActiveWithStatusAsync(
            snapshotIsValid,
            cancellationToken)).Run;

    public async Task<RecoverableRunResult> LoadRecoverableActiveWithStatusAsync(
        Func<string, bool> snapshotIsValid,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(snapshotIsValid);
        return await LoadRecoverableActiveWithStatusAsync(
            (_, snapshot) => snapshotIsValid(snapshot),
            cancellationToken);
    }

    public async Task<RecoverableRunResult> LoadRecoverableActiveWithStatusAsync(
        Func<SavedRun, string, bool> snapshotIsValid,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(snapshotIsValid);
        await using var connection = await OpenInitializedConnectionAsync(cancellationToken);
        using var activeCommand = connection.CreateCommand();
        activeCommand.CommandText =
            """
            SELECT id, name, guide_version, snapshot_json, created_at, updated_at, is_active
            FROM runs
            WHERE is_active = 1
            ORDER BY updated_at DESC
            LIMIT 1;
            """;
        await using var activeReader = await activeCommand.ExecuteReaderAsync(cancellationToken);
        if (!await activeReader.ReadAsync(cancellationToken))
        {
            return new RecoverableRunResult(null, HadActiveRun: false, UsedRevision: false);
        }

        var active = ReadRun(activeReader);
        await activeReader.DisposeAsync();
        if (snapshotIsValid(active, active.SnapshotJson))
        {
            return new RecoverableRunResult(active, HadActiveRun: true, UsedRevision: false);
        }

        using var revisions = connection.CreateCommand();
        revisions.CommandText =
            """
            SELECT snapshot_json
            FROM run_revisions
            WHERE run_id = $id
            ORDER BY revision DESC
            LIMIT $limit;
            """;
        revisions.Parameters.AddWithValue("$id", active.Id);
        revisions.Parameters.AddWithValue("$limit", MaximumRevisionsPerRun);
        await using var revisionReader = await revisions.ExecuteReaderAsync(cancellationToken);
        while (await revisionReader.ReadAsync(cancellationToken))
        {
            var snapshot = revisionReader.GetString(0);
            if (snapshotIsValid(active, snapshot))
            {
                return new RecoverableRunResult(
                    active with { SnapshotJson = snapshot },
                    HadActiveRun: true,
                    UsedRevision: true,
                    UnreadableActiveSnapshot: active.SnapshotJson);
            }
        }

        return new RecoverableRunResult(null, HadActiveRun: true, UsedRevision: false);
    }

    public async Task SaveRecoveryEvidenceAsync(
        string runId,
        string snapshot,
        string reason,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(runId);
        ArgumentNullException.ThrowIfNull(snapshot);
        ArgumentException.ThrowIfNullOrWhiteSpace(reason);
        await using var connection = await OpenInitializedConnectionAsync(cancellationToken);
        using var command = connection.CreateCommand();
        command.CommandText =
            """
            INSERT INTO recovery_evidence(run_id, reason, snapshot_text, created_at)
            VALUES($runId, $reason, $snapshot, $now);
            """;
        command.Parameters.AddWithValue("$runId", runId);
        command.Parameters.AddWithValue("$reason", reason);
        command.Parameters.AddWithValue("$snapshot", snapshot);
        command.Parameters.AddWithValue(
            "$now",
            timeProvider.GetUtcNow().ToUnixTimeMilliseconds());
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<string>> ListRecoveryEvidenceAsync(
        string runId,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(runId);
        await using var connection = await OpenInitializedConnectionAsync(cancellationToken);
        using var command = connection.CreateCommand();
        command.CommandText =
            """
            SELECT snapshot_text
            FROM recovery_evidence
            WHERE run_id = $runId
            ORDER BY id;
            """;
        command.Parameters.AddWithValue("$runId", runId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var snapshots = new List<string>();
        while (await reader.ReadAsync(cancellationToken))
        {
            snapshots.Add(reader.GetString(0));
        }

        return snapshots;
    }

    public async Task<IReadOnlyList<SavedRun>> ListAsync(
        CancellationToken cancellationToken = default)
    {
        await using var connection = await OpenInitializedConnectionAsync(cancellationToken);
        using var command = connection.CreateCommand();
        command.CommandText =
            """
            SELECT id, name, guide_version, snapshot_json, created_at, updated_at, is_active
            FROM runs
            ORDER BY updated_at DESC, id;
            """;
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var runs = new List<SavedRun>();
        while (await reader.ReadAsync(cancellationToken))
        {
            runs.Add(ReadRun(reader));
        }

        return runs;
    }

    public async Task<bool> SetActiveAsync(
        string id,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(id);
        await using var connection = await OpenInitializedConnectionAsync(cancellationToken);
        using var transaction = connection.BeginTransaction(deferred: false);
        using (var exists = connection.CreateCommand())
        {
            exists.Transaction = transaction;
            exists.CommandText = "SELECT EXISTS(SELECT 1 FROM runs WHERE id = $id);";
            exists.Parameters.AddWithValue("$id", id);
            if (Convert.ToInt32(await exists.ExecuteScalarAsync(cancellationToken)) != 1)
            {
                transaction.Rollback();
                return false;
            }
        }

        await ExecuteAsync(
            connection,
            transaction,
            "UPDATE runs SET is_active = 0 WHERE is_active = 1;",
            cancellationToken);
        using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText =
            """
            UPDATE runs
            SET is_active = 1,
                last_opened_at = $now
            WHERE id = $id;
            """;
        command.Parameters.AddWithValue("$id", id);
        command.Parameters.AddWithValue(
            "$now",
            timeProvider.GetUtcNow().ToUnixTimeMilliseconds());
        var changed = await command.ExecuteNonQueryAsync(cancellationToken);
        transaction.Commit();
        return changed == 1;
    }

    public async Task<bool> DeleteAsync(
        string id,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(id);
        await using var connection = await OpenInitializedConnectionAsync(cancellationToken);
        using var command = connection.CreateCommand();
        command.CommandText = "DELETE FROM runs WHERE id = $id;";
        command.Parameters.AddWithValue("$id", id);
        return await command.ExecuteNonQueryAsync(cancellationToken) == 1;
    }

    public async Task<int> CountRevisionsAsync(
        string runId,
        CancellationToken cancellationToken = default)
    {
        await using var connection = await OpenInitializedConnectionAsync(cancellationToken);
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT COUNT(*) FROM run_revisions WHERE run_id = $id;";
        command.Parameters.AddWithValue("$id", runId);
        return Convert.ToInt32(await command.ExecuteScalarAsync(cancellationToken));
    }

    public async Task SetSettingAsync(
        string key,
        string valueJson,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(key);
        ValidateJson(valueJson);
        await using var connection = await OpenInitializedConnectionAsync(cancellationToken);
        using var command = connection.CreateCommand();
        command.CommandText =
            """
            INSERT INTO settings(key, value_json)
            VALUES($key, $value)
            ON CONFLICT(key) DO UPDATE SET value_json = excluded.value_json;
            """;
        command.Parameters.AddWithValue("$key", key);
        command.Parameters.AddWithValue("$value", valueJson);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task<string?> GetSettingAsync(
        string key,
        CancellationToken cancellationToken = default)
    {
        await using var connection = await OpenInitializedConnectionAsync(cancellationToken);
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT value_json FROM settings WHERE key = $key LIMIT 1;";
        command.Parameters.AddWithValue("$key", key);
        return await command.ExecuteScalarAsync(cancellationToken) as string;
    }

    public async Task SaveImportedBuildAsync(
        string id,
        string name,
        string buildJson,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(id);
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        ValidateJson(buildJson);

        await using var connection = await OpenInitializedConnectionAsync(cancellationToken);
        using var command = connection.CreateCommand();
        command.CommandText =
            """
            INSERT INTO imported_builds(id, name, build_json, created_at, updated_at)
            VALUES($id, $name, $json, $now, $now)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                build_json = excluded.build_json,
                updated_at = excluded.updated_at;
            """;
        command.Parameters.AddWithValue("$id", id);
        command.Parameters.AddWithValue("$name", name);
        command.Parameters.AddWithValue("$json", buildJson);
        command.Parameters.AddWithValue(
            "$now",
            timeProvider.GetUtcNow().ToUnixTimeMilliseconds());
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task<string?> GetImportedBuildJsonAsync(
        string id,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(id);
        await using var connection = await OpenInitializedConnectionAsync(cancellationToken);
        using var command = connection.CreateCommand();
        command.CommandText =
            "SELECT build_json FROM imported_builds WHERE id = $id LIMIT 1;";
        command.Parameters.AddWithValue("$id", id);
        return await command.ExecuteScalarAsync(cancellationToken) as string;
    }

    public async Task<IReadOnlyList<string>> ListImportedBuildJsonAsync(
        CancellationToken cancellationToken = default)
    {
        await using var connection = await OpenInitializedConnectionAsync(cancellationToken);
        using var command = connection.CreateCommand();
        command.CommandText =
            """
            SELECT build_json
            FROM imported_builds
            ORDER BY updated_at DESC, id;
            """;
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var builds = new List<string>();
        while (await reader.ReadAsync(cancellationToken))
        {
            builds.Add(reader.GetString(0));
        }

        return builds;
    }

    public async Task<bool> DeleteImportedBuildAsync(
        string id,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(id);
        await using var connection = await OpenInitializedConnectionAsync(cancellationToken);
        using var command = connection.CreateCommand();
        command.CommandText = "DELETE FROM imported_builds WHERE id = $id;";
        command.Parameters.AddWithValue("$id", id);
        return await command.ExecuteNonQueryAsync(cancellationToken) == 1;
    }

    public async Task<string> GetSqliteVersionAsync(CancellationToken cancellationToken = default)
    {
        await using var connection = await OpenInitializedConnectionAsync(cancellationToken);
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT sqlite_version();";
        return (string)(await command.ExecuteScalarAsync(cancellationToken)
            ?? throw new InvalidOperationException("SQLite did not return its version."));
    }

    private async Task<SqliteConnection> OpenInitializedConnectionAsync(
        CancellationToken cancellationToken)
    {
        var directory = Path.GetDirectoryName(databasePath);
        if (!string.IsNullOrEmpty(directory))
        {
            Directory.CreateDirectory(directory);
        }

        var connection = await OpenConnectionAsync(cancellationToken);
        try
        {
            await MigrateAsync(connection, cancellationToken);
            return connection;
        }
        catch
        {
            await connection.DisposeAsync();
            throw;
        }
    }

    private async Task<SqliteConnection> OpenConnectionAsync(CancellationToken cancellationToken)
    {
        var connection = new SqliteConnection(new SqliteConnectionStringBuilder
        {
            DataSource = databasePath,
            Mode = SqliteOpenMode.ReadWriteCreate,
            Cache = SqliteCacheMode.Private,
            ForeignKeys = true,
            Pooling = false,
        }.ToString());
        await connection.OpenAsync(cancellationToken);
        try
        {
            using var command = connection.CreateCommand();
            command.CommandText =
                """
                PRAGMA journal_mode = WAL;
                PRAGMA foreign_keys = ON;
                PRAGMA busy_timeout = 5000;
                """;
            await command.ExecuteNonQueryAsync(cancellationToken);
            return connection;
        }
        catch
        {
            await connection.DisposeAsync();
            throw;
        }
    }

    private async Task MigrateAsync(
        SqliteConnection connection,
        CancellationToken cancellationToken)
    {
        await ExecuteAsync(
            connection,
            """
            CREATE TABLE IF NOT EXISTS schema_migrations(
                version INTEGER PRIMARY KEY,
                applied_at INTEGER NOT NULL
            );
            """,
            cancellationToken);

        using var versionCommand = connection.CreateCommand();
        versionCommand.CommandText = "SELECT COALESCE(MAX(version), 0) FROM schema_migrations;";
        var version = Convert.ToInt32(await versionCommand.ExecuteScalarAsync(cancellationToken));

        if (version > CurrentSchemaVersion)
        {
            throw new InvalidOperationException(
                $"Database schema {version} is newer than supported schema {CurrentSchemaVersion}.");
        }

        if (version > 0 && version < CurrentSchemaVersion)
        {
            await CreateRecoveryCopyAsync(connection, version, cancellationToken);
        }

        using var transaction = connection.BeginTransaction(deferred: false);
        if (version < 1)
        {
            await ExecuteAsync(
                connection,
                transaction,
                """
                CREATE TABLE runs(
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    guide_version TEXT NOT NULL,
                    snapshot_json TEXT NOT NULL,
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    is_active INTEGER NOT NULL DEFAULT 0 CHECK(is_active IN (0, 1))
                );
                CREATE UNIQUE INDEX one_active_run
                    ON runs(is_active)
                    WHERE is_active = 1;
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
                """,
                cancellationToken);

            using var recordMigration = connection.CreateCommand();
            recordMigration.Transaction = transaction;
            recordMigration.CommandText =
                "INSERT INTO schema_migrations(version, applied_at) VALUES(1, $now);";
            recordMigration.Parameters.AddWithValue(
                "$now",
                TimeProvider.System.GetUtcNow().ToUnixTimeMilliseconds());
            await recordMigration.ExecuteNonQueryAsync(cancellationToken);
        }

        if (version < 2)
        {
            await ExecuteAsync(
                connection,
                transaction,
                """
                ALTER TABLE runs ADD COLUMN last_opened_at INTEGER;
                CREATE INDEX run_revisions_recent
                    ON run_revisions(run_id, revision DESC);
                """,
                cancellationToken);

            using var recordMigration = connection.CreateCommand();
            recordMigration.Transaction = transaction;
            recordMigration.CommandText =
                "INSERT INTO schema_migrations(version, applied_at) VALUES(2, $now);";
            recordMigration.Parameters.AddWithValue(
                "$now",
                timeProvider.GetUtcNow().ToUnixTimeMilliseconds());
            await recordMigration.ExecuteNonQueryAsync(cancellationToken);
        }

        if (version < 3)
        {
            await ExecuteAsync(
                connection,
                transaction,
                """
                CREATE TABLE recovery_evidence(
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    run_id TEXT NOT NULL,
                    reason TEXT NOT NULL,
                    snapshot_text TEXT NOT NULL,
                    created_at INTEGER NOT NULL
                );
                CREATE INDEX recovery_evidence_run
                    ON recovery_evidence(run_id, id);
                """,
                cancellationToken);

            using var recordMigration = connection.CreateCommand();
            recordMigration.Transaction = transaction;
            recordMigration.CommandText =
                "INSERT INTO schema_migrations(version, applied_at) VALUES(3, $now);";
            recordMigration.Parameters.AddWithValue(
                "$now",
                timeProvider.GetUtcNow().ToUnixTimeMilliseconds());
            await recordMigration.ExecuteNonQueryAsync(cancellationToken);
        }

        transaction.Commit();
    }

    private async Task CreateRecoveryCopyAsync(
        SqliteConnection source,
        int fromVersion,
        CancellationToken cancellationToken)
    {
        var timestamp = timeProvider
            .GetUtcNow()
            .UtcDateTime
            .ToString("yyyyMMddTHHmmssfffZ", System.Globalization.CultureInfo.InvariantCulture);
        var recoveryPath =
            $"{databasePath}.pre-migration-v{fromVersion}-to-v{CurrentSchemaVersion}-{timestamp}.bak";
        await using var destination = new SqliteConnection(new SqliteConnectionStringBuilder
        {
            DataSource = recoveryPath,
            Mode = SqliteOpenMode.ReadWriteCreate,
            Cache = SqliteCacheMode.Private,
            Pooling = false,
        }.ToString());
        await destination.OpenAsync(cancellationToken);
        source.BackupDatabase(destination);
    }

    private static async Task ExecuteAsync(
        SqliteConnection connection,
        SqliteTransaction transaction,
        string sql,
        CancellationToken cancellationToken)
    {
        using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = sql;
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static async Task ExecuteAsync(
        SqliteConnection connection,
        string sql,
        CancellationToken cancellationToken)
    {
        using var command = connection.CreateCommand();
        command.CommandText = sql;
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static SavedRun ReadRun(SqliteDataReader reader)
    {
        return new SavedRun(
            reader.GetString(0),
            reader.GetString(1),
            reader.GetString(2),
            reader.GetString(3),
            DateTimeOffset.FromUnixTimeMilliseconds(reader.GetInt64(4)),
            DateTimeOffset.FromUnixTimeMilliseconds(reader.GetInt64(5)),
            reader.GetInt64(6) == 1);
    }

    private static void ValidateJson(string json)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(json);
        using var _ = JsonDocument.Parse(json);
    }
}
