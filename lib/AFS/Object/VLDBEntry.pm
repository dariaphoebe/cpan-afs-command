package AFS::Object::VLDBEntry;

use Moose;

extends qw(AFS::Object);

has q{_sites} => ( is => q{rw}, isa => q{ArrayRef}, default => sub { return []; } );

sub getVLDBSites {
    return @{ shift->_sites };
}

sub _addVLDBSite {
    my $self = shift;
    my $site = shift;
    return push @{ $self->_sites }, $site;
}

1;
