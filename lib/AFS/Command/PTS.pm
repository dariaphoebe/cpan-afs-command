package AFS::Command::PTS;

use Moose;
use MooseX::Singleton;
use English;
use Carp;

use feature q{switch};

extends qw(AFS::Command::Base);

use AFS::Object;
use AFS::Object::PTServer;
use AFS::Object::Principal;
use AFS::Object::Group;
use AFS::Object::User;

sub interactive { return shift->_unsupported( q{interactive} ); }
sub sleep       { return shift->_unsupported( q{sleep}       ); }
sub quit        { return shift->_unsupported( q{quit}        ); }
sub source      { return shift->_unsupported( q{source}      ); }

sub _unsupported {
    my $self = shift;
    my $operation = shift;
    croak qq{Unsupported interactive pts operation: $operation};
}

sub getEntry {

    my $self = shift;
    my %args = @_;

    if ( ref $args{nameorid} ) {
        croak qq{Invalid argument: nameorid is a reference\n};
    }

    my $result = $self->examine( %args );

    my ($object) = ( $result->getGroups, $result->getUsers );

    return $object;

}

sub getMembership {

    my $self = shift;
    my %args = @_;

    if ( ref $args{nameorid} ) {
        croak qq{Invalid argument: nameorid is a reference\n};
    }

    my $result = $self->membership( %args );

    my ($object) = ( $result->getGroups, $result->getUsers );
    
    return if not $object;

    return $object->getMembership;

}

sub creategroup {

    my $self = shift;
    my %args = @_;

    my $result = AFS::Object::PTServer->new;

    $self->operation( q{creategroup} );

    $self->_parse_arguments(%args);
    $self->_save_stderr;
    $self->_exec_commands;

    while ( defined($_ = $self->_handle->getline) ) {
        if ( m{group (\S+) has id (-\d+)}ms ) {
            my $group = AFS::Object::Group->new( name => $1, id => $2 );
            $result->_addGroup($group);
        }
    }

    $self->_restore_stderr;
    $self->_reap_commands;

    return $result;

}

sub createuser {

    my $self = shift;
    my %args = @_;

    my $result = AFS::Object::PTServer->new;

    $self->operation( q{createuser} );

    # Workaround for dangerous pts createuser bug
    # See: http://rt.central.org/rt/index.html?q=128343
    # This simulates the error similar to creategroup
    if ( $args{id} and $args{id} <  0 ) {
        croak(
            qq{pts: argument illegal or out of range because },
            qq{user id $args{id} was not positive\n},
        );
    }

    $self->_parse_arguments(%args);
    $self->_save_stderr;
    $self->_exec_commands;

    while ( defined($_ = $self->_handle->getline) ) {
        if ( m{User (\S+) has id (\d+)}ms ) {
            my $user = AFS::Object::User->new( name => $1, id => $2 );
            $result->_addUser($user);
        }
    }

    $self->_restore_stderr;
    $self->_reap_commands;

    return $result;

}

sub examine {

    my $self = shift;
    my %args = @_;

    my $result = AFS::Object::PTServer->new;

    $self->operation( q{examine} );

    $self->_parse_arguments(%args);
    $self->_exec_commands( stderr => q{stdout} );

    my $missing = 0;

    while ( defined($_ = $self->_handle->getline) ) {

        chomp;

        while ( m{,\s*$}ms ) {
            $_ .= $self->_handle->getline;
            chomp;
        }

        next if m{^\s*$}ms;

        if ( m{User or group doesn.t exist}ms ) {
            $missing++;
        } elsif ( m{Name:}ms ) {

            my %data = ();

            foreach my $field ( split m{,\s*}ms ) {
                my ($key,$value) = split( m{:\s+}ms, $field, 2 );
                $key =~ tr{A-Z}{a-z};
                $key =~ s{\s+}{}gms; # group quota -> groupquota
                $value =~ s{\.$}{}ms;
                $data{$key} = $value;
            }

            if ( not $data{id} ) {
                croak qq{pts examine: Unrecognized output: '$_'};
            }

            if ( $data{id} > 0 ) {
                $result->_addUser( AFS::Object::User->new(%data) );
            } else {
                $result->_addGroup( AFS::Object::Group->new(%data) );
            }

        } else {
            $self->_errors( $self->_errors . $_ );
        }

    }

    if ( $self->_errors ) {
        croak $self->_errors;
    }

    if ( $result->getUsers or $result->getGroups ) {
        $self->_reap_commands;
        return $result;
    } elsif ( $missing ) {
        $self->_reap_commands( allowstatus => 1 );
        return;
    } else {
        $self->_reap_commands;
        return $result;
    }

}

sub listentries {

    my $self = shift;
    my %args = @_;

    my $result = AFS::Object::PTServer->new;

    $self->operation( q{listentries} );

    $self->_parse_arguments(%args);
    $self->_save_stderr;
    $self->_exec_commands;

    while ( defined($_ = $self->_handle->getline) ) {

        next if m{^Name}ms;

        my ($name,$id,$owner,$creator) = split;

        #
        # We seem to be getting this one bogus line of data, with no
        # name, and 0's for the IDs.  Probably a bug in pts...
        #
        next if ( not $name and not $id and not $owner and not $creator );

        if ( $id > 0 ) {
            my $user = AFS::Object::User->new(
                name    => $name,
                id      => $id,
                owner   => $owner,
                creator => $creator,
            );
            $result->_addUser($user);
        } else {
            my $group = AFS::Object::Group->new(
                name    => $name,
                id      => $id,
                owner   => $owner,
                creator => $creator,
            );
            $result->_addGroup($group);
        }

    }

    $self->_restore_stderr;
    $self->_reap_commands;

    return $result;

}

sub listmax {

    my $self = shift;
    my %args = @_;

    my $result = AFS::Object::PTServer->new;

    $self->operation( q{listmax} );

    $self->_parse_arguments(%args);
    $self->_save_stderr;
    $self->_exec_commands;

    while ( defined($_ = $self->_handle->getline) ) {
        next if not m{Max user id is (\d+) and max group id is (-\d+)}ms;
        $result->_setAttribute(
            maxuserid  => $1,
            maxgroupid => $2,
        );
    }

    $self->_restore_stderr;
    $self->_reap_commands;

    return $result;

}

sub listowned {

    my $self = shift;
    my %args = @_;

    my $result = AFS::Object::PTServer->new;

    $self->operation( q{listowned} );

    $self->_parse_arguments(%args);
    $self->_exec_commands( stderr => q{stdout} );

    my $user  = undef;
    my $group = undef;

    while ( defined($_ = $self->_handle->getline) ) {

        if ( m{Groups owned by (\S+) \(id: (-?\d+)\)}ms ) {

            my ($name,$id) = ($1,$2);

            if ( $id > 0 ) {
                $user = AFS::Object::User->new( name => $name, id => $id );
            } else {
                $group = AFS::Object::Group->new( name => $name, id => $id );
            }

            while ( defined($_ = $self->_handle->getline) ) {
                chomp;
                s{^\s+}{}gms;
                s{\s+$}{}gms;
                if ( $user ) {
                    $user->_addOwned($_);
                } else {
                    $group->_addOwned($_);
                }
            }

            $result->_addUser($user)   if $user;
            $result->_addGroup($group) if $group;

        } else {
            # pts listowned still (as of OpenAFS 1.5.77) doesn't
            # have proper exit codes.  
            $self->_errors( $self->_errors . $_ );
        }

    }

    $self->_reap_commands;

    if ( $self->_errors ) {
        croak $self->_errors;
    }

    return $result;

}

sub membership {

    my $self = shift;
    my %args = @_;

    my $result = AFS::Object::PTServer->new;

    $self->operation( q{membership} );

    $self->_parse_arguments(%args);
    $self->_exec_commands( stderr => q{stdout} );

    my $user = undef;
    my $group = undef;

    while ( defined($_ = $self->_handle->getline) ) {

        given ( $_ ) {

            when ( m{(\S+) \(id: (-?\d+)\)}ms ) {

                $result->_addUser($user)   if $user;
                $result->_addGroup($group) if $group;

                my ($name,$id) = ($1,$2);

                if ( $id > 0 ) {
                    $user  = AFS::Object::User->new( name => $name, id => $id );
                    $group = undef;
                } else {
                    $user  = undef;
                    $group = AFS::Object::Group->new( name => $name, id => $id );
                }

            }

            when ( m{^\s+(\S+)\s*}ms ) {

                if ( $user ) {
                    $user->_addMembership($1);
                } else {
                    $group->_addMembership($1);
                }

            }

            when ( m{unable to get membership}ms ||
                   m{User or group doesn't exist}ms ||
                   m{membership list for id \d+ exceeds display limit}ms ) {

                #
                # pts still (as of OpenAFS 1.2.8) doesn't have proper exit codes.
                # If we see this string, then let the command fail, even
                # though we might have partial data.
                #
                $self->_errors( $self->_errors . $_ );

            }

        }

    }

    $result->_addUser($user) if $user;
    $result->_addGroup($group) if $group;

    $self->_reap_commands;

    if ( $self->_errors ) {
        croak $self->_errors;
    }

    return $result;

}

1;
