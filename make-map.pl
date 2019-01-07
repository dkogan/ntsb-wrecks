#!/usr/bin/perl
use strict;
use warnings;

use Vnlog::Parser;
use Math::Trig;

use feature ':5.10';
use autodie;

my $lat0           = 34.3;
my $lon0           = -118.0;
my $lat_r          = 0.5;
my $lon_r          = 0.5;
my $input_filename = 'joint.vnl';


my $document_header = <<'EOF';
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
<Document>
<name>Wreck sites</name>
<description>Wreck sites from NTSB reports</description>
EOF

my $markers_header = <<'EOF';
<Folder>
<open>1</open>
<name>Markers</name>
EOF

my $marker = <<'EOF';
<Placemark>
<name>xxxxNAMExxxx</name>
<description>xxxxDESCRIPTIONxxxx</description>
<Style>
<IconStyle>
<hotSpot x="0.5" y="0.5" xunits="fraction" yunits="fraction"/>
<Icon>
<href>http://caltopo.com/icon.png?cfg=point,FF0000</href>
</Icon>
</IconStyle>
</Style>
<Point>
<coordinates>xxxxLONxxxx,xxxxLATxxxx,0
</coordinates>
</Point>
</Placemark>
EOF

my $markers_footer = <<'EOF';
</Folder>
EOF

my $polygons_header = <<'EOF';
<Folder>
<open>1</open>
<name>Lines and Polygons</name>
EOF

my $polygon_header = <<'EOF';
<Placemark>
<Style>
<LineStyle>
<color>FF0000FF</color>
<width>2.0</width>
</LineStyle>
<PolyStyle>
<fill>1</fill>
<outline>1</outline>
<width>2.0</width>
<color>1A0000FF</color>
</PolyStyle>
</Style>
<name>xxxxNAMExxxx</name>
<description>xxxxDESCRIPTIONxxxx</description>
<Polygon>
<altitudeMode>clampToGround</altitudeMode>
<tessellate>1</tessellate>
<outerBoundaryIs>
<LinearRing>
<coordinates>
EOF

my $polygon = <<'EOF';
xxxxLONxxxx,xxxxLATxxxx,0
EOF

my $polygon_footer = <<'EOF';
</coordinates>
</LinearRing>
</outerBoundaryIs>
</Polygon>
</Placemark>
EOF

my $polygons_footer = <<'EOF';
</Folder>
EOF

my $document_footer = <<'EOF';
</Document>
</kml>
EOF


print $document_header;

my $parser;
my $fd;

# First, write the markers
print $markers_header;
$parser = Vnlog::Parser->new();
open $fd, '<', $input_filename;
while (<$fd>)
{
    if ( !$parser->parse($_) )
    {
        die "Error parsing vnlog line '$_': " . $parser->error();
    }

    my $d = $parser->getValuesHash();
    next unless %$d;

    my $lat = convert_latitude( $d->{latitude});
    my $lon = convert_longitude($d->{longitude});
    my $url = $d->{url} =~ s/&/&amp;/gr;

    next unless defined($lat) && defined($lon)   &&
      $lat0-$lat_r < $lat && $lat < $lat0+$lat_r &&
      $lon0-$lon_r < $lon && $lon < $lon0+$lon_r;

    my $this = $marker =~ s/xxxxNAMExxxx/getname($d)/er;
    $this =~ s/xxxxDESCRIPTIONxxxx/$url/;
    $this =~ s/xxxxLONxxxx/$lon/;
    $this =~ s/xxxxLATxxxx/$lat/;
    print $this;
}
close $fd;
print $markers_footer;


# Then, the observing sectors
print $polygons_header;
$parser = Vnlog::Parser->new();
open $fd, '<', $input_filename;
while (<$fd>)
{
    if ( !$parser->parse($_) )
    {
        die "Error parsing vnlog line '$_': " . $parser->error();
    }

    my $d = $parser->getValuesHash();
    next unless %$d;

    my $lat         = $d->{"lat-observing"};
    my $lon         = $d->{"lon-observing"};
    my $direction   = $d->{wx_obs_dir};
    my $distance_nm = $d->{wx_obs_dist};
    my $url         = $d->{url} =~ s/&/&amp;/gr;

    next unless defined($lat) && defined($lon)   &&
      defined($distance_nm)                      &&
      defined($direction)                        &&
      $distance_nm                               &&
      $lat0-$lat_r < $lat && $lat < $lat0+$lat_r &&
      $lon0-$lon_r < $lon && $lon < $lon0+$lon_r;

    my $this =  $polygon_header =~ s/xxxxNAMExxxx/getname($d)/er;
    $this    =~ s/xxxxDESCRIPTIONxxxx/$url/;
    print $this;

    # I generate line segments from the given location along the given
    # direction. I can do this more precisely, but unless the distances are very
    # large, latlon are cartesian if I scale the lon by cos(lat)
    my $clat = cos($lat * pi/180.);
    sub write_point
    {
        my ($lat, $lon, $distance_nm, $direction_deg) = @_;
        my $cdir = cos($direction_deg * pi/180.);
        my $sdir = sin($direction_deg * pi/180.);

        my $d_deg = $distance_nm / 60.; # nautical miles to degrees

        my $this = $polygon =~ s/xxxxLATxxxx/$lat - $d_deg * $cdir/er;
        $this =~ s{xxxxLONxxxx}{$lon - $d_deg * $sdir/$clat}e;
        print $this;
    }

    write_point($lat, $lon, $distance_nm-0.5, $direction-0.5);
    write_point($lat, $lon, $distance_nm-0.5, $direction+0.5);
    write_point($lat, $lon, $distance_nm+0.5, $direction+0.5);
    write_point($lat, $lon, $distance_nm+0.5, $direction-0.5);
    write_point($lat, $lon, $distance_nm-0.5, $direction-0.5);
    print $polygon_footer;
}
close $fd;
print $polygons_footer;

print $document_footer;

sub getname
{
    my ($d) = @_;
    my $year      =  $d->{ev_year}    // '';
    my $make      =  $d->{acft_make}  // '';
    my $model     =  $d->{acft_model} // '';
    return "$year $make $model" =~ s/&/&amp;/gr;
}

sub convert_latitude
{
    my ($l) = @_;
    return undef unless defined $l;

    if($l =~ /^([0-9]+)([0-9][0-9])([0-9][0-9])N$/i)
    {
        return $1 + ($2 + $3/60.)/60.;
    }
    if($l =~ /^([0-9]+)([0-9][0-9])([0-9][0-9])S$/i)
    {
        return -($1 + ($2 + $3/60.)/60.);
    }
    return undef;
}
sub convert_longitude
{
    my ($l) = @_;
    return undef unless defined $l;

    if($l =~ /^([0-9]+)([0-9][0-9])([0-9][0-9])E$/i)
    {
        return $1 + ($2 + $3/60.)/60.;
    }
    if($l =~ /^([0-9]+)([0-9][0-9])([0-9][0-9])W$/i)
    {
        return -($1 + ($2 + $3/60.)/60.);
    }
    return undef;
}
