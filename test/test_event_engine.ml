open Event_engine

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
      check (Printf.sprintf "Duplicate must not be Processed: %s (ts=%d, pl=%s)" proc.id proc.timestamp proc.payload) false
  | Received r ->
      check (Printf.sprintf "Unexpected Received: %s (ts=%d, pl=%s)" r.id r.timestamp r.payload) false
  | Invalid inv ->
      check (Printf.sprintf "Unexpected Invalid: %s (err=%s)" inv.id inv.error) false);

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
      check (Printf.sprintf "Empty payload must not reach Processed: %s (ts=%d, pl=%s)" proc.id proc.timestamp proc.payload) false
  | Received r ->
      check (Printf.sprintf "Unexpected Received: %s (ts=%d, pl=%s)" r.id r.timestamp r.payload) false
  | Duplicate d ->
      check (Printf.sprintf "Unexpected Duplicate: %s (ts=%d)" d.id d.timestamp) false);

  check "Empty payload event ID not added to seen set" (not (is_seen "evt-empty" eng_after_empty));
  check "Engine seen count remains 0" (count_seen eng_after_empty = 0);

  let whitespace_event : raw_event = { id = "evt-spaces"; timestamp = 301; payload = "   \t \n " } in
  let eng_after_ws, state_ws = ingest eng whitespace_event in

  (match state_ws with
  | Invalid inv ->
      check "Whitespace payload transitioned to Invalid" (inv.id = "evt-spaces" && inv.error = "Payload cannot be empty")
  | Processed proc ->
      check (Printf.sprintf "Whitespace payload must not reach Processed: %s (ts=%d, pl=%s)" proc.id proc.timestamp proc.payload) false
  | Received r ->
      check (Printf.sprintf "Unexpected Received: %s (ts=%d, pl=%s)" r.id r.timestamp r.payload) false
  | Duplicate d ->
      check (Printf.sprintf "Unexpected Duplicate: %s (ts=%d)" d.id d.timestamp) false);

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
      check (Printf.sprintf "Blank ID must not reach Processed: %s (ts=%d, pl=%s)" proc.id proc.timestamp proc.payload) false
  | Received r ->
      check (Printf.sprintf "Unexpected Received: %s (ts=%d, pl=%s)" r.id r.timestamp r.payload) false
  | Duplicate d ->
      check (Printf.sprintf "Unexpected Duplicate: %s (ts=%d)" d.id d.timestamp) false);

  check "Engine seen count remains 0" (count_seen eng_after_blank = 0);

  let spaces_id_event : raw_event = { id = "   "; timestamp = 401; payload = "valid data" } in
  let eng_after_spaces, state_spaces = ingest eng spaces_id_event in

  (match state_spaces with
  | Invalid inv ->
      check "Spaces ID transitioned to Invalid" (inv.id = "   " && inv.error = "Event ID cannot be blank")
  | Processed proc ->
      check (Printf.sprintf "Spaces ID must not reach Processed: %s (ts=%d, pl=%s)" proc.id proc.timestamp proc.payload) false
  | Received r ->
      check (Printf.sprintf "Unexpected Received: %s (ts=%d, pl=%s)" r.id r.timestamp r.payload) false
  | Duplicate d ->
      check (Printf.sprintf "Unexpected Duplicate: %s (ts=%d)" d.id d.timestamp) false);

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
      check (Printf.sprintf "Unexpected Received: %s (ts=%d, pl=%s)" r.id r.timestamp r.payload) false
  | Duplicate d ->
      check (Printf.sprintf "Unexpected Duplicate: %s (ts=%d)" d.id d.timestamp) false
  | Invalid inv ->
      check (Printf.sprintf "Unexpected Invalid: %s (err=%s)" inv.id inv.error) false);
  check "Engine remains unchanged after stepping Processed" (eng2 = eng1)

let () =
  Printf.printf "========================================\n";
  Printf.printf " OCaml Event Engine Verification Suite\n";
  Printf.printf "========================================\n\n";
  test_valid_transition ();
  test_duplicate_detection ();
  test_empty_payload_rejection ();
  test_blank_event_id_rejection ();
  test_idempotence_and_stability ();
  Printf.printf "\n========================================\n";
  Printf.printf " Result: %d / %d tests passed successfully.\n" !passed_tests !total_tests;
  Printf.printf "========================================\n"
