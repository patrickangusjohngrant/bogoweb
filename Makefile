all: bogoweb

bogoweb: bogoweb.ml
	ocamlfind ocamlopt bogoweb.ml -package lwt,dns.lwt,core,cohttp.async,async -thread -linkpkg -g -o bogoweb

bogoca_dir:
	mkdir -p /tmp/bogoCA/newcerts

/tmp/bogoCA/index.txt.attr:
	touch /tmp/bogoCA/index.txt.attr /tmp/bogoCA/index.txt

/tmp/bogoCA/serial:
	echo -n 1111 | tee /tmp/bogoCA/serial

/tmp/bogoCA/ca.key.pem: bogoca_dir
	openssl genrsa -out /tmp/bogoCA/ca.key.pem 512

/tmp/bogoCA/ca.cert.pem: bogoca_dir /tmp/bogoCA/ca.key.pem
	openssl req \
		-subj "/C=GB/ST=bogoweb/L=bogoweb/O=bogoweb/OU=Bogoweb Department/CN=Bogoweb CA" \
		-key /tmp/bogoCA/ca.key.pem \
		-new -x509 \
		-days 7300 \
		-sha256 \
		-extensions v3_ca \
		-out /tmp/bogoCA/ca.cert.pem

bogoca: /tmp/bogoCA/ca.cert.pem /tmp/bogoCA/ca.key.pem /tmp/bogoCA/serial /tmp/bogoCA/index.txt.attr
	sudo mkdir -p  /usr/share/ca-certificates/extra
	sudo openssl x509 -in /tmp/bogoCA/ca.cert.pem -inform PEM -out /usr/share/ca-certificates/extra/bogoca.crt
	sudo dpkg-reconfigure ca-certificates

tidyips:
	for i in $(shell ip address | egrep lo$$ | grep -v 127.0 | awk '{print $$2}') ; do sudo ip address del $$i dev lo ; done

run: bogoweb tidyips bogoca
	echo nameserver 127.0.0.1 | sudo tee /etc/resolv.conf
	sudo ./bogoweb

clean: tidyips
	echo nameserver 127.0.1.1 | sudo tee /etc/resolv.conf
	rm -f bogoweb bogoweb.cmi bogoweb.cmx bogoweb.o
	sudo rm -rf /tmp/certs

veryclean: clean
	rm -r /tmp/bogoCA
