# SHUT-061: Squash Merge Finished Shards

- [x] Add focused tests for commit message generation, successful merge state transition, and integration lock.
- [x] Implement repository-state compare-and-set integration locking.
- [x] Implement the squash merge service for integrating a finished shard into `shuttle-main`.
- [x] Mark successfully merged shards as retained `done` shards and reopen repository integration state.
- [ ] Verify with `swift test --filter ShuttleSquashMergeServiceTests`, `swift test`, and `swift build`.
