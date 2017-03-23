all: forward

forward: forward.ml
	ocamlfind ocamlopt forward.ml -package lwt,dns.lwt,core,cohttp.lwt -thread -linkpkg -g -o forward
	sudo chown root forward
	sudo chmod +s forward

clean:
	rm -f forward forward.cmi forward.cmx forward.o
