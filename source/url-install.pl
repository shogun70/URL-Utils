#!/usr/bin/perl

# TODO help message

use Getopt::Std;

my %opts;
getopts('bB:df:g:m:o:p', \%opts);
if ($opts{d}) {
	print STDERR "Create directories option not supported\n";
	exit(1);
}
my $dest = pop @ARGV;

use URI;
use Cwd;

$CURL = '/usr/bin/curl';


my $baseHref = "file://localhost" . getcwd;
my $uri = URI->new_abs($dest, $baseHref);
my $href = $uri->as_string();

if ($uri->scheme eq "file") {
	my $path = $uri->path;
	my $dir = $path;
	$dir =~ s/\/[^\/]+$//;
	if (! -d $dir) {
		system("install -d $dir > /dev/null");
		$? == 0 or exit 1;
	}
        for $fname (@ARGV) {
		if ($fname eq "-") {
			open (OUTFILE, ">$path");
			while (<>) {
				print OUTFILE;
			}
			close (OUTFILE);
		}
		else {
			`cp $fname $path`;
		}
	}
}
elsif ($uri->scheme eq "ftp") {
        for $fname (@ARGV) {
		`$CURL --silent --ftp-create-dirs --netrc --upload-file $fname $href`;
	}
}
elsif ($uri->scheme eq "http") {
        for $fname (@ARGV) {
		`$CURL --silent --upload-file $fname $href`;
	}
}
else {
	print STDERR $uri->scheme . " is not a valid scheme\n";
	exit(1);
}
exit(0);
