package DistroConfig::PostgreSQL::Dicts;
use feature ':5.24';
use strict;
use warnings;
use autodie qw(:all);

use PgCommon qw(get_versions);

use File::Basename ();
use File::Spec     ();

use Exporter 'import';

use DistroConfig::PostgreSQL::Dicts::Helpers qw(
	PG_CACHEDIR
	PG_SHAREDIR
	copy_to_utf8_cache
);

our @EXPORT_OK = qw(
	&scan_and_ut8ify_ispell
	&install_to_pg_share
	&cleanup
);


BEGIN {
	unless ( -x PG_CACHEDIR ) {
		File::Path::make_path(PG_CACHEDIR, {chmod=>0755, verbose=>1});
	}
}

#
# We ut8ify here because we are stateful this is the overview of the valid
# locales for PostgreSQL -- can't uf8ify, you're not valid (for pg purposes)
#
sub scan_and_ut8ify_ispell() {
	my @ispell_locations = ('/usr/share/hunspell', '/usr/share/myspell/dicts');

	state %locales;
	unless ( %locales ) {
	
		say "Building PostgreSQL dictionaries from installed myspell/hunspell packages...";
		for my $dir (@ispell_locations) {
			for my $file (glob "$dir/*.aff") {
				my $file_aff = $file;
				( my $file_dic = $file_aff ) =~ s/\.aff$/\.dic/;

				my ($locale) = lc( File::Basename::fileparse($file_aff, '.aff') );

				unless ( -f $file_dic ) {
					warn "[$0] $locale lacks a '.dict', user-modification detected. ignoring\n";
					next;
				}

				$locales{$locale} = {
					aff    => $file_aff,
					dic    => $file_dic,
					locale => $locale
				};

				## We put this here, because if we can't utf8ify
				## we want to cleanup the files, and not show it
				## as a valid locale
				my $utf8cache = copy_to_utf8_cache( $locales{$locale} );
				next unless $utf8cache;
				say "\t$locale";
				$locales{$locale}{utf8} = $utf8cache;
			}
		}
	}
	
	return \%locales;

}

sub install_to_pg_share() {
	my $locales = scan_and_ut8ify_ispell;

	say "Installing PostgreSQL dictionaries:";
	foreach my $v (get_versions) {
		next if $v < '8.3';

		foreach my $locale ( values %$locales ) {

			my $dest = File::Spec->catdir( PG_SHAREDIR, $v, 'tsearch_data' );
			if ( ! -d $dest ) {
				## WARNING THIS RETURNS PSQL VERSIONS NOT SERVER VERSIONS
				## warn "[$0] $dest unable to proceed with tsearch installation for $v\n";
				next;
			}

			my $file_pgdest_affix = File::Spec->catfile( $dest, "$locale->{locale}.affix" );
			my $file_pgdest_dict  = File::Spec->catfile( $dest, "$locale->{locale}.dict"  );

			## If they're not both links we don't symlink anything
			if (
				-e $file_pgdest_affix    && ! -l $file_pgdest_affix
				or -e $file_pgdest_dict  && ! -l $file_pgdest_dict
			) {
				warn "[$0] Skipping install for $locale, user-modification detected\n";
				next;
			}

			## If either are links, we nuke them
			unlink $file_pgdest_affix if -e $file_pgdest_affix;
			unlink $file_pgdest_dict  if -e $file_pgdest_dict;

			## If the links don't exist, or were just nuked we install new links
			symlink $locale->{utf8}{affix}, $file_pgdest_affix;
			symlink $locale->{utf8}{dict},  $file_pgdest_dict;

			say "\t$v: $locale->{locale}";

		}
	}

	1;

}

sub cleanup() {
	my $locales = scan_and_ut8ify_ispell;

	say "Removing obsolete dictionary files:";
	my $counter = 0;
	foreach my $f ( glob (PG_CACHEDIR."/*") ) {
		my $locale = File::Basename::fileparse($f, qw[.affix .dict]);
		next if $locales->{$locale};
		$counter++;
		say "\t$f";
		unlink $f;
	}
	foreach my $f (
		glob(PG_SHAREDIR."/*/tsearch_data/*.affix"),
		glob(PG_SHAREDIR."/*/tsearch_data/*.dict")
	) {
		next unless -l $f;
	
		my $locale = File::Basename::fileparse($f, qw[.affix .dict]);
		next if $locales->{$locale};
		$counter++;
		say "\t$f";
		unlink $f;
	}

	say "\t$counter removed.";
}
