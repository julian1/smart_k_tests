
(* scan blocks and compute tx indexes
  native.

  corebuild -I src -package pgocaml,microecc,cryptokit,zarith,lwt,lwt.preemptive,lwt.unix,lwt.syntax -syntax camlp4o,lwt.syntax harvester/readblocks2.byte

  Need to get rid of leveldb ref, coming from misc.ml 126

*)

let (>>=) = Lwt.(>>=)
let (>|=) = Lwt.(>|=)  (* like bind, but second arg return type is non-monadic *)
let return = Lwt.return

module L = List
module CL = Core.Core_list
module S = String

module M = Message
module Sc = Scanner

(* open M *)


module Lwt_thread = struct
    include Lwt
    include Lwt_chan
end

module PG = PGOCaml_generic.Make (Lwt_thread)


module Utxos = Map.Make(struct type t = string * int let compare = compare end)
module RValues = Map.Make(struct type t = string let compare = compare end)


type mytype =
{
  tx_count : int;
  db : int PG.t ; (* TODO what is this *)
}

(*
  prepare once, then use...
*)

(*
let simple_query db query =
  (* think this is a complete transaction *)
  PG.prepare db ~query (* ~name*) ()
  >> PG.execute db (* ~name*) ~params:[] ()

  IMARY KEY,
    product_no integer REFERENCES products (product_no),
*)

let log = Lwt_io.write_line Lwt_io.stdout

let decode_id rows =
  (* >>= fun rows -> *)
  match rows with
    (Some field ::_ )::_ -> PG.int_of_string field
    | _ -> raise (Failure "previous tx not found")



let coinbase = M.zeros 32




let create_db db =
    (* note we're already doing a lot more than with leveldb 

        - address hashes are not normalized here. doesn't really matter 
        - likewise for der values
   
        - we want block (for date, ordering), pubkey and der. 
        - and some views to make joining stuff easier.
        - we could normalize address
        - and a flag on block if it's valid chain sequence 
    *)
  PG.(
    begin_work db

    >> inject db "drop table if exists coinbase"
    >> inject db "drop table if exists address"
    >> inject db "drop table if exists input"
    >> inject db "drop table if exists output"
    >> inject db "drop table if exists tx"

    >> inject db "create table tx(id serial primary key, hash bytea)"
    >> inject db "create index on tx(hash)"
    
    >> inject db @@ "create table output(id serial primary key, tx_id integer references tx(id), index int, amount bigint)"
    >> inject db "create index on output(tx_id)"

    >> inject db "create table input(id serial primary key, tx_id integer references tx(id), output_id integer references output(id) unique )"
    >> inject db "create index on input(tx_id)"
    >> inject db "create index on input(output_id)"

    >> inject db "create table address(id serial primary key, output_id integer references output(id), hash bytea)"
    >> inject db "create index on address(output_id)"
    >> inject db "create index on address(hash)"
  

    >> inject db "create table coinbase(id serial primary key, tx_id integer references tx(id))"
    >> inject db "create index on coinbase(tx_id)"


    >> prepare db ~name:"insert_tx" ~query:"insert into tx(hash) values ($1) returning id" ()
    >> prepare db ~name:"select_output_id" ~query:"select output.id from output join tx on tx.id = output.tx_id where tx.hash = $1 and output.index = $2" ()

    >> prepare db ~name:"insert_output" ~query:"insert into output(tx_id,index,amount) values ($1,$2,$3) returning id" ()

    >> prepare db ~name:"insert_input" ~query:"insert into input(tx_id,output_id) values ($1,$2)" ()

    >> prepare db ~name:"insert_address" ~query:"insert into address(output_id, hash) values ($1,$2)" ()

    >> prepare db ~name:"insert_coinbase" ~query:"insert into coinbase(tx_id) values ($1)" ()


 
    >> commit db
  )

let format_tx hash i value script =
  " i " ^ string_of_int i
  ^ " value " ^ string_of_float ((Int64.to_float value ) /. 100000000.)
  ^ " tx " ^ M.hex_of_string hash
  ^ " script " ^ M.format_script script


type my_script =
  | Some of string
  | None
  | Strange


let fold_m f acc lst =
  let adapt f acc e = acc >>= fun acc -> f acc e in
  L.fold_left (adapt f) (return acc) lst


(*
let map_m f lst =
  let adapt f acc e = acc >> f e in
  L.fold_left (adapt f) (return ()) lst
*)

(*
  we have
    - a tx table having tx hash, block id
    - an output table with tx_id, output_index, address, amount
    - an input table with tx_id, and referencing output table id.

  - then we can join everything. for a tx or address
  - it's append only
  - inputs refer directly to outputs using primary_id of output.
  - no aggregate indexes
  - easy to remove txs.

*)

let process_output x (index,output,hash,tx_id) =
    let open M in
    PG.( execute x.db ~name:"insert_output" ~params:[
        Some (string_of_int tx_id);
        Some (string_of_int index);
        Some (string_of_int64 output.value)
        ] () )
    >>= fun rows ->
    let output_id = decode_id rows in 
    let script = M.decode_script output.script in
    let decoded_script = match script with
      (* pay to pubkey *)
      | BYTES s :: OP_CHECKSIG :: [] -> Some (s |> M.sha256 |> M.ripemd160)
      (* pay to pubkey hash*)
      | OP_DUP :: OP_HASH160 :: BYTES s :: OP_EQUALVERIFY :: OP_CHECKSIG :: [] -> Some s
      (* pay to script - 3 *)
      | OP_HASH160 :: BYTES s :: OP_EQUAL :: [] -> Some s
      (* null data *)
      | OP_RETURN :: BYTES _ :: [] -> None
      (* common for embedding raw data, prior to op_return  *)
      | BYTES _ :: [] -> None
      (* N K1 K2 K3 M CHECKMULTISIGVERIFY, addresses? *)
      | (OP_1|OP_2|OP_3) :: _ when List.rev script |> List.hd = OP_CHECKMULTISIG -> None

      | _ -> Strange
    in 
    match decoded_script with
      | Some hash160 ->
          PG.( execute x.db ~name:"insert_address" ~params:[
            Some (string_of_int output_id ); 
            Some (string_of_bytea hash160 ) ] ()
          )
          >> return x 
      | Strange ->
          log @@ "strange " ^ format_tx hash index output.value script
          >> return x
      | None ->
        return x 



let process_input x (index, (input : M.tx_in ), hash,tx_id) =
  (* let process_input x (i, input, hash,tx_id) = *)
    (* extract der signature and r,s keys *)

    let script = M.decode_script input.script  in
    (* why can't we pattern match on string here ? eg. function *)
    (* so we have to look up the tx hash, which means we need an index on it *)

    if input.previous = coinbase then
      PG.execute x.db ~name:"insert_coinbase" ~params:[
        Some (PG.string_of_int tx_id); ] ()
      >> return x
    else


    (* Important - in fact we don't have to return the value, but could just
        select the correct output id and insert at the same time.
        -
      - need an index on tx.hash at least.
      - but should do timing.
      - and avoid preparing the statement each time. should do it in createdb
      2m 5 - to 50k with no index
      1m 19 with index on tx(hash)
      1m 40 with index on tx(hash) and output(index)

    now,
        43,50 secs to 50k.
        30 sec best with separated prepare. but it varys.
            seems to use bitmap scan initially - which is slower.
    
    important - we're also doing a lot more

      we should create another table for addresses (for more than one)
        - since not every output is associated with an address and there
        maybe more than one.
        - likewise for pubkeys - to avoid nulls
      and der sigs...
    *)
      PG.execute x.db ~name:"select_output_id" ~params:[
        Some (PG.string_of_bytea input.previous);
        Some (PG.string_of_int input.index); ] ()
      >>= fun rows ->
        let output_id = decode_id rows in 
        PG.execute x.db ~name:"insert_input" ~params:[
          Some (PG.string_of_int tx_id);
          Some (PG.string_of_int output_id);
        ] ()
    >> return x


let process_tx x (hash,tx) =
  begin
    match x.tx_count mod 10000 with
      | 0 -> log @@ S.concat "" [
        " tx_count "; string_of_int x.tx_count;
      ] >>
          log "comitting"
        >> PG.commit x.db
        >> log "done comitting, starting new transction"
        >> PG.begin_work x.db
      | _ -> return ()
  end
  >>
    let x = { x with tx_count = succ x.tx_count } in
    PG.execute x.db ~name:"insert_tx"  ~params:[ Some (PG.string_of_bytea hash); ] ()
  >>= fun rows ->
    let tx_id = decode_id rows in 
    (* can get rid of the hash *)
    let group index a = (index,a,hash,tx_id) in

    let open M in

    let inputs = L.mapi group tx.inputs in
    fold_m process_input x inputs
  >>= fun x ->
    let outputs = L.mapi group tx.outputs in
    fold_m process_output x outputs





let process_file () =

    log "connecting and create db"

    >>
    PG.connect ~host:"127.0.0.1" ~database: "meteo" ~user:"meteo" ~password:"meteo" ()
    >>= fun db ->
        create_db db
    >>
      Lwt_unix.openfile "blocks.dat.orig" [O_RDONLY] 0
    >>= fun fd ->
      log "scanning blocks..."
    >> Sc.scan_blocks fd
    >>= fun headers ->
      log "done scanning blocks - getting leaves"
    >>
      let leaves = Sc.get_leaves headers in
      log @@ "leaves " ^ (leaves |> L.length |> string_of_int)
    >>
      let longest = Sc.get_longest_path leaves headers in
      log @@ "longest " ^ M.hex_of_string longest
    >>
      log "computed leaves work "
    >>
      let seq = Sc.get_sequence longest headers in
      let seq = CL.drop seq 1 in (* we are missng the first block *)
      (*let seq = CL.take seq 50000 in *)
      (* let seq = [ M.string_of_hex "00000000000004ff6bc3ce1c1cb66a363760bb40889636d2c82eba201f058d79" ] in *)

     let x = {
        tx_count = 0;
        db = db;
      } in

      PG.begin_work db
    >> Sc.replay_tx fd seq headers process_tx x
    >> PG.commit db
    >> PG.close db
    >> 
      log "finished "

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



