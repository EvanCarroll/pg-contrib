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
	download_stopwords_to_utf8_cache
	scan_ispell
);

our @EXPORT_OK = qw(
	&scan_ispell
	&copy_to_utf8_cache
	&install_to_pg_share
	&cleanup_affix_dict
	&download_stopwords_to_utf8_cache
);


BEGIN {
	unless ( -x PG_CACHEDIR ) {
		File::Path::make_path(PG_CACHEDIR, {chmod=>0755, verbose=>1});
	}
}

sub install_to_pg_share {
	my $locale = $_[0];

	my @installed_files;

	foreach my $v (get_versions) {
		next if $v < '8.3';

		my $dest = File::Spec->catdir( PG_SHAREDIR, $v, 'tsearch_data' );
		if ( ! -d $dest ) {
			## WARNING THIS RETURNS PSQL VERSIONS NOT SERVER VERSIONS
			## warn "[$0] $dest unable to proceed with tsearch installation for $v\n";
			next;
		}
		else {
			say "\t$v: $locale->{locale}";
		}

		if ( $locale->{dict} && $locale->{affix} ) {
			my $file_pgdest_affix = File::Spec->catfile( $dest, "$locale->{locale}.affix" );
			my $file_pgdest_dict  = File::Spec->catfile( $dest, "$locale->{locale}.dict"  );

			## If they're not both links we don't symlink anything
			if (
				-e $file_pgdest_affix    && ! -l $file_pgdest_affix
				or -e $file_pgdest_dict  && ! -l $file_pgdest_dict
			) {
				warn "[$0] Skipping dict/affix install for $locale, user-modification detected\n";
			}
			else {

				## If either are links, we nuke them
				unlink $file_pgdest_affix if -e $file_pgdest_affix;
				unlink $file_pgdest_dict  if -e $file_pgdest_dict;

				## If the links don't exist, or were just nuked we install new links
				symlink $locale->{affix}, $file_pgdest_affix;
				symlink $locale->{dict},  $file_pgdest_dict;

				say "\t\t* affix/dict";
			
				push @installed_files,
					$locale->{affix},
					$locale->{dict},  
					$file_pgdest_dict,
					$file_pgdest_affix;

			}
		}

		if ( $locale->{stop} ) {
			my $file_pgdest_stop  = File::Spec->catfile( $dest, "$locale->{locale}.stop"  );

			if ( -e $file_pgdest_stop && ! -l $file_pgdest_stop ) {
				warn "[$0] Skipping stopword install for $locale, user-modification detected\n";
			}
			else {
				unlink $file_pgdest_stop if -e $file_pgdest_stop;
				symlink $locale->{stop}, $file_pgdest_stop;
				push @installed_files, $locale->{stop};
			}
			say "\t\t* stopwords";
		}

	}

	\@installed_files;

}

sub cleanup_affix_dict {
	my $files = $_[0];

	say "Removing obsolete dictionary files:";
	my $counter = 0;
	foreach my $f (
		glob (PG_CACHEDIR."/*.dict"),
		glob (PG_CACHEDIR."/*.affix")
	) {
		my $locale = File::Basename::fileparse($f, qw[.affix .dict]);
		next if $files->{$f};
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
		next if $files->{$f};
		$counter++;
		say "\t$f";
		unlink $f;
	}

	say "\t$counter removed.";
}
