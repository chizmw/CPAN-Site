# Copyrights 1998,2005-2009 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.06.

use warnings;
use strict;

package CPAN::Site::Index;
use vars '$VERSION';
$VERSION = '1.00';

use base 'Exporter';

our @EXPORT_OK = qw/cpan_index/;
our $VERSION;  # required in test-env

use Log::Report     'cpan-site', syntax => 'SHORT';

use version;
use IO::File        ();
use File::Find      qw/find/;
use File::Copy      qw/copy move/;
use File::Basename  qw/basename dirname/;
use HTTP::Date      qw/time2str/;
use File::Spec::Functions qw/catfile catdir splitdir/;
use LWP::UserAgent  ();
use Archive::Tar    ();
use CPAN::Checksums ();

use IO::Compress::Gzip     qw/$GzipError/;
use IO::Uncompress::Gunzip qw/$GunzipError/;

my $tar_gz      = qr/ \.tar \.(gz|Z) $/x;
my $cpan_update = 1.0; #days between reload of full CPAN index

my $ua;

sub package_inventory($$);
sub create_details($$$$);
sub calculate_checksums($);
sub collect_dists($$@);
sub merge_core_cpan($$$);
sub update_core_cpan($@);
sub mkdirhier(@);

sub cpan_index($@)
{   my ($mycpan, $bigcpan_url, %opts) = @_;
    my $merge_with_core = length $bigcpan_url;
    my $lazy            = $opts{lazy};

    if(my $mode = $opts{mode})
    {   dispatcher mode => $mode, 'ALL';
    }

    -d $mycpan
        or error __x"archive top '{dir}' is not a directory"
             , dir => $mycpan;

    my $program     = basename $0;
    $VERSION      ||= 'undef';   # test env at home
    trace "$program version $VERSION";

    my $top         = catdir $mycpan, 'site';
    my $details     = catfile $top, '02packages.details.txt.gz';
    my $newlist     = catfile $top, '02packages.details.tmp.gz';
    mkdirhier $top;

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
    {   trace "backup old details file to $details.bak";
        copy $details, "$details.bak"
            or error __x"cannot rename '{from}' in '{to}'"
                 , from => $details, to => "$details.bak";
    }

    if(-f $newlist)
    {   trace "promoting $newlist to current";
        rename $newlist, $details
            or error __x"cannot rename '{from}' in '{to}'"
                 , from => $newlist, to => $details;
    }

    calculate_checksums $distdirs;
}

#
# Package Inventory
#

# global variables for testing purposes (sorry)
our ($topdir, $findpkgs, %finddirs, $olddists);

sub package_inventory($$)
{  (my $cpan, $olddists) = @_;
   $topdir   = catdir $cpan, 'authors', 'id';
   mkdirhier $topdir;

   $findpkgs = {};
   trace "creating inventory from $topdir";

   find {wanted => \&inspect_entry, no_chdir => 1}, $topdir;
   ($findpkgs, \%finddirs);
}

sub register($$$)
{  my ($package, $this_version, $dist) = @_;
   trace "register $package, "
       . (defined $this_version ? $this_version : 'undef');

   my $registered_version = $findpkgs->{$package}[0];
   return if defined $registered_version
          && defined $this_version
          && qv($registered_version) > qv($this_version);

   $this_version =~ s/^v// if defined $this_version;
   $findpkgs->{$package} = [ $this_version, $dist ];
}

sub package_on_usual_location($)
{  my $file  = shift;
   my ($top, $subdir, @rest) = splitdir $file;
   defined $subdir or return 0;

      !@rest             # path is at top-level of distro
   || $subdir eq 'lib';  # inside lib
}

sub inspect_entry
{   my $fn   = $File::Find::name;
    -f $fn && $fn =~ $tar_gz
        or return;

    trace "inspecting $fn";

    (my $dist = $fn) =~ s!^$topdir[\\/]!!;

    if(exists $olddists->{$dist})
    {   trace "no change in $dist";

        foreach (@{$olddists->{$dist}})
        {  my ($pkg, $version) = @$_;
           register $pkg, $version, $dist;
        }
        return;
    }

    $finddirs{$File::Find::dir}++;

    my $arch =  Archive::Tar->new;
    $arch->read($fn, 1)
        or error __x"no files in archive '{fn}': {err}"
             , fn => $fn, err => $arch->error;

    foreach my $file ($arch->get_files)
    {   my $fn = $file->name;
        $file->is_file && $fn =~ m/\.pm$/i && package_on_usual_location $fn
            or next;

        my @lines  = split /\r?\n/, ${$file->get_content_by_ref};
        my $in_pod = 0;
        my ($package, $version);
        foreach (@lines)
        {   last if m/^__(?:END|DATA)__$/;

            $in_pod = ($1 ne 'cut') if m/^=(\w+)/;
            next if $in_pod;

            if( m/^\s* package \s* ((?:\w+\:\:)*\w+) \s* ;/x )
            {   # version may be added later
                $package = $1;
                trace "package=$package";
                register $package, undef, $dist;
                next;
            }

            if( m/^ (?:use\s+version\s*;\s*)?
                (?:our)? \s* \$ (?: \w+\:\:)* VERSION \s* \= \s* (.*)/x )
            {   defined $1 or next;
                local $VERSION;  # destroyed by eval
                $version = eval "my \$v = $1";
                $version = $version->numify if ref $version;

                trace "version=$version";
                register $package, $version, $dist;
            }
        }
    }
}

sub merge_core_cpan($$$)
{   my ($cpan, $pkgs, $bigcpan_url) = @_;

    info "merging packages with CPAN core list";

    my $mailrc     = "$cpan/authors/01mailrc.txt.gz";
    my $bigdetails = "$cpan/modules/02packages.details.txt.gz";
    my $modlist    = "$cpan/modules/03modlist.data.gz";

    mkdirhier "$cpan/authors", "$cpan/modules";

    update_core_cpan $bigcpan_url, $bigdetails, $modlist, $mailrc
        if ! -f $bigdetails || -M $bigdetails > $cpan_update;

    -f $bigdetails
        or return;

    my $cpan_pkgs = collect_dists $bigdetails, "$cpan/modules"
      , local => 0;

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

   trace "creating package details file '$filename'";
   my $fh = IO::Compress::Gzip->new($filename)
      or error __x"generating gzipped '{fn}': {err}"
          , fn => $filename, err => $GzipError;

   my $lines = keys %$pkgs;
   my $date  = time2str time;
   my $how   = $lazy ? "lazy" : "full";

   info "produced list of $lines packages $how\n";

   my $program     = basename $0;
   my $module      = __PACKAGE__;
   $fh->print (<<__HEADER);
File:         02packages.details.txt
URL:          file://$details
Description:  Packages listed in CPAN and local repository
Columns:      package name, version, path
Intended-For: private CPAN
Line-Count:   $lines
Written-By:   $program with $module $CPAN::Site::Index::VERSION ($how)
Last-Updated: $date

__HEADER

   foreach my $pkg (sort keys %$pkgs)
   {  my ($version, $path) = @{$pkgs->{$pkg}};
      $version = 'undef' if !defined $version || $version eq '';
      $path    =~ s,\\,/,g;
      $fh->printf("%-30s\t%s\t%s\n", $pkg, $version, $path);
   }
}

sub calculate_checksums($)
{   my $dirs = shift;
    trace "updating checksums";

    foreach my $dir (keys %$dirs)
    {   trace "summing $dir";
        CPAN::Checksums::updatedir($dir)
            or warning 'failed calculating checksums in {dir}', dir => $dir;
    }
}

sub collect_dists($$@)
{   my ($fn, $base, %opts) = @_;
    my $check = $opts{local} || 0;

    info "collecting details from $fn".($opts{local} ? ' (local)' : '');

    -f $fn or return {};

    my $fh    = IO::Uncompress::Gunzip->new($fn)
       or error __x"cannot read from '{fn}': {err}"
           , fn => $fn, err => $GunzipError;

    while(my $line = $fh->getline)   # skip header, search first blank
    {  last if $line =~ m/^\s*$/;
    }

    my $time_last_update = (stat $fn)[9];
    my %olddists;
    my $authors = "$base/authors/id";

  PACKAGE:
    while(my $line = $fh->getline)
    {   my ($oldpkg, $version, $dist) = split " ", $line;

        if($check)
        {   -f "$authors/$dist"
                or next PACKAGE;

            if((stat "$authors/$dist")[9] > $time_last_update )
            {   trace "newer $dist, so replace $oldpkg\n";
                next PACKAGE;
            }
        }

        unless($dist)
        {   warning "Error line=$line";
            next;
        }

        push @{$olddists{$dist}}, [ $oldpkg, $version ];
    }

    \%olddists;
}

sub update_core_cpan($@)
{  my ($archive, @files) = @_;

   $ua ||= LWP::UserAgent->new;

   foreach my $destfile (@files)
   {   info "getting update of $destfile from $archive";
       my $fn       = basename $destfile;
       my $group    = basename dirname $destfile;
       my $source   = "$archive/$group/$fn";

       my $response = $ua->get($source, ':content_file' => $destfile);
       next if $response->is_success;

       unlink $destfile;
       error __x"failed to get {uri} for {to}: {err}"
         , uri => $source, to => $destfile, err => $response->status_line;
   }
}

sub mkdirhier(@)
{   foreach my $dir (@_)
    {   next if -d $dir;
        mkdirhier dirname $dir;

        mkdir $dir, 0755
            or fault __x"cannot create directory {dir}", dir => $dir;

        trace "created $dir";
    }
    1;
}

sub mirror($$$@)
{   my ($mycpan, $bigcpan, $mods, %opts) = @_;
    @$mods or return;
    my %need    = map { ($_ => 1) } @$mods;

    if(my $mode = $opts{mode})
    {   dispatcher mode => $mode, 'ALL';
    }

    $ua       ||= LWP::UserAgent->new;

    my $details = catfile $mycpan, 'modules', '02packages.details.txt.gz';
    my $auth    = catdir  $mycpan, 'authors', 'id';

    my $fh      = IO::Uncompress::Gunzip->new($details)
        or error __x"cannot read from '{fn}': {err}"
             , fn => $details, err => $GunzipError;

    while(my $line = $fh->getline)   # skip header, search first blank
    {   last if $line =~ m/^\s*$/;
    }

    while(my $line = $fh->getline)
    {   my ($pkg, $version, $dist) = split ' ', $line;
        delete $need{$pkg} or next;

        my $to = catfile $auth, split m#/#, $dist;
        if(-f $to)
        {   info __x"package {pkg} in distribution {dist}"
              , pkg => $pkg, dist => $dist;
            next;
        }

        my $source   = "$bigcpan/authors/id/$dist";
        mkdirhier dirname $to;
        my $response = $ua->get($source, ':content_file' => $to);
        unless($response->is_success)
        {   unlink $to;
            info __x"failed to get {uri} for {to}: {err}"
              , uri => $source, to => $to, err => $response->status_line;
            next;
        }

        info __x"got {pkg} in {dist}", pkg => $pkg, dist => $dist;
    }

    warning __x"package {pkg} does not exist", pkg => $_
        for sort keys %need;
}

1;
