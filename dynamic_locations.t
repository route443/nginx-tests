#!/usr/bin/perl

use warnings;
use strict;

use Test::More;
use FindBin;
use Time::HiRes qw(time);

BEGIN { chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()
	->has(qw/http proxy/)
	->plan(1);


# h2load params
my $H2LOAD_BIN          = 'h2load';
my $N_MAIN              = 1_000_000;
my $C_MAIN              = 100;
my $T_MAIN              = 4;

my $N_KEEPALIVE         = 200_000;
my $C_KEEPALIVE         = 1;
my $T_KEEPALIVE         = 1;

my $front_port = port(8080);
my $back_port  = port(8081);

my $d = $t->testdir();

#§ Setup test files
mkdir "$d/html" unless -d "$d/html";
$t->write_file('html/1.txt', "OK\n");

mkdir "$d/eval" unless -d "$d/eval";
$t->write_file('eval/proxy_const.conf', <<"EOF");
proxy_pass http://127.0.0.1:$back_port;
EOF
$t->write_file('eval/proxy_var.conf', <<"EOF");
proxy_pass http://127.0.0.1:$back_port\$request_uri;
EOF
$t->write_file('eval/alias.conf', <<"EOF");
alias $d/html/;
EOF

my $conf = <<"EOF";
%%TEST_GLOBALS%%

daemon off;
worker_processes  1;

events {
	worker_connections  8192;
	# accept_mutex off;
}

http {
	%%TEST_GLOBALS_HTTP%%

	keepalive_timeout   1h;
	keepalive_requests  1000000;

	server {
		listen 127.0.0.1:$back_port;
		server_name backend;

		location / {
			return 204;
		}
	}

	server {
		listen 127.0.0.1:$front_port;
		server_name front;

		location = /baseline/static_proxy {
			proxy_pass http://127.0.0.1:$back_port;
		}

		location /baseline/alias/ {
			alias $d/html/;
		}

		location = /eval/data_proxy_const {
			eval "data:proxy_pass http://127.0.0.1:$back_port;";
		}

		location = /eval/data_proxy_var {
			eval "data:proxy_pass http://127.0.0.1:$back_port\$request_uri;";
		}

		location /eval/data_alias/ {
			eval "data:alias $d/html/;";
		}

		location = /eval/file_proxy_const {
			eval eval/proxy_const.conf;
		}

		location = /eval/file_proxy_var {
			eval eval/proxy_var.conf;
		}

		location /eval/file_alias/ {
			eval eval/alias.conf;
		}
	}
}
EOF

$t->write_file_expand('nginx.conf', $conf);
$t->run();

# Warker pids
my @workers = nginx_worker_pids($t);
diag("front_port=$front_port back_port=$back_port workers=@workers");

# CSV output
my $csv = "$d/eval_perf.csv";
open my $csv_fh, '>', $csv or die "can't open $csv: $!\n";
print $csv_fh join(',', qw(
	case
	n c t
	wall_s
	cpu_ticks_delta
	rss_kb_before rss_kb_after
	h2load_status
	h2load_out
)), "\n";
close $csv_fh;

###############################################################################

run_case($t, \@workers, $front_port, $csv, 'baseline_static_proxy',
	"/baseline/static_proxy", $N_MAIN, $C_MAIN, $T_MAIN);

run_case($t, \@workers, $front_port, $csv, 'eval_data_proxy_const',
	"/eval/data_proxy_const", $N_MAIN, $C_MAIN, $T_MAIN);

run_case($t, \@workers, $front_port, $csv, 'eval_file_proxy_const',
	"/eval/file_proxy_const", $N_MAIN, $C_MAIN, $T_MAIN);

run_case($t, \@workers, $front_port, $csv, 'eval_data_proxy_var',
	"/eval/data_proxy_var", $N_MAIN, $C_MAIN, $T_MAIN);

run_case($t, \@workers, $front_port, $csv, 'baseline_alias',
	"/baseline/alias/1.txt", $N_MAIN, $C_MAIN, $T_MAIN);

run_case($t, \@workers, $front_port, $csv, 'eval_data_alias',
	"/eval/data_alias/1.txt", $N_MAIN, $C_MAIN, $T_MAIN);

run_case($t, \@workers, $front_port, $csv, 'eval_file_alias',
	"/eval/file_alias/1.txt", $N_MAIN, $C_MAIN, $T_MAIN);

# todo : keepalive tests
run_case($t, \@workers, $front_port, $csv, 'keepalive_baseline_static_proxy',
	"/baseline/static_proxy", $N_KEEPALIVE, $C_KEEPALIVE, $T_KEEPALIVE);

run_case($t, \@workers, $front_port, $csv, 'keepalive_eval_data_proxy_const',
	"/eval/data_proxy_const", $N_KEEPALIVE, $C_KEEPALIVE, $T_KEEPALIVE);

ok(1, "perf runs completed (results in $csv)");


###############################################################################

sub run_case {
	my ($t, $workers, $port, $csv, $name, $uri, $n, $c, $thr) = @_;

	my $url = "http://127.0.0.1:$port$uri";

	my $rss0 = workers_rss_kb_sum($workers);
	my $cpu0 = workers_cpu_ticks_sum($workers);
	my $t0 = time();

	my ($status, $out) = run_h2load($t, $name, $url, $n, $c, $thr);

	my $t1 = time();
	my $rss1 = workers_rss_kb_sum($workers);
	my $cpu1 = workers_cpu_ticks_sum($workers);

	my $wall = sprintf("%.3f", $t1 - $t0);
	my $cpu_delta = $cpu1 - $cpu0;

	diag("$name: wall=${wall}s cpu_ticks_delta=$cpu_delta rss_kb=$rss0->$rss1 status=$status");
	diag("$name: h2load_out=$out url=$url");

	open my $fh, '>>', $csv or die "can't append $csv: $!\n";
	print $fh join(',', $name, $n, $c, $thr, $wall, $cpu_delta, $rss0, $rss1, $status, $out), "\n";
	close $fh;

	die "h2load failed for $name (status=$status), see $out\n" if $status != 0;
}

sub run_h2load {
	my ($t, $label, $url, $n, $c, $thr) = @_;

	my $out = $t->testdir() . "/h2load.$label.out";

	my @args = (
		$H2LOAD_BIN,
		'--h1',
		'-n', $n,
		'-c', $c,
		'-t', $thr,
		$url
	);

	diag("run: " . join(' ', @args));

	my $pid = fork();
	die "can't fork: $!\n" unless defined $pid;

	if ($pid == 0) {
		open STDOUT, '>', $out or die "can't open $out: $!\n";
		open STDERR, '>&STDOUT' or die "can't dup stderr: $!\n";
		exec { $H2LOAD_BIN } @args;
		die "can't exec $H2LOAD_BIN: $!\n";
	}

	waitpid($pid, 0);
	my $status = $? >> 8;

	return ($status, $out);
}

sub nginx_worker_pids {
	my ($t) = @_;

	my $master = $t->read_file('nginx.pid');
	$master =~ s/\s+//g;

	return () unless $master =~ /^\d+$/;

	my @lines = split /\n/, `ps -o pid= --ppid $master 2>/dev/null`;
	my @pids;
	for my $line (@lines) {
		push @pids, $1 if $line =~ /^\s*(\d+)/;
	}

	if (!@pids) {
		my $comm = `ps -o comm= -p $master 2>/dev/null`;
		push @pids, $master if $comm =~ /nginx/;
	}

	return @pids;
}

sub workers_cpu_ticks_sum {
	my ($pids) = @_;
	my $sum = 0;
	$sum += proc_cpu_ticks($_) for @$pids;
	return $sum;
}

sub workers_rss_kb_sum {
	my ($pids) = @_;
	my $sum = 0;
	$sum += proc_rss_kb($_) for @$pids;
	return $sum;
}

sub proc_cpu_ticks {
	my ($pid) = @_;
	my $path = "/proc/$pid/stat";

	open my $fh, '<', $path or return 0;
	my $s = <$fh>;
	close $fh;

	$s =~ s/^\d+\s+\(.*?\)\s+// or return 0;
	my @f = split /\s+/, $s;

	my $utime = $f[11] // 0;
	my $stime = $f[12] // 0;

	return $utime + $stime;
}

sub proc_rss_kb {
	my ($pid) = @_;
	my $path = "/proc/$pid/status";

	open my $fh, '<', $path or return 0;
	while (my $line = <$fh>) {
		if ($line =~ /^VmRSS:\s+(\d+)\s+kB/) {
			close $fh;
			return $1;
		}
	}
	close $fh;

	return 0;
}
###############################################################################