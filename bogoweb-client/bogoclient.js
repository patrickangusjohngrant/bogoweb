#!/home/patrick/.local/bin/node

const execSync = require('child_process').execSync;
const http = require("http");
const https = require("https");
const random = require("random-js")()
const randomWord = require('random-word');
const TLDs = [".com", ".co.uk", ".nl", ".net", ".fr" ]

var CLIENT_ADDRESSES = [];

for (var i = 1; i < 10; i++) {
    var ip = "10.150.0." + i;
    try {
        execSync("sudo /sbin/ip address add " + ip + " dev lo");
    } catch (e) {;}
    CLIENT_ADDRESSES.push(ip);
}




// TODO: use CA the right way. This just ignores certs.
process.env.NODE_TLS_REJECT_UNAUTHORIZED = "0";

var random_hostname = function () { return (randomWord() + random.pick(TLDs)) };

var INTERWEB_SITES = Array(2).fill(1).map(random_hostname);
console.log(INTERWEB_SITES);

random_hostname = function () { return random.pick(INTERWEB_SITES) };

var go_nuts = function() {
    var options = {
        hostname: random_hostname(),
//        port: 80,
        path: '/',
        method: 'GET',
        localAddress: random.pick(CLIENT_ADDRESSES)
    };
    console.log(options)

    https.request(options, res => res.on("data", function (chunk) {
       if (chunk.indexOf("a") !== 0) {
           console.log("Real internet detected! Exiting!");
           process.exit(1);
       }
    }));

    setTimeout(go_nuts, 100);
}

go_nuts();
