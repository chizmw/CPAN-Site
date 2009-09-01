use ExtUtils::MakeMaker;

# Avoid the loading of a huge number of modules on clients.  When
# someone runs the script as client, it will get a problem with
# missing "CPAN::Checksums", which is not a problem.

my $role = $ENV{CPANSITE_ROLE};
unless(defined $role)
{   print "Set environment variable CPANSITE_ROLE to avoid this question.\n";
    my $a = prompt "Running client or server?", 'client';
    $role = $a =~ m/^s/i ? 'server' : 'client';
}

# Client and server requirements
my @prereq =
 ( Test::More         => 0.82
 , Test::Pod          => 1.00
 , version            => 0.76
 , HTTP::Date         => 0
 );

# Server requirements only
push @prereq,
 ( CPAN::Checksums    => 0
 , Getopt::Long       => 0
 , LWP                => 0
 , Log::Report        => 0.27
 , Archive::Tar       => 1.00
 , IO::Compress::Gzip => 2.00
 ) if $role eq 'server';

WriteMakefile
 ( NAME       => 'CPAN::Site'
 , ABSTRACT   => 'adding site local modules'
 , VERSION    => '1.00'

 , EXE_FILES  => [ 'bin/cpansite' ]

 , AUTHOR     => 'Mark Overmeer'
 , PREREQ_PM  => { @prereq }
 , LICENSE    => 'perl'

 );

#### the next lines are added for OODoc, which generates the
#### distribution.
sub MY::postamble { <<__POSTAMBLE }

# for DIST
RAWDIR          = ../public_html/cpan-site/raw
DISTDIR         = ../public_html/cpan-site/source
LICENSE         = artistic

# for POD
FIRST_YEAR      = 1998,2005
EMAIL           = perl\@overmeer.net
WEBSITE         = http://perl.overmeer.net/cpan-site/

# for HTML
#HTML_OUTPUT	= ../public_html/cpan-site/html
#HTML_DOCROOT	= /cpan-site/html

# We overrule the *PERL to set an extra environment variable
CPANSITE_ROLE	= $role
ABSPERL		= CPANSITE_ROLE=$role \$(PERL)
FULLPERL	= CPANSITE_ROLE=$role \$(PERL)
__POSTAMBLE
