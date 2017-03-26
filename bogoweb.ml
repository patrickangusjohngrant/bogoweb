(* Forwarding DNS server example. Looks up query locally first then forwards to another resolver. *)
open Lwt
open Dns
open Core.Std;;

let lookup_table = Hashtbl.create ~hashable:String.hashable ();;

let random_status () = match Random.int 10 with
  | 0     -> `Unauthorized
  | 1     -> `Not_found
  | 2     -> `Forbidden
  | _ -> `OK

(* TODO: make this do more random stuff:
 - sleep
 - fail
 - fail with different things (403, 401, 500, etc)
*)
let http_server ~body _ req =
  let open Async.Std in
  let open Cohttp in
  let open Cohttp_async in
  Async.Std.after (sec (Random.float 3.0)) >>=
  fun () -> Server.respond_string ~status:(random_status ()) (String.make (Random.int 1000) 'a');;

let generate_certs_sequencer = Async.Std.Throttle.Sequencer.create ();;

let generate_certs name =
  let open Async.Std in
  let cert_dir = "/tmp/certs/" ^ name
  in
  let key_path = cert_dir ^ "/key.out"
  in
  let csr_path = cert_dir ^ "/csr.out"
  in
  let cert_path = cert_dir ^ "/cert.out"
  in
  Unix.mkdir ~p:() cert_dir
  >>= fun _ -> Async_unix.Process.create_exn
    ~prog:"/usr/bin/openssl"
    ~args:[
      "req";
      "-nodes";
      "-newkey"; "rsa:512";
      "-keyout"; key_path;
      "-out"; csr_path;
      "-subj";
      "/C=GB/ST=bogoweb/L=bogoweb/O=bogoweb/OU=Bogoweb Department/CN="^name]
      ()
  >>= Async_unix.Process.wait
  >>= (fun _ -> Throttle.enqueue generate_certs_sequencer (Async_unix.Process.create_exn
    ~prog:"/usr/bin/openssl"
    ~args:[
      "ca";
      "-batch";
      "-config";
      "./openssl.cnf";
      "-keyfile"; "/tmp/bogoCA/ca.key.pem";
      "-cert"; "/tmp/bogoCA/ca.cert.pem";
      "-days"; "375";
      "-notext";
      "-md"; "sha256";
      "-in"; csr_path;
      "-out"; cert_path;]
      ))
  >>= Async_unix.Process.wait
  >>= fun _ -> return (key_path, cert_path)

let http_listener name ip mutex =
  let open Async.Std in
  let open Async_extra.Tcp in
  let open Cohttp in
  let open Cohttp_async in
  let error_logger = (`Call (fun addr exn ->
    Logs.err (fun f -> f "Error from %s" (Socket.Address.to_string addr));
    Logs.err (fun f -> f "%s" @@ Exn.to_string exn))
  )
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
  >>= fun _ -> generate_certs name
  >>= fun (key_path, cert_path) ->
  Server.create
    ~mode:(`OpenSSL (
        `Crt_file_path cert_path,
        `Key_file_path key_path
    ))
    ~on_handler_error:error_logger
    (socket_builder 443)
    http_server
  >>= fun _ ->
  Server.create
    ~mode:`TCP
    ~on_handler_error:error_logger
    (socket_builder 80)
    http_server
  >>= fun _ -> (
    Lwt_mutex.unlock mutex;
    Deferred.never ()
  );;


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
  let mutex = Lwt_mutex.create ()
  in 
  http_listener name ip mutex |> ignore;
  Lwt_mutex.lock mutex >>=
  fun () -> Lwt_mutex.lock mutex >>=
  fun () -> return {
  empty_response with
  Dns.Query.answer=[{
    Dns.Packet.name=Dns.Name.of_string name;
    Dns.Packet.cls=Dns.Packet.RR_IN;
    Dns.Packet.flush=false;
    Dns.Packet.ttl=10l;
    Dns.Packet.rdata=Dns.Packet.A ip
  }];
};;

let dns_process ~src ~dst packet =
      let open Packet in
      match packet.questions with
      | [] -> return None; 
      | [{q_name=query; q_type=Q_A; q_class=_; q_unicast=_}] ->
          let name = Name.to_string query 
          in
          let contains_dots = String.contains name '.'
          in
          if not contains_dots then
            return (Some empty_response)
          else
            Hashtbl.find_or_add
              lookup_table
              name
              ~default:(fun () -> generator name) >>=
            fun x -> (return (Some x))
      | [_] -> return (Some empty_response)
      | _::_::_ -> return None;;

let max_fd = 1000000L;;

(* Up ulimits. Bizarro types. *)
Unix.RLimit.set Unix.RLimit.num_file_descriptors {
  Core.Std.Unix.RLimit.cur = Unix.RLimit.Limit max_fd;
  max = Unix.RLimit.Limit max_fd
};

Thread.create (Async.Std.Scheduler.go_main ~max_num_open_file_descrs:(Int.of_int64_exn max_fd) ~main:(fun () -> ())) ();;

let () =
    Lwt_main.run (  
        let processor = ((Dns_server.processor_of_process dns_process) :> (module Dns_server.PROCESSOR)) in 
        Dns_server_unix.serve_with_processor ~address:"127.0.0.1" ~port:53 ~processor)
