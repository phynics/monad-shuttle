# Shuttle Deployment

This document covers the minimum deployment shape for Shuttle v1.

## V1 Scope

Shuttle v1 manages one repository per Shuttle server instance. It provides:

- a bare managed clone
- a local `shuttle-main` integration branch
- one git worktree per shard
- one container per shard worktree
- REST APIs for shard, conflict, log, refresh, and push actions
- a local/admin operator UI backed by the same REST APIs

## V1 Non-Goals

Shuttle v1 does not include:

- multi-repository management
- distributed workers
- auto-running conflict-resolution shards
- fine-grained auth or per-user permissions
- Shuttle-owned CI or merge validation outside the agent completion report
- automatic pushes to upstream remotes

## Required Volumes

Mount these writable volumes into the Shuttle container:

- `/data/db`
- `/data/git`
- `/data/worktrees`
- `/data/logs`

Mount these read-only configuration volumes:

- `/config`
- `/secrets`

Mount the Docker socket:

- `/var/run/docker.sock`

Shuttle expects all of those paths to exist at startup. Missing volume paths fail startup and move the server into `fatal`.

## Required Files

Provide these files through mounted config and secrets volumes:

- `/config/shuttle.yaml`
- `/config/shuttle-instructions.md`
- the SSH private key referenced by `repository.ssh_key_path`

The SSH key path in the YAML file must be absolute and readable inside the container.

## Docker Socket

Shuttle uses the Docker socket to create, inspect, stop, and exec into shard containers.

V1 assumes:

- shard containers run on the same host as the Shuttle server
- the Shuttle server can create and exec into those containers directly
- shard tools operate only through the shard worktree mount and configured container workdir

If the Docker socket is missing or unreadable, Shuttle stays up but reports Docker as unhealthy and shard container operations fail.

## SSH Credentials

V1 repository access is hand-configured with SSH credentials. Recommended pattern:

1. create a dedicated deploy key with repository access
2. mount it into `/secrets`
3. reference it from `repository.ssh_key_path`
4. keep the secrets volume read-only

Shuttle redacts the configured SSH key path in API config responses.

## Example Layout

```text
/config
  shuttle.yaml
  shuttle-instructions.md
/secrets
  id_ed25519
/data/db
/data/git
/data/worktrees
/data/logs
```

## Example Config

See [deploy/config/shuttle.example.yaml](/Volumes/Development/monad-project/Shuttle/deploy/config/shuttle.example.yaml).

Important fields:

- `repository.url`: upstream repository URL
- `repository.source_branch`: upstream branch Shuttle imports
- `runtime.container_image`: shard container image
- `runtime.container_workdir`: working directory inside shard containers
- `runtime.command_policy`: allow/deny list for container command execution
- `retention`: retained worktree and raw-log cleanup settings
- `limits`: shard concurrency and log size limits
- `push_targets`: named manual push destinations
- `instructions.file_path`: operator-provided instruction file injected into shard agent context

## Compose Skeleton

The repo includes [compose.yaml](/Volumes/Development/monad-project/Shuttle/compose.yaml) as a local deployment skeleton. It is suitable for development and single-host testing. You still need to:

- provide a real repository URL
- provide a real SSH key in `deploy/secrets`
- review the container image reference
- review volume persistence policy for your host

## Startup Behavior

On startup Shuttle:

1. validates mounted config, secrets, and writable paths
2. opens and migrates the SQLite database
3. bootstraps or reuses the managed bare repository
4. ensures repository state exists
5. reconciles shard and repository state against worktrees, conflicts, and Docker
6. runs retention cleanup for expired retained worktrees and expired raw logs
7. probes Docker health

## Persistence Model

- SQLite metadata lives under `/data/db`
- bare repository data lives under `/data/git`
- shard worktrees live under `/data/worktrees`
- raw command and transcript logs live under `/data/logs`

V1 keeps completed shard metadata indefinitely, removes retained worktrees after the retention window, and rotates raw logs by size plus retention policy.

## Deployment Checks

Before treating an instance as usable, verify:

1. `GET /api/status` reports server `ready`
2. Docker subsystem reports healthy
3. config endpoint returns expected redacted values
4. the managed repository bootstrapped from the intended upstream branch
5. shard creation creates a worktree and a shard container successfully

## Related Docs

- [README](/Volumes/Development/monad-project/Shuttle/README.md)
- [docs/operations.md](/Volumes/Development/monad-project/Shuttle/docs/operations.md)
- [design spec](/Volumes/Development/monad-project/workflow/Shuttle/specs/2026-05-28-shuttle-design.md)
