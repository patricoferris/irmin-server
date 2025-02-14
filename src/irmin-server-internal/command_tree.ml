open Lwt.Syntax

module Make
    (IO : Conn.IO)
    (Codec : Conn.Codec.S)
    (Store : Irmin.Generic_key.S)
    (Tree : Tree.S
              with module Private.Store = Store
               and type Local.t = Store.tree)
    (Commit : Commit.S with type hash = Store.hash and type tree = Tree.t) =
struct
  include Context.Make (IO) (Codec) (Store) (Tree)
  module Return = Conn.Return

  module Empty = struct
    type req = unit [@@deriving irmin]
    type res = Tree.t [@@deriving irmin]

    let name = "tree.empty"

    let run conn ctx _ () =
      let empty = Store.Tree.empty in
      let id = incr_id () in
      Hashtbl.replace ctx.trees id (empty ());
      Return.v conn res_t (ID id)
  end

  module Save = struct
    type req = Tree.t [@@deriving irmin]

    type res = [ `Contents of Store.contents_key | `Node of Store.node_key ]
    [@@deriving irmin]

    let name = "tree.save"

    let run conn ctx _ tree =
      let* _, tree = resolve_tree ctx tree in
      let* hash =
        Store.Backend.Repo.batch ctx.repo (fun x y _ ->
            Store.save_tree ctx.repo x y tree)
      in
      Return.v conn res_t hash
  end

  module Add = struct
    type req = Tree.t * Store.path * Store.contents [@@deriving irmin]
    type res = Tree.t [@@deriving irmin]

    let name = "tree.add"

    let run conn ctx _ (tree, path, value) =
      let* _, tree = resolve_tree ctx tree in
      let* tree = Store.Tree.add tree path value in
      let id = incr_id () in
      Hashtbl.replace ctx.trees id tree;
      Return.v conn res_t (ID id)
  end

  module Batch_update = struct
    type req =
      Tree.t
      * (Store.path
        * [ `Contents of
            [ `Hash of Store.Hash.t | `Value of Store.contents ]
            * Store.metadata option
          | `Tree of Tree.t ]
          option)
        list
    [@@deriving irmin]

    type res = Tree.t [@@deriving irmin]

    let name = "tree.batch_update"

    let run conn ctx _ (tree, l) =
      let* _, tree = resolve_tree ctx tree in
      let* tree =
        Lwt_list.fold_left_s
          (fun tree (path, value) ->
            match value with
            | Some (`Contents (`Hash value, metadata)) ->
                let* value = Store.Contents.of_hash ctx.repo value in
                Store.Tree.add tree path ?metadata (Option.get value)
            | Some (`Contents (`Value value, metadata)) ->
                Store.Tree.add tree path ?metadata value
            | Some (`Tree t) ->
                let* _, tree' = resolve_tree ctx t in
                Store.Tree.add_tree tree path tree'
            | None -> Store.Tree.remove tree path)
          tree l
      in
      let id = incr_id () in
      Hashtbl.replace ctx.trees id tree;
      Return.v conn res_t (ID id)
  end

  module Add_tree = struct
    type req = Tree.t * Store.path * Tree.t [@@deriving irmin]
    type res = Tree.t [@@deriving irmin]

    let name = "tree.add_tree"

    let run conn ctx _ (tree, path, tr) =
      let* _, tree = resolve_tree ctx tree in
      let* _, tree' = resolve_tree ctx tr in
      let* tree = Store.Tree.add_tree tree path tree' in
      let id = incr_id () in
      Hashtbl.replace ctx.trees id tree;
      Return.v conn res_t (ID id)
  end

  module Merge = struct
    type req = Tree.t * Tree.t * Tree.t [@@deriving irmin]
    type res = Tree.t [@@deriving irmin]

    let name = "tree.merge"

    let run conn ctx _ (old, tree, tr) =
      let* _, old = resolve_tree ctx old in
      let* _, tree = resolve_tree ctx tree in
      let* _, tree' = resolve_tree ctx tr in
      let* tree =
        Irmin.Merge.f Store.Tree.merge ~old:(Irmin.Merge.promise old) tree tree'
      in
      match tree with
      | Ok tree ->
          let id = incr_id () in
          Hashtbl.replace ctx.trees id tree;
          Return.v conn res_t (ID id)
      | Error e ->
          Return.err conn (Irmin.Type.to_string Irmin.Merge.conflict_t e)
  end

  module Find = struct
    type req = Tree.t * Store.path [@@deriving irmin]
    type res = Store.contents option [@@deriving irmin]

    let name = "tree.find"

    let run conn ctx _ (tree, path) =
      let* _, tree = resolve_tree ctx tree in
      let* contents = Store.Tree.find tree path in
      Return.v conn res_t contents
  end

  module Find_tree = struct
    type req = Tree.t * Store.path [@@deriving irmin]
    type res = Tree.t option [@@deriving irmin]

    let name = "tree.find_tree"

    let run conn ctx _ (tree, path) =
      let* _, tree = resolve_tree ctx tree in
      let* tree = Store.Tree.find_tree tree path in
      let tree =
        Option.map
          (fun tree ->
            let id = incr_id () in
            Hashtbl.replace ctx.trees id tree;
            Tree.ID id)
          tree
      in
      Return.v conn res_t tree
  end

  module Remove = struct
    type req = Tree.t * Store.path [@@deriving irmin]
    type res = Tree.t [@@deriving irmin]

    let name = "tree.remove"

    let run conn ctx _ (tree, path) =
      let* _, tree = resolve_tree ctx tree in
      let* tree = Store.Tree.remove tree path in
      let id = incr_id () in
      Hashtbl.replace ctx.trees id tree;
      Return.v conn res_t (ID id)
  end

  module Cleanup = struct
    type req = Tree.t [@@deriving irmin]
    type res = unit [@@deriving irmin]

    let name = "tree.cleanup"

    let run conn ctx _ tree =
      let () =
        match tree with Tree.ID id -> Hashtbl.remove ctx.trees id | _ -> ()
      in
      Return.ok conn
  end

  module To_local = struct
    type req = Tree.t [@@deriving irmin]
    type res = Tree.Local.concrete [@@deriving irmin]

    let name = "tree.to_local"

    let run conn ctx _ tree =
      let* _, tree = resolve_tree ctx tree in
      let* tree = Tree.Local.to_concrete tree in
      Return.v conn res_t tree
  end

  module Mem = struct
    type req = Tree.t * Store.path [@@deriving irmin]
    type res = bool [@@deriving irmin]

    let name = "tree.mem"

    let run conn ctx _ (tree, path) =
      let* _, tree = resolve_tree ctx tree in
      let* res = Store.Tree.mem tree path in
      Return.v conn res_t res
  end

  module Mem_tree = struct
    type req = Tree.t * Store.path [@@deriving irmin]
    type res = bool [@@deriving irmin]

    let name = "tree.mem_tree"

    let run conn ctx _ (tree, path) =
      let* _, tree = resolve_tree ctx tree in
      let* res = Store.Tree.mem_tree tree path in
      Return.v conn res_t res
  end

  module List = struct
    type req = Tree.t * Store.path [@@deriving irmin]
    type tree = [ `Contents | `Tree ] [@@deriving irmin]
    type res = (Store.Path.step * [ `Contents | `Tree ]) list [@@deriving irmin]

    let name = "tree.list"

    let run conn ctx _ (tree, path) =
      let* _, tree = resolve_tree ctx tree in
      let* l = Store.Tree.list tree path in
      let* x =
        Lwt_list.map_s
          (fun (k, _) ->
            let+ exists = Store.Tree.mem_tree tree (Store.Path.rcons path k) in
            if exists then (k, `Tree) else (k, `Contents))
          l
      in
      Return.v conn res_t x
  end

  module Clear = struct
    type req = Tree.t [@@deriving irmin]
    type res = unit [@@deriving irmin]

    let name = "tree.clear"

    let run conn ctx _ tree =
      let* _, tree = resolve_tree ctx tree in
      Store.Tree.clear tree;
      Return.v conn res_t ()
  end

  module Hash = struct
    type req = Tree.t [@@deriving irmin]
    type res = Store.Hash.t [@@deriving irmin]

    let name = "tree.hash"

    let run conn ctx _ tree =
      let* _, tree = resolve_tree ctx tree in
      let hash = Store.Tree.hash tree in
      Return.v conn res_t hash
  end

  module Key = struct
    type req = Tree.t [@@deriving irmin]
    type res = Store.Tree.kinded_key [@@deriving irmin]

    let name = "tree.key"

    let run conn ctx _ tree =
      let* _, tree = resolve_tree ctx tree in
      let key = Store.Tree.key tree in
      Return.v conn res_t (Option.get key)
  end

  module Cleanup_all = struct
    type req = unit [@@deriving irmin]
    type res = unit [@@deriving irmin]

    let name = "tree.cleanup_all"

    let run conn ctx _ () =
      reset_trees ctx;
      Return.v conn res_t ()
  end

  let commands =
    [
      cmd (module Empty);
      cmd (module Add);
      cmd (module Batch_update);
      cmd (module Remove);
      cmd (module Cleanup);
      cmd (module Cleanup_all);
      cmd (module Mem);
      cmd (module Mem_tree);
      cmd (module List);
      cmd (module To_local);
      cmd (module Find);
      cmd (module Find_tree);
      cmd (module Add_tree);
      cmd (module Clear);
      cmd (module Hash);
      cmd (module Merge);
      cmd (module Save);
    ]
end
