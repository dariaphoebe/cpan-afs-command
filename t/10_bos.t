
use strict;
use English;

use Test::More;
use Test::Exception;
use Data::Dumper;

use lib q{t/lib};
use Test::AFS::Command;

use blib;
use AFS::Command::BOS;

if ( $ENV{AFS_COMMAND_DISABLE_TESTS} =~ /\bbos\b/ ) {
    plan skip_all => q{bos tests explicitly disabled};
} elsif ( $ENV{AFS_COMMAND_CELLNAME} eq q{your.cell.name} ) {
    plan skip_all => q{No cell name configured};
}

my $cell = $AFS::Command::Tests::Config{AFS_COMMAND_CELLNAME} || 
    die qq{Missing configuration variable AFS_COMMAND_CELLNAME\n};

my $dbserver = $AFS::Command::Tests::Config{AFS_COMMAND_DBSERVER} ||
    die qq{Missing configuration variable AFS_COMMAND_PARTITION_LIST\n};

my $binary = $AFS::Command::Tests::Config{AFS_COMMAND_BINARY_BOS} || q{bos};

my $bos = AFS::Command::BOS->new( command => $binary );
ok( ref $bos && $bos->isa( q{AFS::Command::BOS} ), q{AFS::Command::BOS->new} );

my $result = $bos->getdate(
   server => $dbserver,
   cell   => $cell,
   file   => q{bosserver},
);
ok( ref $result && $result->isa( q{AFS::Object} ), q{bos->getdate} );

my @files = $result->getFileNames;
ok( grep { $_ eq q{bosserver} } @files, q{result->getFileNames} );

my $file = $result->getFile( q{bosserver} );
ok( ref $file && $file->isa( q{AFS::Object} ), q{result->getFile} );
ok( $file->date, q{file->date} );

$result = $bos->getlog(
    server => $dbserver,
    cell   => $cell,
    file   => q{/usr/afs/logs/BosLog},
);
ok( ref $result && $result->isa( q{AFS::Object::BosServer} ), q{bos->getlog} );

my $log = $result->log;
ok( $log, q{result->log} );

my ($firstline) = split m{\n+}, $log;

my $tmpfile = qq{/var/tmp/.bos.getlog.results.$PID};

$result = $bos->getlog(
    server   => $dbserver,
    cell     => $cell,
    file     => q{/usr/afs/logs/BosLog},
    redirect => $tmpfile,
);
ok( ref $result && $result->isa( q{AFS::Object::BosServer} ), q{bos->getlog with redirect} );

$log = $result->log;
ok( $log eq $tmpfile, q{bos->getlog returns correct filename} );

my $io = IO::File->new($tmpfile) || 
    die qq{Unable to read $tmpfile: $ERRNO\n};

ok( $io->getline eq qq{$firstline\n}, q{bos->getlog file contents are correct} );

$result = $bos->getrestart(
    server => $dbserver,
    cell   => $cell,
);
ok( ref $result && $result->isa( q{AFS::Object::BosServer} ), q{bos->getrestart} );

ok( $result->restart,  q{result->restart} );
ok( $result->binaries, q{result->binaries} );

$result = $bos->listhosts(
   server => $dbserver,
   cell   => $cell,
);
ok( ref $result && $result->isa( q{AFS::Object::BosServer} ), q{bos->listhosts} );

ok( $result->cell eq $cell, q{result->cell} );

my $hosts = $result->hosts;
ok( ref $hosts eq q{ARRAY}, q{result->hosts} );

$result = $bos->listkeys(
    server => $dbserver,
    cell   => $cell,
);
ok( ref $result && $result->isa( q{AFS::Object::BosServer} ), q{bos->listkeys} );

my @indexes = $result->getKeyIndexes;
ok( @indexes, q{result->getKeyIndexes} );

foreach my $index ( @indexes ) {
    my $key = $result->getKey($index);
    ok( ref $key && $key->isa( q{AFS::Object} ), q{result->getKey} );
    ok( $key->cksum, q{key->cksum} );
}

$result = $bos->listusers(
    server => $dbserver,
    cell   => $cell,
);
ok( ref $result && $result->isa( q{AFS::Object::BosServer} ), q{bos->listusers} );

my $susers = $result->susers;
ok( ref $susers eq q{ARRAY}, q{result->susers} );

$result = $bos->status(
    server => $dbserver,
    cell   => $cell,
);
ok( ref $result && $result->isa( q{AFS::Object::BosServer} ), q{bos->status} );

my @instancenames = $result->getInstanceNames;
ok( @instancenames, q{result->getInstanceNames} );

foreach my $name ( qw(vlserver ptserver) ) {
    ok( grep { $_ eq $name } @instancenames, qq{found instance name $name} );
    my $instance = $result->getInstance($name);
    ok( ref $instance && $instance->isa( q{AFS::Object::Instance} ), q{result->getInstance} );
    ok( $instance->status, q{instance->status} );
}

$result = $bos->status(
    server => $dbserver,
    cell   => $cell,
    long   => 1,
);
ok( ref $result && $result->isa( q{AFS::Object::BosServer} ), q{bos->status} );

foreach my $name ( qw(vlserver ptserver) ) {

    my $instance = $result->getInstance($name);
    ok( ref $instance && $instance->isa( q{AFS::Object::Instance} ), q{result->getInstance} );

    foreach my $attr ( qw(status type startdate startcount) ) {
        ok( $instance->$attr, qq{instance->$attr} );
    }

    my @commands = $instance->getCommands;
    ok( $#commands == 0, q{instance->getCommands} );

    my $command = $commands[0];
    ok( $command->index == 1, q{command->index} );

    ok( $command->command =~ m{$name}ms, q{command->command} );

}

done_testing();
exit 0;
