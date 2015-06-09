
(* scan blocks and compute tx indexes *)

let (>>=) = Lwt.(>>=)
let return = Lwt.return
let (>|=) = Lwt.(>|=)  (* what does this do? *)

module M = Message
module L = List
module S = String
open M

let log = Lwt_io.write_line Lwt_io.stdout

(*
    - we need leveldb / io to check for entries.
    - add / remove entries.
    easy.
    - no just track unspent, and keys separately.
    - then we output those with keys only, and mark whether unspent.
    - ok, but it means we need to carry io return type...  3o
    - hang on maybe we write each one twice...
    - or if we pass a structure, it could contain
*)


(*
    fold_lefti can be done with mapi and then feeding into fold...
    OK. we want to make a key val store
*)
module TXOMap = Map.Make(struct type t = int * string let compare = compare end)


(* note we could even store block hash if we wanted

  - basically nested folds
  - it's better to pass x as monadic argument since allows folds without complication.
  - x can be any structure that we want to record stuff - a record, or () if nothing.
      or a db, or combination.
  - eg. if we want to keep a block count it should be on that structure

  - this could be made more generalizable, but not sure it would make it code simpler and easier.
    just repeat for different context.
    - may even want to remove the partial application functions - and call things directly.
  --------

  so how do we do this?
    txhash / index -> s or u

  what about amounts?

    block <- output <- address
*)

let coinbase = M.zeros 32


let process_output x (i,output,hash) =
  x >>= fun x ->
    let script = decode_script output.script
    in log @@ "output " ^ (M.format_script script)
    >>
    (* we don't have to decode the script type just the length - another fold 
      ok, we want hash 160,,,
        how do we output the value....
    *)
(*
    let u = L.fold_left (fun acc e ->
      match e with
        Bytes s when S.length s = 40 -> acc 
        (* Bytes s -> s :: acc *)
        | _ -> acc
      ) [] script
    in
*)
    let hash160 = match script with 
      | Bytes s :: OP_CHECKSIG :: [] -> s |> M.sha256 |> M.ripemd160 
      | OP_DUP :: OP_HASH160 :: Bytes s :: OP_EQUALVERIFY :: OP_CHECKSIG :: [] -> s
      | _  -> raise ( Failure (M.format_script script )  )
    in

    log @@ "hash160 is " ^ M.hex_of_string hash160
    >>
    return ( TXOMap.add (i,hash) "u" x )


let process_input x input =
  x >>= fun x ->
 (*   log @@ "input  " ^ M.hex_of_string input.previous
      ^ " index " ^ (string_of_int input.index )
  >>
*)
    if input.previous = coinbase then
      return x
    else
      let key = (input.index,input.previous) in
      match TXOMap.mem key x with
        | true -> return x (* (TXOMap.remove key x ) *)
        | false -> raise ( Failure "ughh here" )


let process_tx x (hash,tx) =
  x >>= fun x ->
    (*log "tx"
  >> *)
    L.fold_left process_input (return x) tx.inputs
  >>= fun x ->
    let group i output = (i,output,hash) in
    let outputs = L.mapi group tx.outputs in
    L.fold_left process_output (return x) outputs


let process_block f x payload =
  (*log "block"
  >> *)
    (* let block_hash = M.strsub payload 0 80 |> M.sha256d |> M.strrev in *)
    (* decode tx's and get tx hash *)
    let pos = 80 in
    let pos, tx_count = M.decodeVarInt payload pos in
    let _, txs = M.decodeNItems payload pos M.decodeTx tx_count in
    let txs = L.map (fun tx ->
      let hash = M.strsub payload tx.pos tx.length |> M.sha256d |> M.strrev
      in hash, tx
    ) txs
    in
    L.fold_left f (x) txs


let process_blocks f fd x =
	let rec process_blocks' x =
    x >>= fun x ->
      Misc.read_bytes fd 24
      >>= function
        | None -> return x
        | Some s ->
          (* Lwt_unix.lseek fd 0 SEEK_CUR
          >>= fun pos -> *)
            let _, header = M.decodeHeader s 0 in
            (* log @@ header.command ^ " " ^ string_of_int header.length >> *)
            Misc.read_bytes fd header.length
          >>= function
            | None -> return x
            | Some payload ->
              f (return x) payload
              >>= fun x -> process_blocks' (return x)
  in process_blocks' x


let process_file () =
    Lwt_unix.openfile "blocks.dat" [O_RDONLY] 0
    >>= fun fd ->
      log "scanning blocks..."
    >>
      let process_block = process_block process_tx in
      let x = TXOMap.empty in
      process_blocks process_block fd (return x)
    >>= fun x ->
      Lwt_unix.close fd
      >> log @@ "final " ^ (string_of_int (TXOMap.cardinal x) )



let () = Lwt_main.run (process_file ())








(*

  - ok, we've got the utxo set being calculated. but what about
  1. extract the addresses
  2. look them up.

  can return the list of address -> tx
    use
        tx -> address - and use the existing struccture
            then only remove if not also found..

  - it doesn seem to slow more than would expect
  - think the int should be first

    PROBLEM
        tx's that are spent in same block - are ones we are
        really interested in. because they're auto harvested

  -------

    - ok there's an issue, that a fork block spends txs, then another
    block tries to do the same.
    - we have to pick a path through the blocks.


*)
(*
let process_output index output =
  log @@  string_of_int index ^ " " ^  string_of_int (Int64.to_int output.value )
  >> log @@ "\n  script: " ^ (output.script |> decode_script |> M.format_script )



let sequence f initial lst  =
  L.fold_left (fun acc x -> acc >> f x) initial lst

let sequencei f initial lst  =
  let ret,_ = L.fold_left (fun (acc,i) x -> (acc >> f i x, succ i)) (initial,0) lst in
  ret
*)
(*
  (* these are reversed, - should do inputs then outputs *)
    let x = L.fold_left process_input x tx.inputs in
    let m = L.mapi (fun i output -> (i,output,hash)) tx.outputs in
    L.fold_left process_output x m
*)
(*
  log @@ M.hex_of_string hash
  (* we should probably sequence, not parallelise this *)
  (* >>  Lwt.join ( L.mapi process_output tx.outputs ) *)
  (* >>  Lwt.join ( L.mapi process_output tx.outputs ) *)
  >> sequencei process_output (return ()) tx.outputs
*)


(* issue passing a structure through a series of functions i
  use a module?
  everything is a fold
*)

(*
let process_tx db block_pos ((hash, tx) : string * M.tx )  =
  let coinbase = M.zeros 32
  in
  let process_input (input : M.tx_in) =
    if input.previous = coinbase then
      return ()
    else
      let key = I.encodeKey { hash = input.previous; index = input.index  } in
      Db.get db key
      >>= (fun result ->
        match result with
          Some s ->
            (* we should write functions to do this *)
            let value = I.decodeValue s in
            if value.status <> "u" then
              let msg = "ooops tx is spent" in
              raise (Failure msg)
            else
              Db.put db key (I.encodeValue { value with status = "s";  } )
          | None ->
            let msg = "txo not found " ^ M.hex_of_string input.previous ^ " " ^ string_of_int input.index in
            raise (Failure msg)
      )
  in
  let process_output tx_hash index (output : M.tx_out) =
    let key = I.encodeKey { hash = tx_hash; index = index } in
    let value = I.encodeValue {
        status = "u"; block_pos = block_pos; tx_pos = tx.pos; tx_length = tx.length;
        output_pos = output.pos; output_length = output.length;
      } in
    Db.put db key value
  in
  (* process in parallel inputs, then outputs in sequence *)
  Lwt.join ( L.map process_input tx.inputs )
  >> Lwt.join ( L.mapi (process_output hash) tx.outputs )
*)

(* this thing doesn't use the db, so it should be configured ...  all this stuff is still mucky *)


