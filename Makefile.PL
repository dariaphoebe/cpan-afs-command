use strict;
use warnings;
use English;

use inc::Module::Install;

name         q{AFS-Command};
abstract     q{AFS Command Utility Interface};
author       q{Phillip Moore <wpm@openefs.org>};
perl_version q{5.010};
license      q{unknown};
all_from     q{lib/AFS/Command.pm};

requires q{Moose};
requires q{Date::Format};

tests_recursive;

WriteAll;
