#                              -*- Mode: Perl -*- 
# $Basename: Site.pm $
# $Revision: 1.10 $
# Author          : Ulrich Pfeifer
# Created On      : Wed Jan  7 11:42:46 1998
# Last Modified By: Ulrich Pfeifer
# Last Modified On: Wed May  6 13:30:41 1998
# Language        : CPerl
# Update Count    : 13
# Status          : Unknown, Use with caution!
# 
# (C) Copyright 1998, Ulrich Pfeifer, all rights reserved.
# 
# 

package CPAN::Site;
use CPAN;
use vars qw($VERSION @ISA);
@ISA = qw(CPAN);

# $Format: "$VERSION = sprintf '%5.3f', ($ProjectMajorVersion$ * 100 + ($ProjectMinorVersion$-1))/1000;"$
$VERSION = sprintf '%5.3f', (0 * 100 + (14-1))/1000;

# This line is edited by Makefile.PL. Don't change formatting etc.
unshift @{$CPAN::Config->{urllist}}, q[http://www.forbar.com/CPAN/]
  if $CPAN::Config->{urllist};

my $reload_orig;

BEGIN {
  $reload_orig = \&CPAN::Index::reload;
}

sub import {
  my $pkg = shift;
  my $import = CPAN->can('import');
  @_ = qw(CPAN), @_;
  goto &$import
}

my $last_time = 0;

sub CPAN::Index::reload {
   my($cl,$force) = @_;
   my $time = time;

   # Need this code duplication since reload does nor return something
   # meaningful

   for ($CPAN::Config->{index_expire}) {
     $_ = 0.001 unless $_ > 0.001;
   }
   return if $last_time + $CPAN::Config->{index_expire}*86400 > $time
     and ! $force;

   $last_time = $time;

   my $needshort = $^O eq "dos";

   $reload_orig->(@_);

   $cl->rd_modpacks($cl->reload_x(
                                  "site/02packages.details.txt.gz",
                                  $needshort ? "12packag.gz" : "",
                                  $force));
   $cl->rd_authindex($cl->reload_x(
                                   "site/01mailrc.txt.gz",
                                   $needshort ? "11mailrc.gz" : "",
                                   $force));
   # CPAN Master overwrites?
   $reload_orig->(@_);

 }

1;

__END__

=head1 NAME

CPAN::Site - CPAN.pm subclass for adding site local modules

=head1 SYNOPSIS

  perl -MCPAN::Site -e shell

=head1 WARNING

This is not even alpha software and will be made obsolete by CPAN.pm
extensions/plugins some day.

=head1 DESCRIPTION

This module virtually adds site specific modules to CPAN. The general
idea is to have a local (pseudo) CPAN server which is asked first. If
the request fails - which is the usual case, CPAN.pm switches to the
next URL in the list pointing to a real CPAN server. The pseudo CPAN
server must serve the files F<site/02packages.details.txt.gz> and
F<site/01mailrc.txt.gz> which contain the site local extensions to
CPAN.  You must make sure that the pseudo server can satisfy the
request for these files since a failure will result in CPAN.pm trying
to fetch the F<site/>* files from all the real CPAN servers in your
C<urllist>.

The included B<mkpackages> script can be used to generate the local
F<02packages.details.txt> file. The script does scan the distribution
files for package names an version numbers. Note that lines looking
like VERSION specifications are evaluated!

The F<Makefile.PL> will ask you for the URL of your pseudo CPAN
server.  This URL added to the front of the B<urllist> of the CPAN.pm
configuration when using this module. Note that rereading the
configuraion from the CPAN.pm shell will cause this URL to be
dropped. You must add it again using

C<cpan>E<gt>C< o conf urllist unshift >I<your-URL-here>

in this case.

To use the module, generate your pseudo CPAN on a anonymous FTP, HTTP
or NFS server:

  mkdirhier ~wwwdata/htdocs/CPAN
  mkpackages ~wwwdata/htdocs/CPAN
  
Then use C<-MCPAN::Site> instead of C<-MCPAN>

  perl -MCPAN::Site -e shell

=head1 Adding modules

  mkdirhier ~wwwdata/htdocs/CPAN/authors/id/ULPFR
  mv /tmp/Telekom-0.101.tar.gz ~wwwdata/htdocs/CPAN/authors/id/ULPFR
  mkpackages ~wwwdata/htdocs/CPAN

=head1 AUTHOR

Ulrich Pfeifer E<lt>F<pfeifer@wait.de>E<gt>

=cut
