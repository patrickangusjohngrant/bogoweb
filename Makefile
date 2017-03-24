all: internot

internot: internot.ml
	ocamlfind ocamlopt internot.ml -package lwt,dns.lwt,core,cohttp.async,async -thread -linkpkg -g -o internot
	sudo chown root internot
	sudo chmod +s internot

tidyips:
	for i in $(shell ip address | egrep lo$$ | grep -v 127.0 | awk '{print $$2}') ; do sudo ip address del $$i dev lo ; done

run: internot tidyips
	echo nameserver 127.0.0.1 | sudo tee /etc/resolv.conf
	./internot

clean: tidyips
	echo nameserver 127.0.1.1 | sudo tee /etc/resolv.conf
	rm -f internot internot.cmi internot.cmx internot.o
