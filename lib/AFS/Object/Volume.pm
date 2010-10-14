package AFS::Object::Volume;

use Moose;

extends qw(AFS::Object);

has q{_vldbentry} => ( is => q{rw}, isa => q{AFS::Object::VLDBEntry} );
has q{_headers}   => ( is => q{rw}, isa => q{ArrayRef[AFS::Object::VolumeHeader]},
                       default => sub { return []; } );

sub getVolumeHeaders {
    return @{ shift->_headers };
}

sub _addVolumeHeader {
    return push @{ shift->_headers }, shift;
}

sub getVLDBEntry {
    return shift->_vldbentry;
}

sub _addVLDBEntry {
    return shift->_vldbentry( shift );
}

1;

