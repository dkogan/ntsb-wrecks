#!/usr/bin/perl
use strict;
use warnings;

use Vnlog::Parser;
use Math::Trig;
use Scalar::Util 'looks_like_number';

use feature ':5.10';
use autodie;


my $usage =
  "$0 lat0 lon0 lat1 lon1 input.vnl\n" .
  "  Pass in the corners of the region of interest, and the input vnlog\n";

my ($lat0,$lon0,$lat1,$lon1,$input_filename) = @ARGV;
if( !defined($input_filename) || !-r $input_filename )
{
    $input_filename //= 'UNDEFINED';
    say STDERR $usage;
    say STDERR "I tried to read '$input_filename' as a file, and couldn't";
    exit 1;
}
if( !( defined($lat0) && looks_like_number($lat0) &&
       defined($lon0) && looks_like_number($lon0) &&
       defined($lat1) && looks_like_number($lat1) &&
       defined($lon1) && looks_like_number($lon1) ) )
{
    say STDERR $usage;
    exit 1;
}

my $lat_r = abs($lat1 - $lat0) / 2.;
my $lon_r = abs($lon1 - $lon0) / 2.;
$lat0 = ($lat0 + $lat1) / 2.;
$lon0 = ($lon0 + $lon1) / 2.;



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

my $polygon_point = <<'EOF';
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

    next unless defined($lat) && defined($lon)   &&
      $lat0-$lat_r < $lat && $lat < $lat0+$lat_r &&
      $lon0-$lon_r < $lon && $lon < $lon0+$lon_r;

    my $this = $marker =~ s/xxxxNAMExxxx/getname($d)/er;
    $this =~ s/xxxxDESCRIPTIONxxxx/getdescription($d->{ev_id})/e;
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

    next unless defined($lat) && defined($lon)   &&
      defined($distance_nm)                      &&
      defined($direction)                        &&
      $distance_nm;


    # I generate line segments from the given location along the given
    # direction. I can do this more precisely, but unless the distances are very
    # large, latlon are cartesian if I scale the lon by cos(lat)
    sub position_along_bearing_line
    {
        my ($lat, $lon, $clat, $distance_nm, $direction_deg) = @_;
        my $cdir = cos($direction_deg * pi/180.);
        my $sdir = sin($direction_deg * pi/180.);

        my $d_deg = $distance_nm / 60.; # nautical miles to degrees
        return ($lat - $d_deg * $cdir,
                $lon - $d_deg * $sdir/$clat);
    }
    sub write_point
    {
        my ($lat,$lon) = position_along_bearing_line(@_);
        my $this = $polygon_point =~ s/xxxxLATxxxx/$lat/er;
        $this =~ s{xxxxLONxxxx}{$lon}e;
        print $this;
    }

    my $clat = cos($lat * pi/180.);
    my ($center_lat, $center_lon) =
      position_along_bearing_line($lat, $lon, $clat, $distance_nm, $direction);

    next unless
      $lat0-$lat_r < $center_lat && $center_lat < $lat0+$lat_r &&
      $lon0-$lon_r < $center_lon && $center_lon < $lon0+$lon_r;

    my $this =  $polygon_header =~ s/xxxxNAMExxxx/getname($d)/er;
    $this =~ s/xxxxDESCRIPTIONxxxx/getdescription($d->{ev_id})/e;
    print $this;

    write_point($lat, $lon, $clat, $distance_nm-0.5, $direction-0.5);
    write_point($lat, $lon, $clat, $distance_nm-0.5, $direction+0.5);
    write_point($lat, $lon, $clat, $distance_nm+0.5, $direction+0.5);
    write_point($lat, $lon, $clat, $distance_nm+0.5, $direction-0.5);
    write_point($lat, $lon, $clat, $distance_nm-0.5, $direction-0.5);
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

sub getdescription
{
    my ($id) = @_;
    return "http://ntsb.secretsauce.net/$id\n";

    # The above contains these 3 links:
    # "Summary: https://app.ntsb.gov/pdfgenerator/ReportGeneratorFile.ashx?EventID=$id&amp;AKey=1&amp;RType=HTML&amp;IType=CA\n" .
    # "Brief:   https://www.ntsb.gov/_layouts/ntsb.aviation/brief.aspx?ev_id=$id&amp;key=1\n" .
    # "Full:    https://www.ntsb.gov/investigations/_layouts/ntsb.aviation/brief2.aspx?ev_id=$id&amp;akey=1";
    #
    # Caltopo currently doesn't make it possible to create 3 usable links

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
