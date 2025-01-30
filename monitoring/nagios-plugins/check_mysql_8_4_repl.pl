#!/usr/bin/perl

use strict;
use warnings;
use DBI;
use Getopt::Long;

# Default values for the MySQL connection
my $replication_user = 'root';
my $replication_pass = 'password';
my $replication_slave_address = 'localhost';
my $replication_slave_port = '3306';
my $warning_threshold = 60;  # Default threshold for warning
my $critical_threshold = 300;  # Default threshold for critical
my $socket = '';  # For MySQL socket, default is empty

# Parse command-line arguments
GetOptions(
    'u=s' => \$replication_user,  # MySQL username
    'pw=s' => \$replication_pass,  # MySQL password
    'H=s' => \$replication_slave_address,  # MySQL slave address (host)
    'P=s' => \$replication_slave_port,  # MySQL slave port (3306 by default)
    'S=s' => \$socket,  # Optional MySQL socket
    'w=i' => \$warning_threshold,  # Warning threshold for replication delay
    'c=i' => \$critical_threshold,  # Critical threshold for replication delay
) or die "Usage: $0 -u <user> -p <password> -H <host> -P <port> -S <socket> -w <warning> -c <critical>\n";

# Debugging: Print the arguments received
#print "Arguments:\n";
#print "User: $replication_user\n";
#print "Password: $replication_pass\n";
#print "Host: $replication_slave_address\n";
#print "Port: $replication_slave_port\n";
#print "Socket: $socket\n";
#print "Warning Threshold: $warning_threshold\n";
#print "Critical Threshold: $critical_threshold\n";

# Build DSN connection string based on provided arguments
my $dsn = "DBI:mysql:host=$replication_slave_address;port=$replication_slave_port";
$dsn .= ";mysql_socket=$socket" if $socket && $socket ne '';

# Debugging: Print DSN for verification
print "DSN: $dsn\n";

# Connect to MySQL database
my $dbh = DBI->connect($dsn, $replication_user, $replication_pass, 
    {'RaiseError' => 1, 'AutoCommit' => 1})
    or die "Could not connect to MySQL: $DBI::errstr\n";

# Query to get replication status (fields updated for MySQL 8.4)
my $sth = $dbh->prepare("SHOW REPLICA STATUS");
$sth->execute() or die "Failed to execute query: " . $sth->errstr;

# Check if any rows are returned
my $replica_status = $sth->fetchrow_hashref();

# Check if replication status is found
if (!defined $replica_status) {
    print "UNKNOWN: MySQL Replication Status - No replication status found. Please ensure replication is set up.\n";
    exit 3; # UNKNOWN
}

# Fetch replication status
my $replica_io_running = $replica_status->{Replica_IO_Running};
my $replica_sql_running = $replica_status->{Replica_SQL_Running};
my $seconds_behind_source = $replica_status->{Seconds_Behind_Source} // 0;  # Default to 0 if undefined

# If any expected values are not set, consider them as unknown
if (!defined $replica_io_running || !defined $replica_sql_running) {
    print "UNKNOWN: MySQL Replication Status - Missing replication status fields (Replica_IO_Running or Replica_SQL_Running)\n";
    exit 3; # UNKNOWN
}

if ($replica_io_running eq 'Yes' && $replica_sql_running eq 'Yes' && $seconds_behind_source <= $warning_threshold) {
    print "OK: $replication_slave_address, - Replication is running smoothly, Seconds Behind Source: $seconds_behind_source\n";
    exit 0; # OK
} elsif ($replica_io_running eq 'Yes' && $replica_sql_running eq 'Yes' && $seconds_behind_source <= $critical_threshold) {
    print "WARNING: $replication_slave_address, - Replication is running with delay, Seconds Behind Source: $seconds_behind_source\n";
    exit 1; # WARNING
} elsif ($replica_io_running eq 'Yes' && $replica_sql_running eq 'Yes' && $seconds_behind_source > $critical_threshold) {
    print "CRITICAL: $replication_slave_address, - Replication delay is over critical threshold, Seconds Behind Source: $seconds_behind_source\n";
    exit 2; # CRITICAL
} elsif ($replica_io_running eq 'No' || $replica_sql_running eq 'No') {
    print "CRITICAL: $replication_slave_address, - Replication is not running properly. IO Running: $replica_io_running, SQL Running: $replica_sql_running\n";
    exit 2; # CRITICAL
}

# Cleanup: Finish the statement and disconnect
$sth->finish();
$dbh->disconnect();

