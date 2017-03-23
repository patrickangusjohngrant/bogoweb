all: internot

internot: internot.ml
	ocamlfind ocamlopt internot.ml -package lwt,dns.lwt,core,cohttp.async,async -thread -linkpkg -g -o internot
	sudo chown root internot
	sudo chmod +s internot

clean:
	rm -f internot internot.cmi internot.cmx internot.o
