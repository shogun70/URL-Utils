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
use HTTP::Date;
use Cwd;
use File::Temp qw / tempfile tempdir /;
use Getopt::Std;

use Config::ApacheFormat;


my %opts;
getopts('nH:d', \%opts);

if ($opts{d}) { # TODO create directories support??
	print STDERR "Create directories mode not supported. Handled as no-op. \n";
	exit 0;
}

(@ARGV < 2) and die "No destination specified\n";
my $dest = pop @ARGV;
(@ARGV < 1) and die "No source files specified\n";
if (@ARGV > 1 && $dest !~ /\/$/) {
	warn "Destination directory not terminated with /.\n";
	$dest .= "/";
}
$opts{H} and $HTTP_CONF_FILE = $opts{H};
my $no_exec = $opts{n};

my $baseHref = "file://localhost" . getcwd;
my $uri = URI->new_abs($dest, $baseHref);
$uri->scheme =~ /file|ftp|http|s3/ or die $uri->scheme . " is not a valid scheme\n";

my ($httpConf, $hostConf, $installRoot, @locationConf);
if ($uri->scheme eq "http") {
	$httpConf = new Config::ApacheFormat(
		valid_blocks => ["Host", "Location", "LocationMatch", "Files", "FilesMatch"],
		valid_directives => ["InstallRoot", "Expires", "ProxyExpires", "Filter"],
		inheritance_support => 0,
		duplicate_directives => "error",
		case_sensitive => 1
	);
	$httpConf->read($HTTP_CONF_FILE) or die "Could not read $HTTP_CONF_FILE\n";
	$hostConf = $uri->scheme ? $httpConf->block("Host" => $uri->host) : undef;
	if ($hostConf) {
		$installRoot = $hostConf->get("InstallRoot") || die "InstallRoot not defined for " . $uri->host . "\n";
		push @locationConf, $hostConf;
		foreach ($hostConf->get("LocationMatch")) {
			my $m = $_->[1];
			push @locationConf, $hostConf->block($_) if $uri->path =~ m($m);
		}
		foreach ($hostConf->get("Location")) {
			my $m = $_->[1];
			$m =~ s/\?/[^\/]/;
			$m =~ s/\*/[^\/]*/;
			push @locationConf, $hostConf->block($_) if $uri->path =~ m($m);
		}
	}
}

my $stagedir = tempdir( CLEANUP => 1 );
for $fname (@ARGV) {
	my $rc = ($hostConf) ? redirect($fname) : install($fname, $uri);
}
exit;

sub redirect {
	my $filepath = shift;
	$filepath =~ /([^\/]+)$/;
	my $fname = $1 or die "$filepath is a directory\n";
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
	my ($expires, $proxyExpires, $filter);
	for $conf (@filesConf) {
		my @tokens = $conf->get("Expires");
		$expires ||= \@tokens if scalar(@tokens);
		my @tokens = $conf->get("ProxyExpires");
		$proxyExpires ||= \@tokens if scalar(@tokens);
		my @tokens = $conf->get("Filter");
		$filter ||= \@tokens if scalar(@tokens);
	}
	my $stagingFile = $filepath;
	my $headers = {};
	if ($filter) {
		my @tokens = @{ $filter };
		$stagingFile = "$stagedir/$fname";
		my $infile = $filepath;
		foreach (@tokens) {
			/DEFLATE/ and do {
				my $outfile;
				(undef, $outfile) = tempfile("$fname-XXXX", DIR => $stagedir, SUFFIX => ".gz", OPEN => 0);
				system("$GZIP $infile > $outfile");
				$headers->{"Content-Encoding"} = "gzip";
				$infile = $outfile;
				next;
			};
			die "$_ not recognized\n";
		}
		system("mv $infile $stagingFile");
	}
	if ($expires) {
		my @tokens = @{ $expires };
		my $base = shift @tokens;
		$base eq "access" || $base eq "modification" || die "Only supports 'access plus' or 'modification plus' in Expires directives\n";
		my $plus = shift @tokens;
		$plus == "plus" || die "Only supports 'access plus' or 'modification plus' in Expires directives\n";
		my $maxage = readAge(@tokens);
		for ($base) {
			/access/ and do {
				$headers->{"Cache-Control"} = "max-age=$maxage";
				last;
			};
			/modification/ and do {
				my $expireTime = time() + $maxage;
				$headers->{"Expires"} = time2str($expireTime);
				last;
			};
		}
	}
	if ($proxyExpires) {
		my @tokens = @{ $proxyExpires };
		my $base = shift @tokens;
		$base eq "access" || die "Only supports 'access plus' in ProxyExpires directives\n";
		my $plus = shift @tokens;
		$plus == "plus" || die "Only supports 'access plus' in ProxyExpires directives\n";
		my $maxage = readAge(@tokens);
		for ($base) {
			/access/ and do {
				my $txt = $headers->{"Cache-Control"};
				$txt and $txt .= ", ";
				$txt .= "s-maxage=$maxage";
				$headers->{"Cache-Control"} = $txt;
				last;
			}
		}
	}
	$installRoot =~ s/\/$//;
	my $redirectUri = URI->new($installRoot . $uri->path);
	install($stagingFile, $redirectUri, $headers);
}
		

sub readAge() {
my $age = 0;
while (1) {
	my $n = shift or last;
	my $unit = shift or last;
	for ($unit) {
		/seconds/ and $age += $n;
		/minutes/ and $age += $n * 60;
		/hours/ and $age += $n * 60 * 60;
		/days/ and $age += $n * 24 * 60 * 60;
		/weeks/ and $age += $n * 7 * 24 * 60 * 60;
		/months/ and $age += $n * 30 * 24 * 60 * 60;
		/years/ and $age += $n * 365 * 24 * 60 * 60;
	}
}
return $age;
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
		my $execStr = "$INSTALL $filepath $dir";
		system($execStr) unless $no_exec;
		print STDERR "$execStr\n" if $no_exec;
		next;
	};
	/ftp/ && do {
		my $execStr = "$CURL --silent --ftp-create-dirs --netrc --upload-file $filepath $href";
		system($execStr) unless $no_exec;
		print STDERR "$execStr\n" if $no_exec;
		next;
	};
	/http/ && do {
		my $execStr = "$CURL --silent --upload-file $filepath $href";
		system($execStr) unless $no_exec;
		print STDERR "$execStr\n" if $no_exec;
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
		system($execStr) unless $no_exec;
		print STDERR "$execStr\n" if $no_exec;
		next;
	}
}
}

exit;
