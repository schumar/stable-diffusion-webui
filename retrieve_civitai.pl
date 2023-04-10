#!/usr/bin/perl
#
# Loads the given (civitai)-URL, extracts the JSON from the page and puts
# it into a file in models/meta/

use v5.32;
use warnings;
use HTTP::Tiny;

my $authcookie = 'SET_ME';
my $imgcache = 'https://imagecache.civitai.com/xG1nkqKTMzGDvpLrqFT7WA/';
my $basedir = '/local/stable-diffusion-webui/';
my $metadir = "$basedir/models/meta";

my $cache_html = 0;
my $cache_json = 0;

my $ua = HTTP::Tiny->new(
    default_headers => { Cookie => "__Host-next-auth.csrf-token=$authcookie" }
);

while (my $url = shift @ARGV) {
    die unless $url =~ m!(\d+)/([^/]+)$!;
    my $id = $1;
    my $basename = $2;

    my $json;

    next if ( -e "${basename}_$id.json" and $cache_json );

    my $content;
    if ( -e "${basename}_$id.html" and $cache_json ) {
        local $/ = undef;
        open my $fh, '<', "${basename}_$id.html" or die "$!.";
        $content = <$fh>;
        close $fh;
    } else {
        my $response = $ua->get($url);
        die "Failed: $response->{status} $response->{reason}." unless $response->{success};
        $content = $response->{content};
        if ($cache_html) {
            open my $fh, '>', "${basename}_$id.html" or die "$!.";
            print $fh $content;
            close $fh;
        }
    }

    die unless $content =~ m! type="application/json">(.+?)</script>!;
    $json = $1;

    open my $fh, '>', "${basename}_$id.json" or die "$!.";
    print $fh $json;
    close $fh;

    printf STDERR "Retrieved %s_%s.json\n", $basename, $id;
}

