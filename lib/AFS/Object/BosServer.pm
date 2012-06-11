package AFS::Object::BosServer;

our $VERSION = '2.000_001';
$VERSION = eval $VERSION;  ##  no critic: StringyEval

use Moose;
use Carp;

extends qw(AFS::Object);

has q{_instances} => ( is => q{rw}, isa => q{HashRef}, default => sub { return {}; } );
has q{_files}     => ( is => q{rw}, isa => q{HashRef}, default => sub { return {}; } );
has q{_keys}      => ( is => q{rw}, isa => q{HashRef}, default => sub { return {}; } );

sub getInstanceNames {
    return keys %{ shift->_instances };
}

sub getInstance {
    return shift->_instances->{ shift(@_) };
}

sub getInstances {
    return values %{ shift->_instances };
}

sub _addInstance {
    my $self = shift;
    my $instance = shift;
    $instance->instance or croak q{Invalid instance object};
    return $self->_instances->{ $instance->instance } = $instance;
}

sub getFileNames {
    return keys %{ shift->_files };
}

sub getFile {
    return shift->_files->{ shift(@_) };
}

sub getFiles {
    return values %{ shift->_files };
}

sub _addFile {
    my $self = shift;
    my $file = shift;
    $file->file or croak q{Invalid file object};
    return $self->_files->{ $file->file } = $file;
}

sub getKeyIndexes {
    return keys %{ shift->_keys };
}

sub getKey {
    return shift->_keys->{ shift(@_) };
}

sub getKeys {
    return values %{ shift->_keys };
}

sub _addKey {
    my $self = shift;
    my $key = shift;
    defined( $key->index ) or croak q{Invalid key object};
    return $self->_keys->{ $key->index } = $key;
}

1;

