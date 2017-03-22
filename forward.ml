(* Forwarding DNS server example. Looks up query locally first then forwards to another resolver. *)
open Lwt
open Dns
open Core.Std

let lookup_table = Hashtbl.create ~hashable:String.hashable ();;

let empty_response = {
  Dns.Query.rcode=Dns.Packet.NoError;
  Dns.Query.aa=false;
  Dns.Query.authority=[];
  Dns.Query.additional=[];
  Dns.Query.answer=[];
}

let generator name = {
  empty_response with
  Dns.Query.answer=[{
    Dns.Packet.name=Dns.Name.of_string name;
    Dns.Packet.cls=Dns.Packet.RR_IN;
    Dns.Packet.flush=false;
    Dns.Packet.ttl=10l;
    Dns.Packet.rdata=Dns.Packet.A (Ipaddr.V4.of_int32 (Random.int32 Int32.max_value))
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
