#!/usr/bin/perl
#
# $Id: checkraid.pl 98 2015-11-30 20:25:17Z phil $
#
# checkraid: check controller and disk status
# author, (c): Philippe Kueck <projects at unixadm dot org>
#
# requires: arcconf compat-libstdc++-33 tw_cli MegaCli
# requires: perl(Sys::Syslog) perl(File::Path) perl(Fcntl)
#
use strict;
use warnings;
use Sys::Syslog qw(:standard :macros);
use File::Path qw(mkpath);
use Fcntl qw(:flock);

$ENV{'PATH'} = "$ENV{'PATH'}:/sbin:/usr/sbin:/usr/local/sbin:/bin:/usr/bin:/usr/local/bin";

##############################################################################

my $conf = {
	'timeout' => 15, # timeout for controller check command, returns CRIT after 3 timeouts
	'timeoutfile' => '/dev/shm/checkraid/timeout', # this is where the timeout is stored
	'lockfile' => '/dev/shm/checkraid/lock', # to avoid concurrent instances
	'verbose' => 0, # verbose mode
	# syntax for adding other controllers or other checks
	# 'controller' => {
	# 	'probe' => ['command that returns the controllers', qr/identifier regex/],
	# 	'cli' => 'controller cli call', # TARGET will be replaced by what was probed
	# 	'checks' => [
	# 		[ qr/line regex/, qr/OK regex/, qr/WARN regex/, qr/CRIT regex/]
	# 	]
	# }
	'adaptec' => {
		# adaptec controller nums start at 1 and increment with every additional
		# controller. afaict. so let's just read the amount of controllers out
		# of /proc/bus/pci/devices. ugly, but it works.
		'probe' => ['grep aacraid /proc/bus/pci/devices | cat -n', qr/^\s*(\d+)\s+/],
		'cli' => 'arcconf getconfig TARGET',
		'checks' => [
			[qr/^controllers found: (\d+)$/i, qr/[1-9]/, qr/^0$/, undef],
			[qr/^\s+status of logical device.*:\s+([a-z]+)$/i,
				qr/^Optimal$/, qr/^Degraded$/, undef
			],
			[qr/^\s+state\b.*:\s+([a-z -]+)$/i,
				qr/^(?:Online|Ready|(?:Dedicated|Global)? ?Hot[ -]Spare)$/,
				qr/^Rebuilding$/,
				qr/^(?:Offline|Failed)$/
			],
			[qr/^\s+failed stripes\b.*:\s+(yes|no)$/i,
				qr/^No$/, undef, qr/^Yes$/
			],
			[qr/^\s+S\.M\.A\.R\.T\. warnings\b.*: (\d+)$/,
				qr/^0$/, qr/^(?:[1-9]|[1-4][0-9])$/, qr/^(?:[5-9][0-9]|\d{3,})$/,
			],
			[qr/^\s+segment\b.*:\s+([a-z]+?)\s/i,
				qr/^Present$/, qr/^Rebuilding$/, qr/^(?:Inconsistent|Missing)$/
			],
			[qr/^\s+status of maxcache\b.*:\s+([a-z]+?)$/i,
				qr/^Optimal$/, undef, qr/^(?!Optimal)/
			]
		]
	},
	'3ware' => {
		'probe' => ['tw_cli show', qr/^(c\d+)\s/],
		'cli' => 'tw_cli /TARGET show',
		'checks' => [
			[qr/^(e)rror.*controller does not exist/i, undef, qr/./, undef],
			[qr/^[udp]\d+\s+(?:RAID-\d+)?\s+([a-z]+?)\s/i, qr/OK/, qw/REBUILDING/, qw/DEGRADED/],
		]
	},
	'lsi' => {
		# megacli allows checking all controllers at once, no probing required
		'cli' => 'MegaCli -cfgdsply -aall',
		'checks' => [
			[qr/^State\s+: ([a-z]+)/i, qr/^Optimal$/, undef, qr/^(?:Degraded|Offline)$/],
			[qr/^(?:Media|Other) Error Count: (\d+)$/, qr/^0$/, qr/^(?:[1-9]|[1-4][0-9])$/, qr/^(?:[5-9][0-9]|\d{3,})$/],
			[qr/^Predictive Failure Count: (\d+)$/, qr/^0$/, qr/^(?:[1-9]|[1-4][0-9])$/, qr/^(?:[5-9][0-9]|\d{3,})$/],
			[qr/^Firmware state: ([a-z, ]+)$/i, qr/^Online, Spun Up$/, undef, undef],
			[qr/^Drive has flagged a S\.M\.A\.R\.T alert\s*: (yes|no)$/i, qr/^no$/i, qr/^yes$/i, undef]
		]
	},
	'lsi-storcli' => {
		'probe' => ['storcli show', qr/^\s+(\d+)\s+/],
		'cli' => 'storcli /cTARGET show',
		'checks' => [
			[qr/^\d\/\d\s+\w+\s+(\w+)/, qr/^Optl$/, undef, qr/^(?!Optl)/],
    	]
  	},
	'zfs' => {
		'probe' => ['zpool list -H', qr/^([^\s]+)/],
		'cli' => 'zpool status TARGET',
		'checks' => [
			[qr/^\s+state: ([A-Z]+)$/, qr/ONLINE/, undef, qr/(?:DEGRADED|FAULTED)/],
			[qr/[a-z0-9_-]+\s+(degraded|faulted|offline|online|unavail|removed)(?:\s+\d+){3}/i,
				qr/ONLINE/,
				qr/(?:DEGRADED|REMOVED)/,
				qr/(?:OFFLINE|UNAVAIL|FAULTED)/
			],
			[qr/[a-z0-9_-]+\s+(?:degraded|faulted|offline|online|unavail|removed)\s+(?:\d+\s+){2}(\d+)$/i,
				qr/^0$/, qr/^[^0]$/, undef
			],
			[qr/[a-z0-9_-]+\s+((?:un)?avail)/i, qr/^AVAIL/, qr/UNAVAIL/, undef] # spare
		]
	},
	'md' => {
		'probe' => ['cat /proc/mdstat', qr/^(md\d+)/],
		'cli' => 'mdadm -D /dev/TARGET',
		'checks' => [
			[qr/^\s+State : ([a-z, ]+)$/,
				qr/^(?:clean|active)/, qr/(?:re(?:sync|cover|shap)ing|degraded)/, undef
			],
			[qr/^\s+(?:\d+\s+){4}([a-z]+)/, qr/active/, qr/rebuilding/, qr/removed/],
			[qr/^\s+Failed Devices : (\d+)/, qr/^0$/, undef, qr/^[^0]$/],
		]
	}
};

##############################################################################

my $exit = {0 => 'OK', 1 => 'WARNING', 2 => 'CRITICAL', 3 => 'UNKNOWN'};
my ($ctrl, $target) = ('adaptec', undef);

while ($_ = shift @ARGV) {
	if ($_ eq '-v' || $_ eq '--verbose') {$conf->{'verbose'}++; next}
	if ($_ eq '-T' || $_ eq '--timeout') {
		&usage unless defined $ARGV[0] and $ARGV[0] =~ /^\d+$/;
		$conf->{'timeout'} = shift @ARGV;
		next
	}
	if ($_ eq '-c' || $_ eq '--check') {
		&usage unless defined $ARGV[0];
		if (exists $conf->{$ARGV[0]}->{'cli'}) {$ctrl = shift @ARGV; next}
		bailout(3, sprintf "check '%s' is unknown to me.\n", $ARGV[0])
	}
	if ($_ eq '-t' || $_ eq '--target') {
		&usage unless defined $ARGV[0];
		$target = shift @ARGV;
		next
	}
	&usage
}

##############################################################################

openlog("checkraid", "ndelay,pid", LOG_USER);

my (@ebuf, @outbuf);
my $status = 0;

sub bailout {
	printf "%s - %s\n", $exit->{$_[0]}, $_[1]||$exit->{$_[0]};
	exit $_[0]
}

sub bailout_log {
	syslog(shift, $_[1]);
	closelog();
	bailout(@_)
}

sub usage {
	printf STDERR "usage: $0 [-v] [-c <check>] [-t <target>] [-T <timeout>]\nwhere <check> is one of:\n\n";
	foreach my $c (keys %{$conf}) {
		next unless ref $conf->{$c} eq 'HASH';
		printf STDERR "\t%-10s %s\n", $c, $conf->{$c}->{'cli'}
			if exists $conf->{$c}->{'cli'}
	}
	bailout(3, "check parameters.")
}

sub check {
	open CLI, $_[0] . " 2>&1|" or
		bailout_log("err", 3,
			sprintf("Error opening %s: %s", $conf->{$ctrl}->{'cli'}, $!));

	while (<CLI>) {
		foreach my $c (@{$conf->{$ctrl}->{'checks'}}) {
			chomp;
			next unless $_ =~ $c->[0];
			push @outbuf, $_;
			if (defined $c->[3] && $1 =~ $c->[3]) {
				syslog("err", 'CRIT:'.$_);
				$outbuf[-1] = "\e[30m\e[41m".$outbuf[-1]."\e[0m";
				s/\s+/ /g; push @ebuf, "\@$_[1]: $_";
				$status = 2 if $status < 2
			} elsif (defined $c->[2] && $1 =~ $c->[2]) {
				syslog("warning", 'WARN:'.$_);
				$outbuf[-1] = "\e[30m\e[43m".$outbuf[-1]."\e[0m";
				s/\s+/ /g; push @ebuf, "\@$_[1]: $_";
				$status = 1 if $status < 1
			} elsif (defined $c->[1] && $1 =~ $c->[1]) {
				;
			} else {
				syslog("info", 'UNKN:'.$_);
				$status = 3 if $status == 0
			}
		}
	}
	close CLI;
}

##############################################################################

my $strikes = 3;
my $out;

mkpath(($conf->{'lockfile'} =~ m!^(.+?)[^/]+$!)[0]);
open (my $lock, ">", $conf->{'lockfile'});
eval {no warnings 'closed';flock $lock, LOCK_EX|LOCK_NB or die};
bailout_log("warning", 3, "cannot acquire lockfile, another copy still running?") if $@;

$SIG{'ALRM'} = sub {
	--$strikes;
	mkpath(($conf->{'timeoutfile'} =~ m!^(.+?)[^/]+$!)[0]);
	if (-r $conf->{'timeoutfile'}) {
		open TF, "< ".$conf->{'timeoutfile'};
		while (<TF>) {--$strikes; last if $strikes <= 0}
		close TF
	}
	open TF, ">> ".$conf->{'timeoutfile'}; print TF scalar localtime()."\n"; close TF;
	bailout_log("warning", ($strikes > 0)?1:2, sprintf("Timeout, %d strikes left", $strikes))
};
alarm($conf->{'timeout'});

bailout_log("err", 3, "Not running as root") unless $< == 0;

if (defined $target) {
	$conf->{$ctrl}->{'cli'} =~ s/TARGET/$target/;
	check $conf->{$ctrl}->{'cli'}, "$target"
} elsif (exists $conf->{$ctrl}->{'probe'}) {
	my @ctrlno;
	open CLI, $conf->{$ctrl}->{'probe'}->[0] . " 2>&1|" or
		bailout_log("err", 3, sprintf("Error opening %s: %s", $conf->{$ctrl}->{'probe'}->[0], $!));
	while (<CLI>) {
		next unless $_ =~ $conf->{$ctrl}->{'probe'}->[1];
		push @ctrlno, $1
	}
	close CLI;

	bailout_log("err", 3, "No controller found") unless @ctrlno;

	foreach (@ctrlno) {
		(my $tmp = $conf->{$ctrl}->{'cli'}) =~ s/TARGET/$_/;
		push @outbuf, "check $_";
		check $tmp, "$_"
	}
} else {
	check $conf->{$ctrl}->{'cli'}, "TARGET"
}


unlink $conf->{'timeoutfile'};

alarm(0);

syslog("info", "completed with status %s", $exit->{$status});

closelog();
printf STDERR "%s Output %s\n%s\n", '*'x30, '*'x30, join("\n", @outbuf)
	if $conf->{'verbose'};

bailout($status, join ",", @ebuf);

__END__

=head1 NAME

checkraid - a simple raid checker for nagios

=head1 VERSION

$Revision: 98 $

=head1 SYNOPSIS

 checkraid [options]

=head1 OPTIONS

=over 8

=item B<-c> I<controller>

optional. select I<controller>: B<adaptec>, B<3ware>, B<lsi>, B<lsi-storcli>, B<zfs>, B<md>. Defaults to B<adaptec>. 

=item B<-v>,B<--verbose>

optional. display matched controller utility output

=item B<-t>,B<--target> I<target>

optional. select controller target, e.g. I<md127> for md, I<myzpool> for zfs, I<2> for adaptec raid controller 2..

=item B<-T>,B<--timeout> I<timeout>

optional. set timeout for this check, defaults to 15s.

=back

=head1 DESCRIPTION

This script uses oem tools to check the raid status.

It works with

=over 8

=item * B<Adaptec> (arcconf)

=item * B<_3ware> (tw_cli)

=item * B<LSI> (MegaCli or storcli)

=item * B<zfs> (zpool)

=item * B<md> (mdadm)

=back

=head1 RETURN CODES

=over 8

=item B<exit 0>

OK (no errors, everything is fine)

=item B<exit 1>

WARNING ('rebuilding' state)

=item B<exit 2>

ERROR ('degraded' and 'offline' states)

=item B<exit 3>

UNKNOWN (controller not found, unknown status or usage errors)

=back

=head1 DEPENDENCIES

=over 8

=item * Sys::Syslog

=item * File::Path

=item * Fcntl

=item * arcconf (optional)

=item * tw_cli (optional)

=item * MegaCli (optional)

=item * storcli (optional)

=item * zpool (optional)

=item * mdadm (optional)

=back

=head1 INSTALLATION

Move the script anywhere you like, then add it to your snmpd.conf:

 exec checkraid /path/to/checkraid [options]

or to your nrpe.conf:

 command[check_raid]=sudo /usr/sbin/checkraid [options]

=head1 AUTHOR

Philippe Kueck <projects at unixadm dot org>

=cut

