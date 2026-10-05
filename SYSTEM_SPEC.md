# Specification: Idempotent Event Ingestion Engine

## Target Environment
- Language: OCaml 5.x
- Build System: Dune
- Dependencies: Standard library only (or minimal ppx_deriving if available)

## 1. State Machine
An incoming transaction event moves through strictly four states:
1. `Received`: Initial state containing Event ID (string), Timestamp (int), and Payload (string).
2. `Duplicate`: If the Event ID already exists in the seen set, transition here and discard.
3. `Processed`: If the Event ID is new and Payload is non-empty, record it as seen and transition here.
4. `Invalid`: If the Payload is empty or Event ID is blank, transition here with an error description.

## 2. Invariants
- No duplicate event IDs may enter the `Processed` state.
- Empty payloads must never reach `Processed`.
- Transitions must return an explicit `Result` or domain variant. No exceptions.

## 3. Required Deliverables
1. `lib/event_engine.mli`: Public interface with exact type definitions and signatures.
2. `lib/event_engine.ml`: Implementation satisfying all invariants.
3. `test/test_event_engine.ml`: Test harness covering valid transitions, duplicate detection, and empty payload rejection.
4. `dune-project` and `dune` configuration files configured to compile and run tests.

## 4. Persistence & CLI Specification (Phase 2)

### Log Invariants
- Storage Format: Newline-delimited JSON (`events.jsonl`).
- Replay Invariant: Calling `replay_log "events.jsonl"` on an empty engine must reconstruct the exact `seen_ids` state without re-emitting side effects.
- Atomicity: Writing a processed event must flush immediately to avoid partial-line writes during unexpected termination.

### CLI Binary (`bin/main.ml`)
- Ingress: Reads JSON event strings from standard input (`stdin`) line-by-line.
- Egress: Emits deterministic execution results to standard output (`stdout`):
  - `{"status":"processed","id":"<id>"}`
  - `{"status":"duplicate","id":"<id>"}`
  - `{"status":"invalid","id":"<id>","error":"<reason>"}`
- Exit Codes: Clean exit with code 0 on `EOF`. Non-zero only on unrecoverable disk I/O errors.

## 5. WAL Compaction & Log Rotation Specification (Phase 3)

### Compaction Motivation & Problem Statement
Without bounds, `events.jsonl` will grow monotonically over time, degrading cold-boot recovery latency and consuming disk space. Phase 3 introduces size-triggered log rotation and snapshot checkpointing.

### Configuration Parameters
- `max_log_bytes`: Maximum allowed size of `events.jsonl` before rotation is triggered (default: `10_485_760` bytes / 10MB; configurable down to small byte counts for testing).
- `snapshot_path`: Snapshot file containing engine state (`snapshot.json`).
- `wal_path`: Active write-ahead log path (`events.jsonl`).
- `wal_archive_pattern`: Rotated log archive naming convention (`events.jsonl.1`).

### Invariants & Safety Guarantees
1. **Crash-Safe Snapshot Creation:** 
   - A snapshot must be written to an ephemeral temporary file first (`snapshot.json.tmp`).
   - The engine flushes and closes the temporary file, then executes an atomic rename (`Sys.rename "snapshot.json.tmp" "snapshot.json"`). A crash mid-write must never leave a corrupted active snapshot.
2. **Atomic Rotation Sequence:**
   - Once `snapshot.json` is atomically in place, `events.jsonl` is renamed to `events.jsonl.1` via atomic filesystem rename.
   - A fresh, empty `events.jsonl` is opened for active ingress.
3. **Cold Boot Invariant (Two-Tier Recovery):**
   - If `snapshot.json` exists:
     1. Ingest `snapshot.json` to seed `engine.seen_ids` and the snapshot timestamp.
     2. If `events.jsonl.1` exists, replay it to ensure no tail writes were lost during a rotation crash.
     3. Replay `events.jsonl` to apply any deltas committed after the snapshot.
   - If `snapshot.json` does not exist:
     - Fall back to standard full replay of `events.jsonl` (and `events.jsonl.1` if present).
   - Replay must remain strictly idempotent: re-applying seen IDs must not corrupt state or trigger side effects.
4. **Zero-Drop Invariant:**
   - Ingestion must not drop, duplicate, or lose any incoming event during the rotation boundary. The write lock or state swap must be atomic relative to event ingestion.

### Required Interface Extensions (`lib/event_engine.mli`)
- `type compaction_config = { max_log_bytes : int; base_dir : string }`
- `val should_rotate : config:compaction_config -> wal_path:string -> bool`
- `val create_snapshot : engine -> snapshot_path:string -> (unit, string) result`
- `val rotate_wal : config:compaction_config -> engine -> (engine, string) result`
- `val recover : config:compaction_config -> (engine, string) result`

## 6. Prometheus Observability & HTTP Exporter Specification (Phase 4)

### Observability Motivation & Problem Statement
To integrate the zero-dependency static musl engine into production monitoring and alerting ecosystems (Prometheus, Grafana, OpenTelemetry Collector) without adding third-party HTTP or metrics library dependencies, the engine exposes a standards-compliant Prometheus metrics endpoint over HTTP via OCaml standard library `Unix` sockets and background `Thread`.

### Configuration Parameters
- `--metrics-port <int>`: Port for HTTP Prometheus scrape server (default: `9100`).

### Metric Invariants & Exposition Format
- Protocol: HTTP/1.1 `GET /metrics` returning `Content-Type: text/plain; version=0.0.4`.
- Counters:
  - `events_processed_total`: Monotonically increasing counter for all events successfully admitted to the `Processed` state.
  - `events_duplicate_total`: Monotonically increasing counter for rejected duplicate events discarded in the `Duplicate` state.
  - `events_invalid_total`: Monotonically increasing counter for malformed JSON or invalid domain payloads in the `Invalid` state.
- Format:
  ```text
  # HELP events_processed_total Total count of successfully processed events.
  # TYPE events_processed_total counter
  events_processed_total <val>
  # HELP events_duplicate_total Total count of rejected duplicate events.
  # TYPE events_duplicate_total counter
  events_duplicate_total <val>
  # HELP events_invalid_total Total count of malformed or invalid events.
  # TYPE events_invalid_total counter
  events_invalid_total <val>
  ```
- Non-blocking Execution: The HTTP metrics server runs on an independent background thread and never blocks or introduces latency into the primary stdin/stdout streaming event ingestion pipeline.

### Required Metrics Module Interface (`lib/metrics.mli`)
- `type counter = { name : string; help : string; value : int ref }`
- `type metrics_registry = { processed : counter; duplicate : counter; invalid : counter }`
- `val global_registry : metrics_registry`
- `val inc_processed : unit -> unit`
- `val inc_duplicate : unit -> unit`
- `val inc_invalid : unit -> unit`
- `val format_prometheus : metrics_registry -> string`
- `val start_metrics_server : int -> unit`
