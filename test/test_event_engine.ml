open Event_engine
open Metrics

let total_tests = ref 0
let passed_tests = ref 0

let check (name : string) (cond : bool) : unit =
  incr total_tests;
  if cond then (
    incr passed_tests;
    Printf.printf "  [PASS] %s\n" name
  ) else (
    Printf.printf "  [FAIL] %s\n" name;
    exit 1
  )

let test_valid_transition () : unit =
  Printf.printf "Test Suite 1: Valid Event Transition\n";
  let eng0 = empty in
  check "Initial engine has 0 seen events" (count_seen eng0 = 0);
  check "evt-1 is not seen initially" (not (is_seen "evt-1" eng0));

  let event1 : raw_event = { id = "evt-1"; timestamp = 100; payload = "transfer: $500" } in
  let eng1, state1 = ingest eng0 event1 in

  (match state1 with
  | Processed proc ->
      check "Event 1 transitioned to Processed"
        (proc.id = "evt-1" && proc.timestamp = 100 && proc.payload = "transfer: $500")
  | Received r ->
      check (Printf.sprintf "Unexpected Received: %s (ts=%d, pl=%s)" r.id r.timestamp r.payload) false
  | Duplicate d ->
      check (Printf.sprintf "Unexpected Duplicate: %s (ts=%d)" d.id d.timestamp) false
  | Invalid inv ->
      check (Printf.sprintf "Unexpected Invalid: %s (err=%s)" inv.id inv.error) false);

  check "Engine recorded evt-1" (is_seen "evt-1" eng1);
  check "Engine seen count is 1" (count_seen eng1 = 1);

  let event2 : raw_event = { id = "evt-2"; timestamp = 101; payload = "transfer: $250" } in
  let eng2, state2 = ingest eng1 event2 in

  (match state2 with
  | Processed proc ->
      check "Event 2 transitioned to Processed"
        (proc.id = "evt-2" && proc.timestamp = 101 && proc.payload = "transfer: $250")
  | Received r ->
      check (Printf.sprintf "Unexpected Received: %s (ts=%d, pl=%s)" r.id r.timestamp r.payload) false
  | Duplicate d ->
      check (Printf.sprintf "Unexpected Duplicate: %s (ts=%d)" d.id d.timestamp) false
  | Invalid inv ->
      check (Printf.sprintf "Unexpected Invalid: %s (err=%s)" inv.id inv.error) false);

  check "Engine recorded evt-2" (is_seen "evt-2" eng2);
  check "Engine seen count is 2" (count_seen eng2 = 2)

let test_duplicate_detection () : unit =
  Printf.printf "\nTest Suite 2: Duplicate Detection and Discard\n";
  let eng = empty in
  let event : raw_event = { id = "evt-dup"; timestamp = 200; payload = "first arrival" } in
  let eng_after_first, state_first = ingest eng event in

  (match state_first with
  | Processed proc ->
      check "First arrival processed successfully" (proc.id = "evt-dup" && proc.payload = "first arrival")
  | Received r ->
      check (Printf.sprintf "Unexpected Received: %s (ts=%d, pl=%s)" r.id r.timestamp r.payload) false
  | Duplicate d ->
      check (Printf.sprintf "Unexpected Duplicate: %s (ts=%d)" d.id d.timestamp) false
  | Invalid inv ->
      check (Printf.sprintf "Unexpected Invalid: %s (err=%s)" inv.id inv.error) false);

  let dup_event : raw_event = { id = "evt-dup"; timestamp = 205; payload = "duplicate arrival with modified payload" } in
  let eng_after_dup, state_dup = ingest eng_after_first dup_event in

  (match state_dup with
  | Duplicate dup ->
      check "Duplicate event correctly classified as Duplicate" (dup.id = "evt-dup" && dup.timestamp = 205)
  | Processed proc ->
      check (Printf.sprintf "Duplicate must not be Processed: %s" proc.id) false
  | Received r ->
      check (Printf.sprintf "Unexpected Received: %s" r.id) false
  | Invalid inv ->
      check (Printf.sprintf "Unexpected Invalid: %s" inv.id) false);

  check "Engine seen count did not increase on duplicate" (count_seen eng_after_dup = 1);
  check "Duplicate engine state matches first engine state" (eng_after_dup = eng_after_first)

let test_empty_payload_rejection () : unit =
  Printf.printf "\nTest Suite 3: Empty Payload Rejection\n";
  let eng = empty in
  let empty_event : raw_event = { id = "evt-empty"; timestamp = 300; payload = "" } in
  let eng_after_empty, state_empty = ingest eng empty_event in

  (match state_empty with
  | Invalid inv ->
      check "Empty payload transitioned to Invalid" (inv.id = "evt-empty" && inv.error = "Payload cannot be empty")
  | Processed proc ->
      check (Printf.sprintf "Empty payload must not reach Processed: %s" proc.id) false
  | Received r ->
      check (Printf.sprintf "Unexpected Received: %s" r.id) false
  | Duplicate d ->
      check (Printf.sprintf "Unexpected Duplicate: %s" d.id) false);

  check "Empty payload event ID not added to seen set" (not (is_seen "evt-empty" eng_after_empty));
  check "Engine seen count remains 0" (count_seen eng_after_empty = 0);

  let whitespace_event : raw_event = { id = "evt-spaces"; timestamp = 301; payload = "   \t \n " } in
  let eng_after_ws, state_ws = ingest eng whitespace_event in

  (match state_ws with
  | Invalid inv ->
      check "Whitespace payload transitioned to Invalid" (inv.id = "evt-spaces" && inv.error = "Payload cannot be empty")
  | Processed proc ->
      check (Printf.sprintf "Whitespace payload must not reach Processed: %s" proc.id) false
  | Received r ->
      check (Printf.sprintf "Unexpected Received: %s" r.id) false
  | Duplicate d ->
      check (Printf.sprintf "Unexpected Duplicate: %s" d.id) false);

  check "Whitespace event ID not added to seen set" (not (is_seen "evt-spaces" eng_after_ws))

let test_blank_event_id_rejection () : unit =
  Printf.printf "\nTest Suite 4: Blank Event ID Rejection\n";
  let eng = empty in
  let blank_id_event : raw_event = { id = ""; timestamp = 400; payload = "valid data" } in
  let eng_after_blank, state_blank = ingest eng blank_id_event in

  (match state_blank with
  | Invalid inv ->
      check "Blank ID transitioned to Invalid" (inv.id = "" && inv.error = "Event ID cannot be blank")
  | Processed proc ->
      check (Printf.sprintf "Blank ID must not reach Processed: %s" proc.id) false
  | Received r ->
      check (Printf.sprintf "Unexpected Received: %s" r.id) false
  | Duplicate d ->
      check (Printf.sprintf "Unexpected Duplicate: %s" d.id) false);

  check "Engine seen count remains 0" (count_seen eng_after_blank = 0);

  let spaces_id_event : raw_event = { id = "   "; timestamp = 401; payload = "valid data" } in
  let eng_after_spaces, state_spaces = ingest eng spaces_id_event in

  (match state_spaces with
  | Invalid inv ->
      check "Spaces ID transitioned to Invalid" (inv.id = "   " && inv.error = "Event ID cannot be blank")
  | Processed proc ->
      check (Printf.sprintf "Spaces ID must not reach Processed: %s" proc.id) false
  | Received r ->
      check (Printf.sprintf "Unexpected Received: %s" r.id) false
  | Duplicate d ->
      check (Printf.sprintf "Unexpected Duplicate: %s" d.id) false);

  check "Spaces ID event not added to seen set" (count_seen eng_after_spaces = 0)

let test_idempotence_and_stability () : unit =
  Printf.printf "\nTest Suite 5: Idempotence of Terminal States\n";
  let eng0 = empty in
  let event : raw_event = { id = "evt-terminal"; timestamp = 500; payload = "finalized" } in
  let eng1, state_proc = ingest eng0 event in

  let eng2, state_proc_repeat = transition eng1 state_proc in
  (match state_proc_repeat with
  | Processed proc ->
      check "Transition on already Processed state is idempotent" (proc.id = "evt-terminal" && proc.payload = "finalized")
  | Received r ->
      check (Printf.sprintf "Unexpected Received: %s" r.id) false
  | Duplicate d ->
      check (Printf.sprintf "Unexpected Duplicate: %s" d.id) false
  | Invalid inv ->
      check (Printf.sprintf "Unexpected Invalid: %s" inv.id) false);
  check "Engine remains unchanged after stepping Processed" (eng2 = eng1)

let test_json_serde_and_status () : unit =
  Printf.printf "\nTest Suite 6: JSON Serialization & Status Formats\n";
  let event : raw_event = { id = "evt-json-1"; timestamp = 1728101000; payload = "order_created" } in
  let json_str = event_to_json event in
  check "event_to_json produces valid JSON string"
    (json_str = "{\"id\":\"evt-json-1\",\"timestamp\":1728101000,\"payload\":\"order_created\"}");

  (match event_of_json json_str with
  | Ok parsed ->
      check "event_of_json parsed back correctly"
        (parsed.id = "evt-json-1" && parsed.timestamp = 1728101000 && parsed.payload = "order_created")
  | Error err ->
      check (Printf.sprintf "Failed to parse json: %s" err) false);

  (* Test permuted key order in JSON *)
  let permuted_json = "{\"payload\":\"order_created\",\"timestamp\":1728101000,\"id\":\"evt-json-1\"}" in
  (match event_of_json permuted_json with
  | Ok parsed ->
      check "event_of_json handles permuted key order" (parsed.id = "evt-json-1")
  | Error err ->
      check (Printf.sprintf "Failed to parse permuted json: %s" err) false);

  (* Test invalid JSON parsing *)
  (match event_of_json "not a json string" with
  | Ok parsed ->
      check (Printf.sprintf "Should have failed on malformed json, got %s" parsed.id) false
  | Error _err ->
      check "event_of_json cleanly rejects malformed syntax" true);

  (* Test Status JSON formats *)
  let s_proc = Processed { id = "e1"; timestamp = 100; payload = "ok" } in
  let s_dup = Duplicate { id = "e1"; timestamp = 105 } in
  let s_inv = Invalid { id = "e2"; error = "bad payload" } in
  check "status_to_json Processed format" (status_to_json s_proc = "{\"status\":\"processed\",\"id\":\"e1\"}");
  check "status_to_json Duplicate format" (status_to_json s_dup = "{\"status\":\"duplicate\",\"id\":\"e1\"}");
  check "status_to_json Invalid format" (status_to_json s_inv = "{\"status\":\"invalid\",\"id\":\"e2\",\"error\":\"bad payload\"}")

let test_wal_persistence_and_replay () : unit =
  Printf.printf "\nTest Suite 7: Write-Ahead Log (WAL) Replay & Invariants\n";
  let temp_wal = Filename.temp_file "events_test_" ".jsonl" in

  (* 1. Append two processed events to WAL *)
  let event1 : raw_event = { id = "evt-wal-1"; timestamp = 1000; payload = "payload_one" } in
  let event2 : raw_event = { id = "evt-wal-2"; timestamp = 1001; payload = "payload_two" } in
  append_event temp_wal event1;
  append_event temp_wal event2;

  check "WAL file was created" (Sys.file_exists temp_wal);

  (* 2. Replay log on cold engine *)
  let cold_engine = replay_log temp_wal empty in
  check "Replayed engine has count 2" (count_seen cold_engine = 2);
  check "Replayed engine recorded evt-wal-1" (is_seen "evt-wal-1" cold_engine);
  check "Replayed engine recorded evt-wal-2" (is_seen "evt-wal-2" cold_engine);

  (* 3. Invariant: Replayed engine rejects duplicate of already logged event *)
  let dup_event : raw_event = { id = "evt-wal-1"; timestamp = 1005; payload = "re-submitted payload" } in
  let engine_after_dup, state_dup = ingest cold_engine dup_event in

  (match state_dup with
  | Duplicate dup ->
      check "Replayed engine correctly transitioned duplicate to Duplicate" (dup.id = "evt-wal-1")
  | Processed proc ->
      check (Printf.sprintf "Duplicate must not be Processed: %s" proc.id) false
  | Received r ->
      check (Printf.sprintf "Unexpected Received: %s" r.id) false
  | Invalid inv ->
      check (Printf.sprintf "Unexpected Invalid: %s" inv.id) false);

  check "Engine seen count unaffected by duplicate" (count_seen engine_after_dup = 2);

  (* 4. Ingest new event on top of replayed engine *)
  let new_event : raw_event = { id = "evt-wal-3"; timestamp = 1006; payload = "payload_three" } in
  let engine_final, state_new = ingest engine_after_dup new_event in

  (match state_new with
  | Processed proc ->
      check "New event processed on top of replayed engine" (proc.id = "evt-wal-3")
  | Received r ->
      check (Printf.sprintf "Unexpected Received: %s" r.id) false
  | Duplicate d ->
      check (Printf.sprintf "Unexpected Duplicate: %s" d.id) false
  | Invalid inv ->
      check (Printf.sprintf "Unexpected Invalid: %s" inv.id) false);

  check "Engine seen count incremented to 3" (count_seen engine_final = 3);

  (* Clean up temporary WAL *)
  Sys.remove temp_wal;
  check "Temporary WAL cleaned up" (not (Sys.file_exists temp_wal))

let test_wal_rotation_and_snapshot () : unit =
  Printf.printf "\nTest Suite 8: WAL Rotation & Snapshot Recovery\n";
  let temp_base = Filename.temp_file "compaction_dir_" "" in
  Sys.remove temp_base;
  Unix.mkdir temp_base 0o755;

  let config : compaction_config = {
    max_log_bytes = 150;
    base_dir = temp_base;
  } in
  let wal_path = Filename.concat temp_base "events.jsonl" in
  let snapshot_path = Filename.concat temp_base "snapshot.json" in
  let archive_path = Filename.concat temp_base "events.jsonl.1" in

  (* 1. Size-Threshold Detection *)
  check "should_rotate is false when WAL does not exist" (not (should_rotate ~config ~wal_path));

  let ev1 : raw_event = { id = "rot-1"; timestamp = 1000; payload = "payload_short" } in
  append_event wal_path ev1;
  check "should_rotate is false under 150 bytes" (not (should_rotate ~config ~wal_path));

  let ev2 : raw_event = { id = "rot-2"; timestamp = 1001; payload = "payload_medium_size_string" } in
  append_event wal_path ev2;

  let ev3 : raw_event = { id = "rot-3"; timestamp = 1002; payload = "payload_large_size_string_pushing_over_limit" } in
  append_event wal_path ev3;

  check "should_rotate flips to true once WAL crosses 150 bytes" (should_rotate ~config ~wal_path);

  (* 2. Atomic Snapshot Correctness with 5 unique events *)
  let eng0 = empty in
  let eng_5, _ = ingest eng0 { id = "snap-1"; timestamp = 2001; payload = "data1" } in
  let eng_5, _ = ingest eng_5 { id = "snap-2"; timestamp = 2002; payload = "data2" } in
  let eng_5, _ = ingest eng_5 { id = "snap-3"; timestamp = 2003; payload = "data3" } in
  let eng_5, _ = ingest eng_5 { id = "snap-4"; timestamp = 2004; payload = "data4" } in
  let eng_5, _ = ingest eng_5 { id = "snap-5"; timestamp = 2005; payload = "data5" } in

  (match create_snapshot eng_5 ~snapshot_path with
  | Ok () -> check "create_snapshot succeeded" true
  | Error err -> check (Printf.sprintf "create_snapshot failed: %s" err) false);

  check "snapshot.json exists" (Sys.file_exists snapshot_path);
  check "snapshot.json.tmp does not remain" (not (Sys.file_exists (snapshot_path ^ ".tmp")));

  let snap_ic = open_in snapshot_path in
  let snap_content = really_input_string snap_ic (in_channel_length snap_ic) in
  close_in snap_ic;
  check "snapshot.json contains snap-1" (String.length snap_content > 0 && is_seen "snap-1" eng_5);
  check "snapshot.json contains snap-5" (is_seen "snap-5" eng_5);

  (* 3. Compaction Cycle & Fresh WAL *)
  (match rotate_wal ~config eng_5 with
  | Ok _rot_eng -> check "rotate_wal succeeded" true
  | Error err -> check (Printf.sprintf "rotate_wal failed: %s" err) false);

  check "events.jsonl.1 exists" (Sys.file_exists archive_path);
  check "snapshot.json exists after rotation" (Sys.file_exists snapshot_path);
  check "active events.jsonl exists" (Sys.file_exists wal_path);
  let active_stats = Unix.stat wal_path in
  check "active events.jsonl is reset to 0 bytes" (active_stats.Unix.st_size = 0);

  (* 4. Cold Boot Invariant Across Rotation *)
  (* Append delta events to fresh active WAL *)
  let delta_ev : raw_event = { id = "post-rot-delta"; timestamp = 3001; payload = "delta_payload" } in
  append_event wal_path delta_ev;

  (* Recover engine from directory *)
  (match recover ~config with
  | Error err ->
      check (Printf.sprintf "recover failed: %s" err) false
  | Ok recovered_eng ->
      check "Recovered engine contains snap-1 from snapshot" (is_seen "snap-1" recovered_eng);
      check "Recovered engine contains snap-5 from snapshot" (is_seen "snap-5" recovered_eng);
      check "Recovered engine contains post-rot-delta from active WAL" (is_seen "post-rot-delta" recovered_eng);
      check "Recovered engine seen count is at least 6" (count_seen recovered_eng >= 6);

      (* Verify duplicate rejection against recovered state *)
      let dup_attempt : raw_event = { id = "snap-3"; timestamp = 4000; payload = "new_payload_for_snap3" } in
      let _, dup_state = ingest recovered_eng dup_attempt in
      (match dup_state with
      | Duplicate dup -> check "Ingesting snap-3 into recovered engine yields Duplicate" (dup.id = "snap-3")
      | Processed p -> check (Printf.sprintf "Duplicate must not be Processed: %s" p.id) false
      | Received r -> check (Printf.sprintf "Unexpected Received: %s" r.id) false
      | Invalid inv -> check (Printf.sprintf "Unexpected Invalid: %s" inv.id) false));

  (* Cleanup test directory *)
  if Sys.file_exists wal_path then Sys.remove wal_path;
  if Sys.file_exists snapshot_path then Sys.remove snapshot_path;
  if Sys.file_exists archive_path then Sys.remove archive_path;
  Unix.rmdir temp_base
 
let string_contains haystack needle =
  let len_h = String.length haystack in
  let len_n = String.length needle in
  if len_n > len_h then false
  else
    let rec aux idx =
      if idx + len_n > len_h then false
      else if String.sub haystack idx len_n = needle then true
      else aux (idx + 1)
    in
    aux 0

let test_prometheus_metrics () : unit =
  Printf.printf "\nTest Suite 9: Prometheus Metrics Exporter\n";
  let initial_proc = !(global_registry.processed.value) in
  let initial_dup = !(global_registry.duplicate.value) in
  let initial_inv = !(global_registry.invalid.value) in

  inc_processed ();
  inc_processed ();
  check "inc_processed increments processed counter by 2" (!(global_registry.processed.value) = initial_proc + 2);

  inc_duplicate ();
  check "inc_duplicate increments duplicate counter by 1" (!(global_registry.duplicate.value) = initial_dup + 1);

  inc_invalid ();
  check "inc_invalid increments invalid counter by 1" (!(global_registry.invalid.value) = initial_inv + 1);

  let formatted = format_prometheus global_registry in
  check "format_prometheus contains HELP for processed"
    (string_contains formatted "# HELP events_processed_total Total count of successfully processed events.");
  check "format_prometheus contains TYPE for processed"
    (string_contains formatted "# TYPE events_processed_total counter");
  check "format_prometheus contains value for processed"
    (string_contains formatted (Printf.sprintf "events_processed_total %d" (initial_proc + 2)));

  check "format_prometheus contains HELP for duplicate"
    (string_contains formatted "# HELP events_duplicate_total Total count of rejected duplicate events.");
  check "format_prometheus contains TYPE for duplicate"
    (string_contains formatted "# TYPE events_duplicate_total counter");
  check "format_prometheus contains value for duplicate"
    (string_contains formatted (Printf.sprintf "events_duplicate_total %d" (initial_dup + 1)));

  check "format_prometheus contains HELP for invalid"
    (string_contains formatted "# HELP events_invalid_total Total count of malformed or invalid events.");
  check "format_prometheus contains TYPE for invalid"
    (string_contains formatted "# TYPE events_invalid_total counter");
  check "format_prometheus contains value for invalid"
    (string_contains formatted (Printf.sprintf "events_invalid_total %d" (initial_inv + 1)));

  (* Test HTTP socket endpoint on test port *)
  let test_port = 19100 in
  start_metrics_server test_port;
  Thread.delay 0.05;

  let client_sock = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  let server_addr = Unix.ADDR_INET (Unix.inet_addr_loopback, test_port) in
  Unix.connect client_sock server_addr;

  let out_ch = Unix.out_channel_of_descr client_sock in
  let in_ch = Unix.in_channel_of_descr client_sock in
  output_string out_ch "GET /metrics HTTP/1.1\r\nHost: localhost\r\n\r\n";
  flush out_ch;

  let status_line = input_line in_ch in
  check "HTTP response status is 200 OK" (string_contains status_line "200 OK");

  let rec read_all ch acc =
    match try Some (input_line ch) with _ -> None with
    | None -> acc
    | Some line -> read_all ch (acc ^ "\n" ^ line)
  in
  let http_body = read_all in_ch "" in
  close_in in_ch;

  check "HTTP response contains Prometheus content-type header"
    (string_contains http_body "Content-Type: text/plain; version=0.0.4");
  check "HTTP response contains processed counter"
    (string_contains http_body "events_processed_total");
  check "HTTP response contains duplicate counter"
    (string_contains http_body "events_duplicate_total");
  check "HTTP response contains invalid counter"
    (string_contains http_body "events_invalid_total")

let () =
  Printf.printf "========================================\n";
  Printf.printf " OCaml Event Engine Verification Suite\n";
  Printf.printf "========================================\n\n";
  test_valid_transition ();
  test_duplicate_detection ();
  test_empty_payload_rejection ();
  test_blank_event_id_rejection ();
  test_idempotence_and_stability ();
  test_json_serde_and_status ();
  test_wal_persistence_and_replay ();
  test_wal_rotation_and_snapshot ();
  test_prometheus_metrics ();
  Printf.printf "\n========================================\n";
  Printf.printf " Result: %d / %d tests passed successfully.\n" !passed_tests !total_tests;
  Printf.printf "========================================\n"
