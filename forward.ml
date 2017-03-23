(* Forwarding DNS server example. Looks up query locally first then forwards to another resolver. *)
open Lwt
open Dns
open Core.Std
open Cohttp
open Cohttp_lwt_unix

let lookup_table = Hashtbl.create ~hashable:String.hashable ();;

let http_server name ip =
  let callback _conn req body =
    let uri = req |> Request.uri |> Uri.to_string in
    let meth = req |> Request.meth |> Code.string_of_method in
    let headers = req |> Request.headers |> Header.to_string in
    body |> Cohttp_lwt_body.to_string >|= (fun body ->
      (Printf.sprintf "Uri: %s\nMethod: %s\nHeaders\nHeaders: %s\nBody: %s"
         uri meth headers body))
    >>= (fun body -> Server.respond_string ~status:`OK ~body ())
  in
  Server.create
    ~on_exn:(fun _ -> ())
    ~mode:(`TLS (
        `Crt_file_path "/etc/ssl/certs/ssl-cert-snakeoil.pem",
        `Key_file_path "/etc/ssl/private/ssl-cert-snakeoil.key",
        `No_password,
        `Port 443 )) 
    (Server.make  ~callback ())

let empty_response = {
  Dns.Query.rcode=Dns.Packet.NoError;
  Dns.Query.aa=false;
  Dns.Query.authority=[];
  Dns.Query.additional=[];
  Dns.Query.answer=[];
}

let generator name =
  let ip = (Ipaddr.V4.of_int32 (Random.int32 Int32.max_value))
  in
  let () = (Lwt.async (fun () -> http_server name ip))
in
{
  empty_response with
  Dns.Query.answer=[{
    Dns.Packet.name=Dns.Name.of_string name;
    Dns.Packet.cls=Dns.Packet.RR_IN;
    Dns.Packet.flush=false;
    Dns.Packet.ttl=10l;
    Dns.Packet.rdata=Dns.Packet.A ip
  }];
};;

let process ~src ~dst packet =
      let open Packet in
      match packet.questions with
      | [] -> return None; 
      | [{q_name=query; q_type=Q_A; q_class=_; q_unicast=_}] ->
          let name = Name.to_string query 
          in
          Hashtbl.find_or_add lookup_table name ~default:(fun () -> generator name) |> Option.some |> return
      | [_] -> return (Some empty_response)
      | _::_::_ -> return None;;

let () =
    Lwt_main.run (  
        let processor = ((Dns_server.processor_of_process process) :> (module Dns_server.PROCESSOR)) in 
        Dns_server_unix.serve_with_processor ~address:"127.0.0.1" ~port:53 ~processor)
