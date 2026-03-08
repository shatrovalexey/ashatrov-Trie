use strict;
use Time::HiRes qw(gettimeofday tv_interval);
+ 1;

BEGIN {$::START = [&gettimeofday(),]}
END {warn 'elapsed: ', &tv_interval($::START, [&gettimeofday(),]), ' sec'}