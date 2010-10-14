package AFS::Object::Partition;

use Moose;
use Carp;

extends qw(AFS::Object);

has q{_headers_byid}   => ( is => q{rw}, isa => q{HashRef}, default => sub { return {}; } );
has q{_headers_byname} => ( is => q{rw}, isa => q{HashRef}, default => sub { return {}; } );

sub getVolumeIds {
    return keys %{ shift->_headers_byid };
}

sub getVolumeNames {
    return keys %{ shift->_headers_byname };
}

sub getVolumeHeaderById {
    return shift->_headers_byid->{ shift . q{} };
}

sub getVolumeHeaderByName {
    return shift->_headers_byname->{ shift . q{} };
}

sub getVolumeHeaders {
    return values %{ shift->_headers_byid };
}

sub getVolumeHeader {

    my $self = shift;
    my (%args) = @_;

    if ( exists $args{id} and exists $args{name} ) {
	croak qq{Invalid arguments: both of 'id' or 'name' may not be specified};
    }

    if ( not exists $args{id} and not exists $args{name} )  {
	croak qq{Invalid arguments: at least one of 'id' or 'name' must be specified};
    }

    if ( exists $args{id} ) {
	return $self->_headers_byid->{ $args{id} };
    }

    if ( exists $args{name} ) {
	return $self->_headers_byname->{ $args{name} };
    }

}

sub _addVolumeHeader {

    my $self = shift;
    my $header = shift;

    if ( not ref $header or not $header->isa( q{AFS::Object::VolumeHeader} ) ) {
	croak qq{Invalid argument: must be an AFS::Object::VolumeHeader object};
    }

    if ( $header->hasAttribute( q{name} ) ) {
	$self->_headers_byname->{ $header->name } = $header;
    }

    $self->_headers_byid->{ $header->id } = $header;

    return 1;

}

1;
