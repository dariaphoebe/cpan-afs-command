use strict;
use warnings;
use English;

use ExtUtils::MakeMaker;
use IO::File;

my $version = get_version(
    in  => q{lib/AFS/Command/Version.pm.in},
    out => q{lib/AFS/Command/Version.pm},
);

WriteMakefile(

    NAME             => q{AFS-Command},
    MIN_PERL_VERSION => q{5.010},
    VERSION          => $version,
    ABSTRACT         => q{AFS Command Utility Interface},
    AUTHOR           => q{Daria Phoebe Brashear <dariaphoebe@auristor.com>},
    LICENSE          => q{unknown},

    dist => {
        TARFLAGS => q{-cv --exclude=.git -f},
    },

    PREREQ_PM => {
        q{Moose}             => 0,
        q{MooseX::Singleton} => 0,
        q{Date::Format}      => 0,
        q{Try::Tiny}         => 0,
    },

    TEST_REQUIRES => {
        q{Test::Exception} => 0,
    },

);

sub get_version {

    my %args = @_;

    my $version = $ENV{EFSDEPLOY_RELEASEALIAS} || q{0.001_001};

    my $in = IO::File->new( $args{in} ) ||
        die qq{Unable to read $args{in}: $ERRNO\n};
    my $out = IO::File->new( qq{>$args{out}} ) ||
        die qq{Unable to write to $args{out}: $ERRNO\n};

    while ( defined($_ = $in->getline) ) {
        s{__VERSION__}{$version}ms;
        $out->print( $_ );
    }

    STDOUT->print( qq{Set version to $version in $args{in}\n} );

    $out->close || die qq{Unable to close $args{out}: $ERRNO\n};

    return $version;

}

