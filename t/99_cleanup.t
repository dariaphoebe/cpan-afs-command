
use strict;
use English;

use Test::More;
use Test::Exception;

use lib q{t/lib};
use Test::AFS::Command;

use blib;
use AFS::Command::PTS;

if ( $ENV{AFS_COMMAND_DISABLE_TESTS} =~ /\bpts\b/ ) {
    plan skip_all => q{vos tests explicitly disabled};
} elsif ( $ENV{AFS_COMMAND_CELLNAME} eq q{your.cell.name} ) {
    plan skip_all => q{No cell name configured};
}

my $cell = $ENV{AFS_COMMAND_CELLNAME} ||
    die qq{Missing configuration variable AFS_COMMAND_CELLNAME\n};

my $ptsgroup = $ENV{AFS_COMMAND_PTS_GROUP} ||
    die qq{Missing configuration variable AFS_COMMAND_PTS_GROUP\n};

my $ptsuser = $ENV{AFS_COMMAND_PTS_USER} ||
    die qq{Missing configuration variable AFS_COMMAND_PTS_USER\n};

my $binary = $ENV{AFS_COMMAND_BINARY_PTS} || q{pts};

my $pts = AFS::Command::PTS->new( command => $binary );
ok( ref $pts && $pts->isa( q{AFS::Command::PTS} ), q{AFS::Command::PTS->new} );

ok(
    $pts->delete(
        nameorid => [ $ptsgroup, $ptsuser ],
        cell     => $cell,
    ),
    q{pts->delete},
);

done_testing();
exit 0;
