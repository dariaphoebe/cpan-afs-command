package AFS::Command::FS;

require 5.010;

use Moose;
use English;
use Carp;

use feature q{switch};

extends qw(AFS::Command::Base);

use AFS::Object;
use AFS::Object::CacheManager;
use AFS::Object::Path;
use AFS::Object::Cell;
use AFS::Object::Server;
use AFS::Object::ACL;

sub checkservers {

    my $self = shift;
    my (%args) = @_;

    my $result = AFS::Object::CacheManager->new;

    $self->operation( q{checkservers} );

    $self->_parse_arguments(%args);
    $self->_save_stderr;
    $self->_exec_commands;

    my @servers = ();

    while ( defined($_ = $self->_handle->getline) ) {

        chomp;

        if ( m{The current down server probe interval is (\d+) secs}ms ) {
            $result->_setAttribute( interval => $1 );
        }

        if ( m{These servers are still down:}ms ) {
            while ( defined($_ = $self->_handle->getline) ) {
                s{^\s+}{}gms;
                s{\s+$}{}gms;
                push @servers, $_;
            }
        }
    }

    $result->_setAttribute( servers => \@servers );

    $self->_restore_stderr;
    $self->_reap_commands;

    return $result;

}

sub diskfree {
    return shift->_paths_method( q{diskfree}, @_ );
}

sub examine {
    return shift->_paths_method( q{examine} ,@_ );
}

sub listquota {
    return shift->_paths_method( q{listquota}, @_ );
}

sub quota {
    return shift->_paths_method( q{quota}, @_ );
}

sub storebehind {
    return shift->_paths_method( q{storebehind}, @_ );
}

sub whereis {
    return shift->_paths_method( q{whereis}, @_ );
}

sub whichcell {
    return shift->_paths_method( q{whichcell}, @_ );
}

sub listacl {
    return shift->_paths_method( q{listacl}, @_ );
}

sub _paths_method {

    my $self = shift;
    my $operation = shift;
    my (%args) = @_;

    my $result = AFS::Object::CacheManager->new;

    $self->operation( $operation );

    my $pathkey = $operation eq q{storebehind} ? q{files} : q{path};

    $self->_parse_arguments(%args);
    $self->_exec_commands( stderr => q{stdout} );

    my @paths = ref $args{$pathkey} eq q{ARRAY} ? @{$args{$pathkey}} : ($args{$pathkey});
    my %paths = map { $_ => 1 } @paths;

    my $default = undef; # Used by storebehind

    while ( defined($_ = $self->_handle->getline) ) {

        next if m{^Volume Name}ms;

        my $path = AFS::Object::Path->new;

        if ( m{fs: Invalid argument; it is possible that (.*) is not in AFS.}ms ||
             m{fs: no such cell as \'(.*)\'}ms ||
             m{fs: File \'(.*)\' doesn\'t exist}ms ||
             m{fs: You don\'t have the required access rights on \'(.*)\'}ms ) {

            $path->_setAttribute(
                path  => $1,
                error => $_,
            );

            delete $paths{$1};
            @paths = grep { $_ ne $1 } @paths;

        } else {

            if ( $operation eq q{listacl} ) {

                if ( m{^Access list for (.*) is}ms ) {

                    $path->_setAttribute( path => $1 );
                    delete $paths{$1};

                    my $normal   = AFS::Object::ACL->new;
                    my $negative = AFS::Object::ACL->new;

                    my $type = 0;

                    while ( defined($_ = $self->_handle->getline) ) {

                        s{^\s+}{}gms;
                        s{\s+$}{}gms;
                        last if m{^\s*$}ms;

                        $type = 1, next  if m{^Normal rights:}ms;
                        $type = -1, next if m{^Negative rights:}ms;

                        my ($principal,$rights) = split;

                        if ( $type == 1 ) {
                            $normal->_addEntry( $principal => $rights );
                        } elsif ( $type == -1 ) {
                            $negative->_addEntry( $principal => $rights );
                        }

                    }

                    $path->_setACLNormal($normal);
                    $path->_setACLNegative($negative);

                }

            }

            if ( $operation eq q{whichcell} ) {
                if ( m{^File (\S+) lives in cell \'([^\']+)\'}ms ) {
                    $path->_setAttribute(
                        path => $1,
                        cell => $2,
                    );
                    delete $paths{$1};
                }
            }

            if ( $operation eq q{whereis} ) {
                if ( m{^File (.*) is on hosts? (.*)$}ms ) {
                    $path->_setAttribute(
                        path  => $1,
                        hosts => [split(/\s+/,$2)],
                    );
                    delete $paths{$1};
                }
            }

            if ( $operation eq q{storebehind} ) {

                if ( m{Default store asynchrony is (\d+) kbytes}ms ) {

                    $default = $1;
                    next;

                } elsif ( m{Will store (.*?) according to default.}ms ) {

                    $path->_setAttribute(
                        path       => $1,
                        asynchrony => q{default},
                    );

                    delete $paths{$1};
                    @paths = grep { $_ ne $1 } @paths;

                } elsif ( m{Will store up to (\d+) kbytes of (.*?) asynchronously}ms ) {

                    $path->_setAttribute(
                        path       => $2,
                        asynchrony => $1,
                    );

                    delete $paths{$2};
                    @paths = grep { $_ ne $2 } @paths;

                }

            }

            if ( $operation eq q{quota} ) {
                if ( m{^\s*(\d{1,2})%}ms ) {
                    $path->_setAttribute(
                        path    => $paths[0],
                        percent => $1,
                    );
                    delete $paths{$paths[0]};
                    shift @paths;
                }
            }

            if ( $operation eq q{listquota} ) {

                #
                # This is a bit lame.  We want to be lazy and split on white
                # space, so we get rid of this one annoying instance.
                #
                s{no limit}{nolimit}gms;

                my ($volname,$quota,$used,$percent,$partition) = split;

                $quota     = 0 if $quota eq q{nolimit};
                $percent   =~ s{\D}{}gms; # want numeric result
                $partition =~ s{\D}{}gms; # want numeric result

                $path->_setAttribute(
                    path      => $paths[0],
                    volname   => $volname,
                    quota     => $quota,
                    used      => $used,
                    percent   => $percent,
                    partition => $partition,
                );
                delete $paths{$paths[0]};
                shift @paths;

            }

            if ( $operation eq q{diskfree} ) {

                my ($volname,$total,$used,$avail,$percent) = split;
                $percent =~ s{%}{}gms; # Don't need it -- want numeric result

                $path->_setAttribute(
                    path    => $paths[0],
                    volname => $volname,
                    total   => $total,
                    used    => $used,
                    avail   => $avail,
                    percent => $percent,
                );
                delete $paths{$paths[0]};
                shift @paths;

            }

            if ( $operation eq q{examine} ) {

                if ( m{Volume status for vid = (\d+) named (\S+)}ms ) {

                    $path->_setAttribute(
                        path    => $paths[0],
                        id      => $1,
                        volname => $2,
                    );

                    #
                    # Looking at Transarc's code, we can safely assume we'll
                    # get this output in the order shown. Note we ignore the
                    # "Message of the day" and "Offline reason" output for
                    # now.  Read until we hit a blank line.
                    #
                    while ( defined($_ = $self->_handle->getline) ) {

                        last if m{^\s*$}ms;

                        if ( m{Current disk quota is (\d+|unlimited)}ms ) {
                            $path->_setAttribute(
                                quota => $1 eq q{unlimited} ? 0 : $1,
                            );
                        }

                        if ( m{Current blocks used are (\d+)}ms ) {
                            $path->_setAttribute( used => $1 );
                        }

                        if ( m{The partition has (\d+) blocks available out of (\d+)}ms ) {
                            $path->_setAttribute(
                                avail => $1,
                                total => $2,
                            );
                        }
                    }

                    delete $paths{$paths[0]};
                    shift @paths;

                }

            }

        }

        $result->_addPath($path);

    }

    if ( $operation eq q{storebehind} ) {

        $result->_setAttribute( asynchrony => $default );

        #
        # This is ugly, but we get the default last, and it would be nice
        # to put this value into the Path objects as well, rather than the
        # string 'default'.
        #
        foreach my $path ( $result->getPaths ) {
            if ( $path->asynchrony eq q{default} ) {
                $path->_setAttribute( asynchrony => $default );
            }
        }
    }

    foreach my $pathname ( keys %paths ) {

        my $path = AFS::Object::Path->new(
            path  => $pathname,
            error => q{Unable to determine results},
        );

        $result->_addPath($path);

    }

    $self->_reap_commands( allowstatus => 1 );

    return $result;

}

sub exportafs {

    my $self = shift;
    my (%args) = @_;

    my $result = AFS::Object->new;

    $self->operation( q{exportafs} );

    $self->_parse_arguments(%args);
    $self->_save_stderr;
    $self->_exec_commands;

    while ( defined($_ = $self->_handle->getline) ) {
        given ( $_ ) {
            when ( m{translator is (currently )?enabled}ms ) {
                $result->_setAttribute( enabled => 1 );
            }
            when ( m{translator is disabled}ms ) {
                $result->_setAttribute( enabled => 0 );
            }
            when ( m{convert owner mode bits}ms ) {
                $result->_setAttribute( convert => 1 );
            }
            when ( m{strict unix}ms ) {
                $result->_setAttribute( convert => 0 );
            }
            when ( m{strict \'?passwd sync\'?}ms ) {
                $result->_setAttribute( uidcheck => 1 );
            }
            when ( m{no \'?passwd sync\'?}ms ) {
                $result->_setAttribute( uidcheck => 0 );
            }
            when ( m{allow mounts}msi ) {
                $result->_setAttribute( submounts => 1 );
            }
            when ( m{Only mounts}msi ) {
                $result->_setAttribute( submounts => 0 );
            }
        }
    }

    $self->_restore_stderr;
    $self->_reap_commands;

    return $result;

}

sub getcacheparms {

    my $self = shift;
    my (%args) = @_;

    my $result = AFS::Object::CacheManager->new;

    $self->operation( q{getcacheparms} );

    $self->_parse_arguments(%args);
    $self->_save_stderr;
    $self->_exec_commands;

    while ( defined($_ = $self->_handle->getline) ) {
        if ( m{using (\d+) of the cache.s available (\d+) 1K}ms ) {
            $result->_setAttribute(
                used  => $1,
                avail => $2,
            );
        }
    }

    $self->_restore_stderr;
    $self->_reap_commands;

    return $result;

}

sub getcellstatus {

    my $self = shift;
    my (%args) = @_;

    my $result = AFS::Object::CacheManager->new;

    $self->operation( q{getcellstatus} );

    $self->_parse_arguments(%args);
    $self->_save_stderr;
    $self->_exec_commands;

    while ( defined($_ = $self->_handle->getline) ) {
        if ( m{Cell (\S+) status: (no )?setuid allowed}ms ) {
            my $cell = AFS::Object::Cell->new(
                cell   => $1,
                status => $2 ? 0 : 1,
            );
            $result->_addCell($cell);
        }
    }

    $self->_restore_stderr;
    $self->_reap_commands;

    return $result;

}

sub getclientaddrs {

    my $self = shift;
    my (%args) = @_;

    my $result = AFS::Object::CacheManager->new;

    $self->operation( q{getclientaddrs} );

    $self->_parse_arguments(%args);
    $self->_save_stderr;
    $self->_exec_commands;

    my @addresses = ();

    while ( defined($_ = $self->_handle->getline) ) {
        chomp;
        s{^\s+}{}ms;
        s{\s+$}{}ms;
        push @addresses, $_;
    }

    $result->_setAttribute( addresses => \@addresses );

    $self->_restore_stderr;
    $self->_reap_commands;

    return $result;

}

sub getcrypt {

    my $self = shift;
    my (%args) = @_;

    my $result = AFS::Object::CacheManager->new;

    $self->operation( q{getcrypt} );

    $self->_parse_arguments(%args);
    $self->_save_stderr;
    $self->_exec_commands;

    while ( defined($_ = $self->_handle->getline) ) {
        if ( m{Security level is currently (crypt|clear)}ms ) {
            $result->_setAttribute( crypt => $1 eq q{crypt} ? 1 : 0 );
        }
    }

    $self->_restore_stderr;
    $self->_reap_commands;

    return $result;

}

sub getserverprefs {

    my $self = shift;
    my (%args) = @_;

    my $result = AFS::Object::CacheManager->new;

    $self->operation( q{getserverprefs} );

    $self->_parse_arguments(%args);
    $self->_save_stderr;
    $self->_exec_commands;

    while ( defined($_ = $self->_handle->getline) ) {

        s{^\s+}{}gms;
        s{\s+$}{}gms;

        my ($name,$preference) = split;

        my $server = AFS::Object::Server->new(
            server     => $name,
            preference => $preference,
        );

        $result->_addServer($server);

    }

    $self->_restore_stderr;
    $self->_reap_commands;

    return $result;

}

sub listaliases {

    my $self = shift;
    my (%args) = @_;

    my $result = AFS::Object::CacheManager->new;

    $self->operation( q{listaliases} );

    $self->_parse_arguments(%args);
    $self->_save_stderr;
    $self->_exec_commands;

    while ( defined($_ = $self->_handle->getline) ) {
        if ( m{Alias (.*) for cell (.*)}ms ) {
            my $cell = AFS::Object::Cell->new(
                cell  => $2,
                alias => $1,
            );
            $result->_addCell($cell);
        }
    }

    $self->_restore_stderr;
    $self->_reap_commands;

    return $result;

}

sub listcells {

    my $self = shift;
    my (%args) = @_;

    my $result = AFS::Object::CacheManager->new;

    $self->operation( q{listcells} );

    $self->_parse_arguments(%args);
    $self->_save_stderr;
    $self->_exec_commands;

    while ( defined($_ = $self->_handle->getline) ) {
        if ( m{^Cell (\S+) on hosts (.*)\.$}ms ) {
            my $cell = AFS::Object::Cell->new(
                cell    => $1,
                servers => [split(/\s+/,$2)],
            );
            $result->_addCell($cell);
        }
    }

    $self->_restore_stderr;
    $self->_reap_commands;

    return $result;

}

sub lsmount {

    my $self = shift;
    my (%args) = @_;

    my $result = AFS::Object::CacheManager->new;

    $self->operation( q{lsmount} );

    $self->_parse_arguments(%args);
    $self->_exec_commands( stderr => q{stdout} );

    my @dirs = ref $args{dir} eq q{ARRAY} ? @{$args{dir}} : ($args{dir});
    my %dirs = map { $_ => 1 } @dirs;

    while ( defined($_ = $self->_handle->getline) ) {

        my $current = shift @dirs;
        delete $dirs{$current};

        my $path = AFS::Object::Path->new( path => $current );

        given ( $_ ) {

            when ( m{fs: Can.t read target name}ms ) {
                $path->_setAttribute( error => $_ );
            }
            when ( m{fs: File '.*' doesn't exist}ms ) {
                $path->_setAttribute( error => $_ );
            }
            when ( m{fs: you may not use \'.\'}ms ) {
                $_ .= $self->_handle->getline;
                $path->_setAttribute( error => $_ );
            }
            when ( m{\'(.*?)\' is not a mount point}ms ) {
                $path->_setAttribute( error => $_ );
            }

            when ( m{^\'(.*?)\'.*?\'(.*?)\'$}ms ) {

                my ($dir,$mount) = ($1,$2);

                $path->_setAttribute( symlink => 1 ) if m{symbolic link}ms;
                $path->_setAttribute( readwrite => 1 ) if $mount =~ m{^%}ms;
                $mount =~ s{^(%|\#)}{}ms;

                my ($volname,$cell) = reverse split( m{:}msx, $mount );

                $path->_setAttribute( volname => $volname );
                $path->_setAttribute( cell => $cell) if $cell;

            }

            default {
                croak qq{fs lsmount: Unrecognized output: '$_'};
            }

        }

        $result->_addPath($path);

    }

    foreach my $dir ( keys %dirs ) {
        my $path = AFS::Object::Path->new(
            path  => $dir,
            error => q{Unable to determine results},
        );
        $result->_addPath($path);
    }

    $self->_reap_commands( allowstatus => 1 );

    return $result;

}

#
# This is deprecated in newer versions of OpenAFS
#
sub monitor {
    croak qq{fs monitor: This operation is deprecated and no longer supported};
}

sub sysname {

    my $self = shift;
    my (%args) = @_;

    my $result = AFS::Object::CacheManager->new;

    $self->operation( q{sysname} );

    $self->_parse_arguments(%args);
    $self->_save_stderr;
    $self->_exec_commands;

    my @sysname = ();

    while ( defined($_ = $self->_handle->getline) ) {

        if ( m{Current sysname is \'?([^\']+)\'?}ms ) {
            $result->_setAttribute( sysname => $1 );
        } elsif ( s{Current sysname list is }{}ms ) {
            while ( s{\'([^\']+)\'\s*}{}ms ) {
                push @sysname, $1;
            }
            $result->_setAttribute( sysnames => \@sysname );
            $result->_setAttribute( sysname => $sysname[0] );
        }

    }

    $self->_restore_stderr;
    $self->_reap_commands;

    return $result;

}

sub wscell {

    my $self = shift;
    my (%args) = @_;

    my $result = AFS::Object::CacheManager->new;

    $self->operation( q{wscell} );

    $self->_parse_arguments(%args);
    $self->_save_stderr;
    $self->_exec_commands;

    while ( defined($_ = $self->_handle->getline) ) {
        next if not m{belongs to cell\s+\'(.*)\'}ms;
        $result->_setAttribute( cell => $1 );
    }

    $self->_restore_stderr;
    $self->_reap_commands;

    return $result;

}

1;

