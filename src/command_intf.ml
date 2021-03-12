module type S = sig
  module Store : Irmin_pack_layered.S with type key = string list

  module Tree : Tree.S with module Private.Store = Store

  module Commit : sig
    include Irmin.Private.Commit.S with type hash = Store.hash
  end

  type context = {
    conn : Conn.t;
    repo : Store.Repo.t;
    mutable branch : Store.branch;
    mutable store : Store.t;
    trees : (int, Store.tree) Hashtbl.t;
  }

  type f = Conn.t -> context -> [ `Read ] Args.t -> unit Lwt.t

  module type CMD = sig
    type req

    type res

    val args : int * int

    val name : string

    module Server : sig
      val recv : context -> [ `Read ] Args.t -> req Error.result Lwt.t

      val handle : Conn.t -> context -> req -> res Return.t Lwt.t
    end

    module Client : sig
      val send : [ `Write ] Args.t -> req -> unit Lwt.t

      val recv : [ `Read ] Args.t -> res Error.result Lwt.t
    end
  end

  type t = (module CMD)

  val name : t -> string

  val of_name : string -> t

  val n_args : t -> int

  val n_results : t -> int

  val commands : (string * t) list

  module Commands : sig
    module Ping : CMD with type req = unit and type res = unit

    module Set_branch : CMD with type req = Store.branch and type res = unit

    module Get_branch : CMD with type req = unit and type res = Store.branch

    module Export : CMD with type req = unit and type res = Store.slice

    module Import : CMD with type req = Store.slice and type res = unit

    module Head :
      CMD with type req = Store.branch option and type res = Commit.t option

    module Store : sig
      module Find :
        CMD with type req = Store.key and type res = Store.contents option

      module Set :
        CMD
          with type req = Store.key * Irmin.Info.t * Store.contents
           and type res = unit

      module Test_and_set :
        CMD
          with type req =
                Store.key
                * Irmin.Info.t
                * Store.contents option
                * Store.contents option
           and type res = unit

      module Remove :
        CMD with type req = Store.key * Irmin.Info.t and type res = unit

      module Find_tree :
        CMD with type req = Store.key and type res = Tree.t option

      module Set_tree :
        CMD
          with type req = Store.key * Irmin.Info.t * Tree.t
           and type res = Tree.t

      module Test_and_set_tree :
        CMD
          with type req =
                Store.key * Irmin.Info.t * Tree.t option * Tree.t option
           and type res = Tree.t option

      module Mem : CMD with type req = Store.key and type res = bool

      module Mem_tree : CMD with type req = Store.key and type res = bool
    end

    module Tree : sig
      module Empty : CMD with type req = unit and type res = Tree.t

      module Add :
        CMD
          with type req =
                Tree.t * Tree.Private.Store.key * Tree.Private.Store.contents
           and type res = Tree.t

      module Remove :
        CMD
          with type req = Tree.t * Tree.Private.Store.key
           and type res = Tree.t

      module Abort : CMD with type req = Tree.t and type res = unit

      module Clone : CMD with type req = Tree.t and type res = Tree.t

      module To_local : CMD with type req = Tree.t and type res = Tree.Local.t

      module Mem :
        CMD with type req = Tree.t * Tree.Private.Store.key and type res = bool

      module Mem_tree :
        CMD with type req = Tree.t * Tree.Private.Store.key and type res = bool

      module List :
        CMD
          with type req = Tree.t * Tree.Private.Store.key
           and type res =
                (Tree.Private.Store.Key.step * [ `Contents | `Tree ]) list
    end
  end
end

module type Command = sig
  module type S = S

  module Make (Store : Irmin_pack_layered.S with type key = string list) :
    S with module Store = Store
end
