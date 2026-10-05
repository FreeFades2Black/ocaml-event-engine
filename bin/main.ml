open Event_engine
open Metrics

let config : compaction_config = {
  max_log_bytes = 10_485_760;
  base_dir = ".";
}

let wal_path = Filename.concat config.base_dir "events.jsonl"

let rec process_loop (engine : engine) : unit =
  match input_line stdin with
  | line ->
      let trimmed = String.trim line in
      let next_engine =
        if String.length trimmed = 0 then engine
        else
          match event_of_json trimmed with
          | Error err ->
              inc_invalid ();
              let inv_state = Invalid { id = ""; error = err } in
              print_endline (status_to_json inv_state);
              flush stdout;
              engine
          | Ok raw ->
              let updated_engine, res_state = ingest engine raw in
              let engine_after_commit =
                match res_state with
                | Processed proc ->
                    inc_processed ();
                    append_event wal_path
                      {
                        id = proc.id;
                        timestamp = proc.timestamp;
                        payload = proc.payload;
                      };
                    if should_rotate ~config ~wal_path then
                      match rotate_wal ~config updated_engine with
                      | Ok rot_eng -> rot_eng
                      | Error _ -> updated_engine
                    else updated_engine
                | Duplicate { id = _; timestamp = _ } ->
                    inc_duplicate ();
                    updated_engine
                | Invalid { id = _; error = _ } ->
                    inc_invalid ();
                    updated_engine
                | Received { id = _; timestamp = _; payload = _ } ->
                    updated_engine
              in
              print_endline (status_to_json res_state);
              flush stdout;
              engine_after_commit
      in
      process_loop next_engine
  | exception End_of_file ->
      ()

let () =
  let metrics_port = ref 9100 in
  Arg.parse
    [ ("--metrics-port", Arg.Set_int metrics_port, "Prometheus metrics port (default 9100, 0 to disable)") ]
    (fun _ -> ())
    "Usage: ocaml-event-engine [--metrics-port <port>]";

  if !metrics_port > 0 then
    start_metrics_server !metrics_port;

  let initial_engine =
    match recover ~config with
    | Ok eng -> eng
    | Error _ -> empty
  in
  process_loop initial_engine
