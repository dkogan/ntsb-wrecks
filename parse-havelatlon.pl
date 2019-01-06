#!/usr/bin/perl
use strict;
use warnings;

use feature ':5.10';
use autodie;

my $fd;
open $fd, '<', 'havelatlon.csv';

say '# latitude longitude url';
while(<$fd>)
{
    next if $. == 1;

    my ($lat,$lon,$url) = split(',');

    if($lat =~ /^([0-9][0-9])([0-9][0-9])([0-9][0-9])([NS])/i)
    {
        $lat = $1 + ($2 + $3/60.)/60.;
        $lat *= -1 if $4 =~ /s/i;
    }
    else
    {
        next;
        say STDERR "Couldn't parse lat: '$lat'";
    }

    if($lon =~ /^([0-9]+)([0-9][0-9])([0-9][0-9])([EW])/i)
    {
        $lon = $1 + ($2 + $3/60.)/60.;
        $lon *= -1 if $4 =~ /w/i;
    }
    else
    {
        next;
        say STDERR "Couldn't parse lon: '$lon'";
    }

    print "$lat $lon $url";
}
close $fd;

