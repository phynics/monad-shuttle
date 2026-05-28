# Shuttle Deployment

## Required Mounts

- database volume at `/data/db`
- git volume at `/data/git`
- worktree volume at `/data/worktrees`
- log volume at `/data/logs`
- config volume at `/config`
- secrets volume at `/secrets`
- Docker socket at `/var/run/docker.sock`

## Required Files

- Shuttle YAML config at `/config/shuttle.yaml`
- SSH private key at the path referenced by `repository.ssh_key_path`

## Compose Example

`compose.yaml` provides a local development deployment skeleton for Shuttle. It mounts the required named volumes plus local `deploy/config` and `deploy/secrets` directories.

## Current Limit

The compose file and YAML example are deployment skeletons for `SHUT-003`. Later tickets add the full YAML schema and runtime behavior.
