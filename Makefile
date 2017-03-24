all: bogoweb

bogoweb: bogoweb.ml
	ocamlfind ocamlopt bogoweb.ml -package lwt,dns.lwt,core,cohttp.async,async -thread -linkpkg -g -o bogoweb
	sudo chown root bogoweb
	sudo chmod +s bogoweb

tidyips:
	for i in $(shell ip address | egrep lo$$ | grep -v 127.0 | awk '{print $$2}') ; do sudo ip address del $$i dev lo ; done

run: bogoweb tidyips
	echo nameserver 127.0.0.1 | sudo tee /etc/resolv.conf
	./bogoweb

clean: tidyips
	echo nameserver 127.0.1.1 | sudo tee /etc/resolv.conf
	rm -f bogoweb bogoweb.cmi bogoweb.cmx bogoweb.o
	sudo rm -rf /tmp/certs
