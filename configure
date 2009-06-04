#!/usr/bin/perl
use warnings;
use strict;
use Cwd;
use File::Basename;
use FindBin;

# Preset variables
our @presetVars = qw(top_builddir top_srcdir builddir srcdir configure_input);
our $presetVars = {};
our $top_builddir = getcwd;
our $top_srcdir = $FindBin::RealBin;
our $builddir = $top_builddir;
our $srcdir = $top_srcdir;
our $configure_input = "";

# Predeclared subroutines
sub read_config($$$);
sub expand_configVars();
sub expand_var($$$);
sub process_dir($);
sub process_file($);
sub get_subdirs($);

my %vars;

my @configVars;
my %configVars;
read_config($top_srcdir . "/config.options", \%configVars, \@configVars);
my @buildVars;
read_config($top_builddir . "/config.options", \%configVars, \@buildVars);
foreach (@configVars) {
	$vars{$_} && next; # don't add if already in 
	$vars{$_} = expand_var($_, \%configVars, \%vars);
}

process_dir("");

my $reconfigureScript = <<"";
#!/bin/sh
$top_srcdir/configure

my $reconfigureBin = "$top_builddir/reconfigure";
-e $reconfigureBin or
	`echo "$reconfigureScript" > $reconfigureBin && chmod +x $reconfigureBin`;


sub read_config($$$) {
	
my $configfile = shift;
my $vars = shift;
my $varNames = shift;
open (CONFIG, "< $configfile") or return; # TODO notify failure opening config file
while (<CONFIG>) {
	/^\s*$/ and next; # skip empty lines
	/^#/ and next; # and comments
	/^\s*(\S+)\s*=\s*(.*)\s*(#.*)?$/ or die "Error reading $configfile: \n\t$_";
	$vars->{$1} = $2;
	push @{$varNames}, $1;
}

close (CONFIG);

}

sub expand_var($$$) {
	my ($name, $configVars, $vars) = @_;
	my $val;
	$val = $vars->{$name} and return $val;
	$val = $configVars->{$name} or return $val;
	$val =~ s/\$\((\w+)\)/&expand_var($1, $configVars, $vars)/eg;
	$val =~ s/\$\{(\w+)\}/&expand_var($1, $configVars, $vars)/eg;
	return $val;
}


sub process_dir($) {

my $reldir = shift;
$builddir = $top_builddir;
$builddir .= "/" . $reldir if $reldir;
$srcdir = $top_srcdir;
$srcdir .= "/" . $reldir if $reldir;

$vars{top_builddir} = $top_builddir;
$vars{top_srcdir} = $top_srcdir;
$vars{builddir} = $builddir;
$vars{srcdir} = $srcdir;

if (! -d $builddir) {
	mkdir $builddir || die "Error creating $builddir directory";
}

my @input_files = split(/\s+/, `ls ${srcdir}`);

for my $fname (@input_files) {
	$fname =~ s/\.in$// or next;
	my $relpath = ($reldir) ? $reldir . "/" . $fname : $fname;
	process_file($relpath);	
}

my @subdirs = get_subdirs($reldir);
foreach my $dir (@subdirs) {
	my $subreldir = ($reldir) ? $reldir . "/" : "";
	$subreldir .= $dir;
	process_dir($subreldir);
}

}


sub process_file($) {

my $relpath = shift;

my $infile = $top_srcdir . "/$relpath.in";
open(IN, "< " . $infile) || die "Error opening $infile";

my $outfile = $top_builddir . "/$relpath";
open(OUT, "> " . $outfile) || die "Error opening $outfile";

$configure_input = $infile;

while (<IN>) {
	s/\@(\w+)\@/$vars{$1}/eg;
if (0) {
	foreach my $name (@presetVars, @configVars) {
		my $value = $vars{$name};
		s/\@$name\@/$value/g;
	}
}

	print OUT;
}

close IN;
close OUT;

}


sub get_subdirs($) {

my $reldir = shift;
my $builddir = $top_builddir . "/" . $reldir;
my $Makefile = << 'EOF';
include Makefile

VAR:
	@echo ${${VAR}}
EOF

my $cmd = "echo '$Makefile' | make -I $top_srcdir/mk -C $builddir -f - VAR=SUBDIRS VAR";
my $text = `$cmd`;
return split(/\s+/, $text);
}

