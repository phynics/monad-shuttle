# SHUT-003 Docker Skeleton Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Dockerfile and compose example for Shuttle that match the v1 volume model and document the required mounted config and SSH key paths.

**Architecture:** This ticket is documentation and packaging only. It adds a multi-stage Docker build for the `ShuttleServer` executable, a compose file with the required volumes and Docker socket mount, and example config placeholders that later tickets will make executable.

**Tech Stack:** Docker, Docker Compose, Swift 6, SwiftPM

---

### Task 1: Add Failing Deployment Documentation Test

**Files:**
- Create: `Tests/ShuttleServerTests/ShuttleDeploymentSkeletonTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import Foundation

final class ShuttleDeploymentSkeletonTests: XCTestCase {
    func testDockerDeploymentArtifactsExist() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: "Dockerfile"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: "compose.yaml"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: "deploy/config/shuttle.example.yaml"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: "deploy/env/shuttle.example.env"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ShuttleDeploymentSkeletonTests`
Expected: FAIL because the Docker and deployment example files do not exist yet.

### Task 2: Add Dockerfile, Compose Example, And Deployment Examples

**Files:**
- Create: `Dockerfile`
- Create: `compose.yaml`
- Create: `deploy/config/shuttle.example.yaml`
- Create: `deploy/env/shuttle.example.env`
- Create: `docs/deployment.md`
- Test: `Tests/ShuttleServerTests/ShuttleDeploymentSkeletonTests.swift`

- [ ] **Step 1: Write minimal deployment artifacts**

```dockerfile
FROM swift:6.0-jammy AS build

WORKDIR /workspace

COPY Package.swift Package.resolved ./
COPY Sources ./Sources
COPY Tests ./Tests

RUN swift build -c release --product ShuttleServer

FROM ubuntu:22.04

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git openssh-client \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=build /workspace/.build/release/ShuttleServer /usr/local/bin/ShuttleServer

ENV SHUTTLE_CONFIG_PATH=/config/shuttle.yaml

ENTRYPOINT ["/usr/local/bin/ShuttleServer"]
CMD ["--config", "/config/shuttle.yaml", "--host", "0.0.0.0", "--port", "8080"]
```

```yaml
services:
  shuttle:
    build:
      context: .
      dockerfile: Dockerfile
    image: shuttle:dev
    ports:
      - "8080:8080"
    environment:
      SHUTTLE_CONFIG_PATH: /config/shuttle.yaml
    volumes:
      - shuttle-db:/data/db
      - shuttle-git:/data/git
      - shuttle-worktrees:/data/worktrees
      - shuttle-logs:/data/logs
      - ./deploy/config:/config:ro
      - ./deploy/secrets:/secrets:ro
      - /var/run/docker.sock:/var/run/docker.sock

volumes:
  shuttle-db:
  shuttle-git:
  shuttle-worktrees:
  shuttle-logs:
```

```yaml
repository:
  url: git@github.com:example/example-repo.git
  source_branch: main
  ssh_key_path: /secrets/id_ed25519

runtime:
  container_image: ghcr.io/example/shuttle-runner:latest
  container_workdir: /workspace

server:
  host: 0.0.0.0
  port: 8080
```

```dotenv
# Copy to deploy/env/shuttle.env and adjust values for local deployment.
SHUTTLE_IMAGE=shuttle:dev
SHUTTLE_PORT=8080
```

```markdown
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
```

- [ ] **Step 2: Run test to verify it passes**

Run: `swift test --filter ShuttleDeploymentSkeletonTests`
Expected: PASS with `ShuttleDeploymentSkeletonTests.testDockerDeploymentArtifactsExist` green.

- [ ] **Step 3: Run package verification**

Run: `swift test`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Dockerfile compose.yaml deploy/config/shuttle.example.yaml deploy/env/shuttle.example.env docs/deployment.md Tests/ShuttleServerTests/ShuttleDeploymentSkeletonTests.swift docs/superpowers/plans/2026-05-28-shut-003-docker-skeleton.md
git commit -m "build: add Shuttle Docker skeleton"
```

## Self-Review

- Spec coverage: covers `SHUT-003` acceptance criteria only.
- Placeholder scan: no placeholders remain.
- Type consistency: none required beyond stable file names used by the test.
