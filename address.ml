
(* corebuild  -package zarith,sha,lwt,lwt.unix,lwt.syntax -syntax camlp4o,lwt.syntax address.byte *)

(* 
  what's next?
    - encode the public key... to show all tx inputs and outputs for pay to script. if bytes length is correct.
    - then do script engine.
*)


let encode_base58 (value: string ) =
  (* TODO maybe replace list concat with Buffer for speed. 
  - we only need the Z type for arbitrary precision division/remainder
  might be able to implement ourselves in base 256. *)
  let code_string = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz" in
  let rec f div acc =
    if Z.gt div Z.zero then
      let div1, rem = Z.div_rem div (Z.of_int 58) in
      f div1 (code_string.[Z.to_int rem]::acc)
    else
      acc
  in
  let value = Z.of_bits (Core.Core_string.rev value) in
  Core.Std.String.of_char_list (f value [])


let int_of_hex (c : char) =
  (* change name int_of_hex_char ? *)
  (* straight pattern match might be simpler/faster *)
  let c1 = int_of_char c in
  if c >= '0' && c <= '9' then
    c1 - (int_of_char '0')
  else
    10 + c1 - (int_of_char 'a')


let string_of_hex (s: string) =
  (* TODO perhaps rename binary_of_hex *)
  let n = String.length s in
  let buf = Buffer.create (n/2) in
  for i = 0 to n/2-1 do
    let i2 = i * 2 in
    let x = int_of_hex s.[i2] in
    let y = int_of_hex s.[i2+1] in
    Buffer.add_char buf @@ char_of_int (x lsl 4 + y)
  done;
  Buffer.contents buf


let btc_address_of_hash160 (a: string) =
  let x = "\x00" ^ a in
  let checksum = Message.checksum2 x in
  encode_base58 (x ^ checksum)


(* do we want a utils module with some of this stuff ? *)

let s = "c1a235aafbb6fa1e954a68b872d19611da0c7dc9" in
let () = Printf.printf "string %s\n" s in
let s1 = string_of_hex s in
Printf.printf "encoded %s\n" @@ btc_address_of_hash160 s1


