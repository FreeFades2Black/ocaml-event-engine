type counter = {
  name : string;
  help : string;
  value : int ref;
}

type metrics_registry = {
  processed : counter;
  duplicate : counter;
  invalid : counter;
}

val global_registry : metrics_registry
val inc_processed : unit -> unit
val inc_duplicate : unit -> unit
val inc_invalid : unit -> unit

(** Render metrics in official Prometheus plaintext format *)
val format_prometheus : metrics_registry -> string

(** Start non-blocking HTTP metrics server on specified port *)
val start_metrics_server : int -> unit
