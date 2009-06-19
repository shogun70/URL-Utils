#!/usr/bin/perl
use warnings;
use strict;
use Cwd;
use File::Basename;
use FindBin;

# Preset variables
our $top_builddir = getcwd;
our $top_srcdir = $FindBin::RealBin;
our $builddir = $top_builddir;
our $srcdir = $top_srcdir;
our $cfg_fname = "config.options";
our $mak_fname = "main.mak";

# Predeclared subroutines
sub process_dir($);
sub create_makefile();
sub get_subdirs();

process_dir("");

sub process_dir($) {

my $reldir = shift;
$builddir = $top_builddir;
$builddir .= "/" . $reldir if $reldir;
$srcdir = $top_srcdir;
$srcdir .= "/" . $reldir if $reldir;

if (! -d $builddir) {
	mkdir $builddir || die "Error creating $builddir directory";
}

create_makefile();

my @subdirs = get_subdirs();
foreach my $dir (@subdirs) {
	my $subreldir = ($reldir) ? $reldir . "/" : "";
	$subreldir .= $dir;
	process_dir($subreldir);
}

}


sub create_makefile() {

my $makefile = "$builddir/Makefile";
open(OUT, "> " . $makefile) || die "Error opening $makefile";
print OUT <<"EOF";
srcdir = $srcdir
top_srcdir = $top_srcdir
builddir = $builddir
top_builddir = $top_builddir

include $top_srcdir/$cfg_fname
include $top_builddir/$cfg_fname
include $srcdir/$mak_fname

EOF

close OUT;
}


sub get_subdirs() {

my $Makefile = << 'EOF';
include Makefile

VAR:
	@echo ${${VAR}}
EOF

my $cmd = "echo '$Makefile' | make -C $builddir -f - VAR=SUBDIRS VAR";
my $text = `$cmd`;
return split(/\s+/, $text);
}

