
use strict;
use English;

use Test::More;
use Test::Exception;
use Data::Dumper;

use lib q{t/lib};
use Test::AFS::Command;

use blib;
use AFS::Command::FS;

if ( $ENV{AFS_COMMAND_DISABLE_TESTS} =~ /\bfs\b/ ) {
    plan skip_all => q{fs tests explicitly disabled};
} elsif ( $ENV{AFS_COMMAND_CELLNAME} eq q{your.cell.name} ) {
    plan skip_all => q{No cell name configured};
}

my $cell = $ENV{AFS_COMMAND_CELLNAME} || 
    die qq{Missing configuration variable AFS_COMMAND_CELLNAME\n};

my $pathafs = $ENV{AFS_COMMAND_PATHNAME_AFS} ||
    die qq{Missing configuration variable AFS_COMMAND_PATHNAME_AFS\n};

my $pathnotafs = q{/var/tmp};
my $pathbogus  = q{/this/does/not/exist};

my $binary = $ENV{AFS_COMMAND_BINARY_FS} || q{fs};

my $fs = AFS::Command::FS->new( command => $binary );
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
    diskfree    => [qw( volname total used avail percent )],
    examine     => [qw( volname total avail id quota )],
    listquota   => [qw( volname quota used percent partition )],
    quota       => [qw( percent )],
    storebehind => [qw( asynchrony )],
    whereis     => [qw( hosts )],
    whichcell   => [qw( cell )],
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

# XXX: With exceptions, we might need to use Try::Tiny here

$result = $fs->exportafs( type => q{nfs} );
ok( ref $result && $result->isa( q{AFS::Object::CacheManager} ), q{fs->exportafs} );

ok( defined $result->enabled, q{result->enabled} );

foreach my $attr ( qw(convert uidcheck submounts) ) {
    ok( defined $result->$attr, qq{result->$attr} );
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

my ($server) = $result->getServers;
ok( ref $server && $server->isa( q{AFS::Object::Server} ), q{result->getServers} );
foreach my $attr ( qw(server preference) ) {
    ok( defined $server->$attr, qq{server->$attr} );
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

done_testing();
exit 0;

