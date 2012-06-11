package AFS::Object::VLDBEntry;

our $VERSION = '2.000_001';
$VERSION = eval $VERSION;  ##  no critic: StringyEval

use Moose;

extends qw(AFS::Object);

has q{_sites} => ( is => q{rw}, isa => q{ArrayRef}, default => sub { return []; } );

sub getVLDBSites {
    return @{ shift->_sites };
}

sub _addVLDBSite {
    return push @{ shift->_sites }, shift;
}

1;
