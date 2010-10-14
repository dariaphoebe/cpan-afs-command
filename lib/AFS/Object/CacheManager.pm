package AFS::Object::CacheManager;

use Moose;

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
    return shift->_pathnames->{ shift . q{} };
}

sub _addPath {
    my $self = shift;
    my $path = shift;
    return $self->_pathnames->{ $path->path } = $path;
}

sub getCellNames {
    return keys %{ shift->_cells };
}

sub getCells {
    return values %{ shift->_cells };
}

sub getCell {
    return shift->_cells->{ shift . q{} };
}

sub _addCell {
    my $self = shift;
    my $cell = shift;
    return $self->_cells->{ $cell->cell } = $cell;
}

sub getServerNames {
    return keys %{ shift->_servers };
}

sub getServers {
    return values %{ shift->_servers };
}

sub getServer {
    return shift->_servers->{ shift . q{} };
}

sub _addServer {
    my $self = shift;
    my $server = shift;
    return $self->_servers->{ $server->server } = $server;
}

1;
