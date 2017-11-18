package DistroConfig::PostgreSQL::Dicts::Helpers;
use strict;
use warnings;
use autodie qw(:all);

use File::Spec ();

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
	&download_stopwords_to_utf8_cache
	&scan_ispell
);

use LWP;
use URI;

##
## These functions do *not* modify their arguments
## They may perform I/O
## None of them store state
## None of them print to the screen for success
##

#
# We ut8ify here because we are stateful this is the overview of the valid
# locales for PostgreSQL -- can't uf8ify, you're not valid (for pg purposes)
#
sub scan_ispell() {
	my @ispell_locations = ('/usr/share/hunspell', '/usr/share/myspell/dicts');

	my @locales;
	for my $dir (@ispell_locations) {
		for my $file (glob "$dir/*.aff") {
			my $file_aff = $file;
			( my $file_dic = $file_aff ) =~ s/\.aff$/\.dic/;

			my ($locale) = lc( File::Basename::fileparse($file_aff, '.aff') );

			unless ( -f $file_dic ) {
				warn "[$0] $locale lacks a '.dict', user-modification detected. ignoring\n";
				next;
			}

			push @locales, {
				locale => $locale,
				affix  => $file_aff,
				dict   => $file_dic
			};
		}
	}
	return \@locales;
}

sub copy_to_utf8_cache($) {
	my $locale = $_[0];

	my $enc = get_encoding_aff_file($locale->{affix});
	unless ( $enc ) {
		warn "[$0] Unable to find encoding in '$locale->{affix}', skipping";
		return 0;
	}
	
	my $file_cache_affix = File::Spec->catfile(PG_CACHEDIR, "$locale->{locale}.affix");
	my $file_cache_dict  = File::Spec->catfile(PG_CACHEDIR, "$locale->{locale}.dict" );

	# convert to UTF-8 and write to cache dir
	my $opts = {chmod=>0644, encoding=>$enc};
	encode_to_utf8( $locale->{affix}, $file_cache_affix, $opts ) or next;
	encode_to_utf8( $locale->{dict},  $file_cache_dict,  $opts ) or next;

	return {
		locale=> $locale->{locale},
		affix => $file_cache_affix,
		dict  => $file_cache_dict
	};

}

sub download_stopwords_to_utf8_cache($) {
	my $locale = $_[0];

	$locale->{locale} =~ /^([^_]*)/;
	my $lang = $1;

	my $file_cache_stop = File::Spec->catfile(PG_CACHEDIR, "$locale->{locale}.stop");

	my $ua = LWP::UserAgent->new();
	my $resp = $ua->mirror(
		URI->new(
			"https://raw.githubusercontent.com/stopwords-iso/stopwords-$lang/master/stopwords-$lang.txt"
		),
		$file_cache_stop
	);
	chmod 0644, $file_cache_stop;

	return $resp->is_success ? $file_cache_stop : 0;

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
