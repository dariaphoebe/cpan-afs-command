
use strict;
use English;

use Test::More;
use Test::Exception;
use Data::Dumper;
use Try::Tiny;

use lib q{t/lib};
use Test::AFS::Command;

use blib;
use AFS::Command::FS;
use AFS::Command::VOS;
use AFS::Command::PTS;

if ( $ENV{AFS_COMMAND_DISABLE_TESTS} =~ /\bfs\b/ ) {
    plan skip_all => q{fs tests explicitly disabled};
} elsif ( $ENV{AFS_COMMAND_CELLNAME} eq q{your.cell.name} ) {
    plan skip_all => q{No cell name configured};
}

my $cell = $ENV{AFS_COMMAND_CELLNAME} || 
    die qq{Missing configuration variable AFS_COMMAND_CELLNAME\n};

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

my $result = $fs->checkservers;
ok( ref $result && $result->isa( q{AFS::Object::CacheManager} ), q{fs->checkservers} );

my $servers = $result->servers;
ok( ref $servers eq q{ARRAY}, q{result->servers} );

$result = $fs->checkservers( interval => 0 );
ok( ref $result && $result->isa( q{AFS::Object::CacheManager} ), q{ $fs->checkservers with interval} );

ok( $result->interval =~ m{^\d+$}ms, q{result->interval} );

# All the common _paths_method methods
my $paths = [ $pathafs, $pathnotafs, $pathbogus ];

my %pathops = (
    diskfree        => [qw( volname total used avail percent )],
    examine         => [qw( volname total avail id quota )],
    getcalleraccess => [qw( rights )],
    getfid          => [qw( volume vnode unique )],
    listquota       => [qw( volname quota used percent partition )],
    quota           => [qw( percent )],
    storebehind     => [qw( asynchrony )],
    whereis         => [qw( hosts )],
    whichcell       => [qw( cell )],
);

foreach my $pathop ( keys %pathops ) {

    next if not $fs->supportsOperation($pathop);

    $result = $fs->$pathop(
        ( $pathop eq q{storebehind} ? q{files} : q{path} ) => $paths,
    );
    ok( ref $result && $result->isa( q{AFS::Object::CacheManager} ), qq{fs->$pathop} );

    if ( $pathop eq q{storebehind} ) {
        ok( defined $result->asynchrony, q{result->asynchrony} );
    }

    foreach my $pathname ( @{ $paths } ) {

        my $path = $result->getPath($pathname);
        ok( ref $path && $path->isa( q{AFS::Object::Path} ), qq{result->getPath($pathname)} );

        if ( $pathname eq $pathafs ) {
            foreach my $attr ( @{$pathops{$pathop}} ) {
                ok( defined $path->$attr, qq{path->$attr} );
            }
        } else {
            ok( $path->error, q{path->error} );
        }

    }

}

# fs exportafs -- this one is hard to really test, since we can't
# verify all the parsing unless it is actually supported and enabled,
# so fake it.

my $has_exportafs = 1;

try {
    $result = $fs->exportafs( type => q{nfs} );
} catch {
    $has_exportafs = 0;
};
    
if ( $has_exportafs ) {

    ok( ref $result && $result->isa( q{AFS::Object::CacheManager} ), q{fs->exportafs} );

    ok( defined $result->enabled, q{result->enabled} );

    foreach my $attr ( qw(convert uidcheck submounts) ) {
        ok( defined $result->$attr, qq{result->$attr} );
    }

}

$result = $fs->getcacheparms;
ok( ref $result && $result->isa( q{AFS::Object::CacheManager} ), q{fs->getcacheparms} );

foreach my $attr ( qw(avail used) ) {
    ok( defined $result->$attr, qq{result->$attr} );
}

$result = $fs->getcellstatus( cell => $cell );
ok( ref $result && $result->isa( q{AFS::Object::CacheManager} ), q{fs->getcellstatus} );

my $cellobj = $result->getCell($cell);
ok( ref $cellobj && $cellobj->isa( q{AFS::Object::Cell} ), q{result->getCell} );

foreach my $attr ( qw(cell status) ) {
    ok( defined $cellobj->$attr, qq{result->$attr} );
}

if ( $fs->supportsOperation( q{getclientaddrs} ) ) {
    $result = $fs->getclientaddrs;
    ok( ref $result && $result->isa( q{AFS::Object::CacheManager} ), q{fs->getclientaddrs} );
    my $addresses = $result->addresses;
    ok( ref $addresses eq q{ARRAY}, q{result->addresses} );
}

if ( $fs->supportsOperation( q{getcrypt} ) ) {
    $result = $fs->getcrypt;
    ok( ref $result && $result->isa( q{AFS::Object::CacheManager} ), q{fs->getcrypt} );
    ok( defined $result->crypt, q{result->crypt} );
}

$result = $fs->getserverprefs;
ok( ref $result && $result->isa( q{AFS::Object::CacheManager} ), q{fs->getserverprefs} );

my ($dbserver) = $result->getServers;
ok( ref $dbserver && $dbserver->isa( q{AFS::Object::Server} ), q{result->getServers} );
foreach my $attr ( qw(server preference) ) {
    ok( defined $dbserver->$attr, qq{server->$attr} );
}

#
# fs listaliases -- not tested, but I supposed we could define an
# alias, and then remove it.  Might be kinda intrusive, though.
#

$result = $fs->listcells;
ok( ref $result && $result->isa( q{AFS::Object::CacheManager} ), q{fs->listcells} );

$cellobj = $result->getCell($cell);
ok( ref $cellobj && $cellobj->isa( q{AFS::Object::Cell} ), q{result->getCell} );
ok( $cellobj->cell eq $cell, q{cell name matches} );

$servers = $cellobj->servers;
ok( ref $servers eq 'ARRAY', q{cellobj->servers} );

$result = $fs->sysname;
ok( ref $result && $result->isa( q{AFS::Object::CacheManager} ), q{fs->sysname} );

ok( defined $result->sysname, q{result->sysname} );

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

$result = $fs->lsmount( dir => [values %mtpath] );
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
$paths = [ $mtpath, $pathnotafs, $pathbogus ];

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

if ( $fs->supportsOperation( q{uuid} ) ) {
    if ( $fs->supportsArgumentOptional( qw( uuid generate ) ) ) {
        # NOT testing generation -- too dangerous
        my $result = $fs->uuid;
        ok( ref $result && $result->isa( q{AFS::Object::CacheManager} ), q{fs->uuid} );
        ok( $result->uuid, q{result->uuid} );
    }
}

done_testing();
exit 0;

