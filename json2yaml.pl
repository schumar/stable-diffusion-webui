#!/usr/bin/perl
#
# Reads all json files from the meta directory, searches for information
# pertaining to the passed filename, and creates a .webui.yaml file for it

use v5.32;
use warnings;
use HTTP::Tiny;
use JSON;
use YAML qw(DumpFile);
use Data::Dumper;
use Digest;

my $basedir = '/local/stable-diffusion-webui/';
my $metadir = "$basedir/models/meta";
my $authcookie = 'SET_ME';
my $imgcache = 'https://imagecache.civitai.com/xG1nkqKTMzGDvpLrqFT7WA/';

my $json_codec = JSON->new->allow_nonref;

my $ua = HTTP::Tiny->new(
    default_headers => { Cookie => "__Host-next-auth.csrf-token=$authcookie" }
);

# Mapping from our YAML key names for examples to the ones at civitai
my %example_yaml_keys = (
    size         => 'Size',
    seed         => 'seed',
    'model-hash' => 'Model hash',
    sampler      => 'sampler',
    steps        => 'steps',
    cfg          => 'cfgScale',
    prompt       => 'prompt',
    neg          => 'negativePrompt',
);

# Read all JSONs
my @json;
opendir my $dh, $metadir or die "Can't open $metadir: $!.";
while (readdir $dh) {
    next if /^\./;
    next unless /\.json/;

    local $/ = undef;
    open my $fh, '<', "$metadir/$_" or die "Can't open $_: $!.";
    binmode $fh, ':utf8';
    my $decoded = $json_codec->decode(<$fh>);
    close $fh;
    # my $decoded = YAML::LoadFile("$metadir/$_");
    # hack: create link to page
    $$decoded{props}{pageProps}{trpcState}{json}{queries}[0]{state}{data}{page_url} =
        "https://civitai.com/models/$$decoded{props}{pageProps}{id}/$$decoded{props}{pageProps}{slug}";
    push @json, $$decoded{props}{pageProps}{trpcState}{json}{queries}[0]{state}{data};
}
closedir $dh;

# Example images might refer to a model hash, but not a model name;
# build a list of hash->name
my %name_of_hash;
for my $json (@json) {
    (my $model = $$json{name}) =~ s/[^a-z0-9_ .()-]//gi;
    for my $version (@{$$json{modelVersions}}) {
        (my $vername = $$version{name}) =~ s/[^a-z0-9_ .()-]//gi;
        # Drop version name if the model name ends with it, e.g.
        # 'Realistic Vision V1.3' 'V1.3' -> drop the version
        # 'BigHeadMode' 'BigHeadMode' -> drop the version
        my $prettyname = $model;
        if ($model !~ /\Q$vername\E$/) {
            $prettyname = "$model $vername";
        }
        $prettyname =~ s/\s+/ /g;
        for my $file (@{$$version{files}}) {
            for my $hash (@{$$file{hashes}}) {
                if ($$hash{type} eq 'AutoV2') {
                    $name_of_hash{lc $$hash{hash}} = $prettyname;
                }
            }
        }
    }
}
# print Dumper(\%name_of_hash); exit;

while (my $fn = shift @ARGV) {

    if ( ! -e $fn ) {
        printf STDERR "%s does not exist, skipping.\n", $fn;
        next;
    }
    my $fn_size = (stat(_))[7];

    my ($fn_modelname, $fn_version, $fn_extension);
    if ($fn =~ /^([^_]+)(?:_(.*?))?(\..+)?$/) {
        $fn_modelname = $1;
        $fn_version = $2;
        $fn_extension = defined $3 ? $3 : '';
    }

    ##printf STDERR "    DBG: '%s' '%s' '%s' %d\n",
    ##    $fn_modelname, $fn_version, $fn_extension, $fn_size;

    (my $yaml_fn = $fn) =~ s/\..*$//;
    $yaml_fn .= '.webui.yaml';
    if ( -e $yaml_fn ) {
        # printf STDERR "    %s already exists.\n", $yaml_fn;
        next;
    }

    printf STDERR "Creating YAML for %s\n", $fn;

    # Calculate "AutoV2" hash (first 5 byte of SHA256 digest)
    my $ctx = Digest->new("SHA-256");
    open my $fh, '<', $fn or die "$!.";
    $ctx->addfile($fh);
    close $fh;
    my $autov2 = uc substr($ctx->hexdigest, 0, 10);

    for my $json (@json) {
        my @candidates;
        my @files;
        my $modelname = $$json{name};
        (my $modelname_clean = $modelname) =~ s/[^a-z0-9]//gi;

        VERSION: for my $version (@{$$json{modelVersions}}) {
            my $versionname = $$version{name};

            # civitai seems to remove the model name from the version name,
            # e.g. if model "foo bar" has a version "foo bar v123", the
            # resulting filename will simply be "foobar_v123"
            $versionname =~ s/^\Q$modelname\E\s*//i unless lc $versionname eq lc $modelname;

            (my $versionname_clean = $versionname) =~ s/[^a-z0-9]//gi;
            $versionname_clean = substr($versionname_clean, 0, 20);
            $versionname_clean =~ s/\s+//g;

            ## printf STDERR "    DBG: '%s' '%s'\n", $modelname_clean, $versionname_clean
            ## if $modelname_clean =~ /kidmo/i;

            for my $file (@{$$version{files}}) {
                for my $hash (@{$$file{hashes}}) {
                    if ($$hash{type} eq 'AutoV2' and $$hash{hash} eq $autov2) {
                        printf STDERR "    Found %s (%s) via hash %s\n", $modelname, $versionname, $autov2;
                        push @candidates, $version;
                        next VERSION;
                    }
                }

                if (lc $fn eq lc $$file{name}) {
                    printf STDERR "    Found %s (%s) via filename\n", $modelname, $versionname;
                    push @candidates, $version;
                    next;
                }

                if (defined $fn_version) {
                    my $extension = '';
                    $extension = $1 if $$file{name} =~ /(\.[^.]+)$/;
                    ## printf STDERR "    %f .. %f\n", $$file{sizeKB}-2, $$file{sizeKB}+2
                    ##     if $modelname_clean =~ /kidmo/i;
                    # Civitai seems to cut the names after some length, so we
                    # just check if the model name *begin* with the
                    # parts taken from the file name
                    if ($modelname_clean =~ /^\Q$fn_modelname\E/i and
                        lc $versionname_clean eq lc $fn_version and
                        lc $fn_extension eq lc $extension and
                        $$file{sizeKB}-2 < $fn_size/1024 and
                        $$file{sizeKB}+2 > $fn_size/1024
                    ) {
                        printf STDERR "    Found %s (%s) via heuristics\n", $modelname, $versionname;
                        push @candidates, $version;
                        push @files, $file;
                        next;
                    }
                    # printf STDERR "    %s %s %s != %s %s %s\n",
                    #     $modelname_clean, $versionname_clean, $extension,
                    #     $fn_modelname, $fn_version, $fn_extension;
                }
            }
        }

        next unless @candidates;

        if (@candidates > 1) {
            printf STDERR "    Multiple matching versions found :(\n";
            next;
        }
        my $version = $candidates[0];
        my $file = $files[0];

        ## printf STDERR "    DBG: model name = '%s'\n", $$json{name};

        ### Build our YAML
        my %meta = (
            title => $$json{name},
            type => $$json{type},
            description => $$json{description},
            author  => $$json{user}{username},
            source  => $$json{page_url},
            nsfw    => $$json{nsfw} ? 'true' : 'false',
            version => $$version{name},
            updated => $$version{updatedAt},
            base    => $$version{baseModel},
            trigger => $$version{trainedWords},
            url     => $$file{url},
            'filename-orig' => $$file{name},
        );
        if (exists $$json{checkpointType} and defined $$json{checkpointType}) {
            $meta{type} .= ' '.$$json{checkpointType};
        }
        if (exists $$version{description} and defined $$version{description} and $$version{description} ne '') {
            $meta{description} .= '<h2>Version information</h2>'.$$version{description};
        }
        for my $tag (@{$$json{tagsOnModels}}) {
            push @{$meta{tags}}, $$tag{tag}{name};
        }
        for my $example (@{$$version{images}}) {
            my $ex = $$example{meta};

            # Some example images don't have meta-data :( skip 'em
            next unless exists $$ex{prompt};

            # Find model name
            my $model_name = exists $$ex{Model} ? $$ex{Model} : undef;
            unless (defined $model_name and $model_name ne '') {
                if (exists $$ex{'Model hash'} and defined $$ex{'Model hash'}) {
                    if (exists $name_of_hash{$$ex{'Model hash'}}) {
                        $model_name = $name_of_hash{$$ex{'Model hash'}};
                        ## printf STDERR "    DBG: found model %s by hash %s\n",
                        ##     $model_name, $$ex{'Model hash'};
                    } else {
                        $model_name = undef;
                    }
                } else {
                    $model_name = undef;
                }
            }

            my $ex_hash = {};
            $$ex_hash{'model-name'} = $model_name if defined $model_name;
            for my $key (keys %example_yaml_keys) {
                my $their = $example_yaml_keys{$key};
                $$ex_hash{$key} = $$ex{$their} if exists $$ex{$their} and defined $$ex{$their};
            }
            push @{$meta{examples}}, $ex_hash;
        }

        DumpFile($yaml_fn, \%meta);
        printf STDERR "    Wrote %s\n", $yaml_fn;

        (my $img_fn = $fn) =~ s/\..*$//;
        $img_fn .= '.preview.png';
        my $img = $$version{images}[0];
        if ( ! -e $img_fn ) {
            my $response = $ua->get("$imgcache/$$img{url}/width=$$img{width}");
            die "Failed: $response->{status} $response->{reason}." unless $response->{success};
            my $content = $response->{content};
            open my $fh, '>', $img_fn or die "$!.";
            print $fh $content;
            close $fh;
            printf STDERR "    Downloaded %s\n", $img_fn;
        }


    }
}

