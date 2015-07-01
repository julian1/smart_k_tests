(*
  - it should be easy to stop. and resume this stuff as well, if we want.
  - should test whether have block already and skip...

  - choices
    - avoid exceptions
    - if the block has already been in inserted return something to indiate that ...
    - or simply rely on the db...  

  - should wrap the process_block up... only. other exceptions should kill the  
  - the exception indicates a postgres tx exception which is good...

  - to catch exceptions outside the block...
*)
(* scan blocks and store to db
  corebuild -I src -package pgocaml,cryptokit,zarith,lwt,lwt.preemptive,lwt.unix,lwt.syntax -syntax camlp4o,lwt.syntax harvester/readblocks2.native
  Need to get rid of leveldb ref, coming from misc.ml 126
*)

let (>>=) = Lwt.(>>=)
let (>|=) = Lwt.(>|=)  (* like bind, but second arg return type is non-monadic *)
let return = Lwt.return

module M = Message
module PG = Misc.PG

let log s = Misc.write_stdout s


let process_block x payload =
  Lwt.catch (
    fun () -> Processblock.process_block x payload
  )
  (fun exn ->
    let s = Printexc.to_string exn  ^ "\n" ^ (Printexc.get_backtrace () ) in
    log ("@@@ whoot " ^ s )
    >> return x 
  )


(* read a block at current pos and return it - private *)
let read_block fd =
  Misc.read_bytes fd 24
  >>= function
    | None -> return None
    | Some s ->
      let _, header = M.decodeHeader s 0 in
      (* should check command is 'block' *)
      Misc.read_bytes fd header.length
      >>= function
        | None -> raise (Failure "here2")
        | Some payload -> return (Some payload)


(* scan through blocks in the given sequence
  - perhaps insted of passing in seq and headers should pass just pos list *)

let replay_blocks fd f x =
  let rec replay_blocks' x =
      read_block fd
    >>= function
      | None -> return x
      | Some payload -> f x payload
    >>= fun x ->
      replay_blocks' x
  in
  replay_blocks' x


let process_file () =
  log "connecting and create db"
  >> PG.connect ~host:"127.0.0.1" ~database: "prod" ~user:"meteo" ~password:"meteo" ()
  >>= fun db ->
    Processblock.create_prepared_stmts db
  >> Lwt_unix.openfile "blocks.dat.orig" [O_RDONLY] 0
  >>= fun fd ->
    log "scanning blocks..."
  >>
    let x = 
    Processblock.(
      {
        block_count = 0;
        db = db;
      } )in
      replay_blocks fd process_block x
  
  >> PG.close db
  >> log "finished "


let () = Lwt_main.run (
  Lwt.catch (
    process_file
  )
  (fun exn ->
    (* must close *)
    let s = Printexc.to_string exn  ^ "\n" ^ (Printexc.get_backtrace () ) in
    log ("finishing - exception " ^ s )
    >> return ()
  )
)

