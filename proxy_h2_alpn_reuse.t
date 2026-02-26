#!/usr/bin/perl

# (C) OIS

# Test for keepalive reuse across proxy_http_version (HTTP/2 ALPN vs HTTP/1.1).

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
	->has(qw/http http_ssl http_v2 proxy upstream_keepalive sni/)
	->has_daemon('openssl');

plan(skip_all => 'no ALPN support in OpenSSL')
	if $t->has_module('OpenSSL') and not $t->has_feature('openssl:1.0.2');

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream u_keep {
        server 127.0.0.1:8443;
        keepalive 1;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        proxy_ssl_session_reuse off;
        proxy_set_header Connection "";

        location /prime {
            proxy_pass https://u_keep/;
            proxy_http_version 2;
        }

        location /strict {
            proxy_pass https://u_keep/;
            proxy_http_version 1.1;
            proxy_read_timeout 1s;
            proxy_send_timeout 1s;
        }
    }

    server {
        listen       127.0.0.1:8443 ssl;
        server_name  backend;

        http2 on;

        ssl_certificate localhost.crt;
        ssl_certificate_key localhost.key;

        location / {
            if ($arg_close) { return 444; }
            add_header X-Backend-Conn $connection always;
            add_header X-Backend-Proto $server_protocol always;
            add_header X-Backend-ALPN $ssl_alpn_protocol always;
            return 200 "ok";
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

my $d = $t->testdir();

system('openssl req -x509 -new '
	. "-config $d/openssl.conf -subj /CN=localhost/ "
	. "-out $d/localhost.crt -keyout $d/localhost.key "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't create certificate for localhost: $!\n";

$t->try_run('no proxy_http_version 2')->plan(6);

###############################################################################

my ($r, $n);

like($r = http_get('/prime'), qr/200 OK.*HTTP\/2\.0.*h2/ms, 'prime h2');
$r =~ m/X-Backend-Conn: (\d+)/i; $n = $1;
like(http_get('/prime'),
	qr/200 OK(?=.*HTTP\/2\.0)(?=.*h2)(?=.*X-Backend-Conn: $n)/msi,
	'prime h2 reuse');
like($r = http_get('/strict'), qr/200 OK.*HTTP\/1\.1/ms, 'strict isolated');
unlike($r, qr/X-Backend-Conn: $n/i, 'strict no h2 reuse');
like(http_get('/prime?close=1'), qr/502 Bad Gateway/ms, 'prime close 502');
like(http_get('/strict'), qr/200 OK.*HTTP\/1\.1/ms, 'strict h1 after close');

###############################################################################
