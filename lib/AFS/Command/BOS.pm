package AFS::Command::BOS;

require 5.010;

use Moose;
use English;
use Carp;

extends qw(AFS::Command::Base);

use AFS::Object;
use AFS::Object::BosServer;
use AFS::Object::Instance;

sub getdate {

    my $self = shift;
    my %args = @_;

    my $result = AFS::Object::BosServer->new;

    $self->operation( q{getdate} );

    my $directory = $args{dir} || q{/usr/afs/bin};

    $self->_parse_arguments(%args);
    $self->_save_stderr;
    $self->_exec_commands;

    while ( defined($_ = $self->_handle->getline) ) {

        chomp;

        next if not m{File \s+ $directory/(\S+) \s+ dated \s+ ([^,]+),}msx;

        my $file = AFS::Object->new(
            file => $1,
            date => $2,
        );

        if ( m{\.BAK dated ([^,]+),}ms ) {
            $file->_setAttribute( bak => $1 );
        }

        if ( m{\.OLD dated ([^,\.]+)}ms ) {
            $file->_setAttribute( old => $1 );
        }

        $result->_addFile($file);

    }

    $self->_restore_stderr;
    $self->_reap_commands;

    return $result;

}

sub getlog {

    my $self = shift;
    my %args = @_;

    my $result = AFS::Object::BosServer->new;

    $self->operation( q{getlog} );

    my $redirect = undef;
    my $redirectname = undef;

    if ( $args{redirect} ) {
        $redirectname = delete $args{redirect};
        $redirect = IO::File->new( qq{>$redirectname} ) || 
            croak qq{Unable to write to $redirectname: $ERRNO};
    }

    $self->_parse_arguments(%args);
    $self->_save_stderr;
    $self->_exec_commands;

    my $log = q{};

    while ( defined($_ = $self->_handle->getline) ) {
        next if m{^Fetching log file}ms;
        if ( $redirect ) {
            $redirect->print($_);
        } else {
            $log .= $_;
        }
    }

    if ( $redirect ) {
        $redirect->close || croak qq{Unable to close $redirectname: $ERRNO};
        $result->_setAttribute( log => $redirectname );
    } else {
        $result->_setAttribute( log => $log );
    }

    $self->_restore_stderr;
    $self->_reap_commands;

    return $result;

}

sub getrestart {

    my $self = shift;
    my %args = @_;

    my $result = AFS::Object::BosServer->new;

    $self->operation( q{getrestart} );

    $self->_parse_arguments(%args);
    $self->_save_stderr;
    $self->_exec_commands;

    while ( defined($_ = $self->_handle->getline) ) {

        if ( m{restarts at (.*)}ms || m{restarts (never)}ms ) {
            $result->_setAttribute( restart => $1 );
        } elsif ( m{binaries at (.*)}ms || m{binaries (never)}ms ) {
            $result->_setAttribute( binaries => $1 );
        }

    }

    $self->_restore_stderr;
    $self->_reap_commands;

    return $result;

}

sub getrestricted {

    my $self = shift;
    my %args = @_;

    my $result = AFS::Object::BosServer->new;

    $self->operation( q{getrestricted} );

    $self->_parse_arguments(%args);
    $self->_save_stderr;
    $self->_exec_commands;

    while ( defined($_ = $self->_handle->getline) ) {
        if ( m{Restricted mode is (\S+)}ms ) {
            $result->_setAttribute( restricted => $1 );
        }
    }

    $self->_restore_stderr;
    $self->_reap_commands;

    return $result;

}

sub listhosts {

    my $self = shift;
    my %args = @_;

    my $result = AFS::Object::BosServer->new;

    $self->operation( q{listhosts} );

    $self->_parse_arguments(%args);
    $self->_save_stderr;
    $self->_exec_commands;

    my @hosts = ();

    while ( defined($_ = $self->_handle->getline) ) {

        chomp;

        if ( m{Cell name is (\S+)}msi ) {
            $result->_setAttribute( cell => $1 );
        }

        if ( m{Host \d+ is (\S+)}msi ) {
            push @hosts, $1;
        }

    }

    $result->_setAttribute( hosts => \@hosts );

    $self->_restore_stderr;
    $self->_reap_commands;

    return $result;

}

sub listkeys {

    my $self = shift;
    my %args = @_;

    my $result = AFS::Object::BosServer->new;

    $self->operation( q{listkeys} );

    $self->_parse_arguments(%args);
    $self->_save_stderr;
    $self->_exec_commands;

    while ( defined($_ = $self->_handle->getline) ) {

        chomp;

        if ( m{key (\d+)}ms ) {

            my $key = AFS::Object->new( index => $1 );

            if ( m{has cksum (\d+)}ms ) {
                $key->_setAttribute( cksum => $1 );
            } elsif ( m{is \'([^\']+)\'}ms ) {
                $key->_setAttribute( value => $1 );
            }

            $result->_addKey($key);

        }

        if ( m{last changed on (.*)\.}ms ) {
            $result->_setAttribute( keyschanged => $1 );
        }

    }

    $self->_restore_stderr;
    $self->_reap_commands;

    return $result;

}

sub listusers {

    my $self = shift;
    my %args = @_;

    my $result = AFS::Object::BosServer->new;

    $self->operation( q{listusers} );

    $self->_parse_arguments(%args);
    $self->_save_stderr;
    $self->_exec_commands;

    while ( defined($_ = $self->_handle->getline) ) {

        chomp;

        if ( m{^SUsers are: (.*)}ms ) {
            $result->_setAttribute( susers => [split(/\s+/,$1)] );
        }

    }

    $self->_restore_stderr;
    $self->_reap_commands;

    return $result;

}

sub status {

    my $self = shift;
    my %args = @_;

    my $result = AFS::Object::BosServer->new;

    $self->operation( q{status} );

    $self->_parse_arguments(%args);
    $self->_save_stderr;
    $self->_exec_commands;

    my $instance = undef;

    while ( defined($_ = $self->_handle->getline) ) {

        chomp;

        if ( m{inappropriate access}ms ) {
            $result->_setAttribute( access => 1 );
            next;
        }

        if ( m{Instance (\S+),}ms ) {

            if ( defined $instance ) {
                $result->_addInstance($instance);
            }

            $instance = AFS::Object::Instance->new( instance => $1 );

            #
            # This is ugly, since the order and number of these
            # strings varies.
            #
            if ( m{\(type is (\S+)\)}ms ) {
                $instance->_setAttribute( type => $1 );
            }

            if ( m{(disabled|temporarily disabled|temporarily enabled),}ms ) {
                $instance->_setAttribute( state => $1 );
            }

            if ( m{stopped for too many errors}ms ) {
                $instance->_setAttribute( errorstop => 1 );
            }

            if ( m{has core file}ms ) {
                $instance->_setAttribute( core => 1 );
            }

            if ( m{currently (.*)\.$}ms ) {
                $instance->_setAttribute( status => $1 );
            }

        }

        if ( m{Auxiliary status is: (.*)\.$}ms ) {
            $instance->_setAttribute( auxiliary => $1 );
        }

        if ( m{Process last started at (.*) \((\d+) proc starts\)}ms ) {
            $instance->_setAttribute(
                startdate  => $1,
                startcount => $2,
            );
        }

        if ( m{Last exit at (.*)}ms ) {
            $instance->_setAttribute( exitdate => $1 );
        }

        if ( m{Last error exit at ([^,]+),}ms ) {

            $instance->_setAttribute( errorexitdate => $1 );

            if ( m{due to shutdown request}ms ) {
                $instance->_setAttribute( errorexitdue => q{shutdown} );
            }

            if ( m{due to signal (\d+)}ms ) {
                $instance->_setAttribute(
                    errorexitdue    => q{signal},
                    errorexitsignal => $1,
                );
            }

            if ( m{by exiting with code (\d+)}ms ) {
                $instance->_setAttribute(
                    errorexitdue  => q{code},
                    errorexitcode => $1,
                );
            }

        }

        if ( m{Command\s+(\d+)\s+is\s+\'(.*)\'}ms ) {
            my $command = AFS::Object->new(
                index   => $1,
                command => $2,
            );
            $instance->_addCommand($command);
        }

        if ( m{Notifier\s+is\s+\'(.*)\'}ms ) {
            $instance->_setAttribute( notifier => $1 );
        }

    }

    if ( defined $instance ) {
        $result->_addInstance($instance);
    }

    $self->_restore_stderr;
    $self->_reap_commands;

    return $result;

}

1;
