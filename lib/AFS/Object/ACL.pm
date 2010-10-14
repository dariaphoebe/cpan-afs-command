package AFS::Object::ACL;

use Moose;

extends qw(AFS::Object);

has q{_principals} => ( is => q{rw}, isa => q{HashRef}, default => sub { return {}; } );

sub getPrincipals {
    return keys %{ shift->_principals} };
}

sub getRights {
    return shift->_principals->{ lc( shift ) };
}

sub getEntries {
    return %{ shift->_principals };
}

sub _addEntry {
    return shift->_principals->{ lc( shift ) } = shift;
}

1;
