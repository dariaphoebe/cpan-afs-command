package AFS::Command::Base;

require 5.010;

use Moose;
use English;
use Carp;

use File::Basename qw(basename);
use Date::Format;
use IO::File;
use IO::Pipe;

our $AUTOLOAD = q{};

has q{localtime}  => ( is => q{rw}, isa => q{Int}, default => 0 );
has q{noauth}     => ( is => q{rw}, isa => q{Int}, default => 0 );
has q{localauth}  => ( is => q{rw}, isa => q{Int}, default => 0 );
has q{encrypt}    => ( is => q{rw}, isa => q{Int}, default => 0 );
has q{quiet}      => ( is => q{rw}, isa => q{Int}, default => 0 );
has q{timestamps} => ( is => q{rw}, isa => q{Int}, default => 0 );

has q{command}    => ( is => q{rw}, isa => q{Str}, lazy_build => 1 );

has q{operations} => ( is => q{rw}, isa => q{HashRef}, lazy_build => 1 );
has q{operation_arguments} =>
    ( is => q{rw}, isa => q{HashRef}, default => sub { return {}; } );

sub _build_command {
    my $self  = shift;
    my $class = ref $self;
    my ($command) = reverse split m{\s+}msx, $class;
    return $command;
}

sub _build_operations {

    my $self = shift;
    my $operation = shift;

    my %operations = ();

    #
    # This hack is necessary to support the offline/online "hidden"
    # vos commands.  These won't show up in the normal help output, so
    # we have to check for them individually.  Since offline and
    # online are implemented as a pair, we can just check one of them,
    # and assume the other is there, too.
    #

    foreach my $type ( qw(default hidden) ) {

        if ( $type eq q{hidden} ) {
            next if not $self->isa( q{AFS::Command::VOS} );
        }

        my $pipe = IO::Pipe->new || croak qq{Unable to create pipe: $ERRNO\n};

        my $pid = fork;

        defined $pid || croak qq{Unable to fork: $ERRNO\n};

        if ( $pid == 0 ) {

            STDERR->fdopen( STDOUT->fileno, q{w} ) ||
                croak qq{Unable to redirect stderr: $ERRNO\n};
            STDOUT->fdopen( $pipe->writer->fileno, q{w} ) ||
                croak qq{Unable to redirect stdout: $ERRNO\n};

            my $command = $self->command;

            if ( $type eq q{default} ) {
                $command .= q{ help};
            } else {
                $command .= q{ offline -help};
            }

            exec $command;
            croak qq{Unable to exec $command: $ERRNO\n};

        } else {

            $pipe->reader;

            while ( defined($_ = $pipe->getline) ) {
                if ( $type eq q{default} ) {
                    next if m{Commands \s+ are:}msx;
                    my ($command) = split;
                    next if $command =~ m{^(apropos|help)$}msx;
                    $operations{$command}++;
                } elsif ( m{^Usage:}msx ) {
                    $operations{offline}++;
                    $operations{online}++;
                }
            }

        }

        if ( not waitpid($pid,0) ) {
            croak qq{Unable to get status of child process ($pid)\n};
        }

        if ( $CHILD_ERROR ) {
            croak qq{Error running command help. Unable to configure $class\n};
        }

    }

    return \%operations;

}

sub has_operation {
    my $self = shift;
    my $operation = shift;
    my $operations = $self->operations;
    return exists $operations->{$operation};
}

sub has_argument {
    my $self = shift;
    my $operation = shift;
    my $argument = shift;
    return if not $self->has_operation($operation);
    my $arguments = $self->arguments($operation);
    return exists $arguments->{$argument};
}

sub arguments {

    my $self      = shift;
    my $operation = shift;

    my $arguments = {
        optional => {},
        required => {},
        aliases  => {},
    };

    my $command = $self->command;

    if ( not $self->has_operation($operation) ) {
        croak qq{Unsupported $command operation '$operation'};
    }

    my $operation_arguments = $self->operation_arguments;

    return $operation_arguments->{$operation}
        if ref $operation_arguments->{$operation} eq q{HASH};

    my $pipe = IO::Pipe->new || croak qq{Unable to create pipe: $ERRNO};

    my $pid = fork;

    defined $pid || croak qq{Unable to fork: $ERRNO};

    if ( $pid == 0 ) {

        STDERR->fdopen( STDOUT->fileno, q{w} ) ||
            croak qq{Unable to redirect stderr: $ERRNO};
        STDOUT->fdopen( $pipe->writer->fileno, q{w} ) ||
            croak qq{Unable to redirect stdout: $ERRNO\n};
        exec $command, $operation, '-help';
        croak qq{Unable to exec $command help $operation: $ERRNO};

    } else {

        $pipe->reader;

        while ( defined($_ = $pipe->getline) ) {

            if ( m{Unrecognized \s+ operation \s+ '$operation'}msx ) {
                croak qq{Unsupported @command operation '$operation'};
            }

            next if not s{^Usage:.*\s+$operation\s+}{}ms;

            while ( $_ ) {
                if ( s{^\[\s*-(\w+?)\s*\]\s*}{}ms  ) {
                    $arguments->{optional}->{$1} = 0
                        if $1 ne q{help}; # Yeah, skip it...
                } elsif ( s{^\[\s*-(\w+?)\s+<[^>]*?>\+\s*]\s*}{}ms ) {
                    $arguments->{optional}->{$1} = [];
                } elsif ( s{^\[\s*-(\w+?)\s+<[^>]*?>\s*]\s*}{}ms ) {
                    $arguments->{optional}->{$1} = 1;
                } elsif ( s{^\s*-(\w+?)\s+<[^>]*?>\+\s*}{}ms ) {
                    $arguments->{required}->{$1} = [];
                } elsif ( s{^\s*-(\w+?)\s+<[^>]*?>\s*}{}ms ) {
                    $arguments->{required}->{$1} = 1;
                } elsif ( s{^\s*-(\w+?)\s*}{}ms ) {
                    $arguments->{required}->{$1} = 0;
                } else {
                    croak(
                        qq{Unable to parse $command help for $operation\n},
                        qq{Unrecognized string: '$_'}
                    );
                }
            }

            last;

        }

    }

    #
    # XXX -- Hack Alert!!!
    #
    # Because the force option to vos release changed from -f to
    # -force, you can't use the API tranparently with 2 different vos
    # binaries that support the 2 different options.
    #
    # If we need more of these, we can add them, as this let's us
    # alias one argument to another.
    #
    if ( $self->isa( q{AFS::Command::VOS} ) and $operation eq q{release} ) {
        if ( exists $arguments->{optional}->{f} ) {
            $arguments->{aliases}->{force} = q{f};
        } elsif ( exists $arguments->{optional}->{force} ) {
            $arguments->{aliases}->{f} = q{force};
        }
    }

    if ( not waitpid($pid,0) ) {
        croak qq{Unable to get status of child process ($pid)};
    }

    if ( $CHILD_ERROR ) {
        croak qq{Error running $command $operation -help.  Unable to configure $command $operation};
    }

    return $operation_arguments->{$operation} = $arguments;

}

sub _save_stderr {

    my $self = shift;

    $self->{olderr} = IO::File->new(">&STDERR") || 
        croak qq{Unable to dup stderr: $ERRNO};

    my $command = basename((split /\s+/,@{$self->{command}})[0]);

    $self->{tmpfile} = qq{/tmp/.$command.$self->{operation}.$PID};

    my $newerr = IO::File->new(">$self->{tmpfile}") ||
        croak qq{Unable to open $self->{tmpfile}: $ERRNO};

    STDERR->fdopen( $newerr->fileno, "w" ) || 
        croak qq{Unable to reopen stderr: $ERRNO};

    $newerr->close || 
        croak qq{Unable to close $self->{tmpfile}: $ERRNO};

    return 1;

}

sub _restore_stderr {

    my $self = shift;

    STDERR->fdopen( $self->{olderr}->fileno, "w") || 
        croak qq{Unable to restore stderr: $ERRNO};

    $self->{olderr}->close || 
        croak qq{Unable to close saved stderr: $ERRNO};

    delete $self->{olderr};

    my $newerr = IO::File->new($self->{tmpfile}) || 
        croak qq{Unable to reopen $self->{tmpfile}: $ERRNO};

    $self->{errors} = "";

    while ( <$newerr> ) {
        $self->{errors} .= $_;
    }

    $newerr->close || 
        croak qq{Unable to close $self->{tmpfile}: $ERRNO};

    unlink($self->{tmpfile}) || 
        croak qq{Unable to unlink $self->{tmpfile}: $ERRNO};

    delete $self->{tmpfile};

    return 1;

}

sub _parse_arguments {

    my $self = shift;
    my $class = ref($self);
    my (%args) = @_;

    my $arguments = $self->_arguments($self->{operation});

    if ( not defined $arguments ) {
        crap qq{Unable to obtain arguments for $class->$self->{operation}};
        return;
    }

    $self->{errors} = "";

    $self->{cmds} = [];

    if ( $args{inputfile} ) {

        push( @{$self->{cmds}}, [ 'cat', $args{inputfile} ] );

    } else {

        my @argv = ( @{$self->{command}}, $self->{operation} );

        foreach my $key ( keys %args ) {
            next unless $arguments->{aliases}->{$key};
            $args{$arguments->{aliases}->{$key}} = delete $args{$key};
        }

        foreach my $key ( qw( noauth localauth encrypt ) ) {
            next unless $self->{$key};
            $args{$key}++ if exists $arguments->{required}->{$key};
            $args{$key}++ if exists $arguments->{optional}->{$key};
        }

        unless ( $self->{quiet} ) {
            $args{verbose}++ if exists $arguments->{optional}->{verbose};
        }

        foreach my $type ( qw( required optional ) ) {

            foreach my $key ( keys %{$arguments->{$type}} ) {

                my $hasvalue = $arguments->{$type}->{$key};

                if ( not exists $args{$key} ) {
                    next if $type ne q{required};
                    croak qq{Required argument '$key' not provided};
                }

                if ( $hasvalue ) {
                    if ( ref $args{$key} eq q{HASH} || ref $args{$key} eq q{ARRAY} ) {
                        if ( ref $hasvalue ne q{ARRAY} ) {
                            croak qq{Invalid argument '$key': can't provide a list of values};
                        }
                        push @argv, qq{-$key};
                        foreach my $value ( ref $args{$key} eq 'HASH' ? %{$args{$key}} : @{$args{$key}} ) {
                            push @argv, $value;
                        }
                    } else {
                        push @argv, qq{-$key}, $args{$key};
                    }
                } else {
                    push @argv, qq{-$key} if $args{$key};
                }

                delete $args{$key};

            }

        }

        if ( %args ) {
            croak( qq{Unsupported arguments: } . join(' ',sort keys %args)) );
        }

        push( @{$self->{cmds}}, \@argv );

    }

    return 1;

}

sub _exec_cmds {

    my $self = shift;

    my %args = @_;

    my @cmds = @{$self->{cmds}};

    $self->{pids} = {};

    for ( my $index = 0 ; $index <= $#cmds ; $index++ ) {

        my $cmd = $cmds[$index];

        my $pipe = IO::Pipe->new || 
            croak qq{Unable to create pipe: $ERRNO};

        my $pid = fork;

        defined $pid || croak qq{Unable to fork: $ERRNO};

        if ( $pid == 0 ) {

            if ( $index == $#cmds && exists $args{stdout} && $args{stdout} ne q{stdout} ) {
                my $stdout = IO::File->new( qq{>$args{stdout}} ) ||
                    croak qq{Unable to open $args{stdout}: $ERRNO};
                STDOUT->fdopen( $stdout->fileno, q{w} ) ||
                    croak qq{Unable to redirect stdout: $ERRNO};
            } else {
                STDOUT->fdopen( $pipe->writer->fileno, q{w} ) ||
                    croak qq{Unable to redirect stdout: $ERRNO};
            }

            if ( exists $args{stderr} && $args{stderr} eq q{stdout} ) {
                STDERR->fdopen( STDOUT->fileno, q{w} ) ||
                    croak qq{Unable to redirect stderr: $ERRNO};
            }

            if ( $index == 0 ) {
                if ( exists $args{stdin} && $args{stdin} ne q{stdin} ) {
                    my $stdin = IO::File->new( qq{<$args{stdin}} ) ||
                        croak qq{Unable to open $args{stdin}: $ERRNO};
                    STDIN->fdopen( $stdin->fileno, q{r} ) ||
                        croak qq{Unable to redirect stdin: $ERRNO};
                }
            } else {
                STDIN->fdopen( $self->{handle}->fileno, q{r} ) ||
                    croak qq{Unable to redirect stdin: $ERRNO};
            }

            $ENV{TZ} = q{GMT} unless $self->{localtime};

            exec( { $cmd->[0] } @{$cmd} ) ||
                croak qq{Unable to exec @{$cmd}: $ERRNO};

        }

        $self->{handle} = $pipe->reader;

        $self->{pids}->{$pid} = $cmd;

    }

    return 1;

}

sub _parse_output {

    my $self = shift;

    $self->{errors} = q{};

    while ( defined($_ = $self->{handle}->getline) ) {
        if ( $self->{timestamps} ) {
            $self->{errors} .= time2str( qq{[%Y-%m-%d %H:%M:%S] }, time, q{GMT} );
        }
        $self->{errors} .= $_;
    }

    return 1;

}

sub _reap_cmds {

    my $self = shift;
    my (%args) = @_;

    my $errors = 0;

    $self->{handle}->close ||
        croak qq{Unable to close pipe handle: $ERRNO};

    delete $self->{handle};
    delete $self->{cmds};

    $self->{status} = {};

    my %allowstatus = ();

    if ( $args{allowstatus} ) {
        if ( ref $args{allowstatus} eq q{ARRAY} ) {
            foreach my $status ( @{$args{allowstatus}} ) {
                $allowstatus{$status}++;
            }
        } else {
            $allowstatus{$args{allowstatus}}++;
        }
    }

    foreach my $pid ( keys %{$self->{pids}} ) {

        $self->{status}->{$pid}->{cmd} =
          join( q{ }, @{delete $self->{pids}->{$pid}} );

        if ( waitpid($pid,0) ) {

            $self->{status}->{$pid}->{status} = $CHILD_ERROR;
            if ( $CHILD_ERROR ) {
                if ( %allowstatus ) {
                    $errors++ unless $allowstatus{ $CHILD_ERROR >> 8 };
                } else {
                    $errors++;
                }
            }


        } else {
            $self->{status}->{$pid}->{status} = undef;
            $errors++;
        }

    }

    return if $errors;
    return 1;

}

sub AUTOLOAD {

    my $self = shift;
    my (%args) = @_;

    my $operation = $AUTOLOAD;
    $operation =~ s{.*::}{}ms;

    $self->operation( $operation );

    $self->_parse_arguments(%args);
    $self->_exec_cmds( stderr => q{stdout} );
    $self->_parse_output;
    $self->_reap_cmds;

    return 1;

}

sub DESTROY {}

1;
