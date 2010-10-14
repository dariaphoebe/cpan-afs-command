package Test::AFS::Command;

use strict;
use warnings;
use English;

use IO::File;

my $config = q{};

foreach my $relpath ( qw( . .. ../.. ) ) {
    next if not -f qq{$relpath/CONFIG};
    $config = qq{$relpath/CONFIG};
    last;
}

die qq{Unable to locate CONFIG file\n} if not -f $config;

my $fh = IO::File->new( $config ) 
  die "Unable to open CONFIG file: $ERRNO\n";

while ( defined($_ = $fh->getline) ) {
    next if m{^\#}ms;
    next if not m{^(\w+)\s*=\s*(.*)\s*$}ms;
    my ($key,$value) = ($1,$2);
    if ( exists $ENV{$key} ) {
	warn qq{Environment variable '$key' overrides CONFIG definition\n};
    } else {
	$ENV{$key} = $value;
    }
}

1;
