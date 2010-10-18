
use strict;
use English;

use Test::More;
use Test::Exception;
use Data::Dumper;

use lib q{t/lib};
use Test::AFS::Command;

use blib;
use AFS::Command::VOS;

if ( $ENV{AFS_COMMAND_DISABLE_TESTS} =~ /\bvos\b/ ) {
    plan skip_all => q{vos tests explicitly disabled};
} elsif ( $ENV{AFS_COMMAND_CELLNAME} eq q{your.cell.name} ) {
    plan skip_all => q{No cell name configured};
}

my $volname_prefix = $ENV{AFS_COMMAND_VOLNAME_PREFIX} || 
    die qq{Missing configuration variable AFS_COMMAND_VOLNAME_PREFIX\n};

my $cell = $ENV{AFS_COMMAND_CELLNAME} ||
    die qq{Missing configuration variable AFS_COMMAND_CELLNAME\n};

my $partition_list = $ENV{AFS_COMMAND_PARTITION_LIST} ||
    die qq{Missing configuration variable AFS_COMMAND_PARTITION_LIST\n};

my $binary = $ENV{AFS_COMMAND_BINARY_VOS} || q{vos};

my %enabled = (
    gzip    => $ENV{AFS_COMMAND_GZIP_ENABLED},
    bzip2   => $ENV{AFS_COMMAND_BZIP2_ENABLED},
    gunzip  => $ENV{AFS_COMMAND_GZIP_ENABLED},
    bunzip2 => $ENV{AFS_COMMAND_BZIP2_ENABLED},
);

my $dumpfilter    = $ENV{AFS_COMMAND_DUMP_FILTER};
my $restorefilter = $ENV{AFS_COMMAND_RESTORE_FILTER};
my $tmproot       = $ENV{AFS_COMMAND_TMP_ROOT};

my @servers             = ();
my @partitions          = ();
my $server_primary      = q{};
my $partition_primary   = q{};

foreach my $serverpart ( split m{\s+}msx, $partition_list ) {

    my ($server,$partition) = split m{:}msx, $serverpart;

    if ( not $server or not $partition ) {
        die qq{Invalid server:/partition specification: '$serverpart'\n};
    }

    $server_primary    ||= $server;
    $partition_primary ||= $partition;

    push @servers,    $server;
    push @partitions, $partition;

}

my $vos = AFS::Command::VOS->new( command => $binary );
ok( ref $vos && $vos->isa( q{AFS::Command::VOS} ), q{AFS::Command::VOS->new} );

my $volname          = qq{$volname_prefix.basic.$PID};
my $volname_readonly = qq{$volname.readonly};

ok(
    $vos->create(
        server    => $server_primary,
        partition => $partition_primary,
        name      => $volname,
        cell      => $cell,
    ),
    q{vos->create},
);

throws_ok {
    $vos->examine( id => $volname, cell => $cell, format => 1 );
} qr{Unsupported 'vos examine' argument: -format}ms,
    q{vos->examine raises exception when format is used};

ok( ! $vos->examine( id => q{nosuchvolume}, cell => $cell ),
    q{vos->examine returns false for no vldb entry} );

throws_ok {
    $vos->examine( id => q{nosuchvolume}, cell => q{nosuchcell} );
} qr{can.t find cell nosuchcell's hosts}ms,
    q{vos->examine raises exception for bogus cell name};

my $result = $vos->examine( id => $volname, cell => $cell );
ok( ref $result && $result->isa( q{AFS::Object::Volume} ) );

# First, sanity check the volume header.  There should be ONE of them only.
my @headers = $result->getVolumeHeaders;
ok( $#headers == 0, q{result->getVolumeHeaders count} );

my $header = $headers[0];
ok( ref $header && $header->isa( q{AFS::Object::VolumeHeader} ), q{header object} );

ok( $header->name eq $volname, q{header->name} );
ok( $header->partition eq $partition_primary, q{header->partition} );
ok( $header->server eq $server_primary, q{header->server} );
ok( $header->type eq q{RW}, q{header->type} );

# Check the volume IDs.  rwrite should be numeric, ronly and
# backup should be 0.
my $rwrite = $header->rwrite;

ok( $rwrite =~ m{^\d+$}ms, q{header->rwrite} );
ok( $header->ronly == 0, q{header->ronly} );
ok( $header->backup == 0, q{header->backup} );

# This is a new volume, so access should be 0, and size 2
ok( $header->accesses == 0, q{header->accesses} );
ok( $header->size == 2, q{header->size} );

# Both the update and creation times should be ctime values.
# NOTE: This test may very well break if LANG is set, and
# affects vos output syntax.  Note that in that case, we'll
# need code in VOS.pm to deal with more generic time strings.
foreach my $method ( qw( update creation ) ) {
    ok( $header->$method =~ m{^\S+\s+\S+\s+\d+\s+\d{2}:\d{2}:\d{2}\s+\d{4}$}ms,
        qq{header->$method} );
}

# Finally, maxauota must be numeric, and status should be 'online'
ok( $header->maxquota =~ m{^\d+$}ms, q{header->maxquota} );
ok( $header->status eq q{online}, q{header->status} );

# Second, we check the VLDB entry for this volume.
my $vldbentry = $result->getVLDBEntry;
ok( ref $vldbentry && $vldbentry->isa( q{AFS::Object::VLDBEntry} ), q{result->getVLDBEntry} );
ok( $vldbentry->rwrite =~ m{^\d+$}ms, q{vldbentry->rwrite is numeric} );

# This should match the rwrite ID found in the volume headers, too.
ok( $vldbentry->rwrite == $rwrite, q{vldbentry->rwrite matches header->rwrite} );

my @vldbsites = $vldbentry->getVLDBSites;
ok( $#vldbsites == 0, q{vldbentry->getVLDBSites count} );

my $vldbsite = $vldbsites[0];
ok( ref $vldbsite && $vldbsite->isa( q{AFS::Object::VLDBSite} ), q{vldbentry->getVLDBSites object} );
ok( $vldbsite->partition eq $partition_primary, q{vldbsite->partition} );
ok( $vldbsite->server eq $server_primary, q{vldbsite->server} );

# Create a backup, an verify that the changes in the examine output.
ok(
    $vos->backup(
        id   => $volname,
        cell => $cell,
    ),
    q{vos->backup},
);

$result = $vos->examine(
    id   => $volname,
    cell => $cell,
);
ok( ref $result && $result->isa( q{AFS::Object::Volume} ), q{vos->examine} );

@headers = $result->getVolumeHeaders;
ok( $#headers == 0, q{result->getVolumeHeaders count} );

$header = $headers[0];
$rwrite = 0;

ok( ref $header && $header->isa( q{AFS::Object::VolumeHeader} ), q{header object});

# This time through, we're looking for just the things we
# expect a vos backup to change, and nothing else.
ok( $header->backup =~ m{^\d+$}ms, q{header->backup numeric} );
ok( $header->backup > 0,  q{header->backup non-zero} );

# Now let's add the other replica sites, and release the volume.
for ( my $index = 0 ; $index <= $#servers ; $index++ ) {
    ok(
        $vos->addsite(
            id        => $volname,
            server    => $servers[$index],
            partition => $partitions[$index],
            cell      => $cell,
        ),
        q{vos->addsite},
    );
}

ok( ! $vos->listvldb( name => q{nosuchvolume}, cell => $cell ),
    q{vos->listvldb returns false for no vldb entry} );

throws_ok {
    $vos->listvldb( name => q{nosuchvolume}, cell => q{nosuchcell} );
} qr{can.t find cell nosuchcell's hosts}ms,
    q{vos->listvldb raises exception for bogus cell name};

$result = $vos->listvldb( name => $volname, cell => $cell );
ok( ref $result && $result->isa( q{AFS::Object::VLDB} ), q{vos->listvldb} );

my @volnames = $result->getVolumeNames;
ok( $#volnames == 0, q{result->getVolumeNames count} );

my $volname_queried = $volnames[0];
ok( $volname eq $volname_queried, q{volname is correct} );

$vldbentry = $result->getVLDBEntryByName($volname);
ok( ref $vldbentry && $vldbentry->isa("AFS::Object::VLDBEntry"), q{result->getVLDBEntryByName} );

$rwrite = $vldbentry->rwrite;
my $altentry = $result->getVLDBEntryById($rwrite);
ok( ref $altentry && $altentry->isa("AFS::Object::VLDBEntry"), q{result->getVLDBEntryById} );
ok( $altentry->rwrite == $rwrite, q{altentry->rwrite} );
ok( $altentry->name eq $volname, q{altentry->name} );

@vldbsites = $vldbentry->getVLDBSites;
ok( $#vldbsites == ($#servers+1), q{vldbentry->getVLDBSites count} );

for ( my $index = 0 ; $index <= $#vldbsites ; $index++ ) {

    my $vldbsite = $vldbsites[$index];

    my $serverindex = $index - 1;
    $serverindex = 0 if $serverindex == -1;

    ok( $vldbsite->server eq $servers[$serverindex], q{vldbsite->server} );
    ok( $vldbsite->partition eq $partitions[$serverindex], q{vldbsite->partition} );

    my $typeshould = $index == 0 ? q{RW} : q{RO};
    ok( $vldbsite->type eq $typeshould, q{vldbsite->site} );

    my $statusshould = $index == 0 ? q{} : q{Not released};
    ok( $vldbsite->status eq $statusshould, q{vldbsite->status} );

}

foreach my $force ( qw( none f force ) ) {
    ok(
        $vos->release(
            id   => $volname,
            cell => $cell,
            ($force eq q{none} ? () : ( $force => 1 ) ),
        ),
        qq{vos->release with force=$force}
    );
}



# The volume is released, so now, let's examine the readonly, and make
# sure we get the correct volume headers.
$result = $vos->examine(
    id   => $volname_readonly,
    cell => $cell,
);
ok( ref $result && $result->isa( q{AFS::Object::Volume} ), q{vos->examine} );

@headers = $result->getVolumeHeaders;
ok( $#headers == $#servers, q{result->getVolumeHeaders count} );

for ( my $index = 0 ; $index <= $#headers ; $index++ ) {
    my $header = $headers[$index];
    ok( $header->name eq $volname_readonly, qq{header->name $index} );
    ok( $header->partition eq $partitions[$index], qq{header->partition $index} );
    ok( $header->server eq $servers[$index], qq{header->server $index} );
    ok( $header->type eq q{RO}, qq{header->type $index} );
}

# Finally, let's clean up after ourselves.
for ( my $index = 0 ; $index <= $#servers ; $index++ ) {
    ok(
        $vos->remove(
            id        => $volname_readonly,
            server    => $servers[$index],
            partition => $partitions[$index],
            cell      => $cell,
        ),
        qq{vos->remove, $index},
    );
}

# Test the vos offline functionality, if supported.
if ( $vos->supportsOperation( q{offline} ) ) {

    foreach my $method ( qw(offline online) ) {

        ok(
            $vos->$method(
                id        => $volname,
                server    => $servers[0],
                partition => $partitions[0],
                cell      => $cell,
            ),
            qq{vos->$method},
        );

        $result = $vos->examine(
            id   => $volname,
            cell => $cell,
        );
        ok( ref $result && $result->isa( q{AFS::Object::Volume} ), q{vos->examine} );

        my ($header) = $result->getVolumeHeaders;
        ok( $header->status eq $method, q{header->status, $method} );
        ok( $header->attached, q{header->attached} );

    }

}

ok(
    $vos->remove(
        id        => $volname,
        server    => $servers[0],
        partition => $partitions[0],
        cell      => $cell,
    ),
    q{vos->remove},
);

# Dump/restore tests

$volname = qq{$volname_prefix.dumprest.$PID};

ok(
    $vos->create(
        server    => $server_primary,
        partition => $partition_primary,
        name      => $volname,
        cell      => $cell,
    ),
    q{vos->create},
);

# OK, let's create a few dump files, in different ways.
# First, a vanilla dump, nothing special.
my %files = (
    raw     => qq{$tmproot/$volname.dump},
    gzip    => qq{$tmproot/$volname.dump.gz},
    bzip2   => qq{$tmproot/$volname.dump.bz2},
    gunzip  => qq{$tmproot/$volname.dump.gz},
    bunzip2 => qq{$tmproot/$volname.dump.bz2},
);

ok(
    $vos->dump(
        id   => $volname,
        time => 0,
        file => $files{raw},
        cell => $cell,
    ),
    q{vos->dump},
);

foreach my $ctype ( qw(gzip bzip2) ) {

    next if not $enabled{$ctype};

    # Now, with *implicit* use of gzip (via the filename)
    ok(
        $vos->dump(
            id   => $volname,
            time => 0,
            file => $files{$ctype},
            cell => $cell,
        ),
        qq{vos->dump implicit $ctype},
    );

    ok( -f $files{$ctype}, q{vos->dump implicit created a file} );

    # Next, explicitly, using the gzip/bzip2 argument
    ok(
        $vos->dump(
            id     => $volname,
            time   => 0,
            file   => $files{raw},
            cell   => $cell,
            $ctype => 4,
        ),
        qq{vos->dump explicit $ctype},
    );

    ok( -f $files{$ctype}, q{vos->dump explicit created a file} );

    # Finally, when both are given.
    ok(
        $vos->dump(
            id     => $volname,
            time   => 0,
            file   => $files{$ctype},
            cell   => $cell,
            $ctype => 4,
        ),
        q{vos->dump both implicit/explicit},
    );

    ok( -f $files{$ctype}, q{vos->dump implicit/explicit created a file} );

}

if ( $dumpfilter ) {

    ok(
        $vos->dump(
            id        => $volname,
            time      => 0,
            file      => $files{raw},
            cell      => $cell,
            filterout => [ $dumpfilter ],
        ),
        q{vos->dump with dumpfilter},
    );

    my ($ctype) = ( $enabled{gzip} ?  q{gzip}  :
                    $enabled{bzip2} ? q{bzip2} : q{} );

    if ( $ctype ) {
        ok(
            $vos->dump(
                id        => $volname,
                time      => 0,
                file      => $files{$ctype},
                cell      => $cell,
                filterout => [ $dumpfilter ],
            ),
            q{vos->dump with dumpfilter and compression},
        );
    }

}

# Finally, let's remove that volume, so we can reuse the name for the
# restore tests.
ok(
    $vos->remove(
        server    => $server_primary,
        partition => $partition_primary,
        id        => $volname,
        cell      => $cell,
    ),
    q{vos->remove},
);

# If we made it this far, dump works fine.  Now let's test restore...
ok(
    $vos->restore(
        server               => $server_primary,
        partition            => $partition_primary,
        name                 => $volname,
        file                 => $files{raw},
        overwrite            => q{full},
        cell                 => $cell,
    ),
    q{vos->restore},
);

foreach my $ctype ( qw(gunzip bunzip2) ) {
    next if not $enabled{$ctype};
    ok(
        $vos->restore(
            server    => $server_primary,
            partition => $partition_primary,
            name      => $volname,
            file      => $files{$ctype},
            overwrite => q{full},
            cell      => $cell,
        ),
        qq{vos->restore with $ctype},
    );
}

if ( $restorefilter ) {

    ok(
        $vos->restore(
            server    => $server_primary,
            partition => $partition_primary,
            name      => $volname,
            file      => $files{raw},
            overwrite => 'full',
            cell      => $cell,
            filterin  => [$restorefilter],
        ),
        q{vos->restore with restorefilter},
    );

    my ($ctype) = ( $enabled{gunzip}  ? q{gunzip}  :
                    $enabled{bunzip2} ? q{bunzip2} : q{} );

    if ( $ctype ) {
        ok(
            $vos->restore(
                server    => $server_primary,
                partition => $partition_primary,
                name      => $volname,
                file      => $files{$ctype},
                overwrite => q{full},
                cell      => $cell,
                filterin  => [$restorefilter],
            ),
            q{vos->restore with restorefilter and compression},
        );
    }

}

ok(
    $vos->remove(
        server    => $server_primary,
        partition => $partition_primary,
        id        => $volname,
        cell      => $cell,
    ),
    q{vos->remove},
);

# volserver tests

my $listpart = $vos->listpart(
   server => $server_primary,
   cell   => $cell,
);
ok( ref $listpart && $listpart->isa( q{AFS::Object::FileServer} ), q{vos->listpart} );

my $partinfo = $vos->partinfo(
    server => $server_primary,
    cell   => $cell,
);
ok( ref $partinfo && $partinfo->isa( q{AFS::Object::FileServer} ), q{vos->partinfo} );

foreach my $objectpair ( [ $partinfo, $listpart ], [ $listpart, $partinfo ] ) {

    my ($src,$dst) = @$objectpair;

    my @partitions = $src->getPartitionNames;
    ok( @partitions, q{getPartitionNames} );

    foreach my $partname ( @partitions ) {
        my $partition = $dst->getPartition($partname);
        ok( ref $partition && $partition->isa( q{AFS::Object::Partition} ), q{getPartition(name)} );
        if ( $partition->hasAttribute( q{available} ) ) {
            my $available = $partition->available;
            my $total     = $partition->total;
            ok( $available =~ m{^\d+$}ms && $total =~ m{^\d+$}ms && $available < $total,
                q{available/total values} );
        }
    }

}

if ( $vos->supportsArgument( q{partinfo}, q{summary} ) ) {
    foreach my $attr ( qw( available total partitions ) ) {
        ok( $partinfo->$attr =~ m{^\d+$}ms,
            qq{partinfo->$attr returned when partinfo supports summary} );
    }
}

throws_ok {
    $vos->listvol(
        server => $server_primary,
        cell   => $cell,
        format => 1,
    );
} qr{Unsupported 'vos listvol' argument: -format}ms,
    q{vos->listvol raises exception when format is used};

my $listvol = $vos->listvol(
   server => $server_primary,
   cell   => $cell,
   fast   => 1,
);
ok( ref $listvol && $listvol->isa( q{AFS::Object::VolServer} ), q{vos->listvol} );

my $listpart_names = { map { $_ => 1 } $listpart->getPartitionNames };
my $listvol_names  = { map { $_ => 1 } $listvol->getPartitionNames };

foreach my $hashpair ( [ $listpart_names, $listvol_names ],
                       [ $listvol_names, $listpart_names ] ) {
    my ($src,$dst) = @$hashpair;
    foreach my $partname ( keys %$src ) {
        ok( $dst->{$partname}, q{listvol/listpart partition name} );
    }
}

$listvol = $vos->listvol(
   server    => $server_primary,
   partition => $partition_primary,
   cell      => $cell,
);
ok( ref $listvol && $listvol->isa( q{AFS::Object::VolServer} ), q{vos->listvol} );

my $partition = $listvol->getPartition($partition_primary);
ok( ref $partition && $partition->isa( q{AFS::Object::Partition} ), q{listvol->getPartition} );

my @ids = $partition->getVolumeIds;
ok( @ids, q{partition->getVolumeIds} );

foreach my $id ( @ids ) {

    ok( $id =~ m{^\d+$}ms, q{id is numeric} );

    my $volume_byid = $partition->getVolumeHeaderById($id);
    ok( ref $volume_byid && $volume_byid->isa( q{AFS::Object::VolumeHeader} ),
        q{partition->getVolumeHeaderById} );

    my $volume_generic = $partition->getVolumeHeader( id => $id );
    ok( ref $volume_generic && $volume_generic->isa( q{AFS::Object::VolumeHeader} ),
        q{partition->getVolumeHeader} );

    ok( $volume_byid->id == $volume_generic->id, q{ids match} );

}

my @names = $partition->getVolumeNames;
ok( @names, q{partition->getVolumeNames} );

my $volume_online = q{};

foreach my $name ( sort @names ) {

    my $volume_byname = $partition->getVolumeHeaderByName($name);
    ok( ref $volume_byname && $volume_byname->isa( q{AFS::Object::VolumeHeader} ),
        q{partition->getVolumeHeaderByName} );

    my $volume_generic = $partition->getVolumeHeader( name => $name );
    ok( ref $volume_generic && $volume_generic->isa( q{AFS::Object::VolumeHeader} ),
        q{partition->getVolumeHeader} );

    ok( $volume_byname->name eq $volume_generic->name, q{names match} );

    if ( $volume_byname->status eq q{online} && not ref $volume_online ) {
        $volume_online = $volume_byname;
    }

}

# Since we trust examine by this point, we can examine the one online
# volume we kept track of, and make sure the headers match.
$volname = $volume_online->name;

my $examine = $vos->examine(
   id   => $volname,
   cell => $cell,
);
ok( ref $examine && $examine->isa( q{AFS::Object::Volume} ), q{vos->examine} );

@headers = $examine->getVolumeHeaders;
ok( @headers, q{examine->getVolumeHeaders} );

my $volume_header = q{};

foreach my $header ( @headers ) {
    ok( ref $header && $header->isa( q{AFS::Object::VolumeHeader} ), q{header object} );
    if ( $header->server      eq $server_primary &&
         $header->partition   eq $partition_primary ) {
        $volume_header = $header;
        last;
    }
}

ok( ref $volume_header && $volume_header->isa( q{AFS::Object::VolumeHeader} ),
    q{found matching header} );

ok( ! $vos->size( id => q{nosuchvolume}, cell => $cell ),
    q{vos->size return false for no vldb entry} );

throws_ok {
    $vos->size( id => q{nosuchvolume}, cell => q{nosuchcell} );
} qr{can.t find cell nosuchcell's hosts}ms,
    q{vos->size raises exception for bogus cell name};

$result = $vos->size( id => q{root.afs}, cell => $cell );
ok( ref $result && $result->isa( q{AFS::Object} ), q{vos->size returns correct object} );
ok( $result->volume eq q{root.afs}, q{vos->size->volume} );
ok( $result->dump_size =~ m{^\d+$}ms, q{vos->size->dump_size} );

done_testing();
exit 0;

