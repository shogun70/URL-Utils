#!/usr/bin/perl

# TODO help message
$GZIP = "/usr/bin/gzip -c";
$CURL = '/usr/bin/curl';
$INSTALL = "/usr/bin/install";

use URI;
use Cwd;
use File::Temp qw / tempfile tempdir /;
use Getopt::Std;

my %opts;
getopts('zZ:', \%opts);
(@ARGV < 2) and die "No destination specified\n";
my $dest = pop @ARGV;
(@ARGV < 1) and die "No source files specified\n";
if (@ARGV > 1 && $dest !~ /\/$/) {
	warn "Destination directory not terminated with /.\n";
	$dest .= "/";
}

my $baseHref = "file://localhost" . getcwd;
my $uri = URI->new_abs($dest, $baseHref);
$uri->scheme =~ /file|ftp|http/ or die $uri->scheme . " is not a valid scheme\n";

my $zipdir;
$opts{z} || $opts{Z} and $zipdir = tempdir( CLEANUP => 1 );

for $fname (@ARGV) {
	my $ext = $opts{Z};
	my $zipname = ($ext) ? "$fname.$ext" : $fname;
	if ($zipdir) {
		my $zippath = "$zipdir/$zipname";
		system("$GZIP $fname > $zippath");
		install($zippath, $uri);
		$ext && install ($fname, $uri);
	}
}

sub install {
my $fname = shift;
my $uri = shift;
my $href = $uri->as_string();
for ($uri->scheme) {
	/file/ && do {
		my $path = $uri->path;
		my $dir = $path;
		$dir =~ s/\/[^\/]+$//;
		if (! -d $dir) {
			system("$INSTALL -d $dir > /dev/null");
			$? == 0 or exit 1;
		}
		system("$INSTALL $fname $dir");
		next;
	};
	/ftp/ && do {
		`$CURL --silent --ftp-create-dirs --netrc --upload-file $fname $href`;
		next;
	};
	/http/ && do {
		`$CURL --silent --upload-file $fname $href`;
		next;
	};
}
}

exit;
