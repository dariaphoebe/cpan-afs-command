package AFS::Object::VLDB;

use Moose;
use Carp;

extends qw(AFS::Object);

has q{_names} => ( is => q{rw}, isa => q{HashRef}, default => sub { return {}; } );
has q{_ids}   => ( is => q{rw}, isa => q{HashRef}, default => sub { return {}; } );

sub getVolumeNames {
    return keys %{ shift->_names };
}

sub getVolumeIds {
    return keys %{ shift->_ids };
}

sub getVLDBEntry {

    my $self = shift;
    my %args = @_;

    if ( exists $args{id} and exists $args{name} ) {
	croak qq{Invalid arguments: both of 'id' or 'name' may not be specified};
    }

    if ( not exists $args{id} and not exists $args{name} )  {
	croak qq{Invalid arguments: at least one of 'id' or 'name' must be specified};
    }

    if ( exists $args{id} ) {
	return $self->_ids->{ $args{id} };
    }

    if ( exists $args{name} ) {
	return $self->_names->{ $args{name} };
    }

}

sub getVLDBEntryByName {
    return shift->_names->{ shift(@_) };
}

sub getVLDBEntryById {
    return shift->_ids->{ shift . q{} };
}

sub getVLDBEntries {
    return values %{ shift->_names };
}

sub _addVLDBEntry {

    my $self = shift;
    my $entry = shift;

    if ( not ref $entry or not $entry->isa( q{AFS::Object::VLDBEntry} ) ) {
	croak qq{Invalid argument: must be an AFS::Object::VLDBEntry object};
    }

    foreach my $id ( $entry->rwrite, $entry->ronly,
		     $entry->backup, $entry->rclone ) {
	next unless $id; # Some, in fact most, of those won't exist
	$self->_ids->{ $id } = $entry;
    }

    return $self->_names->{ $entry->name } = $entry;

}

1;
