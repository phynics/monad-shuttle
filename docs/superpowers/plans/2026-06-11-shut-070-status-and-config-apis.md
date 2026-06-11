# SHUT-070: Status And Config APIs

## Goal

Expose stable REST responses for server status and effective config, including repository integration state for managed deployments.

## Scope

- Extend the server environment to open the migrated SQLite database during startup and retain a repository state store.
- Ensure startup persists an initial repository-state row after successful repository bootstrap so `/api/status` has meaningful repo data on first boot.
- Extend `GET /api/status` to return:
  - server state
  - subsystem health
  - repository integration state for managed repositories
- Keep `GET /api/config` on the existing redacted response model.
- Add tests for:
  - healthy managed startup fixture through the router
  - fatal startup fixture
  - redacted config route

## Notes

- `paths.databasePath` is a SQLite file path, not a directory. Startup validation now checks its parent directory, which matches the rest of the codebase and allows real boot with file-backed SQLite.
- The status response uses an optional nested `repository` object so unmanaged/minimal server startup still has a valid payload shape.

## Verification

- `swift test --filter ShuttleServerStatusRouteTests`
- `swift test --filter ShuttleConfigRedactionTests`
- `swift test`
- `swift build`
