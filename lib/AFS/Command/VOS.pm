package AFS::Command::VOS;

use Moose;
use English;
use Carp;

use feature q{switch};

extends qw(AFS::Command::Base);

use AFS::Object;
use AFS::Object::VLDB;
use AFS::Object::VLDBEntry;
use AFS::Object::VLDBSite;
use AFS::Object::Volume;
use AFS::Object::VolumeHeader;
use AFS::Object::VolServer;
use AFS::Object::FileServer;
use AFS::Object::Partition;
use AFS::Object::Transaction;

sub backupsys {

    my $self = shift;
    my %args = @_;

    $self->operation( q{backupsys} );

    my $result = AFS::Object->new;

    $self->_parse_arguments(%args);
    $self->_save_stderr;
    $self->_exec_commands;

    my @volumes = ();

    while ( defined($_ = $self->_handle->getline) ) {

        chomp;

        given ( $_ ) {

            when ( m{Would have backed up volumes}ms ) {
                while ( defined($_ = $self->_handle->getline) ) {
                    chomp;
                    last if m{^done};
                    s{^\s+}{}ms;
                    push @volumes, $_;
                }
            }

            when ( m{Creating backup volume for (\S+)}ms ) {
                push @volumes, $1;
            }

            when ( m{Total volumes backed up: (\d+); failed to backup: (\d+)}ms ) {
                $result->_setAttribute( total => $1, failed => $2 );
            }

        }

    }

    $result->_setAttribute( volumes => \@volumes );

    $self->_restore_stderr;
    $self->_reap_commands;

    return $result;

}

sub examine {

    my $self = shift;
    my %args = @_;

    if ( exists $args{format} ) {
        croak qq{Unsupported 'vos examine' argument: -format\n};
    }

    my $result = AFS::Object::Volume->new;
    my $entry  = AFS::Object::VLDBEntry->new( locked => 0 );

    $self->operation( q{examine} );

    $self->_parse_arguments(%args);
    $self->_save_stderr;
    $self->_exec_commands;

    while ( defined($_ = $self->_handle->getline) ) {

        chomp;

        # These two lines are part of the verbose output
        next if m{Fetching VLDB entry}ms;
        next if m{Getting volume listing}ms;

        #
        # This code parses the volume header information.  If we match
        # this line, then we go after the information we expect to be
        # right after it.  We also test for this first, because we
        # might very well have several of these chunks of data for RO
        # volumes.
        #
        my $header = q{};

        if ( m{^\*{4}}ms ) {

            $header = AFS::Object::VolumeHeader->new;

            if ( m{Volume (\d+) is busy}ms ) {
                $header->_setAttribute(
                    id       => $1,
                    status   => q{busy},
                    attached => 1,
                );
            } elsif ( m{Could not attach volume (\d+)}ms ) {
                $header->_setAttribute(
                    id       => $1,
                    status   => q{offline},
                    attached => 0,
                );
            }

            $result->_addVolumeHeader($header);

            next;

        } elsif ( m{^(\S+)\s+(\d+)\s+(RW|RO|BK)\s+(\d+)\s+K}ms ) {

            $header = AFS::Object::VolumeHeader->new;

            if ( m{^(\S+)\s+(\d+)\s+(RW|RO|BK)\s+(\d+)\s+K\s+([\w-]+)}ms ) {

                $header->_setAttribute(
                    name => $1,
                    id   => $2,
                    type => $3,
                    size => $4,
                );
                $header->_setAttribute( rwrite  => $2 ) if $3 eq q{RW};
                $header->_setAttribute( ronly   => $2 ) if $3 eq q{RO};
                $header->_setAttribute( backup  => $2 ) if $3 eq q{BK};

                my $status = $5;
                $status = q{offline} if $status eq q{Off-line};
                $status = q{online}  if $status eq q{On-line};
                $header->_setAttribute(
                    status   => $status,
                    attached => 1,
                );

            } elsif ( m{^(\S+)\s+(\d+)\s+(RW|RO|BK)\s+(\d+)\s+K\s+used\s+(\d+)\s+files\s+([\w-]+)}ms ) {

                $header->_setAttribute(
                    name  => $1,
                    id    => $2,
                    type  => $3,
                    size  => $4,
                    files => $5,
                );
                $header->_setAttribute( rwrite  => $2 ) if $3 eq q{RW};
                $header->_setAttribute( ronly   => $2 ) if $3 eq q{RO};
                $header->_setAttribute( backup  => $2 ) if $3 eq q{BK};

                my $status = $6;
                $status = q{offline} if $status eq q{Off-line};
                $status = q{online}  if $status eq q{On-line};
                $header->_setAttribute(
                    status   => $status,
                    attached => 1,
                );

            } else {

                croak qq{Unable to parse volume header: '$_'};

            }

            #
            # We are interested in the next 6 lines as they are also
            # from the same volume headers as the one we just matched.
            # Suck data until we get to a blank line.
            #
            while ( defined($_ = $self->_handle->getline) ) {

                chomp;

                given ( $_ ) {

                    when ( m{^\s*$}ms ) {
                        # Stop when we hit the blank line
                        last;
                    }

                    when ( m{^\s+(\S+)\s+(/vicep\w+)\s*$}ms ) {
                        $header->_setAttribute(
                            server    => $1,
                            partition => $2,
                        );
                    }

                    #
                    # Next we get ALL the volume IDs we can off this next
                    # line.
                    #
                    # Q: Do we want to check that the id already found
                    # matches one of these??  Not yet...
                    #
                    when ( m{^\s+RWrite\s+(\d+)\s+ROnly\s+(\d+)\s+Backup\s+(\d+)}ms ) {
                        $header->_setAttribute(
                            rwrite => $1,
                            ronly  => $2,
                            backup => $3,
                        );
                        if ( m{RClone\s+(\d+)}ms ) {
                            $header->_setAttribute( rclone => $1 );
                        }
                    }

                    when ( m{^\s+MaxQuota\s+(\d+)}ms ) {
                        $header->_setAttribute( maxquota => $1 );
                    }

                    when ( m{^\s+Creation\s+(.*)\s*$}ms ) {
                        $header->_setAttribute( creation => $1 );
                    }

                    when ( m{^\s+Copy\s+(.*)\s*$}ms ) {
                        $header->_setAttribute( copyTime => $1 );
                    }

                    when ( m{^\s+Backup\s+(.*)\s*$}ms ) {
                        $header->_setAttribute( backupTime => $1 );
                    }

                    when ( m{^\s+Last Access\s+(.*)\s*$}ms ) {
                        $header->_setAttribute( access => $1 );
                    }

                    when ( m{^\s+Last Update\s+(.*)\s*$}ms ) {
                        $header->_setAttribute( update => $1 );
                    }

                    when ( m{^\s+(\d+) accesses}ms ) {
                        $header->_setAttribute( accesses => $1 );
                    }

                    default {
                        croak( qq{Unrecognized output format:\n} . $_ );
                    }

                }

            }

            #
            # Are we looking for extended data??
            #
            if ( $args{extended} ) {

                my $raw    = AFS::Object->new;
                my $author = AFS::Object->new;

                my $boundary = 0;

                while ( defined($_ = $self->_handle->getline) ) {

                    chomp;

                    $boundary++ if m{^\s+\|-+\|\s*$}ms;

                    last if m{^\s*$}ms and $boundary == 4;

                    next if not m{\s+(\d+)\s+\|\s+(\d+)\s+\|\s+(\d+)\s+\|\s+(\d+)\s+\|}ms;

                    my @column = ( $1, $2, $3, $4 );

                    my $class = q{};
                    my $int   = q{};

                    $class = q{reads}  if m{^Reads}ms;
                    $class = q{writes} if m{^Writes}ms;

                    if ( $class ) {

                        my $same = AFS::Object->new(
                            total => $column[0],
                            auth  => $column[1],
                        );

                        my $diff = AFS::Object->new(
                           total => $column[2],
                           auth  => $column[3],
                          );

                        my $stats = AFS::Object->new(
                            same => $same,
                            diff => $diff,
                        );

                        $raw->_setAttribute( $class => $stats );

                    }

                    $int = q{0sec}  if m{^0-60 sec}ms;
                    $int = q{1min}  if m{^1-10 min}ms;
                    $int = q{10min} if m{^10min-1hr}ms;
                    $int = q{1hr}   if m{^1hr-1day}ms;
                    $int = q{1day}  if m{^1day-1wk}ms;
                    $int = q{1wk}   if m{^> 1wk}ms;

                    if ( $int ) {

                        my $file = AFS::Object->new(
                            same => $column[0],
                            diff => $column[1],
                        );

                        my $dir = AFS::Object->new(
                            same => $column[2],
                            diff => $column[3],
                        );

                        my $stats = AFS::Object->new(
                            file => $file,
                            dir  => $dir,
                        );

                        $author->_setAttribute( $int => $stats );

                    }

                }

                $header->_setAttribute(
                    raw    => $raw,
                    author => $author,
                );

            }

            $result->_addVolumeHeader($header);

            next;

        }

        #
        # The rest of the information we get will be from the
        # VLDB. This will start with the volume ids, which we DO want
        # to check against those found above, since they are from a
        # different source, and a conflict is cause for concern.
        #
        if ( m{^\s+RWrite:\s+(\d+)}ms ) {
            if ( m{RWrite:\s+(\d+)}ms ) { $entry->_setAttribute( rwrite => $1 ); }
            if ( m{ROnly:\s+(\d+)}ms )  { $entry->_setAttribute( ronly  => $1 ); }
            if ( m{Backup:\s+(\d+)}ms ) { $entry->_setAttribute( backup => $1 ); }
            if ( m{RClone:\s+(\d+)}ms ) { $entry->_setAttribute( rclone => $1 ); }
            next;
        }


        #
        # Next we are looking for the number of sites, and then we'll
        # suck that data in as well.
        #
        # NOTE: Because there is more interesting data after the
        # locations, we fall through to the next test once we are done
        # parsing them.
        #
        if ( m{^\s+number of sites ->\s+(\d+)}ms ) {

            while ( defined($_ = $self->_handle->getline) ) {

                chomp;

                last if not m{^\s+server\s+(\S+)\s+partition\s+(/vicep\w+)\s+([A-Z]{2})\s+Site\s*(--\s+)?(.*)?}ms;

                my $site = AFS::Object::VLDBSite->new(
                    server    => $1,
                    partition => $2,
                    type      => $3,
                    status    => $5,
                );

                $entry->_addVLDBSite($site);

            }

        }

        #
        # Last possibility (that we know of) -- volume might be
        # locked.
        #
        if ( m{LOCKED}ms ) {
            $entry->_setAttribute( locked => 1 );
            next;
        }

        #
        # Actually, this is the last possibility...  The volume name
        # leading the VLDB entry stanza.
        #
        if ( m{^(\S+)}ms ) {
            $entry->_setAttribute( name => $1 );
        }

    }

    $result->_addVLDBEntry($entry);

    $self->_restore_stderr;

    if ( $self->_errors =~ m{VLDB: no such entry}ms ) {
        $self->_reap_commands( allowstatus => [ 1, 255 ] );
        return;
    } else {
        $self->_reap_commands;
        return $result;
    }

}

sub listaddrs {

    my $self = shift;
    my %args = @_;

    my @result = ();

    $self->operation( q{listaddrs} );

    $self->_parse_arguments(%args);
    $self->_save_stderr;
    $self->_exec_commands;

    if ( $args{printuuid} ) {

        while ( defined($_ = $self->_handle->getline) ) {

            chomp;

            if ( m{^UUID:\s+(\S+)}ms ) {

                my $fileserver = AFS::Object::FileServer->new( uuid => $1 );

                my @addresses = ();
                my $hostname  = q{};

                while ( defined($_ = $self->_handle->getline) ) {
                    s{^\s*}{}gms;
                    s{\s*$}{}gms;
                    last if m{^\s*$}ms;
                    chomp;
                    if ( m{^\d+\.\d+\.\d+\.\d+$}ms ) {
                        push @addresses, $_;
                    } else {
                        $hostname = $_;
                    }
                }

                $fileserver->_setAttribute( addresses => \@addresses ) if @addresses;
                $fileserver->_setAttribute( hostname => $hostname )    if $hostname;

                push @result, $fileserver;

            }

        }

    } elsif ( $args{uuid} ) {

        my @addresses = ();
        my $hostname  = q{};

        while ( defined($_ = $self->_handle->getline) ) {
            chomp;
            s{^\s*}{}gms;
            s{\s*$}{}gms;
            if ( m{^\d+\.\d+\.\d+\.\d+$}ms ) {
                push @addresses, $_;
            } else {
                $hostname = $_;
            }
        }

        if ( $hostname || @addresses ) {
            my $fileserver = AFS::Object::FileServer->new;
            $fileserver->_setAttribute( addresses => \@addresses ) if @addresses;
            $fileserver->_setAttribute( hostname => $hostname )    if $hostname;
            push @result, $fileserver;
        }

    } else {

        while ( defined($_ = $self->_handle->getline) ) {
            chomp;
            s{^\s*}{}gms;
            s{\s*$}{}gms;
            if ( m{^\d+\.\d+\.\d+\.\d+$}ms ) {
                push @result, AFS::Object::FileServer->new( addresses => [$_] );
            } else {
                push @result, AFS::Object::FileServer->new( hostname => $_ );
            }
        }       

    }

    $self->_restore_stderr;
    $self->_reap_commands;

    return @result;

}

sub listpart {

    my $self = shift;
    my %args = @_;

    my $result = AFS::Object::FileServer->new;

    $self->operation( q{listpart} );

    $self->_parse_arguments(%args);
    $self->_save_stderr;
    $self->_exec_commands;

    while ( defined($_ = $self->_handle->getline) ) {

        chomp;

        next if not m{/vice}ms;

        s{^\s+}{}gms;
        s{\s+$}{}gms;

        foreach my $partname ( split ) {
            my $partition = AFS::Object::Partition->new( partition => $partname );
            $result->_addPartition($partition);
        }

    }

    $self->_restore_stderr;
    $self->_reap_commands;

    return $result;

}

sub listvldb {

    my $self = shift;
    my %args = @_;

    $self->operation( q{listvldb} );

    my $locked = 0;

    my $result = AFS::Object::VLDB->new;

    $self->_parse_arguments(%args);
    $self->_save_stderr;
    $self->_exec_commands;

    while ( defined($_ = $self->_handle->getline) ) {

        chomp;


        # If it starts with a blank line, then its not a volume name.
        next if m{^\s*$}ms;

        # Skip the introductory lines of the form:
        # "VLDB entries for all servers"
        # "VLDB entries for server ny91af01"
        # "VLDB entries for server ny91af01 partition /vicepa"
        next if m{^VLDB entries for }ms;

        s{\s+$}{}gms;              # Might be trailing whitespace...

        #
        # We either get the total number of volumes, or we assume the
        # line is a volume name.
        #
        if ( m{Total entries:\s+(\d+)}ms ) {
            $result->_setAttribute( total => $1 );
            next;
        }

        my $name = $_;

        my $entry = AFS::Object::VLDBEntry->new( name => $name );

        while ( defined($_ = $self->_handle->getline) ) {

            chomp;

            last if m{^\s*$}ms;    # Volume info ends with a blank line

            if ( m{RWrite:\s+(\d+)}ms ) { $entry->_setAttribute( rwrite => $1 ); }
            if ( m{ROnly:\s+(\d+)}ms )  { $entry->_setAttribute( ronly  => $1 ); }
            if ( m{Backup:\s+(\d+)}ms ) { $entry->_setAttribute( backup => $1 ); }
            if ( m{RClone:\s+(\d+)}ms ) { $entry->_setAttribute( rclone => $1 ); }

            if ( m{^\s+number of sites ->\s+(\d+)}ms ) {

                my $sites = $1;

                while ( defined($_ = $self->_handle->getline) ) {

                    chomp;

                    next if not m{^\s+server\s+(\S+)\s+partition\s+(/vicep\w+)\s+([A-Z]{2})\s+Site\s*(--\s+)?(.*)?}ms;

                    $sites--;

                    my $site = AFS::Object::VLDBSite->new(
                        server    => $1,
                        partition => $2,
                        type      => $3,
                        status    => $5,
                    );

                    $entry->_addVLDBSite( $site );

                    last if $sites == 0;

                }

            }

            #
            # Last possibility (that we know of) -- volume might be
            # locked.
            #
            if ( m{LOCKED}ms ) {
                $entry->_setAttribute( locked => 1 );
                $locked++;
            }

        }

        $result->_addVLDBEntry( $entry );

    }

    $result->_setAttribute( locked => $locked );

    $self->_restore_stderr;

    if ( $self->_errors =~ m{VLDB: no such entry}ms ) {
        $self->_reap_commands( allowstatus => 1 );
        return;
    } else {
        $self->_reap_commands;
        return $result;
    }

}


sub listvol {

    my $self = shift;
    my %args = @_;

    if ( exists $args{format} ) {
        croak qq{Unsupported 'vos listvol' argument: -format\n};
    }

    my $result = AFS::Object::VolServer->new;

    $self->operation( q{listvol} );

    $self->_parse_arguments(%args);
    $self->_save_stderr;
    $self->_exec_commands;

    if ( delete $args{extended} ) {
        carp qq{vos listvol: -extended is not supported by this version of the API};
    }

    while ( defined($_ = $self->_handle->getline) ) {

        chomp;

        next if m{^\s*$}ms;        # Blank lines are not interesting

        next if not m{^Total number of volumes on server \S+ partition (\/vice[\w]+): (\d+)}ms;

        my $partition = AFS::Object::Partition->new(
            partition => $1,
            total     => $2,
        );

        while ( defined($_ = $self->_handle->getline) ) {

            chomp;

            last if m{^\s*$}ms and $args{fast};
            next if m{^\s*$};

            s{\s+$}{}ms;

            if ( m{^Total volumes onLine (\d+) ; Total volumes offLine (\d+) ; Total busy (\d+)}ms ) {
                $partition->_setAttribute(
                    online  => $1,
                    offline => $2,
                    busy    => $3,
                );
                last;           # Done with this partition
            }

            if ( m{Volume (\d+) is busy}ms ) {
                my $volume = AFS::Object::VolumeHeader->new(
                    id       => $1,
                    status   => q{busy},
                    attached => 1,
                );
                $partition->_addVolumeHeader($volume);
                next;
            } elsif ( m{Could not attach volume (\d+)}ms ) {
                my $volume = AFS::Object::VolumeHeader->new(
                    id       => $1,
                    status   => q{offline},
                    attached => 0,
                );
                $partition->_addVolumeHeader($volume);
                next;
            }

            #
            # We have to handle multiple formats here.  For now, just
            # parse the "fast" and normal output.  Extended is not yet
            # supported.
            #

            my (@array) = split;
            my ($name,$id,$type,$size,$status) = ();

            my $volume = AFS::Object::VolumeHeader->new;

            if ( @array == 6 ) {
                ($name,$id,$type,$size,$status) = @array[0..3,5];
                $status = q{offline} if $status eq q{Off-line};
                $status = q{online}  if $status eq q{On-line};
                $volume->_setAttribute(
                    id       => $id,
                    name     => $name,
                    type     => $type,
                    size     => $size,
                    status   => $status,
                    attached => 1,
                );
            } elsif ( @array == 1 ) {
                $volume->_setAttribute(
                    id       => $_,
                    status   => q{online},
                    attached => 1,
                );
            } else {
                croak( qq{Unable to parse header summary line:\n} . $_ );
            }

            #
            # If the output is long, then we have some more
            # interesting information to parse.  See vos/examine.pl
            # for notes.  This code was stolen from there...
            #

            if ( $args{long} or $args{extended} ) {

                while ( defined($_ = $self->_handle->getline) ) {

                    given ( $_ ) {

                        when ( m{^\s*$}ms ) {
                            last;
                        }

                        when ( m{^\s+RWrite\s+(\d+)\s+ROnly\s+(\d+)\s+Backup\s+(\d+)}ms ) {
                            $volume->_setAttribute(
                                rwrite => $1,
                                ronly  => $2,
                                backup => $3,
                            );
                            if ( m{RClone\s+(\d+)}ms ) {
                                $volume->_setAttribute( rclone => $1 );
                            }
                        }

                        when ( m{^\s+MaxQuota\s+(\d+)}ms ) {
                            $volume->_setAttribute( maxquota => $1 );
                        }

                        when ( m{^\s+Creation\s+(.*)\s*$}ms ) {
                            $volume->_setAttribute( creation => $1 );
                        }

                        when ( m{^\s+Copy\s+(.*)\s*$}ms ) {
                            $volume->_setAttribute( copyTime    => $1 );
                        }

                        when ( m{^\s+Backup\s+(.*)\s*$}ms ) {
                            $volume->_setAttribute( backupTime  => $1 );
                        }

                        when ( m{^\s+Last Access\s+(.*)\s*$}ms ) {
                            $volume->_setAttribute( access      => $1 );
                        }

                        when ( m{^\s+Last Update\s+(.*)\s*$}ms ) {
                            $volume->_setAttribute( update => $1 );
                        }

                        when ( m{^\s+(\d+) accesses}ms ) {
                            $volume->_setAttribute( accesses => $1 );
                        }

                    }
                    
                }  # while(defined($_ = $self->_handle->getline)) {

            }

            $partition->_addVolumeHeader($volume);

        }

        $result->_addPartition($partition);

    }

    $self->_restore_stderr;
    $self->_reap_commands;

    return $result;

}

sub partinfo {

    my $self = shift;
    my %args = @_;

    my $result = AFS::Object::FileServer->new;

    $self->operation( q{partinfo} );

    if ( $self->supportsArgument( q{partinfo}, q{summary} ) ) {
        $args{summary} = 1;
    }

    $self->_parse_arguments(%args);
    $self->_save_stderr;
    $self->_exec_commands;

    while ( defined($_ = $self->_handle->getline) ) {

        if ( m{partition (/vice\w+): (-?\d+)\D+(\d+)$}ms ) {
            my $partition = AFS::Object::Partition->new(
                partition => $1,
                available => $2,
                total     => $3,
            );
            $result->_addPartition($partition);
        }

        if ( m{Summary: (\d+) KB free out of (\d+) KB on (\d+) partitions}ms ) {
            $result->_setAttribute(
                available  => $1,
                total      => $2,
                partitions => $3,
            );
        }
        
    }

    $self->_restore_stderr;
    $self->_reap_commands;

    return $result;

}

sub size {

    my $self = shift;
    my %args = @_;

    $self->operation( q{size} );

    my $result = AFS::Object->new;

    # This is because without -dump, the command is meaningless
    $args{dump} = 1;

    $self->_parse_arguments(%args);
    $self->_save_stderr;
    $self->_exec_commands;

    while ( defined($_ = $self->_handle->getline) ) {

        chomp;

        given ( $_ ) {
            when ( m{Volume: (.*)}ms ) {
                $result->_setAttribute( volume => $1 );
            }
            when ( m{dump_size: (\d+)}ms ) {
                $result->_setAttribute( dump_size => $1 );
            }
        }

    }

    $self->_restore_stderr;

    if ( $self->_errors =~ m{VLDB: no such entry}ms ) {
        $self->_reap_commands( allowstatus => [ 1, 255 ] );
        return;
    } else {
        $self->_reap_commands;
        return $result;
    }

}

sub status {

    my $self = shift;
    my %args = @_;

    my $result = AFS::Object::VolServer->new;

    $self->operation( q{status} );

    $self->_parse_arguments(%args);
    $self->_save_stderr;
    $self->_exec_commands;

    my $transaction = undef;

    while ( defined($_ = $self->_handle->getline) ) {

        chomp;

        if ( m{No active transactions}ms ) {
            $result->_setAttribute( transactions => 0 );
            last;
        }

        if ( m{Total transactions: (\d+)}ms ) {
            $result->_setAttribute( transactions => $1 );
            next;
        }

        if ( m{^-+\s*$}ms ) {
            if ( $transaction ) {
                $result->_addTransaction($transaction);
                $transaction = undef;
            } else {
                $transaction = AFS::Object::Transaction->new;
            }
        }

        next if not $transaction;

        if ( m{transaction:\s+(\d+)}ms ) {
            $transaction->_setAttribute( transaction => $1 );
        }

        if ( m{created:\s+(.*)$}ms ) {
            $transaction->_setAttribute( created => $1 );
        }

        if ( m{attachFlags:\s+(.*)$}ms ) {
            $transaction->_setAttribute( attachFlags => $1 );
        }

        if ( m{volume:\s+(\d+)}ms ) {
            $transaction->_setAttribute( volume => $1 );
        }

        if ( m{partition:\s+(\S+)}ms ) {
            $transaction->_setAttribute( partition => $1 );
        }

        if ( m{procedure:\s+(\S+)}ms ) {
            $transaction->_setAttribute( procedure => $1 );
        }

        if ( m{packetRead:\s+(\d+)}ms ) {
            $transaction->_setAttribute( packetRead => $1 );
        }

        if ( m{lastReceiveTime:\s+(\d+)}ms ) {
            $transaction->_setAttribute( lastReceiveTime => $1 );
        }

        if ( m{packetSend:\s+(\d+)}ms ) {
            $transaction->_setAttribute( packetSend => $1 );
        }

        if ( m{lastSendTime:\s+(\d+)}ms ) {
            $transaction->_setAttribute( lastSendTime => $1 );
        }

    }

    $self->_restore_stderr;
    $self->_reap_commands;

    return $result;

}

sub dump {

    my $self = shift;
    my %args = @_;

    $self->operation( q{dump} );

    my $file = delete $args{file} || 
        croak qq{Missing required argument: 'file'};

    my $gzip_default  = 6;
    my $bzip2_default = 6;

    my $nocompress = delete $args{nocompress} || undef;
    my $gzip       = delete $args{gzip}       || undef;
    my $bzip2      = delete $args{bzip2}      || undef;
    my $filterout  = delete $args{filterout}  || undef;

    if ( $gzip and $bzip2 and $nocompress ) {
        croak qq{Invalid argument combination: only one of 'gzip' or 'bzip2' or 'nocompress' may be specified};
    }

    if ( $file eq q{stdin} ) {
        croak qq{Invalid argument 'stdin': you can't write output to stdin};
    }

    if ( $file ne q{stdout} ) {

        if ( $file =~ m{\.gz$}ms and not defined $gzip and not defined $nocompress ) {
            $gzip  = $gzip_default;
        } elsif ( $file =~ m{\.bz2$}ms and not defined $bzip2 and not defined $nocompress ) {
            $bzip2 = $bzip2_default;
        }

        if ( $gzip and not $file =~ m{\.gz$}ms ) {
            $file .= q{.gz};
        } elsif ( $bzip2 and not $file =~ m{\.bz2$}ms ) {
            $file .= q{.bz2};
        }

        if ( not $gzip and not $bzip2 and not $filterout ) {
            $args{file} = $file;
        }

    }

    $self->_parse_arguments(%args);

    my @commands = @{ $self->_commands };

    if ( $filterout ) {

        if ( ref $filterout ne q{ARRAY} ) {
            croak qq{Invalid argument 'filterout': must be an ARRAY reference};
        }

        if ( ref $filterout->[0] eq q{ARRAY} ) {
            foreach my $filter ( @$filterout ) {
                if ( ref $filter ne q{ARRAY} ) {
                    croak(
                        qq{Invalid argument 'filterout': must be an ARRAY of ARRAY references, \n},
                        qq{OR an ARRAY of strings.  See the documentation for details},
                    );
                }
                push @commands, $filter;
            }
        } else {
            push @commands, $filterout;
        }

    };

    if ( $gzip ) {
        push @commands, [ q{gzip}, qq{-$gzip}, q{-c} ];
    } elsif ( $bzip2 ) {
        push @commands, [ q{bzip2}, qq{-$bzip2}, q{-c} ];
    }

    $self->_commands( \@commands );

    $self->_save_stderr;
    $self->_exec_commands( stdout => ( $args{file} ? q{/dev/null} : $file ) );
    $self->_restore_stderr;
    $self->_reap_commands;

    return 1;

}

sub restore {

    my $self = shift;
    my %args = @_;

    $self->operation( q{restore} );

    my $file = delete $args{file} || 
        croak qq{Missing required argument: 'file'};

    my $nocompress = delete $args{nocompress} || undef;
    my $gunzip     = delete $args{gunzip}     || undef;
    my $bunzip2    = delete $args{bunzip2}    || undef;
    my $filterin   = delete $args{filterin}   || undef;;

    if ( $gunzip and $bunzip2 and $nocompress ) {
        croak qq{Invalid argument combination: only one of 'gunzip' or 'bunzip2' or 'nocompress' may be specified};
    }

    if ( $file eq q{stdout} ) {
        croak qq{Invalid argument 'stdout': you can't read input from stdout};
    }

    if ( $file ne q{stdin} ) {

        if ( $file =~ m{\.gz$} and not defined $gunzip and not defined $nocompress ) {
            $gunzip = 1;
        } elsif ( $file =~ m{\.bz2$}ms and not defined $bunzip2 and not defined $nocompress ) {
            $bunzip2 = 1;
        }

        if ( not $gunzip and not $bunzip2 and not $filterin ) {
            $args{file} = $file;
        }

    }

    $self->_parse_arguments(%args);

    my @commands = @{ $self->_commands };

    if ( $filterin ) {

        if ( ref $filterin ne q{ARRAY} ) {
            croak qq{Invalid argument 'filterin': must be an ARRAY reference};
        }

        if ( ref $filterin->[0] eq q{ARRAY} ) {
            foreach my $filter ( @{ $filterin } ) {
                if ( ref $filter ne q{ARRAY} ) {
                    croak(
                        qq{Invalid argument 'filterin': must be an ARRAY of ARRAY references, \n},
                        qq{OR an ARRAY of strings.  See the documentation for details},
                    );
                }
                unshift @commands, $filter;
            }
        } else {
            unshift @commands, $filterin;
        }

    };

    if ( $gunzip ) {
        unshift @commands, [ q{gunzip}, q{-c} ];
    } elsif ( $bunzip2 ) {
        unshift @commands, [ q{bunzip2}, q{-c} ];
    }

    $self->_commands( \@commands );

    $self->_exec_commands(
        stderr => q{stdout},
        stdin  => $args{file} ? q{/dev/null} : $file,
    );

    $self->_parse_output;
    $self->_reap_commands;

    return 1;

}

1;

