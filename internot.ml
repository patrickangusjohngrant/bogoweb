(* Forwarding DNS server example. Looks up query locally first then forwards to another resolver. *)
open Lwt
open Dns
open Core.Std

let lookup_table = Hashtbl.create ~hashable:String.hashable ();;

let http_server ~body _ req =
  let open Async.Std in
  let open Cohttp in
  let open Cohttp_async in
  match req |> Cohttp.Request.meth with
  | `POST ->
        (Body.to_string body) >>= (fun body ->
          Log.Global.info "Body: %s" body;
          Server.respond `OK)
  | `GET -> Server.respond_string ~status:`OK (String.make (Random.int 1000) 'a')
  | _ -> Server.respond `Method_not_allowed;;

let http_listener name ip =
  let open Async.Std in
  let open Async_extra.Tcp in
  let open Cohttp in
  let open Cohttp_async in
  let cert_dir = "/tmp/certs/" ^ name
  in
  let socket_builder port =
    Where_to_listen.create
      ~socket_type:Socket.Type.tcp 
      ~address:(
        Socket.Address.Inet.create (ip |> Ipaddr.V4.to_int32 |> Async.Std.Unix.Inet_addr.inet4_addr_of_int32) port
      )
      ~listening_on:Socket.Address.Inet.to_host_and_port
  in
  Async_unix.Process.create_exn
    ~prog:"/sbin/ip"
    ~args:["address"; "add"; Ipaddr.V4.to_string ip; "dev"; "lo"] ()
  >>= Async_unix.Process.wait
  >>= fun _ -> Unix.mkdir ~p:() cert_dir
  >>= fun _ -> Async_unix.Process.create_exn
    ~prog:"/usr/bin/openssl"
    ~args:[
      "req";
      "-nodes";
      "-newkey"; "rsa:512";
      "-keyout"; cert_dir ^ "/key.out";
      "-out"; cert_dir ^ "/csr.out";
      "-subj";
      "/C=GB/ST=patrick/L=patrick/O=patrick/OU=Patrick Department/CN="^name]
      ()
  >>= fun _ ->
  Server.create
    ~mode:(`OpenSSL (
        `Crt_file_path "/etc/ssl/certs/ssl-cert-snakeoil.pem",
        `Key_file_path "/etc/ssl/private/ssl-cert-snakeoil.key"
    ))
    (socket_builder 443)
    http_server
  >>= fun _ ->
  Server.create
    ~mode:`TCP
    (socket_builder 80)
    http_server
  >>= fun _ -> Deferred.never ();;


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
  let () = http_listener name ip |> ignore
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

Thread.create Async.Std.Scheduler.go () |> ignore;;

let () =
    Lwt_main.run (  
        let processor = ((Dns_server.processor_of_process process) :> (module Dns_server.PROCESSOR)) in 
        Dns_server_unix.serve_with_processor ~address:"127.0.0.1" ~port:53 ~processor)
