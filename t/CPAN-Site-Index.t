#!/usr/bin/perl
use warnings;
use strict;

# CPAN-Site-Index.t - unit tests for CPAN::Site::Index
#-------------------------------------------------------------------------------
use strict;
use warnings;
use FindBin qw($Bin);
use Test::More tests => 47;

use_ok('CPAN::Site::Index')
    || BAIL_OUT('Failed to compiled module CPAN::Site::Index');

test_inspect_entry();

exit;

#-------------------------------------------------------------------------------

sub test_inspect_entry {

    # See  http://rt.cpan.org/Ticket/Display.html?id=39831

    # inspect_entry() relies upon a global variable $topdir which
    # we is declared with 'our' in Index.pm so we can set it here for testing.
    $CPAN::Site::Index::topdir = "$Bin/test_data";

    # inspect_entry is called in Index.pm using File::Find
    #   find { wanted => \&inspect_entry, no_chdir => 1 }, $topdir;
    # so we set two variables that File::Find normally sets:
    $File::Find::name = "$CPAN::Site::Index::topdir/Text-PDF-0.29a.tar.gz";
    $File::Find::dir  = $CPAN::Site::Index::topdir;
    note("Checking $File::Find::name in $File::Find::dir");

    CPAN::Site::Index::inspect_entry();
    my %want_packages = (
        'Text::PDF::Array'           => undef,
        'Text::PDF::Bool'            => undef,
        'Text::PDF::Dict'            => undef,
        'Text::PDF::File'            => '0.27',
        'Text::PDF::Filter'          => undef,
        'Text::PDF::ASCII85Decode'   => undef,
        'Text::PDF::RunLengthDecode' => undef,
        'Text::PDF::ASCIIHexDecode'  => undef,
        'Text::PDF::FlateDecode'     => undef,
        'Text::PDF::LZWDecode'       => undef,
        'Text::PDF::Name'            => undef,
        'Text::PDF::Null'            => undef,
        'Text::PDF::Number'          => undef,
        'Text::PDF::Objind'          => undef,
        'Text::PDF::Page'            => undef,
        'Text::PDF::Pages'           => undef,
        'Text::PDF::SFont'           => undef,
        'Text::PDF::String'          => undef,
        'Text::PDF::TTFont'          => undef,
        'Text::PDF::TTIOString'      => undef,
        'Text::PDF::TTFont0'         => undef,
        'Text::PDF::Utils'           => undef,
        'Text::PDF'                  => '0.29',
    );
    my @missing_pkgs = ();
    foreach my $want_pkg ( sort keys %want_packages ) {
        my $have_package = exists $CPAN::Site::Index::findpkgs->{$want_pkg};
        ok( $have_package, "Found package '$want_pkg' in tarball." )
            || push @missing_pkgs, $want_pkg;
    SKIP: {
            skip("Didn't find '$want_pkg', no point in testing VERSION", 1 )
                 unless $have_package;
            my $have_version = $CPAN::Site::Index::findpkgs->{$want_pkg}->[0];
            my $want_version = $want_packages{$want_pkg};
            is( $have_version, $want_version,
                "Got expected version of $want_pkg" );
        }
    }
    if(@missing_pkgs) {
        diag(
            "Missing packages: @missing_pkgs\n\n",
            'Packages found: ',
            explain($CPAN::Site::Index::findpkgs)
        );
    }

    #diag Test::More::explain($CPAN::Site::Index::findpkgs);
}
