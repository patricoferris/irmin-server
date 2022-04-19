open Irmin_server_internal

type addr =
  [ `TLS of [ `Hostname of string ] * [ `IP of Ipaddr.t ] * [ `Port of int ]
  | `TCP of [ `IP of Ipaddr.t ] * [ `Port of int ]
  | `Ws of string
  | `Unix_domain_socket of [ `File of string ] ]

module type IO = sig
  include Conn.IO

  type ctx

  val default_ctx : ctx lazy_t
  val connect : ctx:ctx -> addr -> (flow * ic * oc) Lwt.t
  val close : ic * oc -> unit Lwt.t
end

module type S = sig
  type t
  type hash
  type contents
  type branch
  type commit
  type path
  type tree
  type step
  type slice
  type metadata
  type stats = Stats.t
  type contents_key

  val stats_t : stats Irmin.Type.t
  val slice_t : slice Irmin.Type.t

  module IO : IO
  module Path : Irmin.Path.S with type t = path and type step = step
  module Hash : Irmin.Hash.S with type t = hash
  module Metadata : Irmin.Metadata.S with type t = metadata
  module Info : Irmin.Info.S

  module Schema :
    Irmin.Schema.S
      with type Path.t = path
       and type Path.step = step
       and type Hash.t = hash
       and type Branch.t = branch
       and type Metadata.t = metadata

  module Private : sig
    module Store : Irmin.Generic_key.S with module Schema = Schema
    module Tree : Tree.S with module Private.Store = Store
  end

  type batch =
    (path
    * [ `Contents of [ `Hash of hash | `Value of contents ] * metadata option
      | `Tree of Private.Tree.t ]
      option)
    list

  type conf = {
    uri : Uri.t;
    tls : bool;
    hostname : string;
    batch_size : int;
    ctx : IO.ctx;
  }

  val connect : conf -> t Lwt.t
  (** Connect to the server *)

  val reconnect : t -> unit Lwt.t

  val uri : t -> Uri.t
  (** Get the URI the client is connected to *)

  val close : t -> unit Lwt.t
  (** Close connection to the server *)

  val dup : t -> t Lwt.t
  (** Duplicate a client. This will create a new connection with the same configuration *)

  val stats : t -> stats Error.result Lwt.t
  (** Get stats from the server *)

  val ping : t -> unit Error.result Lwt.t
  (** Ping the server *)

  val export : ?depth:int -> t -> slice Error.result Lwt.t
  val import : t -> slice -> unit Error.result Lwt.t

  type watch

  val watch :
    (commit Irmin.Diff.t -> unit Lwt.t) -> t -> watch Error.result Lwt.t

  val unwatch : watch -> unit Error.result Lwt.t

  module Commit : sig
    type key

    val key_t : key Irmin.Type.t

    val v :
      t -> info:Info.f -> parents:key list -> tree -> commit Error.result Lwt.t
    (** Create a new commit
        NOTE: this will invalidate all intermediate trees *)

    val of_key : t -> key -> commit option Error.result Lwt.t
    val of_hash : t -> hash -> commit option Error.result Lwt.t

    val key : commit -> key
    (** Get commit key *)

    val hash : t -> commit -> hash option Error.result Lwt.t
    (** Get commit hash *)

    val parents : commit -> key list
    (** The commit parents. *)

    val info : commit -> Info.t
    (** The commit info. *)

    val t : commit Irmin.Type.t
    (** [t] is the value type for {!t}. *)

    val hash_t : hash Irmin.Type.t
    (** [hash_t] is the value type for {!hash}. *)

    val tree : t -> commit -> tree
    (** Commit tree *)

    type t = commit
  end

  module Contents : sig
    type key = contents_key

    val of_hash : t -> hash -> contents option Error.result Lwt.t
    (** Find the contents associated with a hash *)

    val exists : t -> contents -> bool Error.result Lwt.t
    (** Check if [contents] exists in the store already *)

    val save : t -> contents -> contents_key Error.result Lwt.t
    (** Save value to store without associating it with a path *)

    include Irmin.Contents.S with type t = contents
  end

  module Branch : sig
    val set_current : t -> branch -> unit Error.result Lwt.t
    (** Set the current branch for a single connection *)

    val get_current : t -> branch Error.result Lwt.t
    (** Get the branch for a connection *)

    val get : ?branch:branch -> t -> commit option Error.result Lwt.t
    (** Get the head commit for the given branch, or the current branch if none is specified *)

    val set : ?branch:branch -> t -> commit -> unit Error.result Lwt.t
    (** Set the head commit for the given branch, or the current branch if none is specified *)

    val remove : t -> branch -> unit Error.result Lwt.t
    (** Delete a branch *)

    include Irmin.Branch.S with type t = branch
  end

  module Tree : sig
    type key

    val key_t : key Irmin.Type.t

    val split : tree -> t * Private.Tree.t * batch
    (** Get private fields from [Tree.t] *)

    val v : t -> ?batch:batch -> Private.Tree.t -> tree
    (** Create a new tree *)

    val of_key : t -> key -> tree
    (** Create a tree from a key that specifies a tree that already exists in the store *)

    val empty : t -> tree
    (** Create a new, empty tree *)

    val clear : tree -> unit Error.result Lwt.t
    (** Clear caches on the server for a given tree *)

    val key : tree -> key Error.result Lwt.t
    (** Get key of tree *)

    val build : t -> ?tree:Private.Tree.t -> batch -> tree Error.result Lwt.t
    (** [build store ~tree batch] performs a batch update of [tree], or
        an empty tree if not specified *)

    val add :
      tree -> path -> ?metadata:metadata -> contents -> tree Error.result Lwt.t
    (** Add contents to a tree, this may be batched so the update on the server
        could be delayed *)

    val add' : tree -> path -> contents -> tree Error.result Lwt.t
    (** Non-batch version of [add] *)

    val add_tree : tree -> path -> tree -> tree Error.result Lwt.t

    val add_tree' : tree -> path -> tree -> tree Error.result Lwt.t
    (** Non-batch version of [add_tree] *)

    val batch_update : tree -> batch -> tree Error.result Lwt.t
    (** Batch update tree *)

    val find : tree -> path -> contents option Error.result Lwt.t
    (** Find the value associated with the given path *)

    val find_tree : tree -> path -> tree option Error.result Lwt.t
    (** Find the tree associated with the given path *)

    val remove : tree -> path -> tree Error.result Lwt.t
    (** Remove value from a tree, returning a new tree *)

    val cleanup : tree -> unit Error.result Lwt.t
    (** Invalidate a tree, this frees the tree on the server side *)

    val cleanup_all : t -> unit Error.result Lwt.t
    (** Cleanup all trees *)

    val mem : tree -> path -> bool Error.result Lwt.t
    (** Check if a path is associated with a value *)

    val mem_tree : tree -> path -> bool Error.result Lwt.t
    (** Check if a path is associated with a tree *)

    val list :
      tree ->
      path ->
      (Path.step * [ `Contents | `Tree ]) list Error.result Lwt.t
    (** List entries at the specified root *)

    val merge : old:tree -> tree -> tree -> tree Error.result Lwt.t
    (** Three way merge *)

    val hash : tree -> hash Error.result Lwt.t

    val save :
      tree ->
      [ `Contents of Private.Store.contents_key
      | `Node of Private.Store.node_key ]
      Error.result
      Lwt.t

    module Local = Private.Tree.Local
    (*with type path = path
      and type contents = contents
      and type hash = hash
      and type step = Path.step
      and type t = Private.Store.tree*)

    val to_local : tree -> Local.t Error.result Lwt.t
    (** Exchange [tree], which may be a hash or ID, for a tree
        NOTE: this will encode the full tree and should be avoided if possible  *)

    val of_local : t -> Local.t -> tree Lwt.t
    (** Convert a local tree into a remote tree *)

    type t = tree
  end

  val find : t -> path -> contents option Error.result Lwt.t
  (** Find the value associated with a path, if it exists *)

  val find_tree : t -> path -> Tree.t option Error.result Lwt.t
  (** Find the tree associated with a path, if it exists *)

  val set : t -> info:Info.f -> path -> contents -> unit Error.result Lwt.t
  (** Associate a new value with the given path *)

  val test_and_set :
    t ->
    info:Info.f ->
    path ->
    test:contents option ->
    set:contents option ->
    unit Error.result Lwt.t
  (** Set a value only if the [test] parameter matches the existing value *)

  val remove : t -> info:Info.f -> path -> unit Error.result Lwt.t
  (** Remove a value from the store *)

  val set_tree : t -> info:Info.f -> path -> Tree.t -> Tree.t Error.result Lwt.t
  (** Set a tree at the given path *)

  val test_and_set_tree :
    t ->
    info:Info.f ->
    path ->
    test:Tree.t option ->
    set:Tree.t option ->
    Tree.t option Error.result Lwt.t
  (** Set a value only if the [test] parameter matches the existing value *)

  val mem : t -> path -> bool Error.result Lwt.t
  (** Check if the given path has an associated value *)

  val mem_tree : t -> path -> bool Error.result Lwt.t
  (** Check if the given path has an associated tree *)

  val merge : t -> info:Info.f -> branch -> unit Error.result Lwt.t
  (** Merge the current branch with the provided branch *)

  val merge_commit : t -> info:Info.f -> Commit.t -> unit Error.result Lwt.t
  (** Merge the current branch with the provided commit *)

  val last_modified : t -> path -> Commit.t list Error.result Lwt.t
  (** Get a list of commits that modified the specified path *)
end

module type Client = sig
  module type S = S

  type nonrec addr = addr

  module type IO = IO

  val config :
    ?batch_size:int -> ?tls:bool -> ?hostname:string -> Uri.t -> Irmin.config

  module Make (I : IO) (Codec : Conn.Codec.S) (Store : Irmin.Generic_key.S) :
    S
      with type hash = Store.hash
       and type contents = Store.contents
       and type branch = Store.branch
       and type path = Store.path
       and type step = Store.step
       and type metadata = Store.metadata
       and type slice = Store.slice
       and module Schema = Store.Schema
       and type Private.Store.tree = Store.tree
       and type Commit.key = Store.commit_key
       and type contents_key = Store.contents_key
       and module IO = I

  module Make_store
      (I : IO)
      (Codec : Conn.Codec.S)
      (Store : Irmin.Generic_key.S) :
    Irmin.Generic_key.S
      with module Schema = Store.Schema
       and type Backend.Remote.endpoint = unit
       and type commit_key = Store.commit_key
       and type contents_key = Store.contents_key
       and type node_key = Store.node_key
end
