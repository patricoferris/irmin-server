open Lwt.Syntax
open Lwt.Infix
open Irmin_client_unix
module Store = Irmin_mem.KV.Make (Irmin.Contents.String)
module Client = Make (Store)
module Info = Info (Client.Info)

let main =
  let uri = Uri.of_string "tcp://localhost:9090" in
  let* client = Client.connect ~uri () in

  (* Get current branch name *)
  let* current_branch =
    Client.Branch.get_current client >|= Error.unwrap "Branch.get_current"
  in
  assert (current_branch = Client.Branch.main);

  (* Set a/b/c on [current_branch] *)
  let info = Info.v "set a/b/c" in
  let* () =
    Client.set ~info client [ "a"; "b"; "c" ] "123" >|= Error.unwrap "Store.set"
  in

  (* Switch to new [test] branch *)
  let* () =
    Client.Branch.set_current client "test"
    >|= Error.unwrap "Branch.set_current"
  in

  (* Get a/b/c in [test] branch (should be None) *)
  let* abc =
    Client.find client [ "a"; "b"; "c" ] >|= Error.unwrap "Store.find"
  in
  assert (Option.is_none abc);

  (* Switch back to [current_branch] and get a/b/c *)
  let* () =
    Client.Branch.set_current client current_branch
    >|= Error.unwrap "Branch.set_current"
  in
  let+ abc =
    Client.find client [ "a"; "b"; "c" ] >|= Error.unwrap "Store.find"
  in
  assert (Option.is_some abc)

let () = Lwt_main.run main
