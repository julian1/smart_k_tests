(* tcp server example 
	ocamlfind c -w A -linkpkg -package lwt,lwt.unix,lwt.syntax -syntax camlp4o,lwt.syntax myecho.ml -o myecho 
*)
(* This code refers to https://github.com/avsm/ocaml-cohttpserver/blob/master/server/http_tcp_server.ml *)
open Lwt

let server_port = 12345
let so_timeout = Some 20
let backlog = 10

let try_close chan =
  catch (fun () -> Lwt_io.close chan)
  (function _ -> return ())

let init_socket sockaddr =
  let socket = Lwt_unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Lwt_unix.setsockopt socket Unix.SO_REUSEADDR true;
  Lwt_unix.bind socket sockaddr;
  Lwt_unix.listen socket backlog;
  socket

let process socket ~timeout ~callback =
  let rec _process () =
    Lwt_unix.accept socket >>=
      (fun (socket_cli, _) ->
        let inchan = Lwt_io.of_fd ~mode:Lwt_io.input socket_cli in
        let outchan = Lwt_io.of_fd ~mode:Lwt_io.output socket_cli in
        let c = callback inchan outchan in
        let events =
          match timeout with
          | None -> [c]
          | Some t -> [c; Lwt_unix.sleep (float_of_int t) >> return ()]
        in
        ignore (Lwt.pick events >> try_close outchan >> try_close inchan);
        _process ()
      )
  in
  _process ()

let _ =
  let sockaddr = Unix.ADDR_INET (Unix.inet_addr_any, server_port) in
  let socket = init_socket sockaddr in

 

  Lwt_main.run (
    process
      socket
      ~timeout:so_timeout
      ~callback:
        (fun inchan outchan ->
          Lwt_io.read ~count:4 inchan 
			>>= fun msg -> Lwt_io.write_line outchan "hithere" 
			>>  return (msg,123)  
			>>= (fun _ -> let result = "received " ^ msg ^ (string_of_int @@ String.length msg) in 
				Lwt_io.write_line Lwt_io.stdout result )
		)
  )

