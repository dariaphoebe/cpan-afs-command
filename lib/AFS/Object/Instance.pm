package AFS::Object::Instance;

use Moose;

extends qw(AFS::Object);

has q{_commands} => ( is => q{rw}, isa => q{HashRef}, default => sub { return {}; } );

sub getCommandIndexes {
    return sort keys %{ shift->_commands };
}

sub getCommands {
    return values %{ shift->_commands };
}

sub getCommand {
    return shift->_commands->{ shift . q{} };
}

sub _addCommand {
    my $self = shift;
    my $command = shift;
    return $self->_commands->{ $command->index } = $command;
}

1;
