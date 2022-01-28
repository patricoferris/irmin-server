open Lwt.Syntax
module Store = Irmin_mem.KV.Make (Irmin.Contents.String)
module Client = Irmin_client.Make (Store)

let main =
  let uri = Uri.of_string "tcp://localhost:9090" in
  let* client = Client.connect ~uri () in
  let+ res = Client.ping client in
  match res with
  | Ok () -> print_endline "OK"
  | Error e ->
      Printf.printf "ERROR: %s\n" (Irmin_server_types.Error.to_string e)

let () = Lwt_main.run main
