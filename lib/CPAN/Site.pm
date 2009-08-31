# Copyrights 1998,2005-2009 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.06.

use warnings;
use strict;

package CPAN::Site;
use vars '$VERSION';
$VERSION = '0.26';

use base 'CPAN';

our $reload_orig;
our $config_loader;
BEGIN {
  $reload_orig = \&CPAN::Index::reload;
  eval "require CPAN::HandleConfig";
  $config_loader = $@ ? 'CPAN::Config' : 'CPAN::HandleConfig';
}

# Add "CPAN" to the list of exported items
sub import
{  my $class  = shift;
   unshift @_, 'CPAN';

   my $import = CPAN->can('import');
   goto &$import;
}

$config_loader->load
    if $config_loader->can('load');

if(my $urls = $ENV{CPANSITE})
{   unshift @{$CPAN::Config->{urllist}}, split ' ', $urls;
}

my $last_time = 0;

no warnings 'redefine';
sub CPAN::Index::reload {
   my($cl, $force) = @_;
   my $time = time;

   # Need this code duplication since reload does not return something
   # meaningful

   my $expire = $CPAN::Config->{index_expire};
   $expire = 0.001 if $expire < 0.001;

   return if $last_time + $expire*86400 > $time
          && !$force;

   $last_time = $time;

#  $reload_orig->(@_);

   $cl->rd_authindex($cl->reload_x("authors/01mailrc.txt.gz", '', $force));
   $cl->rd_modpacks($cl->reload_x("site/02packages.details.txt.gz",'',$force));
   $cl->rd_modlist($cl->reload_x("modules/03modlist.data.gz", '', $force));
}

1;

__END__

