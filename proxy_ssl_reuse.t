#!/usr/bin/perl

# (C) OIS

# Tests for keepalive cache of upstream TLS conn with different proxy_ssl_*:
# - proxy_ssl_verify
# - proxy_ssl_name
# - proxy_ssl_server_name
# - proxy_ssl_verify_depth
# - proxy_ssl_crl
# - proxy_ssl_ciphers
# - proxy_ssl_protocols
# - proxy_ssl_certificate + proxy_ssl_certificate_key
# - proxy_ssl_conf_command
# - proxy_bind
# - ?

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()
	->has(qw/http http_ssl proxy upstream_keepalive sni/)
	->has_daemon('openssl')->plan(20)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream u_verify {
        server 127.0.0.1:8081;
        keepalive 1;
    }

    upstream u_name {
        server 127.0.0.1:8082;
        keepalive 1;
    }

    upstream u_sni {
        server 127.0.0.1:8083;
        keepalive 1;
    }

    upstream u_depth {
        server 127.0.0.1:8084;
        keepalive 1;
    }

    upstream u_crl {
        server 127.0.0.1:8085;
        keepalive 1;
    }

    upstream u_ciphers {
        server 127.0.0.1:8086;
        keepalive 1;
    }

    upstream u_protocols {
        server 127.0.0.1:8087;
        keepalive 1;
    }

    upstream u_cert {
        server 127.0.0.1:8088;
        keepalive 1;
    }

    upstream u_conf {
        server 127.0.0.1:8088;
        keepalive 1;
    }

    upstream u_bind {
        server 127.0.0.1:8089;
        keepalive 1;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        proxy_http_version 1.1;
        proxy_set_header Connection $args;
        proxy_ssl_session_reuse off;

        # proxy_ssl_verify

        location /verify_prime {
            proxy_pass https://u_verify/;
            proxy_ssl_verify off;
            proxy_ssl_trusted_certificate verify.trusted.crt;
            proxy_ssl_server_name on;
            proxy_ssl_name verify.backend;
        }

        location /verify_strict {
            proxy_pass https://u_verify/;
            proxy_ssl_verify on;
            proxy_ssl_trusted_certificate verify.trusted.crt;
            proxy_ssl_server_name on;
            proxy_ssl_name verify.backend;
        }

        # proxy_ssl_name

        location /name_prime {
            proxy_pass https://u_name/;
            proxy_ssl_verify on;
            proxy_ssl_trusted_certificate bad.example.com.crt;
            proxy_ssl_server_name on;
            proxy_ssl_name bad.example.com;
        }

        location /name_strict {
            proxy_pass https://u_name/;
            proxy_ssl_verify on;
            proxy_ssl_trusted_certificate bad.example.com.crt;
            proxy_ssl_server_name on;
            proxy_ssl_name good.example.com;
        }

        # proxy_ssl_server_name

        location /sni_prime {
            proxy_pass https://u_sni/;
            proxy_ssl_verify off;
            proxy_ssl_name sni.example.com;
            proxy_ssl_server_name on;
        }

        location /sni_strict {
            proxy_pass https://u_sni/;
            proxy_ssl_verify off;
            proxy_ssl_name sni.example.com;
            proxy_ssl_server_name off;
        }

        # proxy_ssl_verify_depth

        location /depth_prime {
            proxy_pass https://u_depth/;
            proxy_ssl_verify on;
            proxy_ssl_trusted_certificate depth.root.crt;
            proxy_ssl_server_name on;
            proxy_ssl_name depth.example.com;
            proxy_ssl_verify_depth 2;
        }

        location /depth_strict {
            proxy_pass https://u_depth/;
            proxy_ssl_verify on;
            proxy_ssl_trusted_certificate depth.root.crt;
            proxy_ssl_server_name on;
            proxy_ssl_name depth.example.com;
            proxy_ssl_verify_depth 1;
        }

        # proxy_ssl_crl

        location /crl_prime {
            proxy_pass https://u_crl/;
            proxy_ssl_verify on;
            proxy_ssl_trusted_certificate crl.root.crt;
            proxy_ssl_server_name on;
            proxy_ssl_name crl.backend;
        }

        location /crl_strict {
            proxy_pass https://u_crl/;
            proxy_ssl_verify on;
            proxy_ssl_trusted_certificate crl.root.crt;
            proxy_ssl_server_name on;
            proxy_ssl_name crl.backend;
            proxy_ssl_crl crl.root.crl;
        }

        # proxy_ssl_ciphers

        location /ciphers_prime {
            proxy_pass https://u_ciphers/;
            proxy_ssl_verify off;
            proxy_ssl_protocols TLSv1.2;
            proxy_ssl_ciphers ECDHE-RSA-AES256-GCM-SHA384;
        }

        location /ciphers_strict {
            proxy_pass https://u_ciphers/;
            proxy_ssl_verify off;
            proxy_ssl_protocols TLSv1.2;
            proxy_ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256;
        }

        # proxy_ssl_protocols

        location /protocols_prime {
            proxy_pass https://u_protocols/;
            proxy_ssl_verify off;
            proxy_ssl_protocols TLSv1.2;
        }

        location /protocols_strict {
            proxy_pass https://u_protocols/;
            proxy_ssl_verify off;
            proxy_ssl_protocols TLSv1.3;
        }

        # proxy_ssl_certificate + proxy_ssl_certificate_key

        location /cert_prime {
            proxy_pass https://u_cert/;
            proxy_ssl_verify off;
            proxy_ssl_certificate client.good.crt;
            proxy_ssl_certificate_key client.good.key;
        }

        location /cert_strict {
            proxy_pass https://u_cert/;
            proxy_ssl_verify off;
            proxy_ssl_certificate client.bad.crt;
            proxy_ssl_certificate_key client.bad.key;
        }

        # proxy_ssl_conf_command

        location /conf_prime {
            proxy_pass https://u_conf/;
            proxy_ssl_verify off;
            proxy_ssl_certificate client.bad.crt;
            proxy_ssl_certificate_key client.bad.key;
            proxy_ssl_conf_command Certificate client.good.crt;
            proxy_ssl_conf_command PrivateKey client.good.key;
        }

        location /conf_strict {
            proxy_pass https://u_conf/;
            proxy_ssl_verify off;
            proxy_ssl_certificate client.good.crt;
            proxy_ssl_certificate_key client.good.key;
            proxy_ssl_conf_command Certificate client.bad.crt;
            proxy_ssl_conf_command PrivateKey client.bad.key;
        }

        # proxy_bind

        location /bind_prime {
            proxy_pass http://u_bind/;
            proxy_bind 127.0.0.2;
        }

        location /bind_strict {
            proxy_pass http://u_bind/;
            proxy_bind 127.0.0.1;
        }
    }

    server {
        listen       127.0.0.1:8081 ssl;
        server_name  verify.backend;

        ssl_certificate verify.backend.crt;
        ssl_certificate_key verify.backend.key;

        location / {
            add_header X-Connection $connection always;
        }
    }

    server {
        listen       127.0.0.1:8082 ssl;
        server_name  bad.example.com;

        ssl_certificate bad.example.com.crt;
        ssl_certificate_key bad.example.com.key;

        location / {
            add_header X-Connection $connection always;
            add_header X-Name $ssl_server_name, always;
        }
    }

    server {
        listen       127.0.0.1:8083 ssl;
        server_name  sni.backend;

        ssl_certificate sni.backend.crt;
        ssl_certificate_key sni.backend.key;

        location / {
            add_header X-Connection $connection always;
            add_header X-Name $ssl_server_name, always;
        }
    }

    server {
        listen       127.0.0.1:8084 ssl;
        server_name  depth.example.com;

        ssl_certificate depth.chain.crt;
        ssl_certificate_key depth.example.com.key;

        location / {
            add_header X-Connection $connection always;
        }
    }

    server {
        listen       127.0.0.1:8085 ssl;
        server_name  crl.backend;

        ssl_certificate crl.backend.crt;
        ssl_certificate_key crl.backend.key;

        location / {
            add_header X-Connection $connection always;
        }
    }

    server {
        listen       127.0.0.1:8086 ssl;
        server_name  ciphers.backend;

        ssl_certificate ciphers.backend.crt;
        ssl_certificate_key ciphers.backend.key;

        ssl_protocols TLSv1.2;
        ssl_ciphers ECDHE-RSA-AES256-GCM-SHA384;

        location / {
            add_header X-Connection $connection always;
        }
    }

    server {
        listen       127.0.0.1:8087 ssl;
        server_name  protocols.backend;

        ssl_certificate protocols.backend.crt;
        ssl_certificate_key protocols.backend.key;

        ssl_protocols TLSv1.2;

        location / {
            add_header X-Connection $connection always;
        }
    }

    server {
        listen       127.0.0.1:8088 ssl;
        server_name  cert.backend;

        ssl_certificate cert.backend.crt;
        ssl_certificate_key cert.backend.key;

        ssl_verify_client on;
        ssl_client_certificate ca.good.crt;

        location / {
            add_header X-Connection $connection always;
            add_header X-Cert $ssl_client_s_dn always;
        }
    }

    server {
        listen       127.0.0.1:8089;
        server_name  bind.backend;

        location / {
            add_header X-Connection $connection always;
            add_header X-IP $remote_addr always;
        }
    }
}

EOF

$t->write_file('openssl.conf', <<'EOF');
[ req ]
default_bits = 2048
encrypt_key = no
distinguished_name = req_distinguished_name

[ req_distinguished_name ]
EOF

$t->write_file('openssl.ca.conf', <<'EOF');
[ req ]
default_bits = 2048
encrypt_key = no
distinguished_name = req_distinguished_name
x509_extensions = myca_extensions

[ req_distinguished_name ]

[ myca_extensions ]
basicConstraints = critical,CA:TRUE
EOF

$t->write_file_expand('crl.ca.conf', <<'EOF');
[ ca ]
default_ca = myca

[ myca ]
new_certs_dir = %%TESTDIR%%
database = %%TESTDIR%%/crl.certindex
default_md = sha256
policy = myca_policy
serial = %%TESTDIR%%/crl.certserial
default_days = 1

[ myca_policy ]
commonName = supplied
EOF

$t->write_file('depth.ca.ext', <<'EOF');
basicConstraints=CA:TRUE,pathlen:10
keyUsage=keyCertSign,cRLSign
subjectKeyIdentifier=hash
EOF

$t->write_file('depth.leaf.ext', <<'EOF');
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
subjectKeyIdentifier=hash
EOF

$t->write_file('client.ext', <<'EOF');
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=clientAuth
subjectKeyIdentifier=hash
EOF

my $d = $t->testdir();

foreach my $name ('verify.backend', 'verify.trusted', 'bad.example.com',
	'sni.backend', 'depth.root', 'ciphers.backend', 'protocols.backend',
	'cert.backend')
{
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

foreach my $name ('ca.good', 'ca.bad') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.ca.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

foreach my $name ('client.good', 'client.bad') {
	system("openssl genrsa -out $d/$name.key 2048 "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create private key for $name: $!\n";
	system('openssl req -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-key $d/$name.key -out $d/$name.csr "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create CSR for $name: $!\n";
}

system('openssl x509 -req '
	. "-in $d/client.good.csr "
	. "-CA $d/ca.good.crt -CAkey $d/ca.good.key -CAcreateserial "
	. "-days 3650 -extfile $d/client.ext "
	. "-out $d/client.good.crt "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't sign client.good certificate: $!\n";

system('openssl x509 -req '
	. "-in $d/client.bad.csr "
	. "-CA $d/ca.bad.crt -CAkey $d/ca.bad.key -CAcreateserial "
	. "-days 3650 -extfile $d/client.ext "
	. "-out $d/client.bad.crt "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't sign client.bad certificate: $!\n";

system('openssl req -x509 -new '
	. "-config $d/openssl.ca.conf -subj /CN=crl.root/ "
	. "-out $d/crl.root.crt -keyout $d/crl.root.key "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't create certificate for crl.root: $!\n";

system("openssl genrsa -out $d/crl.backend.key 2048 "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't create private key for crl.backend: $!\n";

system('openssl req -new '
	. "-config $d/openssl.conf -subj /CN=crl.backend/ "
	. "-key $d/crl.backend.key -out $d/crl.backend.csr "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't create CSR for crl.backend: $!\n";

$t->write_file('crl.certserial', '1000');
$t->write_file('crl.certindex', '');

system("openssl ca -batch -config $d/crl.ca.conf "
	. "-keyfile $d/crl.root.key -cert $d/crl.root.crt "
	. "-subj /CN=crl.backend/ "
	. "-in $d/crl.backend.csr -out $d/crl.backend.crt "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't sign certificate for crl.backend: $!\n";

system("openssl ca -config $d/crl.ca.conf -revoke $d/crl.backend.crt "
	. "-keyfile $d/crl.root.key -cert $d/crl.root.crt "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't revoke crl.backend.crt: $!\n";

system("openssl ca -gencrl -config $d/crl.ca.conf "
	. "-keyfile $d/crl.root.key -cert $d/crl.root.crt "
	. "-out $d/crl.root.crl -crldays 1 "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't create CRL for crl.root: $!\n";

foreach my $name ('depth.int1', 'depth.int2', 'depth.example.com') {
	system("openssl genrsa -out $d/$name.key 2048 "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create private key for $name: $!\n";
	system('openssl req -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-key $d/$name.key -out $d/$name.csr "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create CSR for $name: $!\n";
}

system('openssl x509 -req '
	. "-in $d/depth.int1.csr "
	. "-CA $d/depth.root.crt -CAkey $d/depth.root.key -CAcreateserial "
	. "-days 3650 -extfile $d/depth.ca.ext "
	. "-out $d/depth.int1.crt "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't sign depth.int1 certificate: $!\n";

system('openssl x509 -req '
	. "-in $d/depth.int2.csr "
	. "-CA $d/depth.int1.crt -CAkey $d/depth.int1.key -CAcreateserial "
	. "-days 3650 -extfile $d/depth.ca.ext "
	. "-out $d/depth.int2.crt "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't sign depth.int2 certificate: $!\n";

system('openssl x509 -req '
	. "-in $d/depth.example.com.csr "
	. "-CA $d/depth.int2.crt -CAkey $d/depth.int2.key -CAcreateserial "
	. "-days 3650 -extfile $d/depth.leaf.ext "
	. "-out $d/depth.example.com.crt "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't sign depth.example.com certificate: $!\n";

open my $out, '>', "$d/depth.chain.crt"
	or die "Can't open depth.chain.crt: $!\n";

foreach my $name ('depth.example.com', 'depth.int2', 'depth.int1') {
	open my $in, '<', "$d/$name.crt"
		or die "Can't open $name.crt: $!\n";
	while (my $line = <$in>) {
		print $out $line;
	}
	close $in;
}

close $out;

$t->write_file('index.html', 'SEE-THIS');
$t->run();

###############################################################################

http_get('/verify_prime');
like(http_get('/verify_strict'), qr/502 Bad/ms, 'verify isolated');
http_get('/verify_prime?close');
like(http_get('/verify_strict'), qr/502 Bad/ms, 'verify fresh');

http_get('/name_prime');
like(http_get('/name_strict'), qr/502 Bad/ms, 'name isolated');
http_get('/name_prime?close');
like(http_get('/name_strict'), qr/502 Bad/ms, 'name fresh');

http_get('/sni_prime');
like(http_get('/sni_strict'), qr/200 OK.*X-Name: ,/ms, 'sni isolated');
http_get('/sni_prime?close');
like(http_get('/sni_strict'), qr/200 OK.*X-Name: ,/ms, 'sni fresh');

http_get('/depth_prime');
like(http_get('/depth_strict'), qr/502 Bad/ms, 'depth isolated');
http_get('/depth_prime?close');
like(http_get('/depth_strict'), qr/502 Bad/ms, 'depth fresh');

http_get('/crl_prime');
like(http_get('/crl_strict'), qr/502 Bad/ms, 'crl isolated');
http_get('/crl_prime?close');
like(http_get('/crl_strict'), qr/502 Bad/ms, 'crl fresh');

http_get('/ciphers_prime');
like(http_get('/ciphers_strict'), qr/502 Bad/ms, 'ciphers isolated');
http_get('/ciphers_prime?close');
like(http_get('/ciphers_strict'), qr/502 Bad/ms, 'ciphers fresh');

http_get('/protocols_prime');
like(http_get('/protocols_strict'), qr/502 Bad/ms, 'proto isolated');
http_get('/protocols_prime?close');
like(http_get('/protocols_strict'), qr/502 Bad/ms, 'proto fresh');

http_get('/cert_prime');
like(http_get('/cert_strict'), qr/(?:400|502) Bad/ms, 'cert isolated');
http_get('/cert_prime?close');
like(http_get('/cert_strict'), qr/(?:400|502) Bad/ms, 'cert fresh');

http_get('/conf_prime');
like(http_get('/conf_strict'), qr/(?:400|502) Bad/ms, 'conf isolated');
http_get('/conf_prime?close');
like(http_get('/conf_strict'), qr/(?:400|502) Bad/ms, 'conf fresh');

http_get('/bind_prime');
like(http_get('/bind_strict'), qr/200 OK.*127\.0\.0\.1/ms, 'bind isolated');
http_get('/bind_prime?close');
like(http_get('/bind_strict'), qr/200 OK.*127\.0\.0\.1/ms, 'bind fresh');

###############################################################################
