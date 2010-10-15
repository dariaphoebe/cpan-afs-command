package AFS::Object::PTServer;

use Moose;
use Carp;

extends qw(AFS::Object);

has q{_groups_byname} => ( is => q{rw}, isa => q{HashRef}, default => sub { return {}; } );
has q{_groups_byid}   => ( is => q{rw}, isa => q{HashRef}, default => sub { return {}; } );
has q{_users_byname}  => ( is => q{rw}, isa => q{HashRef}, default => sub { return {}; } );
has q{_users_byid}    => ( is => q{rw}, isa => q{HashRef}, default => sub { return {}; } );

sub getGroupNames {
    return keys %{ shift->_groups_byname };
}

sub getGroupIds {
    return keys %{ shift->_groups_byid };
}

sub getGroups {
    return values %{ shift->_groups_byname };
}

sub getGroupByName {
    return shift->_groups_byname->{ shift(@_) };
}

sub getGroupById {
    return shift->_groups_byid->{ shift(@_) };
}

sub getGroup {

    my $self = shift;
    my %args = @_;

    if ( exists $args{id} && exists $args{name} ) {
        croak qq{Invalid arguments: both of 'id' or 'name' may not be specified};
    }

    unless ( exists $args{id} || exists $args{name} )  {
        croak qq{Invalid arguments: at least one of 'id' or 'name' must be specified};
    }

    if ( exists $args{id} ) {
        return $self->_groups_byid->{ $args{id} };
    }

    if ( exists $args{name} ) {
        return $self->_groups_byname->{ $args{name} };
    }

}

sub _addGroup {

    my $self = shift;
    my $group = shift;

    if ( not ref $group or not $group->isa( q{AFS::Object::Group} ) ) {
        croak qq{Invalid argument: must be an AFS::Object::Group object};
    }

    $self->_groups_byname->{ $group->name } = $group;
    $self->_groups_byid->{ $group->id } = $group;

    return 1;

}

sub getUserNames {
    return keys %{ shift->_users_byname };
}

sub getUserIds {
    return keys %{ shift->_users_byid };
}

sub getUsers {
    return values %{ shift->_users_byname };
}

sub getUserByName {
    return shift->_users_byname->{ shift(@_) };
}

sub getUserById {
    return shift->_users_byid->{ shift(@_) };
}

sub getUser {

    my $self = shift;
    my %args = @_;

    if ( exists $args{id} && exists $args{name} ) {
        croak qq{Invalid arguments: both of 'id' or 'name' may not be specified};
    }

    unless ( exists $args{id} || exists $args{name} )  {
        croak qq{Invalid arguments: at least one of 'id' or 'name' must be specified};
    }

    if ( exists $args{id} ) {
        return $self->_users_byid->{ $args{id} };
    }

    if ( exists $args{name} ) {
        return $self->_users_byname->{ $args{name} };
    }

}

sub _addUser {

    my $self = shift;
    my $user = shift;

    if ( not ref $user or not $user->isa( q{AFS::Object::User} ) ) {
        croak qq{Invalid argument: must be an AFS::Object::User object};
    }

    $self->_users_byname->{ $user->name } = $user;
    $self->_users_byid->{ $user->id } = $user;

    return 1;

}

1;
