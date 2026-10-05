(** Idempotent Event Ingestion Engine

    Strict four-state lifecycle with explicit algebraic data types
    and zero wildcard pattern matching. *)

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
