
package AFS::Command::VOS;

use strict;
use English;

use AFS::Command::Base;
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

our @ISA = qw(AFS::Command::Base);
our $VERSION = '1.99';

sub backupsys {

    my $self = shift;
    my (%args) = @_;

    my $result = AFS::Object->new();

    $self->{operation} = "backupsys";

    return unless $self->_parse_arguments(%args);

    return unless $self->_save_stderr();

    my $errors = 0;

    $errors++ unless $self->_exec_cmds();

    while ( defined($_ = $self->{handle}->getline()) ) {

	chomp;

	next unless ( /Total\s+volumes\s+backed\s+up:\s+(\d+);\s+failed\s+to\s+back\s+up:\s+(\d+)/ );

    $result->_setAttribute(
        total => $1,
        failed => $2,
    );

    }

    $errors++ unless $self->_reap_cmds();
    $errors++ unless $self->_restore_stderr();

    return if $errors;
    return $result;

}

sub eachfs {

    my $self = shift;
    my (%args) = @_;

    my $result = AFS::Object->new();

    $self->{operation} = "eachfs";

    # verbose output for 'eachfs' isn't useful
    my $quiet = ( exists $self->{quiet} and $self->{quiet} );
    $self->{quiet} = 1 unless ( exists $args{verbose} or $quiet );

    return unless $self->_parse_arguments(%args);

    return unless $self->_save_stderr();

    my $errors = 0;

    $errors++ unless $self->_exec_cmds();

    my @output;
    while ( defined($_ = $self->{handle}->getline()) ) {

	chomp;
    push @output, $_;

    }

    $result->_setAttribute( output => \@output );

    $errors++ unless $self->_reap_cmds();
    $errors++ unless $self->_restore_stderr();

    # reset quiet
    delete $self->{quiet} unless ( $quiet );

    return $result;

}

sub eachvol {

    my $self = shift;
    my (%args) = @_;

    my $result = AFS::Object->new();

    $self->{operation} = "eachvol";

    # verbose output for 'eachvol' isn't useful
    # need to restart
    my $quiet = ( exists $self->{quiet} and $self->{quiet} );
    $self->{quiet} = 1 unless ( exists $args{verbose} or $quiet );

    return unless $self->_parse_arguments(%args);

    return unless $self->_save_stderr();

    my $errors = 0;

    $errors++ unless $self->_exec_cmds( );

    my @output;
    while ( defined($_ = $self->{handle}->getline()) ) {

	chomp;
    push @output, $_;

    }

    $result->_setAttribute( output => \@output );

    $errors++ unless $self->_reap_cmds();
    $errors++ unless $self->_restore_stderr();

    # reset quiet
    delete $self->{quiet} unless ( $quiet );

    return $result;

}

sub examine {

    my $self = shift;
    my (%args) = @_;

    my $result = AFS::Object::Volume->new();
    my $entry = AFS::Object::VLDBEntry->new( locked => 0 );

    $self->{operation} = "examine";

    return unless $self->_parse_arguments(%args);

    return unless $self->_save_stderr();

    my $errors = 0;

    $errors++ unless $self->_exec_cmds();

    my $auristor;

    while ( defined($_ = $self->{handle}->getline()) ) {

	chomp;

	#
	# These two lines are part of the verbose output
	#
	next if /Fetching (VLDB entry|information) for/;
	next if /Getting volume listing/;

	#
	# This code parses the volume header information.  If we match
	# this line, then we go after the information we expect to be
	# right after it.  We also test for this first, because we
	# might very well have several of these chunks of data for RO
	# volumes.
	#
	if ( /^\*{4}/ ) {

	    my $header = AFS::Object::VolumeHeader->new();

	    if ( /Volume (\d+) is busy/ ) {
		$header->_setAttribute
		  (
		   id			=> $1,
		   status		=> 'busy',
		   attached		=> 1,
		  );
	    } elsif ( /Could not attach volume (\d+)/ ) {
		$header->_setAttribute
		  (
		   id			=> $1,
		   status		=> 'offline',
		   attached		=> 0,
		  );
	    }

	    $result->_addVolumeHeader($header);

	    next;

    # AuriStor changed from
    # root.cell                         536870915 RW         33 K used 28 files On-line
    #
    # to
    #
    # root.cell
    #     RWrite: 1048578       ROnly: 1048579
    #
    #     afs.your-cell-name.com:7005 /vicepa    1048578 RW On-line
    #
    #     Used                31 K
    #     FileCount           26
    } elsif ( /^(\S+)$/ ) {
        # AuriStor volume name and volume IDs
        $auristor->{name} = $1;
        next unless ( defined($_ = $self->{handle}->getline()) );
        $self->_Carp("Unrecognized output format (expected AuriStor volume IDs):\n" . $_)
            unless ( /RWrite:/ );
        $auristor->{rwrite} = $1 if ( /RWrite:\s*(\d+)/ );
        $auristor->{ronly}  = $1 if ( /ROnly:\s*(\d+)/ );
        $auristor->{backup} = $1 if ( /Backup:\s*(\d+)/ );
        $auristor->{rclone} = $1 if ( /RClone:\s+(\d+)/ );

	} elsif ( /^(\S+)\s+(\d+)\s+(RW|RO|BK)\s+(\d+)\s+K/ or /^\s*(\S+):(\d+)\s+(\/vicep\w+)\s+(\d+)\s+(RW|RO|BK)\s+(\S+)/ ) {

	    my $header = AFS::Object::VolumeHeader->new();

	    if ( /^(\S+)\s+(\d+)\s+(RW|RO|BK)\s+(\d+)\s+K\s+([\w-]+)/ ) {

		$header->_setAttribute (
		   name			=> $1,
		   id 			=> $2,
		   type 		=> $3,
		   size 		=> $4,
		  );
		$header->_setAttribute( rwrite	=> $2 ) if $3 eq 'RW';
		$header->_setAttribute( ronly	=> $2 ) if $3 eq 'RO';
		$header->_setAttribute( backup	=> $2 ) if $3 eq 'BK';

		my $status = $5;
		$status = 'offline' if $status eq 'Off-line';
		$status = 'online' if $status eq 'On-line';
		$header->_setAttribute
		  (
		   status 		=> $status,
		   attached		=> 1,
		  );

	    } elsif ( /^(\S+)\s+(\d+)\s+(RW|RO|BK)\s+(\d+)\s+K\s+used\s+(\d+)\s+files\s+([\w-]+)/ ) {

		$header->_setAttribute
		  (
		   name			=> $1,
		   id			=> $2,
		   type 		=> $3,
		   size 		=> $4,
		   files 		=> $5,
		  );
		$header->_setAttribute( rwrite	=> $2 ) if $3 eq 'RW';
		$header->_setAttribute( ronly	=> $2 ) if $3 eq 'RO';
		$header->_setAttribute( backup	=> $2 ) if $3 eq 'BK';

		my $status = $6;
		$status = 'offline' if $status eq 'Off-line';
		$status = 'online' if $status eq 'On-line';
		$header->_setAttribute
		  (
		   status 		=> $status,
		   attached		=> 1,
		  );

        # AuriStor header line
        } elsif ( /^\s*(\S+):(\d+)\s+(\/vicep\w+)\s+(\d+)\s+(RW|RO|BK)\s+(\S+)/ ) {

            $self->_Carp("Unrecognized output format (missing volume name):\n" . $_)
                unless ( ref $auristor eq 'HASH' and exists $auristor->{name});

            $header->_setAttribute (
                server		=> $1,
                port        => $2,
                partition 	=> $3,
                id          => $4,
                type 		=> $5,
                name        => $auristor->{name},
            );
            $header->_setAttribute( rwrite	=> $4 ) if $5 eq 'RW';
            $header->_setAttribute( ronly	=> $4 ) if $5 eq 'RO';
            $header->_setAttribute( backup	=> $4 ) if $5 eq 'BK';
            $entry->_setAttribute( $_ => $auristor->{$_} ) foreach grep(!/name$/, keys %$auristor);

            my $status = $6;
            $status = 'offline' if $status eq 'Off-line';
            $status = 'online' if $status eq 'On-line';
            $header->_setAttribute
            (
                status 		=> $status,
                attached		=> 1,
            );

	    } else {

		$self->_Carp("Unable to parse volume header: '$_'");

	    }

	    #
	    # We are interested in the next 6 lines as they are also
	    # from the same volume headers as the one we just matched.
	    # Suck data until we get to a blank line.
	    #
	    while ( defined($_ = $self->{handle}->getline()) ) {

		chomp;

		last if /^\s*$/; # Stop when we hit the blank line

		if ( m:^\s+(\S+)\s+(/vicep\w+)\s*$: ) {
		    $header->_setAttribute
		      (
		       server		=> $1,
		       partition	=> $2,
		      );
		    next;
		}

		#
		# Next we get ALL the volume IDs we can off this next
		# line.
		#
		# Q: Do we want to check that the id already found
		# matches one of these??  Not yet...
		#
		if ( /^\s+RWrite\s+(\d+)\s+ROnly\s+(\d+)\s+Backup\s+(\d+)/ ) {

		    $header->_setAttribute
		      (
		       rwrite		=> $1,
		       ronly		=> $2,
		       backup		=> $3,
		      );

		    if ( /RClone\s+(\d+)/ ) {
			$header->_setAttribute( rclone	=> $1 );
		    }
		    next;

		}

		if ( /^\s+MaxQuota\s+(\d+)/ ) {
		    $header->_setAttribute( maxquota	=> $1 );
		    next;
		}

        # AuriStor places size on a separate line
		if ( /^\s+Used\s+(\d+)\s+K/ ) {
		    $header->_setAttribute( size => $1 );
		    next;
		}

        # AuriStor places file count on a separate line
		if ( /^\s+FileCount\s+(\d+)/ ) {
		    $header->_setAttribute( files => $1 );
		    next;
		}

		if ( /^\s+Creation\s+(.*)\s*$/ ) {
		    $header->_setAttribute( creation	=> $1 );
		    next;
		}

		if ( /^\s+Copy\s+(.*)\s*$/ ) {
		    $header->_setAttribute( copyTime	=> $1 );
		    next;
		}

		if ( /^\s+Backup\s+(.*)\s*$/ ) {
		    $header->_setAttribute( backupTime	=> $1 );
		    next;
		}

		if ( /^\s+Last Access\s+(.*)\s*$/ ) {
		    $header->_setAttribute( access	=> $1 );
		    next;
		}

		if ( /^\s+Last Update\s+(.*)\s*$/ ) {
		    $header->_setAttribute( update	=> $1 );
		    next;
		}

		if ( /^\s+(\d+) accesses/ ) {
		    $header->_setAttribute( accesses	=> $1 );
		    next;
		}

		#
		# If we get this far, then we have an unrecognized
		# line of vos examine output.  Complain.
		#
		$self->_Carp("Unrecognized output format:\n" . $_);

	    }

	    #
	    # Are we looking for extended data??
	    #
	    if ( $args{extended} ) {

		my $raw = AFS::Object->new();
		my $author = AFS::Object->new();

		my $boundary = 0;

		while ( defined($_ = $self->{handle}->getline()) ) {

		    chomp;

		    $boundary++ if /^\s+\|-+\|\s*$/;

		    last if /^\s*$/ && $boundary == 4;

            # AuriStor: legacy format of
            #                       Raw Read/Write Stats
            #           |-------------------------------------------|
            #           |    Same Network     |    Diff Network     |
            #           |----------|----------|----------|----------|
            #           |  Total   |   Auth   |   Total  |   Auth   |
            #           |----------|----------|----------|----------|
            # Reads     |        0 |        0 |       12 |       12 |
            # Writes    |        0 |        0 |        0 |        0 |
            #           |-------------------------------------------|
            #
            # has finally been replaced with
            #
            #             Raw Read/Write Stats
            #           |----------|----------|
            #           |  Total   |   Auth   |
            #           |----------|----------|
            # Reads     |        9 |        9 |
            # Writes    |        0 |        0 |
            #           |---------------------|
            #
            # i.e. there's no differentiation based on network

		    next unless /\s+(\d+)\s+\|\s+(\d+)\s+\|\s+(\d+)\s+\|\s+(\d+)\s+\|/ or /\s+(\d+)\s+\|\s+(\d+)\s+\|/;

		    my @column = ( $1, $2, $3, $4 );

		    my $class			= "";
		    my $int			= "";

		    $class = 'reads' 		if /^Reads/;
		    $class = 'writes' 		if /^Writes/;

		    if ( $class ) {
                if ( defined $column[2] ) {
                    my $same = AFS::Object->new( total => $column[0], auth => $column[1] );
                    my $diff = AFS::Object->new ( total => $column[2], auth => $column[3] );
                    my $stats = AFS::Object->new ( same => $same, diff => $diff );
                    $raw->_setAttribute( $class	=> $stats );
                } else {
                    my $stats = AFS::Object->new( total => $column[0], auth => $column[1] );
                    $raw->_setAttribute( $class	=> $stats );
                }
            }

		    $int = '0sec' 		if /^0-60 sec/;
		    $int = '1min' 		if /^1-10 min/;
		    $int = '10min' 		if /^10min-1hr/;
		    $int = '1hr' 		if /^1hr-1day/;
		    $int = '1day' 		if /^1day-1wk/;
		    $int = '1wk' 		if /^> 1wk/;

		    if ( $int ) {
                if ( defined $column[2] ) {
                    my $file = AFS::Object->new( same => $column[0], diff => $column[1] );
                    my $dir = AFS::Object->new ( same => $column[2], diff => $column[3] );
                    my $stats = AFS::Object->new ( file => $file, dir => $dir );
                    $author->_setAttribute( $int	=> $stats );
                } else {
                    my $stats = AFS::Object->new( file => $column[0], dir => $column[1] );
                    $author->_setAttribute( $int	=> $stats );
                }
            }
		}

		$header->_setAttribute( raw => $raw, author => $author );

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
	if ( /^\s+RWrite:\s+(\d+)/ ) {

	    if ( /RWrite:\s+(\d+)/ ) { $entry->_setAttribute( rwrite	=> $1 ); }
	    if ( /ROnly:\s+(\d+)/ )  { $entry->_setAttribute( ronly	=> $1 ); }
	    if ( /Backup:\s+(\d+)/ ) { $entry->_setAttribute( backup	=> $1 ); }
	    if ( /RClone:\s+(\d+)/ ) { $entry->_setAttribute( rclone	=> $1 ); }

	    next;

	}			# if ( /^\s+RWrite:....

	#
	# Next we are looking for the number of sites, and then we'll
	# suck that data in as well.
	#
	# NOTE: Because there is more interesting data after the
	# locations, we fall through to the next test once we are done
	# parsing them.
	#
	if ( /^\s+number of sites ->\s+(\d+)/ ) {

        $entry->_setAttribute( sites => $1 );

	    while ( defined($_ = $self->{handle}->getline()) ) {

		chomp;

        last unless m%^\s+server\s+([^:]+)(:(\d+))?\s+partition\s+(/vicep\w+)\s+([A-Z]{2})\s+Site\s*(--\s+)?(.*)?%;

        my $port = ( defined $3 ) ? $3 : 7005;
		my $site = AFS::Object::VLDBSite->new
		  (
		   server		=> $1,
           port         => $port,
		   partition	=> $4,
		   type			=> $5,
		   status		=> $7,
		  );

		$entry->_addVLDBSite($site);

	    }

	}

	#
	# Last possibility (that we know of) -- volume might be
	# locked.
	#
	if ( /LOCKED/ ) {
	    $entry->_setAttribute( locked => 1 );
	    next;
	}

	#
	# Actually, this is the last possibility...  The volume name
	# leading the VLDB entry stanza.
	#
	if ( /^(\S+)/ ) {
	    $entry->_setAttribute( name => $1 );
	}

    }

    $result->_addVLDBEntry($entry);

    $errors++ unless $self->_reap_cmds();

    $errors++ unless $self->_restore_stderr();

    return if $errors;
    return $result;

}

sub listaddrs {

    my $self = shift;
    my (%args) = @_;

    my @result = ();

    $self->{operation} = "listaddrs";

    return unless $self->_parse_arguments(%args);

    return unless $self->_save_stderr();

    my $errors = 0;

    $errors++ unless $self->_exec_cmds();

    if ( $args{printuuid} ) {

	while ( defined($_ = $self->{handle}->getline()) ) {

	    chomp;

	    if ( /^UUID:\s+(\S+)/ ) {

		my $fileserver = AFS::Object::FileServer->new( uuid => $1 );

		my @addresses = ();
		my $hostname = "";

		while ( defined($_ = $self->{handle}->getline()) ) {
		    s/^\s*//g;
		    s/\s*$//g;
		    last if /^\s*$/;
		    chomp;
		    if ( /^(\[)?(\d+\.\d+\.\d+\.\d+)(\])?(:\d+)?$/ ) {
			push(@addresses,$2);
		    } else {
			$hostname = $_;
            $hostname =~ s/:\d+//;
		    }
		}

		$fileserver->_setAttribute( addresses => \@addresses ) if @addresses;
		$fileserver->_setAttribute( hostname => $hostname ) if $hostname;

		push(@result,$fileserver);

	    }

	}

    } elsif ( $args{uuid} ) {

	my @addresses = ();
	my $hostname = "";

	while ( defined($_ = $self->{handle}->getline()) ) {
	    chomp;
	    s/^\s*//g;
	    s/\s*$//g;
        if ( /^(\[)?(\d+\.\d+\.\d+\.\d+)(\])?(:\d+)?$/ ) {
		push(@addresses,$2);
	    } else {
		$hostname = $_;
	    }
	}

	if ( $hostname || @addresses ) {
	    my $fileserver = AFS::Object::FileServer->new();
	    $fileserver->_setAttribute( addresses => \@addresses ) if @addresses;
	    $fileserver->_setAttribute( hostname => $hostname ) if $hostname;
	    push(@result,$fileserver);
	}

    } else {

	while ( defined($_ = $self->{handle}->getline()) ) {
	    if ( /^UUID:\s+(\S+)/ ) {

            my $fileserver = AFS::Object::FileServer->new( uuid => $1 );

            my @addresses = ();
            my $hostname = "";

            while ( defined($_ = $self->{handle}->getline()) ) {
                s/^\s*//g;
                s/\s*$//g;
                last if /^\s*$/;
                chomp;
                if ( /^(\[)?(\d+\.\d+\.\d+\.\d+)(\])?(:\d+)?$/ ) {
                push(@addresses,$2);
                } else {
                $hostname = $_;
                $hostname =~ s/:\d+//;
                }
            }

            $fileserver->_setAttribute( addresses => \@addresses ) if @addresses;
            $fileserver->_setAttribute( hostname => $hostname ) if $hostname;

            push(@result,$fileserver);

	    } else {

            chomp;
            s/^\s*//g;
            s/\s*$//g;
		    if ( /^(\[)?(\d+\.\d+\.\d+\.\d+)(\])?(:\d+)?$/ ) {
            push(@result,AFS::Object::FileServer->new( addresses => [$2] ));
            } else {
            push(@result,AFS::Object::FileServer->new( hostname => $_ ));
            }
        }
	}

    }

    $errors++ unless $self->_reap_cmds();
    $errors++ unless $self->_restore_stderr();

    return if $errors;
    return @result;

}

sub listpart {

    my $self = shift;
    my (%args) = @_;

    my $result = AFS::Object::FileServer->new();

    $self->{operation} = "listpart";

    return unless $self->_parse_arguments(%args);

    return unless $self->_save_stderr();

    my $errors = 0;

    $errors++ unless $self->_exec_cmds();

    while ( defined($_ = $self->{handle}->getline()) ) {

	chomp;

	next unless m:/vice:;

	s/^\s+//g;
	s/\s+$//g;

	foreach my $partname ( split ) {
	    my $partition = AFS::Object::Partition->new( partition => $partname );
	    $result->_addPartition($partition);
	}

    }

    $errors++ unless $self->_reap_cmds();
    $errors++ unless $self->_restore_stderr();

    return if $errors;
    return $result;

}

sub listvldb {

    my $self = shift;
    my (%args) = @_;

    $self->{operation} = "listvldb";

    my $locked = 0;

    my $result = AFS::Object::VLDB->new();

    return unless $self->_parse_arguments(%args);

    return unless $self->_save_stderr();

    my $errors = 0;

    $errors++ unless $self->_exec_cmds();

    while ( defined($_ = $self->{handle}->getline()) ) {

	chomp;

	next if /^\s*$/;	# If it starts with a blank line, then
				# its not a volume name.
	#
	# Skip the introductory lines of the form:
	# "VLDB entries for all servers"
	# "VLDB entries for server ny91af01"
	# "VLDB entries for server ny91af01 partition /vicepa"
	#
	next if /^(VLDB entries|Location information) for /;

	s/\s+$//g;		# Might be trailing whitespace...

	#
	# We either get the total number of volumes, or we assume the
	# line is a volume name.
	#
	if ( /Total entries:\s+(\d+)/ ) {
	    $result->_setAttribute( total => $1 );
	    next;
	}

	my $name = $_;

	my $entry = AFS::Object::VLDBEntry->new( name => $name );

	while ( defined($_ = $self->{handle}->getline()) ) {

	    chomp;

	    last if /^\s*$/;	# Volume info ends with a blank line

	    #
	    # Code to parse this output lives in examine.pl.  This
	    # will need to be made generic and used here to parse and
	    # return the full vldb entry.
	    #

	    if ( /RWrite:\s+(\d+)/ ) { $entry->_setAttribute( rwrite 	=> $1 ); }
	    if ( /ROnly:\s+(\d+)/ )  { $entry->_setAttribute( ronly 	=> $1 ); }
	    if ( /Backup:\s+(\d+)/ ) { $entry->_setAttribute( backup	=> $1 ); }
	    if ( /RClone:\s+(\d+)/ ) { $entry->_setAttribute( rclone	=> $1 ); }

	    if ( /^\s+number of sites ->\s+(\d+)/ ) {

		my $sites = $1;
        $entry->_setAttribute( sites => $sites );

		while ( defined($_ = $self->{handle}->getline()) ) {

		    chomp;

		    next unless m%^\s+server\s+([^:]+)(:(\d+))?\s+partition\s+(/vicep\w+)\s+([A-Z]{2})\s+Site\s*(--\s+)?(.*)?%;

		    $sites--;

            my $port = ( defined $3 ) ? $3 : 7005;
		    my $site = AFS::Object::VLDBSite->new
		      (
		       server		=> $1,
               port         => $port,
		       partition	=> $4,
		       type		=> $5,
		       status		=> $7,
		      );

		    $entry->_addVLDBSite( $site );

		    last if $sites == 0;

		}

	    }

	    #
	    # Last possibility (that we know of) -- volume might be
	    # locked.
	    #
	    if ( /LOCKED/ ) {
		$entry->_setAttribute( locked => 1 );
		$locked++;
	    }

	}

	$result->_addVLDBEntry( $entry );

    }

    $result->_setAttribute( locked => $locked );

    $errors++ unless $self->_reap_cmds();

    $errors++ unless $self->_restore_stderr();

    return if $errors;
    return $result;

}


sub listvol {

    my $self = shift;
    my (%args) = @_;

    my $result = AFS::Object::VolServer->new();

    $self->{operation} = "listvol";

    foreach my $unsupported ( qw/extended format/ ) {
        if ( delete $args{$unsupported} ) {
        $self->_Croak("vos listvol: -$unsupported is not supported by this version of the API");
        }
    }

    return unless $self->_parse_arguments(%args);

    return unless $self->_save_stderr();

    my $errors = 0;

    $errors++ unless $self->_exec_cmds();

    while ( defined($_ = $self->{handle}->getline()) ) {

	chomp;

	next if /^\s*$/;	# Blank lines are not interesting

	next unless /^Total number of volumes on server \S+(:\d+)? partition (\/vice[\w]+): (\d+)/;

	my $partition = AFS::Object::Partition->new
	  (
	   partition			=> $2,
	   total			=> $3,
	  );

	while ( defined($_ = $self->{handle}->getline()) ) {

	    chomp;

        # AuriStor output has no footer, so the header starts a new entry
        if ( /^Total number of volumes on server \S+(:\d+)? partition (\/vice[\w]+): (\d+)/ ) {
            if ( $partition->getAttribute(q{partition}) ) {
                $result->_addPartition($partition);
                $partition = AFS::Object::Partition->new
                    (
                     partition  => $2,
                     total      => $3,
                    );

            }
            next;
        }
        # there's no blank lines in AuriStor
	    last if /^\s*$/ && $args{fast};

	    next if /^\s*$/;

	    s/\s+$//;

	    if ( /^Total volumes onLine (\d+) ; Total volumes offLine (\d+) ; Total busy (\d+)/ ) {
		$partition->_setAttribute
		  (
		   online		=> $1,
		   offline		=> $2,
		   busy			=> $3,
		  );
		last;		# Done with this partition
	    }

	    if ( /Volume (\d+) is busy/ ) {
		my $volume = AFS::Object::VolumeHeader->new
		  (
		   id			=> $1,
		   status		=> 'busy',
		   attached		=> 1,
		  );
		$partition->_addVolumeHeader($volume);
		next;
	    } elsif ( /Could not attach volume (\d+)/ ) {
		my $volume = AFS::Object::VolumeHeader->new
		  (
		   id			=> $1,
		   status		=> 'offline',
		   attached		=> 0,
		  );
		$partition->_addVolumeHeader($volume);
		next;
	    }

	    #
	    # We have to handle multiple formats here.  For
	    # now, just parse the "fast" and normal output.
	    # Extended is not yet supported.
	    #

	    my (@array) = split;
	    my ($name,$id,$type,$size,$status) = ();

	    my $volume = AFS::Object::VolumeHeader->new();

	    if ( @array == 6 ) {
		($name,$id,$type,$size,$status) = @array[0..3,5];
		$status = 'offline' if $status eq 'Off-line';
		$status = 'online' if $status eq 'On-line';
		$volume->_setAttribute
		  (
		   id			=> $id,
		   name			=> $name,
		   type			=> $type,
		   size			=> $size,
		   status		=> $status,
		   attached		=> 1,
		  );
	    } elsif ( @array == 1 ) {
		$volume->_setAttribute
		  (
		   id			=> $_,
		   status		=> 'online',
		   attached		=> 1,
		  );
	    } else {
		$self->_Carp("Unable to parse header summary line:\n" . $_);
		$errors++;
		next;
	    }

	    #
	    # If the output is long, then we have some more
	    # interesting information to parse.  See vos/examine.pl
	    # for notes.  This code was stolen from there...
	    #

	    if ( $args{long} || $args{extended} ) {

		while ( defined($_ = $self->{handle}->getline()) ) {

		    last if /^\s*$/;

		    if ( /^\s+RWrite\s+(\d+)\s+ROnly\s+(\d+)\s+Backup\s+(\d+)/ ) {
			$volume->_setAttribute
			  (
			   rwrite		=> $1,
			   ronly		=> $2,
			   backup		=> $3,
			  );
			if ( /RClone\s+(\d+)/ ) {
			    $volume->_setAttribute( rclone => $1 );
			}
			next;
		    }

		    if ( /^\s+MaxQuota\s+(\d+)/ ) {
			$volume->_setAttribute( maxquota => $1 );
			next;
		    }

		    if ( /^\s+Creation\s+(.*)\s*$/ ) {
			$volume->_setAttribute( creation => $1 );
			next;
		    }

		if ( /^\s+Copy\s+(.*)\s*$/ ) {
		    $volume->_setAttribute( copyTime	=> $1 );
		    next;
		}

		if ( /^\s+Backup\s+(.*)\s*$/ ) {
		    $volume->_setAttribute( backupTime	=> $1 );
		    next;
		}

		if ( /^\s+Last Access\s+(.*)\s*$/ ) {
		    $volume->_setAttribute( access	=> $1 );
		    next;
		}

		    if ( /^\s+Last Update\s+(.*)\s*$/ ) {
			$volume->_setAttribute( update => $1 );
			next;
		    }

		    if ( /^\s+(\d+) accesses/ ) {
			$volume->_setAttribute( accesses => $1 );
			next;
		    }
		}		# while(defined($_ = $self->{handle}->getline()))

	    }

	    $partition->_addVolumeHeader($volume);

	}

	$result->_addPartition($partition);

    }

    $errors++ unless $self->_reap_cmds();

    $errors++ unless $self->_restore_stderr();

    return if $errors;
    return $result;

}

sub partinfo {

    my $self = shift;
    my (%args) = @_;

    my $result = AFS::Object::FileServer->new();

    $self->{operation} = "partinfo";

    return unless $self->_parse_arguments(%args);

    return unless $self->_save_stderr();

    my $errors = 0;

    $errors++ unless $self->_exec_cmds();

    while ( defined($_ = $self->{handle}->getline()) ) {

	next unless m|partition (/vice\w+): (-?\d+)\D+(\d+)$|;

	my $partition = AFS::Object::Partition->new
	  (
	   partition 		=> $1,
	   available		=> $2,
	   total		=> $3,
	  );

	$result->_addPartition($partition);

    }

    $errors++ unless $self->_reap_cmds();

    $errors++ unless $self->_restore_stderr();

    return if $errors;
    return $result;

}

sub status {

    my $self = shift;
    my (%args) = @_;

    my $result = AFS::Object::VolServer->new();

    $self->{operation} = "status";

    return unless $self->_parse_arguments(%args);

    return unless $self->_save_stderr();

    my $errors = 0;

    $errors++ unless $self->_exec_cmds();

    my $transaction = undef;

    while ( defined($_ = $self->{handle}->getline()) ) {

	chomp;

	if ( /No active transactions/ ) {
	    $result->_setAttribute( transactions => 0 );
	    last;
	}

	if ( /Total transactions: (\d+)/ ) {
	    $result->_setAttribute( transactions => $1 );
	    next;
	}

	if ( /^-+\s*$/ ) {

	    if ( $transaction ) {
		$result->_addTransaction($transaction);
		$transaction = undef;
	    } else {
		$transaction = AFS::Object::Transaction->new();
	    }

	}

	next unless $transaction;

	if ( /transaction:\s+(\d+)/ ) {
	    $transaction->_setAttribute( transaction => $1 );
	}

	if ( /created:\s+(.*)$/ ) {
	    $transaction->_setAttribute( created => $1 );
	}

	if ( /attachFlags:\s+(.*)$/ ) {
	    $transaction->_setAttribute( attachFlags => $1 );
	}

	if ( /volume:\s+(\d+)/ ) {
	    $transaction->_setAttribute( volume => $1 );
	}

	if ( /partition:\s+(\S+)/ ) {
	    $transaction->_setAttribute( partition => $1 );
	}

	if ( /procedure:\s+(\S+)/ ) {
	    $transaction->_setAttribute( procedure => $1 );
	}

	if ( /packetRead:\s+(\d+)/ ) {
	    $transaction->_setAttribute( packetRead => $1 );
	}

	if ( /lastReceiveTime:\s+(\d+)/ ) {
	    $transaction->_setAttribute( lastReceiveTime => $1 );
	}

	if ( /packetSend:\s+(\d+)/ ) {
	    $transaction->_setAttribute( packetSend => $1 );
	}

	if ( /lastSendTime:\s+(\d+)/ ) {
	    $transaction->_setAttribute( lastSendTime => $1 );
	}

    }

    $errors++ unless $self->_reap_cmds();

    $errors++ unless $self->_restore_stderr();

    return if $errors;
    return $result;

}

sub dump {

    my $self = shift;
    my (%args) = @_;

    $self->{operation} = 'dump';

    my $file = delete $args{file} || do {
	$self->_Carp("Missing required argument: 'file'");
	return;
    };

    my $gzip_default = 6;
    my $bzip2_default = 6;

    my $nocompress = delete $args{nocompress} || undef;
    my $gzip = delete $args{gzip} || undef;
    my $bzip2 = delete $args{bzip2} || undef;
    my $filterout = delete $args{filterout} || undef;

    if ( $gzip && $bzip2 && $nocompress ) {
	$self->_Carp("Invalid argument combination: only one of 'gzip' or 'bzip2' or 'nocompress' may be specified");
	return;
    }

    if ( $file eq 'stdin' ) {
	$self->_Carp("Invalid argument 'stdin': you can't write output to stdin");
	return;
    }

    if ( $file ne 'stdout' ) {

	if ( $file =~ /\.gz$/ && not defined $gzip and not defined $nocompress ) {
	    $gzip = $gzip_default;
	} elsif ( $file =~ /\.bz2$/ && not defined $bzip2 and not defined $nocompress ) {
	    $bzip2 = $bzip2_default;
	}

	if ( $gzip && $file !~ /\.gz$/ ) {
	    $file .= ".gz";
	} elsif ( $bzip2 && $file !~ /\.bz2/ ) {
	    $file .= ".bz2";
	}

	unless ( $gzip || $bzip2 || $filterout ) {
	    $args{file} = $file;
	}

    }

    return unless $self->_parse_arguments(%args);

    if ( $filterout ) {

	unless ( ref $filterout eq 'ARRAY' ) {
	    $self->_Carp("Invalid argument 'filterout': must be an ARRAY reference");
	    return;
	}

	if ( ref($filterout->[0]) eq 'ARRAY' ) {
	    foreach my $filter ( @$filterout ) {
		unless ( ref $filter eq 'ARRAY' ) {
		    $self->_Carp("Invalid argument 'filterout': must be an ARRAY of ARRAY references, \n" .
				    "OR an ARRAY of strings.  See the documentation for details");
		    return;
		}
		push( @{$self->{cmds}}, $filter );
	    }
	} else {
	    push( @{$self->{cmds}}, $filterout );
	}

    };

    if ( $gzip ) {
	push( @{$self->{cmds}}, [ 'gzip', "-$gzip", '-c' ] );
    } elsif ( $bzip2 ) {
	push( @{$self->{cmds}}, [ 'bzip2', "-$bzip2", '-c' ] );
    }

    return unless $self->_save_stderr();

    my $errors = 0;

    $errors++ unless $self->_exec_cmds
      (
       stdout 			=> ( $args{file} ? "/dev/null" : $file ),
      );

    $errors++ unless $self->_reap_cmds();

    $errors++ unless $self->_restore_stderr();

    return if $errors;
    return 1;

}

sub restore {

    my $self = shift;
    my (%args) = @_;

    $self->{operation} = "restore";

    my $file = delete $args{file} || do {
	$self->_Carp("Missing required argument: 'file'");
	return;
    };

    my $nocompress = delete $args{nocompress} || undef;
    my $gunzip = delete $args{gunzip} || undef;
    my $bunzip2 = delete $args{bunzip2} || undef;
    my $filterin = delete $args{filterin} || undef;;

    if ( $gunzip && $bunzip2 && $nocompress ) {
	$self->_Carp("Invalid argument combination: only one of 'gunzip' or 'bunzip2' or 'nocompress' may be specified");
	return;
    }

    if ( $file eq 'stdout' ) {
	$self->_Carp("Invalid argument 'stdout': you can't read input from stdout");
	return;
    }

    if ( $file ne 'stdin' ) {

	if ( $file =~ /\.gz$/ && not defined $gunzip and not defined $nocompress ) {
	    $gunzip = 1;
	} elsif ( $file =~ /\.bz2$/ && not defined $bunzip2 and not defined $nocompress ) {
	    $bunzip2 = 1;
	}

	unless ( $gunzip || $bunzip2 || $filterin ) {
	    $args{file} = $file;
	}

    }

    return unless $self->_parse_arguments(%args);

    if ( $filterin ) {

	unless ( ref $filterin eq 'ARRAY' ) {
	    $self->_Carp("Invalid argument 'filterin': must be an ARRAY reference");
	    return;
	}

	if ( ref($filterin->[0]) eq 'ARRAY' ) {
	    foreach my $filter ( @$filterin ) {
		unless ( ref $filter eq 'ARRAY' ) {
		    $self->_Carp("Invalid argument 'filterin': must be an ARRAY of ARRAY references, \n" .
				"OR an ARRAY of strings.  See the documentation for details");
		    return;
		}
		unshift( @{$self->{cmds}}, $filter );
	    }
	} else {
	    unshift( @{$self->{cmds}}, $filterin );
	}

    };

    if ( $gunzip ) {
	unshift( @{$self->{cmds}}, [ 'gunzip', '-c' ] );
    } elsif ( $bunzip2 ) {
	unshift( @{$self->{cmds}}, [ 'bunzip2', '-c' ] );
    }

    my $errors = 0;

    $errors++ unless $self->_exec_cmds
      (
       stderr 			=> 'stdout',
       stdin			=> ( $args{file} ? "/dev/null" : $file ),
      );

    $errors++ unless $self->_parse_output();
    $errors++ unless $self->_reap_cmds();

    return if $errors;
    return 1;

}

sub size {

    my $self = shift;
    my (%args) = @_;

    my $result = AFS::Object->new();

    $self->{operation} = "size";

    return unless $self->_parse_arguments(%args);

    return unless $self->_save_stderr();

    my $errors = 0;

    $errors++ unless $self->_exec_cmds();

    while ( defined($_ = $self->{handle}->getline()) ) {

	chomp;

    $result->_setAttribute( lc $1 => $2 ) if ( /(\S+):\s+(\S+)/ );

    }

    $errors++ unless $self->_reap_cmds();
    $errors++ unless $self->_restore_stderr();

    return if $errors;
    return $result;

}

#
# XXX -- Hack Alert!!!
#
# AuriStor has changed the sub-command name for certain VOS operations,
# notably 'vldb' is replaced by 'loc'.
# Note: only sub-commands with complex return codes need to be aliased,
#   as _parse_arguments deals with aliasing commands

*listfs = \&listaddrs;
*listloc = \&listvldb;

1;

