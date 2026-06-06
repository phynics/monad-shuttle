# SHUT-053: Implement Request-Finish Flow

- [x] Add focused tests for request-finish on running, non-running, and finished shards.
- [x] Implement a finish-request service that records an operator/system finish instruction without changing shard state.
- [x] Inject pending finish instructions into the shard agent runner system prompt.
- [x] Extend audit-store coverage for the new request-finish event and instruction retrieval.
- [ ] Verify with `swift test --filter ShuttleShardFinishRequestServiceTests`, `swift test`, and `swift build`.
