#                              -*- Mode: Perl -*- 
# $Basename: Makefile.PL $
# $Revision: 1.5 $
# Author          : Ulrich Pfeifer
# Created On      : Wed Jan  7 14:34:24 1998
# Last Modified By: Ulrich Pfeifer
# Last Modified On: Thu Jan  8 12:25:34 1998
# Language        : CPerl
# 
# (C) Copyright 1998, UUNET Deutschland GmbH, Germany
# 

use ExtUtils::MakeMaker;
use IO::File;

my $default_url = 'file:/tmp/CPAN/';

# Use old default url if CPAN::Site is installed already
eval { require CPAN::Site };
if ($@ eq '') {
  my $in  = new IO::File '<' . $INC{"CPAN/Site.pm"}
  or die "Reading $INC{'CPAN/Site.pm'}: $!\n";
  while (defined ($_ = $in->getline)) {
    $default_url = $1
      if /^unshift\b .* q\[(\w+:\S+)\]$/x
  }
}
print STDERR "URL to your private CPAN [$default_url] ";
if (my $url = <>) {
  for ($url) {s/^\s+//; s/\s+$//;}
  $url ||= $default_url;
  rename 'Site.pm', 'Site.pm~'
    or die "Could not rename 'Site.pm': $!\n";
  my $in  = new IO::File "<Site.pm~" or die "Reading Site.pm~: $!\n";
  my $out = new IO::File ">Site.pm"  or die "Writing Site.pm: $!\n";
  while (defined ($_ = $in->getline)) {
    s{q\[\w+:\S+\]}{q\[$url\]} if /^unshift\b/;
    $out->print($_);
  }
}

WriteMakefile
  (
   'NAME'	=> 'CPAN::Site',
   # $Format: "   'VERSION'    => sprintf('%5.3f', ($ProjectMajorVersion$ * 100 + ( $ProjectMinorVersion$-1))/1000),"$ 
   'VERSION'    => sprintf('%5.3f', (0 * 100 + ( 8-1))/1000),
   'dist'       => {
                    COMPRESS => 'gzip -9f',
                    PREOP    => 'pod2text Site.pm > README',
                   },
   'EXE_FILES'  => [ 'mkpackages' ],
  );
