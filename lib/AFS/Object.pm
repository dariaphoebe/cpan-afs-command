package AFS::Object;

use Moose;
use Carp;

our $AUTOLOAD = q{};

has q{_attrs} => ( is => q{rw}, isa => q{HashRef}, default => sub { return {}; } );

sub BUILD {
    shift->_attrs( shift );
}

sub listAttributes {
    return keys %{ shift->_attrs };
}

sub getAttribute {
    return shift->_attrs->{ shift(@_) };
}

sub getAttributes {
    return %{ shift->_attrs };
}

sub hasAttribute {
    return exists shift->_attrs->{ shift(@_) };
}

sub _setAttribute {
    my $self = shift;
    my (%data) = @_;
    foreach my $attr ( keys %data ) {
        $self->_attrs->{$attr} = $data{$attr};
    }
    return 1;
}

sub AUTOLOAD {
    my $self = shift;
    my $attr = $AUTOLOAD;
    $attr =~ s{.*::}{}ms;
    return $self->getAttribute( $attr );
}

1;
