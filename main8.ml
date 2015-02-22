
(*
	corebuild  -package sha,lwt,lwt.unix,lwt.syntax -syntax camlp4o,lwt.syntax main8.byte
   *)

(* open Core  *)
(*open Sha256 *)

open Lwt (* for >>= *)

type header =
{
  magic : int;
  command : string;
  length : int;
  checksum : int;
}

type ip_address =
{
  address : int * int * int * int;
  port : int;
}

(* change name version_pkt? or version msg *)
type version =
{
  protocol : int ;
  nlocalServices : Int64.t;
  nTime : Int64.t;
  from : ip_address;
  to_ : ip_address;
  nonce : Int64.t;
  agent : string;
  height : int;
  relay : int;
}

let printf = Printf.printf

let hex_of_char c =
  let hexa = "0123456789abcdef" in
  let x = Char.code c in
  hexa.[x lsr 4], hexa.[x land 0xf]

let hex_of_string s =
  (* functional *)
  let n = String.length s in
  let buf = Buffer.create (n*2) in
  for i = 0 to n-1 do
    let x, y = hex_of_char s.[i] in
    Buffer.add_char buf x;
    Buffer.add_char buf y;
    (*Buffer.add_char buf ' ';
    Buffer.add_char buf s.[i];
    Buffer.add_char buf '\n';
    *)
  done;
  Buffer.contents buf

(* horrible *)
let hex_of_int =
  Printf.sprintf "%x"


(* decode byte in s at pos *)
let dec1 s pos = int_of_char @@ String.get s pos

(* other endiness form
let dec s pos bytes =
let rec dec_ s pos bytes acc =
	let value = (acc lsl 8) + (dec1 s pos) in
    if pos >= bytes then value
    else dec_ s (pos+1) bytes value in
	dec_ s pos (pos+bytes-1) 0
*)

(* decode integer value of string s at position using n bytes *)
let dec s start bytes =
  let rec dec_ pos acc =
    let value = (acc lsl 8) + (dec1 s pos) in
      if pos == start then value
      else dec_ (pos-1) value in
    dec_ (start+bytes-1) 0

(* with new position in string - change name decodeInteger *)
let dec_ s pos n = n+pos, dec s pos n
let decodeInteger8 s pos = dec_ s pos 1
let decodeInteger32 s pos = dec_ s pos 4

(* decode integer value of string s at position using n bytes *)
let dec64_ s start bytes =
  let rec dec_ pos acc =
    let value = Int64.add (Int64.shift_left acc 8) (Int64.of_int (dec1 s pos)) in
      if pos == start then value
      else dec_ (pos-1) value in
    dec_ (start+bytes-1) 0L

let decodeInteger64 s pos = 8+pos, dec64_ s pos 8

(* string manipulation *)
let strsub = String.sub
let strlen = String.length
let strrev = Core.Core_string.rev
let zeros n = String.init n (fun _ -> char_of_int 0)

(* returning position *)
let decs_ s pos n = n+pos, strsub s pos n

(* hashing *)
let sha256 s = s |> Sha256.string |> Sha256.to_bin
let sha256d s = s |> sha256 |> sha256
let checksum s = s |> sha256d |> fun x -> dec x 0 4

let decodeString s pos =
  let pos, len = decodeInteger8 s pos in
  let pos, s = decs_ s pos len in
  pos, s

let decodeAddress s pos =
  (* let () = printf "Addr %s\n" @@ hex_of_string (strsub s pos 26 ) in *)
  let pos, _ = dec_ s pos 20 in
  let pos, a = decodeInteger8 s pos in
  let pos, b = decodeInteger8 s pos in
  let pos, c = decodeInteger8 s pos in
  let pos, d = decodeInteger8 s pos in
  let pos, e = decodeInteger8 s pos in
  let pos, f = decodeInteger8 s pos in
  let port = (e lsl 8 + f) in
  pos, { address = a, b, c, d; port = port }

let decodeHeader s pos =
  let pos, magic = decodeInteger32 s pos in
  let pos, command = decs_ s pos 12 in
  let pos, length = decodeInteger32 s pos in
  let _, checksum = decodeInteger32 s pos in
  { magic = magic; 
  
  (* factor into function decodeCommand s pos ? *)
  command = strsub command 0 (String.index_from command 0 '\x00' ); 

  length = length; checksum = checksum; }

let decodeVersion s pos =
  let pos, protocol = decodeInteger32 s pos in
  let pos, nlocalServices = decodeInteger64 s pos in
  let pos, nTime = decodeInteger64 s pos in
  let pos, from = decodeAddress s pos in
  let pos, to_ = decodeAddress s pos in
  let pos, nonce = decodeInteger64 s pos in
  let pos, agent = decodeString s pos in
  let pos, height = decodeInteger32 s pos in
  let _, relay = decodeInteger8 s pos in
  { protocol = protocol; nlocalServices = nlocalServices; nTime = nTime;
  from = from; to_ = to_; nonce  = nonce; agent = agent; height = height;
  relay = relay;
  }

let enc bytes value =
  String.init bytes (fun i ->
    let h = 0xff land (value lsr (i * 8)) in
    char_of_int h
  )

let encodeInteger8 value = enc 1 value
let encodeInteger16 value = enc 2 value
let encodeInteger32 value = enc 4 value

let enc64 bytes value =
  String.init bytes (fun i ->
    let h = Int64.logand 0xffL (Int64.shift_right value (i * 8)) in
    char_of_int (Int64.to_int h)
  )

let encodeInteger64 value = enc64 8 value

let encodeString (h : string) = enc 1 (strlen h) ^ h

(* should use a concat function, for string building *)
let encodeAddress (h : ip_address) =
  (* replace with concat, better algorithmaclly *)
  let a,b,c,d = h.address in
  encodeInteger8 0x1
  ^ zeros 17
  ^ encodeInteger16 0xffff
  ^ encodeInteger8 a
  ^ encodeInteger8 b
  ^ encodeInteger8 c
  ^ encodeInteger8 d
  ^ (encodeInteger8 (h.port lsr 8))
  ^ (encodeInteger8 h.port )

let encodeVersion (h : version) =
  encodeInteger32 h.protocol
  ^ encodeInteger64 h.nlocalServices
  ^ encodeInteger64 h.nTime
  ^ encodeAddress h.from
  ^ encodeAddress h.to_
  ^ encodeInteger64 h.nonce
  ^ encodeString h.agent
  ^ encodeInteger32 h.height
  ^ encodeInteger8 h.relay

let encodeHeader (h : header) =
  encodeInteger32 h.magic
  ^ h.command
  ^ zeros (12 - strlen h.command)
  ^ encodeInteger32 h.length
  ^ encodeInteger32 h.checksum


(* dump the string - not pure *)
let rec printRaw s a b =
	let () = printf "magic %d - '%c' %d %d %d\n" a s.[a] (int_of_char s.[a]) (dec s a 4) (dec s a 8) in
  if a > b then ()
  else printRaw s (a+1) b


let formatHeader (h : header) =
  String.concat "" [
    "magic:    "; hex_of_int h.magic;
    "\ncommand:  "; h.command;
    "\nlength:   "; string_of_int h.length;
    "\nchecksum: "; hex_of_int h.checksum
  ]

let formatAddress (h : ip_address ) =
  let soi = string_of_int in
  let a,b,c,d = h.address  in
  String.concat "" [
    soi a; "." ; soi b; "."; soi c; "."; soi d; ":"; soi h.port
  ]

let formatVersion (h : version) =
  (* we can easily write a concat that will space fields, insert separator etc, pass as tuple pairs instead*)
  String.concat "" [
    "protocol_version: "; string_of_int h.protocol;
    "\nnLocalServices:   "; Int64.to_string h.nlocalServices;
    "\nnTime:            "; Int64.to_string h.nTime;
    "\nfrom:             "; formatAddress h.from;
    "\nto:               "; formatAddress h.to_;
    "\nnonce:            "; Int64.to_string h.nonce;
    "\nagent:            "; h.agent;
    "\nrelay:            "; string_of_int h.relay
  ]



let mytest1 () =
  let h =
  if false
  then
    "\xF9\xBE\xB4\xD9version\x00\x00\x00\x00\x00j\x00\x00\x00\xE8\xFF\x94\xD0q\x11\x01\x00\x01\x00\x00\x00\x00\x00\x00\x00(#\xE0T\x00\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xFF\xFF\x7F\x00\x00\x01 \x8D\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xFF\xFF\x12\xBDzI \x8D\xE9\xD4n\x1F0!\xF8\x11\x14/bitcoin-ruby:0.0.6/\xD1\xF3\x01\x00\xFF" else
    let in_channel = open_in "response.bin" in
    let h = Core.In_channel.input_all in_channel in
    let () = close_in in_channel in
    h
in
  let header = decodeHeader h 0 in
  let payload = strsub h 24 header.length in
  let version = decodeVersion payload 0 in
  let () = printf "%s" @@ formatHeader header in
  let () = printf "\n" in
  let () = printf "%s" @@ formatVersion version in
  let () = printf "checksum is %x \n" ( checksum payload ) in
  let () = printf "----------\n" in
  let u = encodeVersion version in
  let () = printf "%s" @@ formatVersion ( decodeVersion u 0 ) in
  let () = printf "checksum is %x\n" ( checksum u ) in
  printf "----------\n"


let mytest2 () =
  (* lets try to manually pack the payload *)
  let payload = {
      protocol = 70002;
      nlocalServices = 1L;
      nTime = 1424343350L;
      from = { address = 203,57,212,102; port = 34185 };
      to_ = { address = 50,68,44,128; port = 8333 };
      nonce = -4035119509127777989L ;
      agent = "/Satoshi:0.9.4/";
      height = 344194;
      relay = 1;
  } in
  let u = encodeVersion payload in
  let header = {
    magic = 0xf9beb4d9;
    command = "version";
    length = strlen u ;
    checksum = checksum u;
  } in
  let eheader = encodeHeader header in
  let dheader = decodeHeader eheader 0 in
  let () = printf "**** here\n" in
  let () = printf "%s" @@ formatHeader dheader in
  ()




let y =
  let payload = encodeVersion {
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
  let header = encodeHeader {
    magic = 0xd9b4bef9;
    command = "version";
    length = strlen payload;
    checksum = checksum payload;
  } in
  header ^ payload


let z =
  encodeHeader {
    magic = 0xd9b4bef9;
    command = "verack";
    length = 0;
    (* clients seem to use e2e0f65d - hash of first part of header? *)
    checksum = 0;
  }




let handleMessage header payload outchan =
  (* we kind of want to be able to write to stdout here 
    and return a value...
    - we may want to do async database actions here. so keep the io
  *)
  match header.command with
  | "version"  -> 
    let version = decodeVersion payload 0 in
    Lwt_io.write_line Lwt_io.stdout ("* whoot got version\n" ^ formatVersion version)
    >>= fun _ -> Lwt_io.write_line Lwt_io.stdout "* sending verack"
    >>= fun _ -> Lwt_io.write outchan z


  | "verack"  -> 
    Lwt_io.write_line Lwt_io.stdout ("* got veack" )

  | "inv"  -> 



    (*let x = if count < 0xfd then count  *)
    let pos = 0 in
    let pos, count = decodeInteger8 payload pos in
    let pos, inv_type = decodeInteger32 payload pos in
    let pos, hash = decs_ payload pos 32 in

    Lwt_io.write_line Lwt_io.stdout ( 
      "* got inv - "
      ^ "\n payload length " ^ string_of_int header.length
      ^ "\n count " ^ string_of_int count
      ^ "\n inv_type " ^ string_of_int inv_type 
      ^ "\n hash " ^ hex_of_string (strrev hash )
    )

  | _ -> 
    Lwt_io.write_line Lwt_io.stdout ("* unknown '" ^ header.command ^ "'" )


let mainLoop inchan outchan =
  let rec loop () =
    (* read header *)
    Lwt_io.read ~count:24 inchan
    (* read payload *)
    >>= fun s -> let header = decodeHeader s 0 in
      Lwt_io.read ~count: header.length inchan
    (* handle  *)
    >>= fun s -> handleMessage header s outchan
    (* repeat *)
    >>= fun _ -> loop ()
  in
    loop()


let addr ~host ~port =
  lwt entry = Lwt_unix.gethostbyname host in
  if Array.length entry.Unix.h_addr_list = 0 then begin
    failwith (Printf.sprintf "no address found for host %S\n" host)
  end;
  return (Unix.ADDR_INET (entry.Unix.h_addr_list.(0) , port))


let mytest3 () =  
  Lwt_main.run (
    addr ~host: "50.68.44.128" ~port: 8333  
    (*    149.210.187.10  *)
    (* addr ~host: "173.69.49.106" ~port: 8333  *)
    (* addr ~host: "198.52.212.235" ~port: 8333 was good *)
    (* addr ~host: "127.0.0.1" ~port: 8333 *)

    >>= fun ip -> Lwt_io.write_line Lwt_io.stdout "decoded address "
    (* connect *)
    >>= fun () -> let fd = Lwt_unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
      let inchan = Lwt_io.of_fd ~mode:Lwt_io.input fd in
      let outchan = Lwt_io.of_fd ~mode:Lwt_io.output fd in
      Lwt_unix.connect fd ip
    (* send version *)
    >>= fun _ -> Lwt_io.write outchan y
    >>= fun _ -> Lwt_io.write_line Lwt_io.stdout "sending version"
    (* enter main loop *)
    >>= fun _ -> mainLoop inchan outchan
    (* return () *)
    (*  >>= (fun () -> Lwt_unix.close fd)  *)
  )

let () = mytest3 ()


(*
  ok, we need to work out why it's not responding ... when we send our packet
*)

(*
let () = mytest () in
let () = mytest2 () in
*)





(*
  TODO
  - need to hex functions - to easily compare the data .
    can only use printf %x with integers
*)


(*
283     static member Parse(reader: BinaryReader) =
284         let version = reader.ReadInt32()
285         let services = reader.ReadInt64()
286         let timestamp = reader.ReadInt64()
287         let recv = reader.ReadBytes(26)
288         let from = reader.ReadBytes(26)
289         let nonce = reader.ReadInt64()
290         let userAgent = reader.ReadVarString()
291         let height = reader.ReadInt32()
292         let relay = reader.ReadByte()
293         new Version(version, services, timestamp, recv, from, nonce, userAgent, height, relay)

279     static member Create(timestamp: Instant, recv: IPEndPoint, from: IPEndPoint, nonce: int64, userAgent: string, height: int32, relay:     by

PrddrYou.ToString(), addr.ToString());
 551     PushMessage("version", PROTOCOL_VERSION, nLocalServices, nTime, addrYou, addrMe,
 552                 nLocalHostNonce, FormatSubVersion(CLIENT_NAME, CLIENT_VERSION, std::vector<string>()), nBestHeight, true);
 553 }
 554
intf.printf "payload %d\n" (dec h 16 4);
printf "version %d\n" (dec h 20 4);
*)

