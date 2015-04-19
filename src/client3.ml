(*
corebuild    -package leveldb,microecc,cryptokit,zarith,lwt,lwt.unix,lwt.syntax -syntax camlp4o,lwt.syntax  src/client3.byte

*)


let (>>=) = Lwt.(>>=)
let return = Lwt.return



module M = Message




type my_app_state =
{
  (* this structure really should'nt be exposed *)

  (* jobs :  Misc.my_event Lwt.t list ; *)
  jobs :  Misc.jobs_type  ;

  connections : Misc.connection list ;

  (* responsible for downloading chain *)
  chain :  Chain.t; 


(*
  (* really should be able to hide this *)
  heads : Misc.my_head Misc.SS.t ;

 (* time_of_last_received_block : float;
  time_of_last_inv_request : float; *)


  inv_pending	 : (Lwt_unix.file_descr * float ) option ; (* should include time also *) 

  (* should be a tuple with the file_desc so if it doesn't send we can clear it 
      - very important - being able to clear the connection, means we avoid
      accumulating a backlog of slow connections.

      - the test should be, if there are blocks_on_request and no block for
      x time, then wipe the connection and bloks on request.
  *)
  blocks_on_request : Misc.SSS.t ;

   (* should change to be blocks_fd
      does this file descriptor even need to be here. it doesn't change?
    *)
(*  blocks_oc : Lwt_io.output Lwt_io.channel ; *)
  (* db : LevelDB.db ; *)
*)
}


let log s = Misc.write_stdout s >> return Misc.Nop

(* let m = 0xdbb6c0fb   litecoin *)

(* initial version message to send *)
let initial_version =
  let payload = M.encodeVersion {
      protocol = 70002;
      nlocalServices = 1L; (* doesn't seem to like non- full network 0L *)
      nTime = 1424343054L;
      from = { address = 127,0,0,1; port = 8333 };
      to_ = { address = 50,68,44,128; port = 8333 };
      (* nonce = -4035119509127777989L ; *)
      nonce = -8358291686216098076L ;
      agent = "/Satoshi:0.9.3/"; (* "/bitcoin-ruby:0.0.6/"; *)
      height = 127953;
      relay = 0xff;
  } in
  Misc.encodeMessage "version" payload

(* verack response to send *)
let initial_verack =
  Misc.encodeSimpleMessage "verack"

 
let initial_getaddr =
  Misc.encodeSimpleMessage "getaddr"



let get_connection host port =
  (* what is this lwt entry *)
  Lwt_unix.gethostbyname host  (* FIXME this should be in lwt catch as well *)
  >>= fun entry ->
    if Array.length entry.Unix.h_addr_list = 0 then
      return @@ Misc.GotConnectionError ( "could not resolve hostname " ^ host )
    else
      let a_ = entry.Unix.h_addr_list.(0) in
      let a = Unix.ADDR_INET ( a_ , port) in
      let fd = Lwt_unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
      let (inchan : 'mode Lwt_io.channel )= Lwt_io.of_fd ~mode:Lwt_io.input fd in
      let outchan = Lwt_io.of_fd ~mode:Lwt_io.output fd
      in
      Lwt.catch
        (fun  () ->
          Lwt_unix.connect fd a
          >>
          let (conn : Misc.connection) = {
              addr = Unix.string_of_inet_addr a_;
              port = port;
              fd = fd;
              ic = inchan ;
              oc = outchan;
          } in
          return @@ Misc.GotConnection conn
        )
        (fun exn ->
          (* must close *)
          let s = Printexc.to_string exn in
          Lwt_unix.close fd
          >> return @@ Misc.GotConnectionError s
        )

(* read exactly n bytes from channel, returning a string
  - change name to readn or something? *)

(* timeout throws an exception which is horrible
  - althought we could just wrap it inside the pick to emit a value ...
*)

let readChannel inchan length (* timeout here *)  =
  let buf = Bytes.create length in

  Lwt.pick [
    Lwt_unix.timeout 180.
    (* >> Lwt_io.write_line Lwt_io.stdout "timeout!!!" doesn't run *)
    ;
    Lwt_io.read_into_exactly inchan buf 0 length
  ]
  >>= fun _ ->
    return @@ Bytes.to_string buf



let get_message (conn : Misc.connection ) =
    Lwt.catch (
      fun () ->
      (* read header *)

        let ic = conn.ic in
        readChannel ic 24
        >>= fun s ->
          let _, header = M.decodeHeader s 0 in
          if header.length < 10*1000000 then
            (* read payload *)
            readChannel ic header.length
            >>= fun p ->
            return @@ Misc.GotMessage ( conn, header, s, p)
          else
            return @@ Misc.GotMessageError (conn, "payload too big - command is "
              ^ header.command
              ^ " size " ^ string_of_int header.length )
      )
      ( fun exn ->
          let s = Printexc.to_string exn in
          return @@ Misc.GotMessageError (conn, "here2 " ^ s)
      )



(*
- jobs = jobs, tasks, threads, fibres
- within a task we can sequence as many sub tasks using >>= as we like
- we only have to thread stuff through this main function, when the app state changes
   and we have to synchronize,
- app state is effectively a fold over the network events...
*)




(* 50.199.113.193:8333 *)

(*
let format_addr conn = String.concat "" [ conn.addr ; ":" ; string_of_int conn.port ]
*)


(* manage p2p *)
let manage_p2p (state : my_app_state ) e =

  match e with
    | Misc.Nop -> state
    | Misc.GotConnection conn ->
      { state with
        connections = conn :: state.connections;
        jobs = state.jobs @ [
          log @@ Misc.format_addr conn ^  " got connection "  ^
            ", connections now " ^ ( string_of_int @@ List.length state.connections )
          >> Misc.send_message conn initial_version
          >> log @@ "*** sent our version " ^ Misc.format_addr conn
          ;
           get_message conn
        ];
      }

    | Misc.GotConnectionError msg ->
      { state with
        jobs = state.jobs @ [  log @@ "connection error " ^ msg ]
      }

    | Misc.GotMessageError ((conn : Misc.connection), msg) ->
      { state with
        (* fd test is physical equality *)
        connections = List.filter (fun (c : Misc.connection) -> c.fd != conn.fd) state.connections;
        jobs = state.jobs @ [
          log @@ Misc.format_addr conn ^ "msg error " ^ msg;
          match Lwt_unix.state conn.fd with
            Opened -> ( Lwt_unix.close conn.fd ) >> return Misc.Nop
            | _ -> return Misc.Nop
        ]
      }


    | Misc.GotMessage (conn, header, raw_header, payload) ->
      (
      match header.command with

        | "version" ->
          { state with
            jobs = state.jobs @ [
              log @@ Misc.format_addr conn ^ " got version message"
              >> Misc.send_message conn initial_verack
              >> log @@ "*** sent verack " ^ Misc.format_addr conn
              ;
              get_message conn
            ];
          }

        | "verack" ->
          { state with
            jobs = state.jobs @ [
              (* should be 3 separate jobs? *)
              log @@ Misc.format_addr conn ^ " got verack";
              (* >> send_message conn initial_getaddr *)
              get_message conn
            ]
          }

        (* - there's stuff to manage p2p
            - then there's stuff to manage chainstate..
            - can we separate this out into another file...
            - blocks and inv etc.


            - we could actually just have a complete module ...
            with msg interface...
              - hiding the blocks and db file descriptors etc...
        *)


        | "addr" ->
            let pos, count = M.decodeVarInt payload 0 in
            (* should take more than the first *)
            let pos, _ = M.decodeInteger32 payload pos in (* timeStamp  *)
            let _, addr = M.decodeAddress payload pos in
            let formatAddress (h : M.ip_address ) =
              let soi = string_of_int in
              let a,b,c,d = h.address  in
              String.concat "." [
              soi a; soi b; soi c; soi d
              ] (* ^ ":" ^ soi h.port *)
            in
            let a = formatAddress addr in
            (* ignore, same addr instances on different ports *)
            let already_got = List.exists (fun (c : Misc.connection) -> c.addr = a (* && peer.conn.port = addr.port *) ) state.connections
            in
            if already_got || List.length state.connections >= 30 then
              { state with
                jobs = state.jobs @ [
                  log @@ Misc.format_addr conn ^ " addr - already got or ignore "
                    ^ a ^ ":" ^ string_of_int addr.port ;
                  get_message conn
                  ]
                }
            else
              { state with
              jobs = state.jobs @ [
                 log @@ Misc.format_addr conn ^ " addr - count "  ^ (string_of_int count )
                    ^  " " ^ a ^ " port " ^ string_of_int addr.port ;
                  get_connection (formatAddress addr) addr.port ;
                  get_message conn
                ]
              }

        | s ->
          { state with
            jobs = state.jobs @ [
              log @@ Misc.format_addr conn ^ " message " ^ s ;
              get_message conn
              ]
          }

        )


let run f =

  Lwt_main.run (

    Chain.create () 
    >>= fun chain ->   

    (* we actually need to read it as well... as write it... *)
    let state =
      let jobs = [
        (* https://github.com/bitcoin/bitcoin/blob/master/share/seeds/nodes_main.txt *)
        get_connection     "23.227.177.161" 8333;
        get_connection     "23.227.191.50" 8333;
        get_connection     "23.229.45.32" 8333;
        get_connection     "23.236.144.69" 8333;

        get_connection     "50.142.41.23" 8333;
        get_connection     "50.199.113.193" 8333;
        get_connection     "50.200.78.107" 8333;


        get_connection     "61.72.211.228" 8333;
        get_connection     "62.43.40.154" 8333;
        get_connection     "62.43.40.154" 8333;
        get_connection     "62.80.185.213" 8333;

      ] in
      (* this code needs to be factored out *)
      let genesis = M.string_of_hex "000000000000000007ba2de6ea612af406f79d5b2101399145c2f3cbbb37c442" in
(*      let genesis = M.string_of_hex "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f" in *)
      let heads =
          Misc.SS.empty
          |> Misc.SS.add genesis
           ({
            previous = "";
            height = 0;
            (* difficulty = 123; *)
          } : Misc.my_head )  in
      {
        jobs = jobs;
        connections = [];

        chain = chain ;
(*
        heads = heads ;


        inv_pending	 = None ; 


(*        time_of_last_received_block = 0. ;
        time_of_last_inv_request = 0.; *)
        blocks_on_request = Misc.SSS.empty  ;

    (*    db = LevelDB.open_db "mydb"; *)

      (*  blocks_oc = blocks_oc *)
*)
      }
    in

    let rec loop state =
      Lwt.catch (
      fun () -> Lwt.nchoose_split state.jobs

        >>= fun (complete, incomplete) ->
          (*Lwt_io.write_line Lwt_io.stdout  @@
            "complete " ^ (string_of_int @@ List.length complete )
            ^ ", incomplete " ^ (string_of_int @@ List.length incomplete)
            ^ ", connections " ^ (string_of_int @@ List.length state.connections )
        >>
      *)
          let new_state = List.fold_left f { state with jobs = incomplete } complete
          in if List.length new_state.jobs > 0 then
            loop new_state
          else
            Lwt_io.write_line Lwt_io.stdout "finishing - no more jobs to run!!"
            >> return ()
      )
        (fun exn ->
          (* must close *)


          let s = Printexc.to_string exn  ^ "\n" ^ (Printexc.get_backtrace () ) in
          Lwt_io.write_line Lwt_io.stdout ("finishing - exception " ^ s )
          >> (* just exist cleanly *)
            return ()
        )
    in
      loop state
  )


let f state e =
  let state = manage_p2p state e in
(*
  let state = Chainstate.manage_chain state e in
*)

  let (chain, jobs) = Chain.update state.chain e in 
(*  Chain.update e 
  >>= fun (chain, jobs ) -> 
 *) 
  state


let () = run f



