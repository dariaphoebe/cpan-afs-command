package AFS::Object::Principal;

use Moose;

extends qw(AFS::Object);

has q{_owned}      => ( is => q{rw}, isa => q{HashRef}, default => sub { return {}; } );
has q{_membership} => ( is => q{rw}, isa => q{HashRef}, default => sub { return {}; } );

sub _addOwned {
    return shift->_owned->{ shift(@_) }++;
}

sub getOwned {
    return keys %{ shift->_owned };
}

sub _addMembership {
    return shift->_membership->{ shift(@_) }++;
}

sub getMembership {
    return keys %{ shift->_membership };
}

1;
