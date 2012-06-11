package AFS::Command;

use strict;
use warnings;
use English;

#
# For historical reasons, we have VERSION defined in all the modules,
# and removing it causes a lot of pain for people who specified
# dependencies on specific versions of specific modules.
#
# IOW, if you change this, change it everywhere.  distzilla can
# automate VERSION generation, and we need to look into that.
#
our $VERSION = '2.000_001';
$VERSION = eval $VERSION;  ##  no critic: StringyEval

use AFS::Command::Base;

use AFS::Command::VOS;
use AFS::Command::BOS;
use AFS::Command::PTS;
use AFS::Command::FS;

1;
