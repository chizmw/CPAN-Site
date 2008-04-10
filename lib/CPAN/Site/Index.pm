# Copyrights 1998,2005-2008 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.04.

use warnings;
use strict;

package CPAN::Site::Index;
use vars '$VERSION';
$VERSION = '0.20';
use base 'Exporter';
our @EXPORT_OK = qw/cpan_index/;
our $VERSION;  # required in test-env

use version;
use IO::File        ();
use File::Find      qw/find/;
use File::Copy      qw/copy move/;
use File::Basename  qw/basename dirname/;
use Net::FTP        ();
use HTTP::Date      qw/time2str/;
use File::Spec      ();

my $tar_gz      = qr/ \.tar \.(gz|Z) $/x;
my $gzip_read   = 'gzip -cd';
my $gzip_write  = 'gzip';
my $cpan_update = 1.0; #days between reload of full CPAN index

my $verbose;
my $debug;

sub package_inventory($$);
sub create_details($$$$);
sub calculate_checksums($);
sub collect_dists($$@);
sub merge_core_cpan($$$);
sub update_core_cpan($@);
sub mkdirhier(@);

sub cpan_index($@)
{   my ($mycpan, %opts) = @_;
    $verbose     = $opts{verbose};
    $debug       = $opts{debug};

    my $bigcpan_url     = $opts{bigcpan_url};
    my $merge_with_core = length $bigcpan_url;
    my $lazy            = $opts{lazy};

    -d $mycpan
        or die "ERROR: archive top '$mycpan' is not a directory\n";

    mkdirhier "$mycpan/site";

    my $program     = basename $0;
    $VERSION      ||= 'undef';   # test env at home
    print "$program version $VERSION\n" if $verbose;

    my $details    = "$mycpan/site/02packages.details.txt.gz";
    my $newlist    = "$mycpan/site/02packages.details.tmp.gz";

    # Create packages.details

    my $reuse_dists = {};
    $reuse_dists    = collect_dists $details, $mycpan, local => 1
       if $lazy;

    my ($mypkgs, $distdirs) = package_inventory $mycpan, $reuse_dists;

    merge_core_cpan($mycpan, $mypkgs, $bigcpan_url)
       if $merge_with_core;

    create_details $details, $newlist, $mypkgs, $lazy;

    # Install packages.details

    if(-f $details)
    {   print "backup old details to $details.bak\n" if $verbose;
        copy $details, "$details.bak"
           or die "ERROR: cannot rename '$details' in '$details.bak': $!\n";
    }

    if(-f $newlist)
    {   print "promoting $newlist to current.\n" if $verbose;
        rename $newlist, $details
           or die "ERROR: cannot rename '$newlist' in '$details': $!\n";
    }

    # Calculate checksums

    print "updating checksums\n" if $verbose;
    calculate_checksums $distdirs;
}

#
# Package Inventory
#

# find requires global variables (sorry)
my ($topdir, $findpkgs, %finddirs, $olddists);

sub package_inventory($$)
{  (my $cpan, $olddists) = @_;
   $topdir   = "$cpan/authors/id";
   mkdirhier $topdir;

   $findpkgs = {};

   print "creating inventory from $topdir\n" if $verbose;

   find {wanted => \&inspect_entry, no_chdir => 1}, $topdir;
   ($findpkgs, \%finddirs);
}

sub register($$$)
{  my ($package, $version, $dist) = @_;
   print "reg(@_)\n" if $debug;

   my $registered_version = $findpkgs->{$package}[0] || '0';
   return if exists $findpkgs->{$package}
          && qv($registered_version) > qv($version);

   $version =~ s/^v//;
   $findpkgs->{$package} = [ $version, $dist ];
}

sub package_on_usual_location($)
{  my $file  = shift;
   my ($top, $subdir, @rest) = File::Spec->splitdir($file);
   defined $subdir or return 0;

      !@rest             # path is at top-level of distro
   || $subdir eq 'lib';  # inside lib
}

sub inspect_entry
{  my $fn   = $File::Find::name;
   return if ! -f $fn || $fn !~ $tar_gz;

   print "inspecting $fn\n" if $debug;

   (my $dist = $fn) =~ s!^$topdir/!!;

   if(exists $olddists->{$dist})
   {  print "no change in $dist\n" if $debug;

      foreach (@{$olddists->{$dist}})
      {   my ($pkg, $version) = @$_;
          register $pkg, $version, $dist;
      }
      return;
   }

   $finddirs{$File::Find::dir}++;

   (my $readme_file = basename $fn) =~ s!$tar_gz!/README!;

   my $fh = IO::File->new("$gzip_read '$fn' |")
       or die "ERROR: failed to read distribution file $fn': $!\n";

   my ($file, $package, $version);
   my $in_buf       = '';
   my $out_buf      = '';
   my $tarball_name = basename $dist;
   my $dist_name    = $tarball_name =~ /(.*)\.tar\.gz/ ? $1 : undef;
   my $readme_fh;

BLOCK:
   while($fh->sysread($in_buf, 512))
   {
      if($in_buf =~ /^(\S*?)\0/)
      {
          $file = $1;
          substr($file, 0, length $dist_name) eq $dist_name
              or next BLOCK;

# when the package contains non-text files, this produces garbage
#         print "file=$file\n" if $debug && length $file;

          if($file eq $readme_file)
          {  print "found README in $readme_file\n" if $debug;

#            my $outputfn = File::Spec->catfile($File::Find::dir,$readme_file);
#            $outputfn =~ s/\bREADME$/\.readme/;

             my $readmefn = $dist_name. ".readme";
             my $outputfn = File::Spec->catfile($File::Find::dir, $readmefn);
             print "README full path '$outputfn'\n" if $debug;

             $readme_fh = IO::File->new($outputfn, 'w')
                 or die "Could not write to README file $outputfn: $!";

             warn "Creating README file: $outputfn\n" if $debug;
          }
          else
          {  undef $readme_fh;
          }

         undef $package;
         undef $version;
         $out_buf = '';
         next BLOCK;
      }

      $readme_fh->print(substr $in_buf, 0, index($in_buf, "\0"))
         if $readme_fh;

      $out_buf .= $in_buf;
      while($out_buf =~ s/^([^\n]*)\n//)
      {
         local $_ = $1;
         local $VERSION;  # destroyed by eval

         if( m/^\s* package \s* ((\w+\:\:)*\w+) \s* ;/x )
         {  $package = $1;
            print "package=$package\n" if $debug;
            next;
         }

         if( m/^ (?:use\s+version\s*;\s*)?
                 (?:our)? \s* \$ (?: \w+\:\:)* VERSION \s* \= \s* (.*)/x )
         {  $version = eval "my \$v = $1";
            $version = $version->numify if ref $version;
            print "version=$version\n"  if $debug;

            register $package, $version, $dist
                if $file && $package && $file =~ m/\.pm$/
                && package_on_usual_location $file;
         }
      }
   }
}

sub merge_core_cpan($$$)
{   my ($cpan, $pkgs, $bigcpan_url) = @_;

    print "merging packages with CPAN core list\n"
       if $verbose;

    my $mailrc     = "$cpan/authors/01mailrc.txt.gz";
    my $bigdetails = "$cpan/modules/02packages.details.txt.gz";
    my $modlist    = "$cpan/modules/03modlist.data.gz";

    mkdirhier "$cpan/authors", "$cpan/modules";

    update_core_cpan $bigcpan_url, $bigdetails, $modlist, $mailrc
        if ! -f $bigdetails || -M $bigdetails > $cpan_update;

    -f $bigdetails or return;

    my $cpan_pkgs = collect_dists $bigdetails, "$cpan/modules", local => 0;

    while(my ($cpandist, $cpanpkgs) = each %$cpan_pkgs)
    {   foreach (@$cpanpkgs)
        {  my ($pkg, $version) = @$_;
           next if exists $pkgs->{$pkg};
           $pkgs->{$pkg} = [$version, $cpandist];
        }
    }
}

sub create_details($$$$)
{  my ($details, $filename, $pkgs, $lazy) = @_;

   print "creating package details file '$filename'\n" if $debug;
   my $fh = IO::File->new("| $gzip_write >$filename")
      or die "Generating $filename: $!\n";

   my $lines = keys %$pkgs;
   my $date  = time2str time;
   my $how   = $lazy ? "lazy" : "full";

   print "produced list of $lines packages $how\n" if $verbose;

   my $program     = basename $0;
   my $module      = __PACKAGE__;
   $fh->print (<<__HEADER);
File:         02packages.details.txt
URL:          file://$details
Description:  Packages listed in CPAN and local repository
Columns:      package name, version, path
Intended-For: Standard CPAN with additional private resources
Line-Count:   $lines
Written-By:   $program with $module $CPAN::Site::Index::VERSION ($how)
Last-Updated: $date

__HEADER

   foreach my $pkg (sort keys %$pkgs)
   {  my ($version, $path) = @{$pkgs->{$pkg}};
      $version    = 'undef' if !defined $version || $version eq '';
      $fh->printf("%-30s\t%s\t%s\n", $pkg,  $version, $path);
   }
}

sub calculate_checksums($)
{   my $dirs = shift;
    eval "require CPAN::Checksums";
    die "ERROR: please install CPAN::Checksums\n" if $@;

    foreach my $dir (keys %$dirs)
    {   print "summing $dir\n" if $debug;
        CPAN::Checksums::updatedir($dir)
            or warn "WARNING: failed calculating checksums in $dir\n";
    }
}

sub collect_dists($$@)
{   my ($fn, $base, %opts) = @_;
    my $check = $opts{local} || 0;

    print "collecting details from $fn".($opts{local} ? ' (local)' : '')."\n"
        if $verbose;

    -f $fn or return {};

    my $fh    = IO::File->new("$gzip_read $fn |")
       or die "ERROR: cannot read from $fn: $!\n";

    while(my $line = $fh->getline)   # search first blank
    {  last if $line =~ m/^\s*$/;
    }

    my $time_last_update = (stat $fn)[9];
    my %olddists;
    my $authors = "$base/authors/id";

  PACKAGE:
    while(my $line = $fh->getline)
    {   my ($oldpkg, $version, $dist) = split " ", $line;

        if($check)
        {   unless( -f "$authors/$dist" )
            {   print "removed $dist, so ignore $oldpkg\n" if $debug;
                next PACKAGE;
            }

            if((stat "$authors/$dist")[9] > $time_last_update )
            {   print "newer $dist, so ignore $oldpkg\n" if $debug;
                next PACKAGE;
            }
        }

        warn "Error line=$line", next unless $dist;
        push @{$olddists{$dist}}, [ $oldpkg, $version ];
    }

    \%olddists;
}

sub update_core_cpan($@)
{  my ($archive, @files) = @_;

   if($archive !~ m[^ftp://([^/]+)(/.*)])
   {   warn "WARNING: illegal ftp address for CPAN: $archive\n";
       return;
   }
   my ($host, $path) = ($1, $2);

   my $ftp = Net::FTP->new($host, Debug => 0);
   unless($ftp)
   {  warn "WARNING: cannot connect to $host: $@";
      return;
   }

   unless($ftp->login("anonymous",'-anonymous@'))
   {  warn "WARNING: cannot login on $host: ", $ftp->message;
      return;
   }

   unless($ftp->cwd($path))
   {  warn "WARNING: directory $path on $host: ", $ftp->message;
      return;
   }

   $ftp->binary;

   foreach my $destfile (@files)
   {   print "getting update of $destfile from $archive\n" if $verbose;

       my $fn    = basename $destfile;
       my $group = basename dirname $destfile;

       unless($ftp->get("$group/$fn", $destfile))
       {   my $full = "ftp://$host$path/$group/$fn";
           warn "WARNING: get of $full failed ", $ftp->message;
           return;
       }
   }

   $ftp->close;
}

sub mkdirhier(@)
{   foreach my $dir (@_)
    {   next if -d $dir;
        mkdirhier(dirname $dir);

        mkdir $dir, 0755
            or die "ERROR: cannot create directory $dir: $!";

        print "created $dir\n" if $verbose;
    }
    1;
}

1;
