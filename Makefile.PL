use ExtUtils::MakeMaker;

# Avoid the loading of a huge number of modules on clients.  When
# someone runs the script as client, it will get a problem with
# missing "CPAN::Checksums", which is not a problem.

my $role = $ENV{CPANSITE_ROLE};
unless(defined $role)
{   print "Set environment variable CPANSITE_ROLE to avoid this question.\n";
    $role = prompt "Running client or server?", 'client';
}

my @prereq =
 ( Test::More        => 0.82
 , Test::Pod         => 1.00
 , version           => 0.76
 );

push @prereq,
 ( 'CPAN::Checksums' => 0
 , 'Getopt::Long'    => 0
 , 'HTTP::Date'      => 0
 , 'Net::FTP'        => 0
 ) if $role =~ m/^s/i;

WriteMakefile
 ( NAME       => 'CPAN::Site'
 , ABSTRACT   => 'adding site local modules'
 , VERSION    => '0.24'

 , EXE_FILES  =>
    [ 'bin/mkpackages'
    , 'bin/cpansite'
    ]

 , AUTHOR     => 'Mark Overmeer'
 , PREREQ_PM  => { @prereq }
 , LICENSE    => 'perl'
 );

#### the next lines are added for OODoc, which generates the
#### distribution.
sub MY::postamble { <<'__POSTAMBLE' }

# for DIST
RAWDIR          = ../public_html/cpan-site/raw
DISTDIR         = ../public_html/cpan-site/source
LICENSE         = artistic

# for POD
FIRST_YEAR      = 1998,2005
EMAIL           = perl@overmeer.net
WEBSITE         = http://perl.overmeer.net/cpan-site/

# for HTML
#HTML_OUTPUT     = ../public_html/cpan-site/html
#HTML_DOCROOT    = /cpan-site/html

__POSTAMBLE
