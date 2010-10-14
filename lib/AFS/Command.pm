package AFS::Command;

use strict;
use warnings;
use English;

our $VERSION = '1.999_001';
$VERSION = eval $VERSION;  ##  no critic: StringyEval

use AFS::Command::Base;

use AFS::Command::VOS;
use AFS::Command::BOS;
use AFS::Command::PTS;
use AFS::Command::FS;

1;
