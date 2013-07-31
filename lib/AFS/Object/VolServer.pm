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
    $partition->partition or croak q{Invalid partition object};
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
    $transaction->volume or croak qq{Invalid transaction object};
    return $self->_volumes->{ $transaction->volume } = $transaction;
}

1;
