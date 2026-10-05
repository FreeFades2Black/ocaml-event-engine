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
