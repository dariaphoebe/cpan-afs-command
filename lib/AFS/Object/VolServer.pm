package AFS::Object::VolServer;

use Moose;
use Carp;

extends qw(AFS::Object);

has q{_partitions} => ( is => q{rw}, isa => q{HashRef}, default => sub { return {}; } );
has q{_volumes}    => ( is => q{rw}, isa => q{HashRef}, default => sub { return {}; } );

sub getPartitionNames {
    return keys %{ shift->_partitions };
}

sub getPartitions {
    return values %{ shift->_partitions };
}

sub getPartition {
    return shift->_partitions->{ shift(@_) };
}

sub _addPartition {
    my $self = shift;
    my $partition = shift;
    return $self->_partitions->{ $partition->partition } = $partition;
}

sub getTransactions {
    return values %{ shift->_volumes };
}

sub getVolumes {
    return keys %{ shift->_volumes };
}

sub getTransactionByVolume {
    return shift->_volumes->{ shift(@_) };
}

sub _addTransaction {

    my $self = shift;
    my $transaction = shift;

    if ( not ref $transaction or not $transaction->isa( q{AFS::Object::Transaction} ) ) {
	croak qq{Invalid argument: must be an AFS::Object::Transaction object};
    }

    if ( not $transaction->volume ) {
	croak qq{Invalid AFS::Object::Transaction object: has no 'volume' attribute};
    }

    return $self->_volumes->{ $transaction->volume } = $transaction;

}

1;
