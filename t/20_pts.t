
use strict;
use English;

use Test::More;
use Test::Exception;
use Data::Dumper;
use Try::Tiny;

use lib q{t/lib};
use Test::AFS::Command;

use blib;
use AFS::Command::PTS;

if ( $ENV{AFS_COMMAND_DISABLE_TESTS} =~ /\bpts\b/ ) {
    plan skip_all => q{vos tests explicitly disabled};
} elsif ( $ENV{AFS_COMMAND_CELLNAME} eq q{your.cell.name} ) {
    plan skip_all => q{No cell name configured};
}

my $cell = $AFS::Command::Tests::Config{AFS_COMMAND_CELLNAME} ||
    die qq{Missing configuration variable AFS_COMMAND_CELLNAME\n};

my $ptsgroup = $AFS::Command::Tests::Config{AFS_COMMAND_PTS_GROUP} ||
    die qq{Missing configuration variable AFS_COMMAND_PTS_GROUP\n};

my $ptsuser = $AFS::Command::Tests::Config{AFS_COMMAND_PTS_USER} ||
    die qq{Missing configuration variable AFS_COMMAND_PTS_USER\n};

my $binary = $AFS::Command::Tests::Config{AFS_COMMAND_BINARY_PTS} || q{pts};

my $pts = AFS::Command::PTS->new( command => $binary );
ok( ref $pts && $pts->isa( q{AFS::Command::PTS} ), q{ AFS::Command::PTS->new} );

my $result = $pts->listmax( cell => $cell );
ok( ref $result && $result->isa( q{AFS::Object::PTServer} ), q{pts->listmax} );

foreach my $attr ( qw( maxuserid maxgroupid ) ) {
    my $id = $result->$attr;
    if ( $attr eq q{maxuserid} ) {
        ok( $id > 0, qq{result->$attr} );
    } else {
        ok( $id < 0, qq{result->$attr} );
    }
}

foreach my $name ( $ptsgroup, $ptsuser ) {

    #
    # First, let's make sure our test IDs aren't defined, so we can
    # redefine them.
    #

    try {
        $pts->delete( nameorid => $name, cell => $cell );
    } catch {
        my @error = @_;
        # XXX: ???
    };

    if ( $result ) {
        print "ok $TestCounter\n";
    } elsif ( defined($pts->errors()) && $pts->errors() =~ /unable to find entry/ ) {
        print "ok $TestCounter\n";
    } else {
        print "not ok $TestCounter..$TestTotal\n";
        die("Unable to delete the test pts id ($name), or verify it doesn't exist\n" .
            Data::Dumper->Dump([$pts],['pts']));
    }
    $TestCounter++;

    my $method  = $name eq $ptsgroup ? q{creategroup} : q{createuser};
    my $type    = $name eq $ptsgroup ? q{Group}       : q{User};
    my $class   = qq{AFS::Object::$type};

    $result = $pts->$method(
        name => $name,
        cell => $cell,
    );
    ok( ref $result && $result->isa( q{AFS::Object::PTServer} ), qq{pts->$method} );

    my $byname  = $name eq $ptsgroup ? q{getGroupByName} : q{getUserByName};
    my $byid    = $name eq $ptsgroup ? q{getGroupById}   : q{getUserById};
    my $getall  = $name eq $ptsgroup ? q{getGroups}      : q{getUsers};

    my $entry = $result->$byname($name);
    ok( ref $entry && $entry->isa($class), qq{result->$byname} );

    my $id = $entry->id;
    if ( $name eq $ptsgroup ) {
        ok( $id < 0, q{entry->id} );
    } else {
        ok( $id > 0, q{entry->id} );
    }

    $entry = $result->$byid($id);
    ok( ref $entry && $entry->isa($class), qq{result->$byid} );

    my $othername = $entry->name();
    ok( $name eq $othername, q{entry->name} );

    ($entry) = $result->$getall();
    ok( ref $entry && $entry->isa($class), qq{result->$getall} );

    $result = $pts->examine(
        nameorid => $name,
        cell     => $cell,
    );
    ok( ref $result && $result->isa( q{AFS::Object::PTServer} ), q{pts->examine} );

    ($entry) = $result->$getall();
    ok( ref $entry && $entry->isa($class), qq{result->$getall} );

    foreach my $attr ( qw( name id owner creator membership flags groupquota ) ) {
        ok( defined $entry->$attr, qq{entry->$attr} );
    }

}

ok(
    $pts->chown(
        name  => $ptsgroup,
        owner => $ptsuser,
        cell  => $cell,
    ),
    q{pts->chown},
);

$result = $pts->listowned(
    nameorid => $ptsuser,
    cell     => $cell,
);
ok( ref $result && $result->isa( q{AFS::Object::PTServer} ), q{pts->listowned} );

my ($user) = $result->getUsers;
ok( ref $user && $user->isa( q{AFS::Object::User} ), q{result->getUsers} );

my @owned = $user->getOwned;
ok( $#owned == 0 && $owned[0] eq $ptsgroup, q{user->getOwned} );

ok(
    $pts->adduser(
        user  => $ptsuser,
        group => $ptsgroup,
        cell  => $cell,
    ),
    q{pts->adduser},
);

foreach my $name ( $ptsgroup, $ptsuser ) {

    $result = $pts->membership(
        nameorid => $name,
        cell     => $cell,
    );
    ok( ref $result && $result->isa( q{AFS::Object::PTServer} ), q{pts-<membership} );

    my $type    = $name eq $ptsgroup ? q{Group} : q{User};
    my $class   = qq{AFS::Object::$type};
    my $getall  = $name eq $ptsgroup ? q{getGroups} : q{getUsers};

    my ($entry) = $result->$getall;
    ok( ref $entry && $entry->isa($class), qq{result->$getall} );

    my @membership = $entry->getMembership;
    ok( $#membership == 0, q{entry->getMembership} );

    if ( $name eq $ptsgroup ) {
        ok( $membership[0] eq $ptsuser, q{correct membership} );
    } else {
        ok( $membership[0] eq $ptsgroup, q{correct membership} );
    }

}

if ( $pts->supportsOperation( q{listentries} ) ) {

    foreach my $name ( $ptsgroup, $ptsuser ) {

        my $flag        = $name eq $ptsgroup ? q{groups} : q{users};
        my $type        = $name eq $ptsgroup ? q{Group}  : q{User};
        my $class       = qq{AFS::Object::$type};
        my $getentry    = $name eq $ptsgroup ? q{getGroupByName} : q{getUserByName};

        my $result = $pts->listentries(
            cell  => $cell,
            $flag => 1,
        );
        ok( ref $result && $result->isa( q{AFS::Object::PTServer} ), q{pts->listentries} );

        my $entry = $result->$getentry($name);
        ok( ref $entry && $entry->isa($class), qq{result->$getentry} );

        foreach my $attr ( qw(id owner creator) ) {
            ok( defined $entry->$attr, qq{entry->$attr} );
        }

    }

}

$result = $pts->membership(
    nameorid => q{ThisSurelyDoesNotExist},
    cell     => $cell,
);
ok( ref $result && $result->isa( q{AFS::Object::PTServer} ), q{pts->membership} );

done_testing();
exit 0;
