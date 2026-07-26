# Dependency decisions

## SQLite native bundle override

- Date: 2026-07-25
- Research baseline: `Microsoft.Data.Sqlite` 10.0.10, transitively resolving
  `SQLitePCLRaw.lib.e_sqlite3` 2.1.11.
- Restore result: blocked by `NU1903` / `GHSA-2m69-gcr7-jv3q` (high severity).
- Decision: retain `Microsoft.Data.Sqlite` 10.0.10 and directly pin
  `SQLitePCLRaw.bundle_e_sqlite3` 3.0.4 so the vulnerable native bundle is not selected.
- Required evidence: clean restore, package graph inspection, SQLite open/write/read smoke
  test, vulnerability audit, and x64 publish inventory.

Do not suppress this advisory or revert to the researched transitive baseline.
