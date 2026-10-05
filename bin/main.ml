open Event_engine

let log_file = "events.jsonl"

let rec process_loop (engine : engine) : unit =
  match input_line stdin with
  | line ->
      let trimmed = String.trim line in
      let next_engine =
        if String.length trimmed = 0 then engine
        else
          match event_of_json trimmed with
          | Error err ->
              let inv_state = Invalid { id = ""; error = err } in
              print_endline (status_to_json inv_state);
              flush stdout;
              engine
          | Ok raw ->
              let updated_engine, res_state = ingest engine raw in
              (match res_state with
              | Processed proc ->
                  append_event log_file
                    {
                      id = proc.id;
                      timestamp = proc.timestamp;
                      payload = proc.payload;
                    }
              | Duplicate { id = _; timestamp = _ } ->
                  ()
              | Invalid { id = _; error = _ } ->
                  ()
              | Received { id = _; timestamp = _; payload = _ } ->
                  ());
              print_endline (status_to_json res_state);
              flush stdout;
              updated_engine
      in
      process_loop next_engine
  | exception End_of_file ->
      ()

let () =
  let initial_engine = replay_log log_file empty in
  process_loop initial_engine
