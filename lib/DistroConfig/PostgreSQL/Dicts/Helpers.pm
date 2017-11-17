package DistroConfig::PostgreSQL::Dicts::Helpers;
use strict;
use warnings;
use autodie qw(:all);

use File::Basename ();

use Exporter 'import';

use constant {
	PG_CACHEDIR => '/var/cache/postgresql/dicts',
	PG_SHAREDIR => '/usr/share/postgresql'
};

our @EXPORT_OK = qw(
	PG_CACHEDIR
	PG_SHAREDIR
	&get_encoding_aff_file
	&encode_to_utf8
	&copy_to_utf8_cache
);

##
## These functions do *not* modify their arguments
## They may perform I/O
## None of them store state
## None of them print to the screen for success
##

sub copy_to_utf8_cache($) {
	my $locale = $_[0];

	my $enc = get_encoding_aff_file($locale->{aff});
	unless ( $enc ) {
		warn "[$0] Unable to find encoding in $locale->{aff}, skipping";
		return 0;
	}
	
	my $file_cache_affix = File::Spec->catfile(PG_CACHEDIR, "$locale->{locale}.affix");
	my $file_cache_dict  = File::Spec->catfile(PG_CACHEDIR, "$locale->{locale}.dict" );

	# convert to UTF-8 and write to cache dir
	my $opts = {chmod=>0644, encoding=>$enc};
	encode_to_utf8( $locale->{aff}, $file_cache_affix, $opts ) or next;
	encode_to_utf8( $locale->{dic}, $file_cache_dict,  $opts ) or next;

	return {
		affix => $file_cache_affix,
		dict  => $file_cache_dict
	};

}


# determine encoding of an .aff file
sub get_encoding_aff_file($) {
	my $file = $_[0];	
	open (my $fh, '<', $file);
	while (<$fh>) {
		if (/^SET ([\w-]+)\s*$/) { return $1; }
	}
	warn "[$0] No encoding defined in $file\n";
	return 0;
}

sub encode_to_utf8 {
	my ( $input_file, $output_file, $opts ) = @_;

	ref $opts eq 'HASH'
		or die "[$0] encode_to_utf8 requires a hashref opts argument";

	eval {
		use warnings FATAL => qw(utf8);
		open ( my $fh_input,  "<:encoding($opts->{encoding})",  $input_file );
		open ( my $fh_output, ">:encoding(utf-8)",              $output_file );
		print $fh_output $_ while <$fh_input>;
		close $fh_output;
		if ( $opts->{chmod} ) {
			chmod $opts->{chmod}, $output_file;
		}
	};
	if ($@) {
		warn "[$0] Conversion of $input_file failed\n\t$@\n";
		unlink $output_file;
		return 0;
	}
	return 1;
}

1;
