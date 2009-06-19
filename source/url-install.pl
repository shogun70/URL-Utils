#!/usr/bin/perl 
# TODO help message
$GZIP = "/usr/bin/gzip -c";
$CURL = '/usr/bin/curl';
$S3CURL = 's3curl.pl';
$S3_KEY_ID = 'primary';
$AWS = 'aws';
$INSTALL = "/usr/bin/install";
$HTTP_CONF_FILE = $ENV{HOME} . "/.shurl/http.conf";

use URI;
use Cwd;
use File::Temp qw / tempfile tempdir /;
use Getopt::Std;

use Config::ApacheFormat;


my %opts;
getopts('H:', \%opts);
(@ARGV < 2) and die "No destination specified\n";
my $dest = pop @ARGV;
(@ARGV < 1) and die "No source files specified\n";
if (@ARGV > 1 && $dest !~ /\/$/) {
	warn "Destination directory not terminated with /.\n";
	$dest .= "/";
}
$opts{H} and $HTTP_CONF_FILE = $opts{H};

my $baseHref = "file://localhost" . getcwd;
my $uri = URI->new_abs($dest, $baseHref);
$uri->scheme =~ /file|ftp|http|s3/ or die $uri->scheme . " is not a valid scheme\n";

my ($httpConf, $hostConf, $installRoot, @locationConf);
$httpConf = new Config::ApacheFormat(
	valid_blocks => ["Host", "Location", "LocationMatch", "Files", "FilesMatch"],
	valid_directives => ["InstallRoot", "Expires", "Filter"],
	inheritance_support => 1,
	duplicate_directives => "error",
	case_sensitive => 1
);
$httpConf->read($HTTP_CONF_FILE) or die "Could not read $HTTP_CONF_FILE\n";
$hostConf = $uri->scheme ? $httpConf->block("Host" => $uri->host) : undef;
if ($hostConf) {
	$installRoot = $hostConf->get("InstallRoot") || die "InstallRoot not defined for " . $uri->host . "\n";
	unshift @locationConf, $hostConf;
	foreach ($hostConf->get("LocationMatch")) {
		my $m = $_->[1];
		unshift @locationConf, $hostConf->block($_) if $uri->path =~ m($m);
	}
	foreach ($hostConf->get("Location")) {
		my $m = $_->[1];
		$m =~ s/\?/[^\/]/;
		$m =~ s/\*/[^\/]*/;
		unshift @locationConf, $hostConf->block($_) if $uri->path =~ m($m);
	}
}

my $stagedir = tempdir( CLEANUP => 1 );
for $fname (@ARGV) {
	if ($hostConf) {
		redirect($fname);
		exit;
	}
	install($fname, $uri);
	exit;
}

sub redirect {
	my $fname = shift;
	my @filesConf;
	for my $conf (@locationConf) {
		my @tmpConf;
		unshift @tmpConf, $conf;
		for ($conf->get("FilesMatch")) {
			my $m = $_->[1];
			unshift @tmpConf, $conf->block($_) if $fname =~ m($m);
		}
		for ($conf->get("Files")) {
			my $m = $_->[1];
			$m =~ s/\?/[^\/]/;
			$m =~ s/\*/[^\/]*/;
			unshift @tmpConf, $conf->block($_) if $fname =~ m($m);
		}
		unshift @filesConf, @tmpConf;
	}
	my ($expires, $filter);
	for $conf (@filesConf) {
		my @expTokens = $conf->get("Expires");
		$expires ||= \@expTokens;
		$filter ||= $conf->get("Filter");
	}
	my $stagingFile = $fname;
	my $headers = {};
	if ($filter) {
		$stagingFile = "$stagedir/$fname";
		for ($filter) {
			/DEFLATE/ and do {
				system("$GZIP $fname > $stagingFile");
				$headers->{"Content-Encoding"} = "gzip";
				next;
			};
			die "$filter not recognized\n";
		}
	}
	if ($expires) {
		my @tokens = @{ $expires };
		my $base = shift @tokens;
		$base == "access" || die "Only supports 'access plus' in Expires directive\n";
		my $plus = shift @tokens;
		$plus == "plus" || die "Only supports 'access plus' in Expires directive\n";
		my $maxage = 0;
		while (1) {
			my $n = shift @tokens or last;
			my $unit = shift @tokens or last;
			for ($unit) {
				/seconds/ and $maxage += $n;
				/minutes/ and $maxage += $n * 60;
				/hours/ and $maxage += $n * 60 * 60;
				/days/ and $maxage += $n * 24 * 60 * 60;
				/weeks/ and $maxage += $n * 7 * 24 * 60 * 60;
				/months/ and $maxage += $n * 30 * 24 * 60 * 60;
				/years/ and $maxage += $n * 365 * 24 * 60 * 60;
			}
		}
		$headers->{"Cache-Control"} = "maxage $maxage";
	}
	$installRoot =~ s/\/$//;
	my $redirectUri = URI->new($installRoot . $uri->path);
	install($stagingFile, $redirectUri, $headers);
}
		

sub install {
my $filepath = shift;
my $uri = shift;
my $headers = shift;
$filepath =~ /([^\/]+)$/;
my $fname = $1;
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
		system("$INSTALL $filepath $dir");
		next;
	};
	/ftp/ && do {
		`$CURL --silent --ftp-create-dirs --netrc --upload-file $filepath $href`;
		next;
	};
	/http/ && do {
		`$CURL --silent --upload-file $filepath $href`;
		next;
	};
	/s3/ && do {
		my $bucket = $uri->authority;
		my $key = $uri->path . $fname;
		my $headerString = '';
		foreach (keys %{ $headers }) {
			my $val = $headers->{$_};
			$headerString .= "\"$_: $val\" ";
		}
		my $execStr = "$AWS put $headerString $bucket$key $filepath --public";
		system($execStr);
		next;
	}
}
}

exit;
