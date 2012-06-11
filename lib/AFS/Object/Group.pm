package AFS::Object::Group;

our $VERSION = '2.000_001';
$VERSION = eval $VERSION;  ##  no critic: StringyEval

use Moose;

extends qw(AFS::Object::Principal);

1;
