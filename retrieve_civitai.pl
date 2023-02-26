#!/usr/bin/perl
#

use v5.32;
use warnings;
use HTTP::Tiny;
use JSON;
use Data::Dumper;

my $authcookie = 'SET_ME';
my $imgcache = 'https://imagecache.civitai.com/xG1nkqKTMzGDvpLrqFT7WA/';
my $basedir = '/local/stable-diffusion-webui/';
my @sfwdir = ('_SFW', '_NSFW');

my %dir_of_type = (
    'LORA' => "$basedir/models/Lora",
    'TextualInversion' => "$basedir/embeddings",
    'Checkpoint' => "$basedir/models/Stable-diffusion",
    'Hypernetwork' => "$basedir/models/hypernetworks",
    'Controlnet' => "$basedir/models/ControlNet",
);

my $cache_html = 0;
my $cache_json = 1;

my $ua = HTTP::Tiny->new(
    default_headers => { Cookie => "__Host-next-auth.csrf-token=$authcookie" }
);

my $json_codec = JSON->new->allow_nonref;

while (my $url = shift @ARGV) {
    die unless $url =~ m!(\d+)/([^/]+)$!;
    my $id = $1;
    my $basename = $2;

    my $json;

    if ( -e "${basename}_$id.json" and $cache_json ) {
        local $/ = undef;
        open my $fh, '<', "${basename}_$id.json" or die "$!.";
        $json = <$fh>;
        close $fh;

    } else {
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
    }

    my $meta = $json_codec->decode($json);

    my $data = $$meta{props}{pageProps}{trpcState}{json}{queries}[0]{state}{data};
    my $name = $$data{name};
    my $type = $$data{type};
    my $nsfw = exists $$data{nsfw} ? $$data{nsfw} : 0;

    printf STDERR "Name: %s (%s)%s\n", $name, $type, $nsfw ? ' !NSFW!' : '';


    ### Find location of model file (so we can add a Preview)

    # but not for Poses
    next if $type eq 'Poses';

    unless ( exists $dir_of_type{$type} and -d "$dir_of_type{$type}" ) {
        printf STDERR "    Unknown type %s, skipping.\n", $type;
        next;
    }

    (my $camel_name = $name) =~ s/ (.)/uc($1)/eg;   # camel case
    $camel_name =~ s/^(.)/lc($1)/e;                 # first char lower-case
    $camel_name =~ s/[^a-z0-9]//gi;                 # remove forbidden chars

    my $version = $$meta{props}{pageProps}{trpcState}{json}{queries}[0]{state}{data}{modelVersions}[0];
    (my $ver_name = $$version{name}) =~ s/[^a-z0-9]//gi;
    $ver_name = lc $ver_name;

    my $basefn = "${camel_name}_${ver_name}";
    $basefn = lc $$version{trainedWords}[0] if $type eq 'TextualInversion' and exists $$version{trainedWords} and defined $$version{trainedWords}[0];
    $basefn =~ s/\..*//;
    my $basepath = "$dir_of_type{$type}/$sfwdir[$nsfw]/$basefn";

    # Search for model
    for my $sfwdir (@sfwdir) {
        opendir my $dh, "$dir_of_type{$type}/$sfwdir" or next;
        while (readdir $dh) {
            next if /^\./;
            if ($_ =~ /^(\Q$basefn\E)\.(.+)$/i) {
                $basepath = "$dir_of_type{$type}/$sfwdir/$1";
                last;
            }
        }
        closedir $dh;
    }

    printf STDERR "    path: %s\n", $basepath;

    my $img_fn = "$basepath.png";
    $img_fn = "$basepath.preview.png";
    my $img = $$version{images}[0];

    if ( ! -e $img_fn ) {
        my $response = $ua->get("$imgcache/$$img{url}/width=$$img{width}");
        die "Failed: $response->{status} $response->{reason}." unless $response->{success};
        my $content = $response->{content};
        open my $fh, '>', $img_fn or die "$!.";
        print $fh $content;
        close $fh;
        printf STDERR "    downloaded %s\n", $img_fn;
    }

}

