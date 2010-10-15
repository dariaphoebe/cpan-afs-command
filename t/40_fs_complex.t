
use strict;
use English;

use Test::More;
use Test::Exception;
use Data::Dumper;

use lib q{t/lib};
use Test::AFS::Command;

use blib;
use AFS::Command::PTS;
use AFS::Command::FS;
use AFS::Command::VOS ;

if ( $ENV{AFS_COMMAND_CELLNAME} eq q{your.cell.name} ) {
    plan skip_all => q{No cell name configured};
}

my $cell = $ENV{AFS_COMMAND_CELLNAME} || 
    die qq{Missing configuration variable AFS_COMMAND_CELLNAME\n};

my $ptsgroup = $ENV{AFS_COMMAND_PTS_GROUP} ||
    die qq{Missing configuration variable AFS_COMMAND_PTS_GROUP\n};

my $ptsuser = $ENV{AFS_COMMAND_PTS_USER} ||
    die qq{Missing configuration variable AFS_COMMAND_PTS_USER\n};

my $ptsexisting = $ENV{AFS_COMMAND_PTS_EXISTING} ||
    die qq{Missing configuration variable AFS_COMMAND_PTS_EXISTING\n};

my $volname_prefix = $ENV{AFS_COMMAND_VOLNAME_PREFIX} ||
    die qq{Missing configuration variable AFS_COMMAND_VOLNAME_PREFIX\n};

my $partition_list = $ENV{AFS_COMMAND_PARTITION_LIST} ||
    die qq{Missing configuration variable AFS_COMMAND_PARTITION_LIST\n};

my $pathafs = $ENV{AFS_COMMAND_PATHNAME_AFS} ||
    die qq{Missing configuration variable AFS_COMMAND_PATHNAME_AFS\n};

my $pathnotafs = q{/var/tmp};
my $pathbogus  = q{/this/does/not/exist};

my ($server_partition)  = split m{\s+}msx, $partition_list;
my ($server,$partition) = split m{:}msx, $server_partition;

my %binary = (
    pts => $ENV{AFS_COMMAND_BINARY_PTS} || q{pts},
    vos => $ENV{AFS_COMMAND_BINARY_VOS} || q{vos},
    fs  => $ENV{AFS_COMMAND_BINARY_FS}  || q{fs},
);

my $pts = AFS::Command::PTS->new( command => $binary{pts} );
ok( ref $pts && $pts->isa( q{AFS::Command::PTS} ), q{AFS::Command::PTS->new} );

my $vos = AFS::Command::VOS->new( command => $binary{vos} );
ok( ref $vos && $vos->isa( q{AFS::Command::VOS} ), q{AFS::Command::VOS->new} );

my $fs = AFS::Command::FS->new( command => $binary{fs} );
ok( ref $fs && $fs->isa( q{AFS::Command::FS} ), q{AFS::Command::FS->new} );

my $volname = qq{$volname_prefix.fscomp.$PID};

ok(
    $vos->create(
        server    => $server,
        partition => $partition,
        name      => $volname,
        cell      => $cell,
    ),
    q{vos->create},
);

# Mount it (several different ways)
my %mtpath = (
    rw    => qq{$pathafs/$volname-rw},
    cell  => qq{$pathafs/$volname-cell},
    plain => qq{$pathafs/$volname-plain},
);

foreach my $type ( keys %mtpath ) {
    my %mkmount = (
        dir => $mtpath{$type},
        vol => $volname,
    );
    $mkmount{cell} = $cell if $type eq q{cell};
    $mkmount{rw}   = 1     if $type eq q{rw};
    ok( $fs->mkmount( %mkmount ), qq{fs->mkmount $type} );
}

my $result = $fs->lsmount( dir => [values %mtpath] );
ok( ref $result && $result->isa( q{AFS::Object::CacheManager} ), q{fs->lsmount} );

foreach my $type ( keys %mtpath ) {

    my $mtpath = $mtpath{$type};

    my $path = $result->getPath($mtpath);
    ok( ref $path && $path->isa( q{AFS::Object::Path} ), qq{result->getPath $type} );

    ok( $path->volname eq $volname, qq{path->volname $type} );

    if ( $type eq q{cell} ) {
        ok( $path->cell eq $cell, q{path->cell} );
    }

    if ( $type eq q{rw} ) {
        ok( defined $path->readwrite, q{path>readwrite} );
    }

}

ok(
    $fs->rmmount( dir => [ $mtpath{rw}, $mtpath{plain} ] ),
    q{fs->rmmount},
);

#
# This is the one mtpt we know will work.  The AFS path you gave me
# might NOT be in the same cell you specified, so using the
# cell-specific mount is necessary.
#
my $mtpath = $mtpath{cell};

#
# Set and test the ACL (several different ways)
#
my $paths = [ $mtpath, $pathnotafs, $pathbogus ];

$result = $fs->listacl( path => $paths );
ok( ref $result && $result->isa( q{AFS::Object::CacheManager} ), q{fs->listacl} );

my %acl = ();

foreach my $pathname ( @$paths ) {

    my $path = $result->getPath($pathname);
    ok( ref $path && $path->isa( q{AFS::Object::Path} ), qq{result->getPath($pathname)} );

    if ( $pathname eq $mtpath ) {

        my $normal = $path->getACL;
        ok( ref $normal && $normal->isa( q{AFS::Object::ACL} ), qq{path->getACL} );

        my $negative = $path->getACL( q{negative} );
        ok( ref $negative && $negative->isa( q{AFS::Object::ACL} ), qq{path->getACL negative} );

        %acl = (
            normal   => $normal,
            negative => $negative,
        );

    } else {
        
        # XXX: This all changes with exceptions

    }

}

#
# Sadly, if the localhost is not in the same AFS cell as that being
# tested, the setacl command is guaranteed to fail, because the test
# pts entries will not be defined.
#
# Thus, we use a different, existing pts entry for these tests, and
# not the ones we created above.
#
my %entries = ( $ptsexisting => q{rlidwk} );

foreach my $type ( qw(normal negative) ) {

    ok(
        $fs->setacl(
            dir => $mtpath,
            acl => \%entries,
            ( $type eq q{negative} ? ( negative => 1 ) : () ),
        ),
        q{fs->setacl},
    );

    $result = $fs->listacl( path => $mtpath );
    ok( ref $result && $result->isa( q{AFS::Object::CacheManager} ), q{fs->listacl} );

    my $path = $result->getPath($mtpath);
    ok( ref $path && $path->isa( q{AFS::Object::Path} ), q{result->getPath} );

    my $acl = $path->getACL($type);
    ok( ref $acl && $acl->isa( q{AFS::Object::ACL} ), q{path->getACL} );

    foreach my $principal ( keys %entries ) {
        ok( $acl->getRights($principal) eq $entries{$principal}, q{acl->getRights} );
    }

}

ok( $fs->rmmount( dir => $mtpath ), q{fs->rmmount} );

ok(
    $vos->remove(
        server    => $server,
        partition => $partition,
        id        => $volname,
        cell      => $cell,
    ),
    q{vos->remove},
);

done_testing();
exit 0;
