#!/usr/bin/perl
use strict;
use warnings;

use feature ':5.10';
use autodie;

my %airports;
my $fd;
open $fd, '<', 'airports.vnl';
while(<$fd>)
{
    next if /^#/;
    my ($id,$lat,$lon) = split;
    $airports{$id} = [$lat,$lon];
}
close $fd;


print <<'EOF';
<?xml version="1.0" encoding="UTF-8"?>
<gpx xmlns:gpxx="http://www.garmin.com/xmlschemas/GpxExtensions/v3" xmlns="http://www.topografix.com/GPX/1/1" version="1.1">
EOF


open $fd, '<', 'havelatlon.vnl';
while(<$fd>)
{
    next if /^#/;
    my ($lat,$lon,$url) = split;

    # only keep stuff in the general vicinity of LA for now
    next unless $lat > 34.3-.5 && $lat < 34.3+.5 && $lon > -118.5 && $lon < -117.5;

    $url =~ s/&/&amp;/g;
    say qq{<wpt lat="$lat" lon="$lon"><name></name><cmt>$url</cmt></wpt>};
}
close $fd;

open $fd, '<', 'observed.vnl';
while(<$fd>)
{
    next if /^#/;
    my ($id,$distance_nm,$direction,$url) = split;

    my $latlon = $airports{uc $id};
    if(!defined $latlon)
    {
        # I have a lot of airports in my list, but there're still lots missing
        next;
    }


    my ($lat,$lon) = @$latlon;

    # only keep stuff in the general vicinity of LA for now
    next unless $lat > 34.3-.5 && $lat < 34.3+.5 && $lon > -118.5 && $lon < -117.5;

    # I generate a line segment from the given location along the given
    # direction from distance-0.5nm to distance+0.5nm. I can do this more
    # precisely, but unless the distances are very large, latlon are cartesian
    # if I scale the lon by cos(lat)


    my $pi = 3.14159265358979;
    my $clat = cos($lat * $pi/180.);
    my $cdir = cos($direction * $pi/180.);
    my $sdir = sin($direction * $pi/180.);

    my $d0_deg = ($distance_nm - 0.5) / 60.; # nautical miles to degrees
    my $d1_deg = ($distance_nm + 0.5) / 60.; # nautical miles to degrees

    my @xy0 = ($lat,$lon * $clat); # lat first because theta=0 points North
    my @xy1 = ($lat,$lon * $clat); # lat first because theta=0 points North
    $xy0[0] -= $d0_deg * $cdir;
    $xy0[1] -= $d0_deg * $sdir;
    $xy1[0] -= $d1_deg * $cdir;
    $xy1[1] -= $d1_deg * $sdir;
    $xy0[1] /= $clat;
    $xy1[1] /= $clat;





    $url =~ s/&/&amp;/g;
    print <<EOF;
<trk><name></name><cmt>$url</cmt>
<extensions><gpxx:TrackExtension><gpxx:DisplayColor>Red</gpxx:DisplayColor></gpxx:TrackExtension></extensions>
<trkseg>
<trkpt lat="$xy0[0]" lon="$xy0[1]"/>
<trkpt lat="$xy1[0]" lon="$xy1[1]"/>
</trkseg>
</trk>
EOF
}
close $fd;

say '</gpx>';
