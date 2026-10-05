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

let global_registry = {
  processed = {
    name = "events_processed_total";
    help = "Total count of successfully processed events.";
    value = ref 0;
  };
  duplicate = {
    name = "events_duplicate_total";
    help = "Total count of rejected duplicate events.";
    value = ref 0;
  };
  invalid = {
    name = "events_invalid_total";
    help = "Total count of malformed or invalid events.";
    value = ref 0;
  };
}

let inc_processed () = incr global_registry.processed.value
let inc_duplicate () = incr global_registry.duplicate.value
let inc_invalid () = incr global_registry.invalid.value

let format_prometheus r =
  let render_counter c =
    Printf.sprintf "# HELP %s %s\n# TYPE %s counter\n%s %d\n"
      c.name c.help c.name c.name !(c.value)
  in
  render_counter r.processed ^
  render_counter r.duplicate ^
  render_counter r.invalid

let rec drain_headers in_ch =
  match try Some (input_line in_ch) with _ -> None with
  | None -> ()
  | Some line ->
      let trimmed = String.trim line in
      if trimmed = "" then ()
      else drain_headers in_ch

let handle_client client_sock =
  try
    Unix.setsockopt_float client_sock Unix.SO_RCVTIMEO 2.0;
    let in_ch = Unix.in_channel_of_descr client_sock in
    let out_ch = Unix.out_channel_of_descr client_sock in
    let _request_line = try input_line in_ch with _ -> "" in
    drain_headers in_ch;
    let body = format_prometheus global_registry in
    let response =
      Printf.sprintf
        "HTTP/1.1 200 OK\r\nContent-Type: text/plain; version=0.0.4\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s"
        (String.length body) body
    in
    output_string out_ch response;
    flush out_ch;
    try close_in in_ch with _ -> ()
  with _ ->
    try Unix.close client_sock with _ -> ()

let start_metrics_server port =
  let server_sock = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt server_sock Unix.SO_REUSEADDR true;
  Unix.bind server_sock (Unix.ADDR_INET (Unix.inet_addr_any, port));
  Unix.listen server_sock 10;
  let _thread =
    Thread.create
      (fun () ->
        while true do
          try
            let client_sock, _ = Unix.accept server_sock in
            try handle_client client_sock with _ -> ()
          with _ -> ()
        done)
      ()
  in
  ignore _thread
