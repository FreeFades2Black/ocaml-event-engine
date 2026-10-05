module StringSet = Set.Make (String)

type raw_event = {
  id : string;
  timestamp : int;
  payload : string;
}

type state =
  | Received of raw_event
  | Duplicate of { id : string; timestamp : int }
  | Processed of { id : string; timestamp : int; payload : string }
  | Invalid of { id : string; error : string }

type engine = {
  seen_ids : StringSet.t;
}

type compaction_config = {
  max_log_bytes : int;
  base_dir : string;
}

let empty : engine = {
  seen_ids = StringSet.empty;
}

let is_seen (id : string) (engine : engine) : bool =
  StringSet.mem id engine.seen_ids

let count_seen (engine : engine) : int =
  StringSet.cardinal engine.seen_ids

let make_event ~(id : string) ~(timestamp : int) ~(payload : string) : state =
  Received { id; timestamp; payload }

let transition (engine : engine) (s : state) : engine * state =
  match s with
  | Received event ->
      let trimmed_id = String.trim event.id in
      let trimmed_payload = String.trim event.payload in
      if String.length trimmed_id = 0 then
        (engine, Invalid { id = event.id; error = "Event ID cannot be blank" })
      else if String.length trimmed_payload = 0 then
        (engine, Invalid { id = event.id; error = "Payload cannot be empty" })
      else if StringSet.mem event.id engine.seen_ids then
        (engine, Duplicate { id = event.id; timestamp = event.timestamp })
      else
        let updated_seen = StringSet.add event.id engine.seen_ids in
        let next_engine = { seen_ids = updated_seen } in
        let next_state =
          Processed
            {
              id = event.id;
              timestamp = event.timestamp;
              payload = event.payload;
            }
        in
        (next_engine, next_state)
  | Duplicate dup ->
      (engine, Duplicate { id = dup.id; timestamp = dup.timestamp })
  | Processed proc ->
      ( engine,
        Processed
          {
            id = proc.id;
            timestamp = proc.timestamp;
            payload = proc.payload;
          } )
  | Invalid inv ->
      (engine, Invalid { id = inv.id; error = inv.error })

let ingest (engine : engine) (event : raw_event) : engine * state =
  transition engine (Received event)

let json_escape (s : string) : string =
  let buf = Buffer.create (String.length s + 16) in
  String.iter
    (function
      | '"' -> Buffer.add_string buf "\\\""
      | '\\' -> Buffer.add_string buf "\\\\"
      | '\n' -> Buffer.add_string buf "\\n"
      | '\r' -> Buffer.add_string buf "\\r"
      | '\t' -> Buffer.add_string buf "\\t"
      | c -> Buffer.add_char buf c)
    s;
  Buffer.contents buf

let event_to_json (event : raw_event) : string =
  Printf.sprintf "{\"id\":\"%s\",\"timestamp\":%d,\"payload\":\"%s\"}"
    (json_escape event.id) event.timestamp (json_escape event.payload)

let status_to_json (s : state) : string =
  match s with
  | Processed proc ->
      Printf.sprintf "{\"status\":\"processed\",\"id\":\"%s\"}"
        (json_escape proc.id)
  | Duplicate dup ->
      Printf.sprintf "{\"status\":\"duplicate\",\"id\":\"%s\"}"
        (json_escape dup.id)
  | Invalid inv ->
      Printf.sprintf "{\"status\":\"invalid\",\"id\":\"%s\",\"error\":\"%s\"}"
        (json_escape inv.id) (json_escape inv.error)
  | Received r ->
      Printf.sprintf "{\"status\":\"received\",\"id\":\"%s\"}"
        (json_escape r.id)

type token =
  | Tok_LBrace
  | Tok_RBrace
  | Tok_LBracket
  | Tok_RBracket
  | Tok_Colon
  | Tok_Comma
  | Tok_String of string
  | Tok_Int of int
  | Tok_Other of string

let tokenize (s : string) : (token list, string) result =
  let len = String.length s in
  let rec scan idx acc =
    if idx >= len then Ok (List.rev acc)
    else
      match s.[idx] with
      | ' ' | '\t' | '\r' | '\n' -> scan (idx + 1) acc
      | '{' -> scan (idx + 1) (Tok_LBrace :: acc)
      | '}' -> scan (idx + 1) (Tok_RBrace :: acc)
      | '[' -> scan (idx + 1) (Tok_LBracket :: acc)
      | ']' -> scan (idx + 1) (Tok_RBracket :: acc)
      | ':' -> scan (idx + 1) (Tok_Colon :: acc)
      | ',' -> scan (idx + 1) (Tok_Comma :: acc)
      | '"' ->
          let buf = Buffer.create 32 in
          let rec read_str j =
            if j >= len then Error "Unterminated string in JSON"
            else
              match s.[j] with
              | '"' -> Ok (j + 1, Buffer.contents buf)
              | '\\' ->
                  if j + 1 >= len then Error "Invalid escape in JSON string"
                  else
                    let next_char =
                      match s.[j + 1] with
                      | '"' -> '"'
                      | '\\' -> '\\'
                      | '/' -> '/'
                      | 'n' -> '\n'
                      | 'r' -> '\r'
                      | 't' -> '\t'
                      | 'b' -> '\b'
                      | c -> c
                    in
                    Buffer.add_char buf next_char;
                    read_str (j + 2)
              | c ->
                  Buffer.add_char buf c;
                  read_str (j + 1)
          in
          (match read_str (idx + 1) with
          | Ok (next_idx, str_val) -> scan next_idx (Tok_String str_val :: acc)
          | Error err -> Error err)
      | '-' | '0' .. '9' ->
          let start_idx = idx in
          let rec read_num j =
            if j < len && ((s.[j] >= '0' && s.[j] <= '9') || s.[j] = '-') then
              read_num (j + 1)
            else j
          in
          let end_idx = read_num (idx + 1) in
          let num_str = String.sub s start_idx (end_idx - start_idx) in
          (match int_of_string_opt num_str with
          | Some n -> scan end_idx (Tok_Int n :: acc)
          | None -> Error (Printf.sprintf "Invalid integer: %s" num_str))
      | _ ->
          let start_idx = idx in
          let rec read_other j =
            if
              j < len
              && s.[j] <> ','
              && s.[j] <> '}'
              && s.[j] <> ']'
              && s.[j] <> ' '
              && s.[j] <> '\t'
              && s.[j] <> '\r'
              && s.[j] <> '\n'
            then read_other (j + 1)
            else j
          in
          let end_idx = read_other (idx + 1) in
          let o_str = String.sub s start_idx (end_idx - start_idx) in
          scan end_idx (Tok_Other o_str :: acc)
  in
  scan 0 []

let event_of_json (s : string) : (raw_event, string) result =
  match tokenize s with
  | Error err -> Error err
  | Ok tokens -> (
      match tokens with
      | Tok_LBrace :: rest ->
          let rec parse_pairs cur_toks id_opt ts_opt pl_opt =
            match cur_toks with
            | Tok_RBrace :: [] -> (
                match (id_opt, ts_opt, pl_opt) with
                | Some id, Some ts, Some pl ->
                    Ok { id; timestamp = ts; payload = pl }
                | None, _, _ -> Error "Missing required field 'id'"
                | _, None, _ -> Error "Missing required field 'timestamp'"
                | _, _, None -> Error "Missing required field 'payload'")
            | Tok_String key :: Tok_Colon :: Tok_String str_val :: remaining ->
                let next_id, next_pl, next_ts =
                  if key = "id" then (Some str_val, pl_opt, ts_opt)
                  else if key = "payload" then (id_opt, Some str_val, ts_opt)
                  else if key = "timestamp" then
                    (id_opt, pl_opt, int_of_string_opt str_val)
                  else (id_opt, pl_opt, ts_opt)
                in
                check_sep remaining next_id next_ts next_pl
            | Tok_String key :: Tok_Colon :: Tok_Int int_val :: remaining ->
                let next_ts =
                  if key = "timestamp" then Some int_val else ts_opt
                in
                check_sep remaining id_opt next_ts pl_opt
            | Tok_String _key :: Tok_Colon :: Tok_Other _ :: remaining ->
                check_sep remaining id_opt ts_opt pl_opt
            | _ -> Error "Syntax error in JSON object structure"
          and check_sep toks id_opt ts_opt pl_opt =
            match toks with
            | Tok_Comma :: next_pairs ->
                parse_pairs next_pairs id_opt ts_opt pl_opt
            | Tok_RBrace :: [] -> parse_pairs [ Tok_RBrace ] id_opt ts_opt pl_opt
            | _ -> Error "Expected comma or closing brace in JSON object"
          in
          parse_pairs rest None None None
      | _ -> Error "JSON must be an object starting with '{'")

let append_event (path : string) (event : raw_event) : unit =
  let oc = open_out_gen [ Open_append; Open_creat; Open_text ] 0o644 path in
  output_string oc (event_to_json event);
  output_char oc '\n';
  flush oc;
  close_out oc

let replay_log (path : string) (engine : engine) : engine =
  if not (Sys.file_exists path) then engine
  else
    let ic = open_in path in
    let rec loop acc =
      match input_line ic with
      | line ->
          let trimmed = String.trim line in
          let next_acc =
            if String.length trimmed = 0 then acc
            else
              match event_of_json trimmed with
              | Ok evt ->
                  if String.length (String.trim evt.id) > 0 then
                    { seen_ids = StringSet.add evt.id acc.seen_ids }
                  else acc
              | Error err ->
                  ignore err;
                  acc
          in
          loop next_acc
      | exception End_of_file ->
          close_in ic;
          acc
    in
    try loop engine
    with exn ->
      ignore exn;
      close_in_noerr ic;
      engine

let should_rotate ~(config : compaction_config) ~(wal_path : string) : bool =
  try
    let stats = Unix.stat wal_path in
    stats.Unix.st_size >= config.max_log_bytes
  with
  | Unix.Unix_error (Unix.ENOENT, _, _) -> false
  | exn ->
      ignore exn;
      false

let create_snapshot (eng : engine) ~(snapshot_path : string) :
    (unit, string) result =
  let tmp_path = snapshot_path ^ ".tmp" in
  try
    let oc = open_out_gen [ Open_wronly; Open_creat; Open_trunc ] 0o644 tmp_path in
    output_string oc "{\"seen_ids\":[";
    let first = ref true in
    StringSet.iter
      (fun id ->
        if not !first then output_string oc "," else first := false;
        Printf.fprintf oc "\"%s\"" (json_escape id))
      eng.seen_ids;
    output_string oc "]}\n";
    flush oc;
    close_out oc;
    Sys.rename tmp_path snapshot_path;
    Ok ()
  with
  | Sys_error err -> Error ("Snapshot failure: " ^ err)
  | exn -> Error ("Unexpected snapshot failure: " ^ Printexc.to_string exn)

let load_snapshot (path : string) (eng : engine) : (engine, string) result =
  if not (Sys.file_exists path) then Ok eng
  else
    try
      let ic = open_in path in
      let content = really_input_string ic (in_channel_length ic) in
      close_in ic;
      match tokenize content with
      | Error err -> Error ("Snapshot tokenization error: " ^ err)
      | Ok tokens ->
          let rec parse_ids toks acc in_seen_ids =
            match toks with
            | [] -> Ok { seen_ids = acc }
            | Tok_String "seen_ids" :: Tok_Colon :: Tok_LBracket :: rest ->
                parse_ids rest acc true
            | Tok_String id :: rest when in_seen_ids ->
                parse_ids rest (StringSet.add id acc) true
            | Tok_RBracket :: rest ->
                parse_ids rest acc false
            | _other :: rest ->
                parse_ids rest acc in_seen_ids
          in
          parse_ids tokens eng.seen_ids false
    with
    | Sys_error err -> Error ("Failed to read snapshot: " ^ err)
    | exn -> Error ("Unexpected error loading snapshot: " ^ Printexc.to_string exn)

let rotate_wal ~(config : compaction_config) (eng : engine) :
    (engine, string) result =
  let wal_path = Filename.concat config.base_dir "events.jsonl" in
  let snapshot_path = Filename.concat config.base_dir "snapshot.json" in
  let wal_archive = Filename.concat config.base_dir "events.jsonl.1" in
  match create_snapshot eng ~snapshot_path with
  | Error err -> Error err
  | Ok () -> (
      try
        if Sys.file_exists wal_path then Sys.rename wal_path wal_archive;
        let oc =
          open_out_gen [ Open_wronly; Open_creat; Open_trunc ] 0o644 wal_path
        in
        flush oc;
        close_out oc;
        Ok eng
      with
      | Sys_error err -> Error ("WAL rotation failure: " ^ err)
      | exn ->
          Error ("Unexpected WAL rotation failure: " ^ Printexc.to_string exn))

let recover ~(config : compaction_config) : (engine, string) result =
  let wal_path = Filename.concat config.base_dir "events.jsonl" in
  let snapshot_path = Filename.concat config.base_dir "snapshot.json" in
  let wal_archive = Filename.concat config.base_dir "events.jsonl.1" in
  let base_engine = empty in
  let snapshot_res =
    if Sys.file_exists snapshot_path then
      load_snapshot snapshot_path base_engine
    else Ok base_engine
  in
  match snapshot_res with
  | Error err -> Error err
  | Ok eng_snap ->
      let eng_archive =
        if Sys.file_exists wal_archive then replay_log wal_archive eng_snap
        else eng_snap
      in
      let eng_final =
        if Sys.file_exists wal_path then replay_log wal_path eng_archive
        else eng_archive
      in
      Ok eng_final
