package AFS::Object::ACL;

our $VERSION = '2.000_001';
$VERSION = eval $VERSION;  ##  no critic: StringyEval

use Moose;

extends qw(AFS::Object);

has q{_principals} => ( is => q{rw}, isa => q{HashRef}, default => sub { return {}; } );

sub getPrincipals {
    return keys %{ shift->_principals };
}

sub getRights {
    return shift->_principals->{ shift(@_) };
}

sub getEntries {
    return %{ shift->_principals };
}

sub _addEntry {
    # return shift->_principals->{ shift(@_) } = shift;
    my $self = shift;
    my $principal = shift;
    my $rights = shift;
    $self->_principals->{ $principal } = $rights;
}

1;
