use ExtUtils::MakeMaker;

# Avoid the loading of a huge number of modules on clients.  When
# someone runs the script as client, it will get a problem with
# missing "CPAN::Checksums", which is not a problem.

my $role = $ENV{CPANSITE_ROLE};
unless(defined $role)
{   print "Set environment variable CPANSITE_ROLE to avoid this question.\n";
    prompt "Running client or server?", 'client';
}

my @prereq;
push @prereq,
 ( 'CPAN::Checksums' => 0
 , 'Getopt::Long'    => 0
 , 'HTTP::Date'      => 0
 , 'Net::FTP'        => 0
 ) if $role =~ m/^s/i;

WriteMakefile
 ( NAME       => 'CPAN::Site'
 , ABSTRACT   => 'adding site local modules'
 , VERSION    => '0.14'

 , EXE_FILES  =>
    [ 'bin/mkpackages'
    , 'bin/cpansite'
    ]

 , PREREQ_PM  => { @prereq }
 );

#### the next lines are added for OODoc, which generates the
#### distribution.
sub MY::postamble { <<'__POSTAMBLE' }

# for DIST
RAWDIR          = ../public_html/cpansite/raw
DISTDIR         = ../public_html/cpansite/source
LICENSE         = artistic

# for POD
FIRST_YEAR      = 1998,2005
EMAIL           = perl@overmeer.net
WEBSITE         = http://perl.overmeer.net/cpansite/

# for HTML
#HTML_OUTPUT     = ../public_html/cpansite/html
#HTML_DOCROOT    = /cpansite/html

__POSTAMBLE
