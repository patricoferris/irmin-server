module Error = Irmin_client.Error

module Info (I : Irmin.Info.S) : sig
  include Irmin.Info.S with type t = I.t

  val init : ?author:string -> ?message:string -> int64 -> t
  val v : ?author:string -> ('b, Format.formatter, unit, f) format4 -> 'b
end

module type S = sig
  include Irmin_client.S


end

module Make
    (Codec : Irmin_server_internal.Conn.Codec.S)
    (Store : Irmin.Generic_key.S) :
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
