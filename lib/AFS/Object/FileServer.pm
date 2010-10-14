package AFS::Object::FileServer;

use Moose;

extends qw(AFS::Object);

has q{_partitions} => ( is => q{rw}, isa => q{HashRef}, default => sub { return {}; } );

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

1;
