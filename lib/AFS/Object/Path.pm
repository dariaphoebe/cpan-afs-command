package AFS::Object::Path;

use Moose;

extends base qw(AFS::Object);

has q{_acl_normal}   => ( is => q{rw}, isa => q{AFS::Object::ACL} );
has q{_acl_negative} => ( is => q{rw}, isa => q{AFS::Object::ACL} );

sub getACL {
    my $self = shift;
    my $type = shift || 'normal';
    return $self->_acl_normal   if $type eq q{normal};
    return $self->_acl_negative if $type eq q{negative};
}

sub getACLNormal {
    return shift->_acl_normal;
}

sub getACLNegative {
    return shift->_acl_negative;
}

sub _setACLNormal {
    return shift->_acl_normal( shift );
}

sub _setACLNegative {
    return shift->_acl_negative( shift );
}

1;
