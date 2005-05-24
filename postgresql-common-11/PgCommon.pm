# Common functions for the postgresql-common framework
# (C) 2005 Martin Pitt <mpitt@debian.org>

package PgCommon;

use Exporter;
$VERSION = 1.00;
@ISA = ('Exporter');
@EXPORT = qw/error user_cluster_map get_cluster_port set_cluster_port
    get_cluster_socketdir set_cluster_socketdir
    get_program_path cluster_info get_versions get_newest_version
    get_version_clusters next_free_port cluster_exists install_file
    change_ugid/;
@EXPORT_OK = qw/$confroot/;

# configuration
$mapfile = "/etc/postgresql-common/user_clusters";
$confroot = "/etc/postgresql";
$common_confdir = "/etc/postgresql-common";
$binroot = "/usr/lib/postgresql";
$defaultport = 5432;

# Print an error message to stderr and exit with status 1
sub error {
    print STDERR 'Error: ', $_[0], "\n";
    exit 1;
}

# Return parameter from a PostgreSQL configuration file, or undef if the parameter
# does not exist.
# Arguments: <version> <cluster> <config file name> <parameter name>
sub get_conf_value {
    return 0 unless $_[0] && $_[1];
    my $fname = "$confroot/$_[0]/$_[1]/$_[2]";
    -e $fname or $fname = "$common_confdir/$_[2]";

    if (open F, $fname) {
        while (<F>) {
            return $1 if /^\s*$_[3]\s*=\s*(\w+)\b/; # simple value
            return $1 if /^\s*$_[3]\s*=\s*'([^']*)'/; # string value
        }
        close F;
    }
    return undef;
}

# Set parameter of a PostgreSQL configuration file.
# Arguments: <version> <cluster> <config file name> <parameter name> <value>
sub set_conf_value {
    my $fname = "$confroot/$_[0]/$_[1]/$_[2]";
    my $value;

    if ($_[4] =~ /^\w+$/) {
	$value = $_[4];
    } else {
	$value = "'$_[4]'";
    }

    # read configuration file lines
    open (F, $fname) or die "Error: could not open $fname for reading";
    push @lines, $_ while (<F>);
    close F;

    my $found = 0;
    for ($i=0; $i <= $#lines; ++$i) {
	if ($lines[$i] =~ /^\s*#?\s*$_[3]\s*=/) {
	    $lines[$i] = "$_[3] = $value\n";
	    $found = 1;
	}
    }
    push (@lines, "$_[3] = $value\n") unless $found;

    # write configuration file lines
    open (F, '>'.$fname) or die "Error: could not open $fname for writing";
    foreach (@lines) {
	print F $_;
    }
    close F;
}

# Return the port of a particular cluster or undef if the cluster
# does not exist.
# Arguments: <version> <cluster>
sub get_cluster_port {
    return get_conf_value($_[0], $_[1], 'postgresql.conf', 'port');
}

# Set the port of a particular cluster. 
# Arguments: <version> <cluster> <port>
sub set_cluster_port {
    set_conf_value $_[0], $_[1], 'postgresql.conf', 'port', $_[2];
}

# Return the socket directory of a particular cluster or undef if the cluster
# does not exist.
# Arguments: <version> <cluster>
sub get_cluster_socketdir {
    return get_conf_value($_[0], $_[1], 'postgresql.conf', 'unix_socket_directory') || '/tmp';
}

# Set the socket directory of a particular cluster. 
# Arguments: <version> <cluster> <directory>
sub set_cluster_socketdir {
    set_conf_value $_[0], $_[1], 'postgresql.conf', 'unix_socket_directory', $_[2];
}

# Return the path of a program of a particular version.
# Arguments: <program name> <version>
sub get_program_path {
    return '' unless defined($_[0]) && defined($_[1]);
    my $path = "$binroot/$_[1]/bin/$_[0]";
    return $path if -x $path;
    return '';
}

# Check whether a postmaster server is running at the specified port.
# Arguments: <version> <cluster> <port>
sub port_running {
    my $psql = get_program_path 'psql', $_[0];
    my $socketdir = get_cluster_socketdir $_[0], $_[1];
    die "port_running: invalid port $_[2]" if $_[2] !~ /\d+/;
    $out = `LANG=C $psql -h '$socketdir' -p $_[2] -l 2>&1 > /dev/null`;
    return 1 unless $?;
    return (index ($out, "could not connect") < 0);
}

# Return a hash with information about a specific cluster.
# Arguments: <version> <cluster name>
# Returns: information hash (keys: pgdata, port, running, logfile, configdir,
# owneruid, ownergid, socketdir)
sub cluster_info {
    $result{'configdir'} = "$confroot/$_[0]/$_[1]";
    $result{'pgdata'} = readlink ($result{'configdir'} . "/pgdata");
    $result{'logfile'} = readlink ($result{'configdir'} . "/log");
    $result{'port'} = (get_conf_value $_[0], $_[1], 'postgresql.conf', 'port') || $defaultport;
    $result{'socketdir'} = (get_conf_value $_[0], $_[1], 'postgresql.conf', 'unix_socket_directory') || '/tmp';
    $result{'running'} = port_running ($_[0], $_[1], $result{'port'});
    if ($result{'pgdata'}) {
        ($result{'owneruid'}, $result{'ownergid'}) = 
            (stat $result{'pgdata'})[4,5];
    }

    # autovacuum settings

    if (get_program_path 'pg_autovacuum', $_[0]) {
	$enableval = get_conf_value ($_[0], $_[1], 'autovacuum.conf', 'start');
	$enableval ||= 'no';
	$result{'avac_enable'} = ($enableval eq 'yes');
	$result{'avac_log'} = readlink ($result{'configdir'} . "/autovacuum_log");
	$result{'avac_sleep_base'} = get_conf_value ($_[0], $_[1], 'autovacuum.conf', 'sleep_base_value');
	$result{'avac_sleep_scale'} = get_conf_value ($_[0], $_[1], 'autovacuum.conf', 'sleep_scaling_factor');
	$result{'avac_vac_base'} = get_conf_value ($_[0], $_[1], 'autovacuum.conf', 'vacuum_base_thresold');
	$result{'avac_vac_scale'} = get_conf_value ($_[0], $_[1], 'autovacuum.conf', 'vacuum_scaling_factor');
	$result{'avac_anal_base'} = get_conf_value ($_[0], $_[1], 'autovacuum.conf', 'analyze_base_threshold');
	$result{'avac_anal_scale'} = get_conf_value ($_[0], $_[1], 'autovacuum.conf', 'analyze_scaling_factor');
    }
    
    return %result;
}

# Return an array of all available PostgreSQL versions
sub get_versions {
    my @versions = ();
    if (opendir (D, $binroot)) {
        while (defined ($f = readdir D)) {
            push @versions, $f if get_program_path ('psql', $f);
        }
        closedir D;
    }
    return @versions;
}

# Return the newest available version
sub get_newest_version {
    $newest = 0;
    map { $newest = $_ if $newest < $_ } get_versions;
    return $newest;
}

# Return an array of all available clusters of given version
# Arguments: <version>
sub get_version_clusters {
    my $vdir = $confroot.'/'.$_[0].'/';
    my @clusters = ();
    if (opendir (D, $vdir)) {
        while (defined ($f = readdir D)) {
            if (-l $vdir.$f.'/pgdata' && -r $vdir.$f.'/postgresql.conf') {
                push @clusters, $f;
            }
        }
        closedir D;
    }
    return @clusters;
}

# Check if a cluster exists.
# Arguments: <version> <cluster>
sub cluster_exists {
    for $c (get_version_clusters $_[0]) {
	return 1 if $c eq $_[1];
    }
    return 0;
}

# Return the next free PostgreSQL port.
sub next_free_port {
    # create list of already used ports
    for $v (get_versions) {
	for $c (get_version_clusters $v) {
	    $p = (get_conf_value $v, $c, 'postgresql.conf', 'port') || $defaultport;
	    push @ports, $p;
	}
    }

    for ($port = $defaultport; ; ++$port) {
	last unless grep { $_ == $port } @ports;
    }

    return $port;
}

# Return the major server version that belongs to the given port. Return undef
# if there is no cluster for this port.
# Arguments: <port>
sub port_version {
    for $v (get_versions) {
	for $c (get_version_clusters $v) {
	    $p = (get_conf_value $v, $c, 'postgresql.conf', 'port') || $defaultport;
	    return $v if $p == $_[0];
	}
    }

    return undef;
}

# Return the PostgreSQL version, cluster, and database to connect to. version
# is always set (defaulting to the version of the default port if no matching
# entry is found, or finally to the latest installed version if there are no
# clusters at all), cluster and database may be 'undef'. If only one cluster
# exists, and no matching entry is found in the map files, that cluster is
# returned.
sub user_cluster_map {
    my ($user, $pwd, $uid, $gid) = getpwuid $>;
    my $group = (getgrgid  $gid)[0];

    # check per-user configuration file
    $home = $ENV{"HOME"} || (getpwuid $>)[7];
    $homemapfile = $home . '/.postgresqlrc';
    if (open MAP, $homemapfile) {
	while (<MAP>) {
	    s/(.*?)#.*/$1/;
	    next if /^\s*$/;
	    ($v,$c,$db) = split;
	    if ($db) {
		close MAP;
		return ($v, $c, ($db eq "*") ? undef : $db);
	    } else {
		print  "Warning: ignoring invalid line $. in $homemapfile\n";
		next;
	    }
	}
	close MAP;
    }

    # check global map file
    if (! open MAP, $mapfile) {
        print "Warning: could not open $mapfile, connecting to default port\n";
        return (undef,undef,$user);
    }
    while (<MAP>) {
        s/(.*?)#.*/$1/;
        next if /^\s*$/;
        ($u,$g,$v,$c,$db) = split;
        if (!$db) {
            print  "Warning: ignoring invalid line $. in $mapfile\n";
            next;
        }
        if (($u eq "*" || $u eq $user) && ($g eq "*" || $g eq $group)) {
	    close MAP;
            return ($v,$c, ($db eq "*") ? undef : $db);
        }
    }
    close MAP;

    # if only one cluster exists, use that
    $count = 0;
    my ($last_version, $last_cluster);
    for $v (get_versions) {
	for $c (get_version_clusters $v) {
            $last_version = $v;
            $last_cluster = $c;
            ++$count;
	}
    }
    return ($last_version, $last_cluster, undef) if $count == 1;

    # return version of single cluster or latest version if there are no local
    # clusters
    return ((port_version $defaultport) || get_newest_version, undef, undef);
}

# Copy a file to a destination and setup permissions
# Arguments: <source file> <destination file or dir> <uid> <gid> <permissions>
sub install_file {
    ($source, $dest, $uid, $gid, $perm) = @_;
    
    if (system '/usr/bin/install', '-o', $uid, '-g', $gid, '-m', $perm, $source, $dest) {
	error "install_file: could not install $source to $dest";
    }
}

# Change effective and real user and group id. If the user id is member of the
# "shadow" group, then "shadow" will be in the set of effective groups. Exits
# with an error message if user/group ID cannot be changed.
# Arguments: <user id> <group id>
sub change_ugid {
    my ($uid, $gid) = @_;
    my $groups = $gid;
    $groups .= " $groups"; # first additional group

    # check whether owner is in the shadow group, and keep shadow privileges in
    # this case; this is a poor workaround for the lack of initgroups().
    my @shadowmembers = split /\s+/, ((getgrnam 'shadow')[3]);
    for my $m (@shadowmembers) {
	my $mid = getpwnam $m;
	if ($mid == $uid) {
	    $groups .= ' ' . (getgrnam 'shadow');
	    last;
	}
    }

    $( = $) = $groups;
    $< = $> = $uid;
    error 'Could not change user id' if $< != $uid;
    error 'Could not change group id' if $( != $gid;
}