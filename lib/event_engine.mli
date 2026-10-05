(** Idempotent Event Ingestion Engine

    Strict four-state lifecycle with explicit algebraic data types,
    zero wildcard pattern matching, durable write-ahead logging,
    and atomic WAL compaction with snapshot checkpointing. *)

module StringSet : Set.S with type elt = string

(** Represents the raw incoming event payload and metadata *)
type raw_event = {
  id : string;
  timestamp : int;
  payload : string;
}

(** Strictly four states of an event in the lifecycle *)
type state =
  | Received of raw_event
  | Duplicate of { id : string; timestamp : int }
  | Processed of { id : string; timestamp : int; payload : string }
  | Invalid of { id : string; error : string }

(** The state of the ingestion engine holding seen event IDs *)
type engine = {
  seen_ids : StringSet.t;
}

(** Configuration parameters for WAL compaction and log rotation *)
type compaction_config = {
  max_log_bytes : int;
  base_dir : string;
}

(** [empty] creates an initial engine state with an empty seen set *)
val empty : engine

(** [is_seen id engine] checks if [id] has already been recorded in [engine] *)
val is_seen : string -> engine -> bool

(** [count_seen engine] returns the total number of unique events processed *)
val count_seen : engine -> int

(** [make_event ~id ~timestamp ~payload] constructs an initial [Received] event *)
val make_event : id:string -> timestamp:int -> payload:string -> state

(** [transition engine state] advances a [Received] event to its terminal state
    ([Duplicate], [Processed], or [Invalid]). Already terminal states remain unchanged.
    Returns the updated engine and the resulting state. *)
val transition : engine -> state -> engine * state

(** [ingest engine raw_event] wraps [raw_event] in [Received] and transitions it through [engine] *)
val ingest : engine -> raw_event -> engine * state

(** [event_to_json event] serializes [event] to a single JSON line *)
val event_to_json : raw_event -> string

(** [event_of_json json_str] deserializes a JSON string into a [raw_event].
    Returns [Error reason] if parsing fails. *)
val event_of_json : string -> (raw_event, string) result

(** [status_to_json state] produces the deterministic CLI JSON output:
    - {"status":"processed","id":"<id>"}
    - {"status":"duplicate","id":"<id>"}
    - {"status":"invalid","id":"<id>","error":"<reason>"} *)
val status_to_json : state -> string

(** [append_event log_path event] writes a single serialized JSON line to [log_path]
    with an immediate flush. *)
val append_event : string -> raw_event -> unit

(** [replay_log log_path engine] reconstructs [engine.seen_ids] by reading [log_path]
    line-by-line without re-emitting side effects. Returns [engine] if [log_path] does not exist. *)
val replay_log : string -> engine -> engine

(** [should_rotate ~config ~wal_path] checks whether the file size of [wal_path]
    has met or exceeded [config.max_log_bytes]. *)
val should_rotate : config:compaction_config -> wal_path:string -> bool

(** [create_snapshot engine ~snapshot_path] writes an atomic JSON snapshot of all
    [seen_ids] via a temporary file ([snapshot.json.tmp]) followed by an atomic rename. *)
val create_snapshot : engine -> snapshot_path:string -> (unit, string) result

(** [rotate_wal ~config engine] executes atomic log rotation:
    1. Creates atomic [snapshot.json].
    2. Renames active [events.jsonl] to [events.jsonl.1].
    3. Re-opens a fresh empty [events.jsonl]. *)
val rotate_wal : config:compaction_config -> engine -> (engine, string) result

(** [recover ~config] executes two-tier cold-boot recovery:
    1. Ingests [snapshot.json] if present.
    2. Replays [events.jsonl.1] if present.
    3. Replays active [events.jsonl] if present. *)
val recover : config:compaction_config -> (engine, string) result
