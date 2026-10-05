(** Idempotent Event Ingestion Engine

    Strict four-state lifecycle with explicit algebraic data types,
    zero wildcard pattern matching, and durable write-ahead logging. *)

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
