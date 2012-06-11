package AFS::Object::CacheManager;

our $VERSION = '2.000_001';
$VERSION = eval $VERSION;  ##  no critic: StringyEval

use Moose;
use Carp;

extends qw(AFS::Object);

has q{_pathnames} => ( is => q{rw}, isa => q{HashRef}, default => sub { return {}; } );
has q{_cells}     => ( is => q{rw}, isa => q{HashRef}, default => sub { return {}; } );
has q{_servers}   => ( is => q{rw}, isa => q{HashRef}, default => sub { return {}; } );

sub getPathNames {
    return keys %{ shift->_pathnames };
}

sub getPaths {
    return values %{ shift->_pathnames };
}

sub getPath {
    return shift->_pathnames->{ shift(@_) };
}

sub _addPath {
    my $self = shift;
    my $path = shift;
    $path->path or croak q{Invalid path object};
    return $self->_pathnames->{ $path->path } = $path;
}

sub getCellNames {
    return keys %{ shift->_cells };
}

sub getCells {
    return values %{ shift->_cells };
}

sub getCell {
    return shift->_cells->{ shift(@_) };
}

sub _addCell {
    my $self = shift;
    my $cell = shift;
    $cell->cell or croak q{Invalid cell object};
    return $self->_cells->{ $cell->cell } = $cell;
}

sub getServerNames {
    return keys %{ shift->_servers };
}

sub getServers {
    return values %{ shift->_servers };
}

sub getServer {
    return shift->_servers->{ shift(@_) };
}

sub _addServer {
    my $self = shift;
    my $server = shift;
    $server->server or croak q{Invalid server object};
    return $self->_servers->{ $server->server } = $server;
}

1;
