#!/usr/bin/perl

# (C) Nginx, Inc.

# Tests for dav_follow_symlinks directive.

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

my $t = Test::Nginx->new()->has(qw/http dav symlink/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        dav_methods PUT DELETE MKCOL COPY MOVE;

        location / {
        }

        location /off/ {
            dav_follow_symlinks off;
        }
    }
}

EOF

my $d = $t->testdir();

mkdir("$d/dir");
mkdir("$d/dir/target");
$t->write_file('dir/target/file', '');

mkdir("$d/off");

for my $loc ('', 'off/') {
    mkdir("$d/${loc}test");
    $t->write_file("${loc}test/file", '');
    symlink("$d/dir/target", "$d/${loc}test/link");
}

# symlink to file

$t->write_file('dir/target/extfile', '');
symlink("$d/dir/target/extfile", "$d/off/test/filelink");

# root symlink

mkdir("$d/dir/rootdir");
$t->write_file('dir/rootdir/file', '');
symlink("$d/dir/rootdir", "$d/off/rootlink");

# file symlink only

mkdir("$d/off/fileonly");
$t->write_file('off/fileonly/regular', '');
symlink("$d/dir/target/extfile", "$d/off/fileonly/flink");

# clean tree

mkdir("$d/off/clean");
$t->write_file('off/clean/a', '');
$t->write_file('off/clean/b', '');

# existing destination

mkdir("$d/off/existing");
$t->write_file('off/existing/old', '');

$t->try_run('no dav_follow_symlinks')->plan(16);

###############################################################################

# default

my $r = http(<<EOF);
COPY /test/ HTTP/1.1
Host: localhost
Destination: /test-copy/
Connection: close

EOF

ok(-f "$d/test-copy/link/file", 'copy dir symlink (default)');

$t->write_file('dir/target/file', '');

$r = http(<<EOF);
DELETE /test/ HTTP/1.1
Host: localhost
Connection: close

EOF

ok(!-f "$d/dir/target/file", 'delete dir symlink (default)');

$t->write_file('dir/target/file', '');
$t->write_file('dir/target/extfile', '');

# off

$r = http(<<EOF);
COPY /off/test/ HTTP/1.1
Host: localhost
Destination: /off/test-copy/
Connection: close

EOF

like($r, qr/403 Forbidden/, 'copy dir symlink (off)');
ok(!-e "$d/off/test-copy", 'copy no partial state (off)');

# overwrite

$r = http(<<EOF);
COPY /off/test/ HTTP/1.1
Host: localhost
Destination: /off/existing/
Overwrite: T
Connection: close

EOF

like($r, qr/403 Forbidden/, 'copy overwrite symlink (off)');
ok(-f "$d/off/existing/old", 'overwrite preserved (off)');

$r = http(<<EOF);
DELETE /off/test/ HTTP/1.1
Host: localhost
Connection: close

EOF

ok(!-e "$d/off/test", 'delete tree (off)');
ok(-f "$d/dir/target/file", 'delete dir symlink target (off)');
ok(-f "$d/dir/target/extfile", 'delete file symlink target (off)');

# root symlink

$r = http(<<EOF);
COPY /off/rootlink/ HTTP/1.1
Host: localhost
Destination: /off/rootlink-copy/
Connection: close

EOF

like($r, qr/403 Forbidden/, 'copy root symlink (off)');

$r = http(<<EOF);
DELETE /off/rootlink/ HTTP/1.1
Host: localhost
Connection: close

EOF

ok(!-e "$d/off/rootlink", 'delete root symlink (off)');
ok(-d "$d/dir/rootdir", 'delete root symlink target (off)');

# clean tree

$r = http(<<EOF);
COPY /off/clean/ HTTP/1.1
Host: localhost
Destination: /off/clean-copy/
Connection: close

EOF

like($r, qr/201 Created/, 'copy clean dir (off)');
ok(-f "$d/off/clean-copy/a", 'copy clean file (off)');

$r = http(<<EOF);
DELETE /off/clean-copy/ HTTP/1.1
Host: localhost
Connection: close

EOF

ok(!-e "$d/off/clean-copy", 'delete clean dir (off)');

# file symlink

$r = http(<<EOF);
COPY /off/fileonly/ HTTP/1.1
Host: localhost
Destination: /off/fileonly-copy/
Connection: close

EOF

like($r, qr/403 Forbidden/, 'copy file symlink (off)');

###############################################################################
