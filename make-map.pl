#!/usr/bin/perl
use strict;
use warnings;

use Vnlog::Parser;
use Math::Trig;
use Scalar::Util 'looks_like_number';
use DBI;
use DBD::SQLite::Constants qw/:file_open/;

use feature ':5.10';
use autodie;


my $usage =
  "$0 lat0 lon0 lat1 lon1 input.vnl|input.sqlite\n" .
  "  Pass in the corners of the region of interest, and the input vnlog (or sqlite db)\n";

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
{"type":"FeatureCollection","features":[
EOF

my $markers_header = <<'EOF';
EOF

my $marker = <<'EOF';
{"properties":{"title":"xxxxNAMExxxx","description":"xxxxDESCRIPTIONxxxx"},"geometry":{"type":"Point", "coordinates":[xxxxLONxxxx,xxxxLATxxxx]}}
EOF

my $markers_footer = <<'EOF';
EOF

my $polygons_header = <<'EOF';
EOF

my $polygon_header = <<'EOF';
{"properties":{"title":"xxxxNAMExxxx","description":"xxxxDESCRIPTIONxxxx"},"geometry":{"type":"Polygon","coordinates":[[
EOF

my $polygon_point = <<'EOF';
[xxxxLONxxxx,xxxxLATxxxx]
EOF

my $polygon_footer = <<'EOF';
]]}}
EOF

my $polygons_footer = <<'EOF';
EOF

my $document_footer = <<'EOF';
]}
EOF


print $document_header;

my $parser;
my $fd;
my $dbh;

# First, write the markers
my $marker_printed_one = undef;
print $markers_header;



sub ingest_point
{
    my ($lat,$lon,$ev_id,$ev_year,$acft_make,$acft_model) = @_;

    print "," if $marker_printed_one;
    $marker_printed_one = 1;

    my $this = $marker =~ s/xxxxNAMExxxx/getname($ev_year,$acft_make,$acft_model)/er;
    $this =~ s/xxxxDESCRIPTIONxxxx/getdescription($ev_id)/e;
    $this =~ s/xxxxLONxxxx/$lon/;
    $this =~ s/xxxxLATxxxx/$lat/;

    print $this;
}

if($input_filename =~ /vnl$/)
{
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

        my $lat = $d->{latitude};
        my $lon = $d->{longitude};

        next unless defined($lat) && defined($lon)   &&
          $lat0-$lat_r < $lat && $lat < $lat0+$lat_r &&
          $lon0-$lon_r < $lon && $lon < $lon0+$lon_r;

        ingest_point($lat,$lon,$d->{ev_id},$d->{ev_year},$d->{acft_make},$d->{acft_model})
    }
    close $fd;
}
else
{
    $dbh = DBI->connect("dbi:SQLite:$input_filename",undef,undef,
                        {sqlite_open_flags => SQLITE_OPEN_READONLY});
    my $sql =
      'SELECT latitude,longitude,ev_id,ev_year,acft_make,acft_model ' .
      "FROM 'table' WHERE " .
      "latitude  IS NOT NULL AND " .
      "longitude IS NOT NULL AND " .
      "$lat0-$lat_r < latitude  AND latitude  < $lat0+$lat_r AND " .
      "$lon0-$lon_r < longitude AND longitude < $lon0+$lon_r;";
    my $sth = $dbh->prepare($sql);
    $sth->execute();
    while (my @row = $sth->fetchrow_array)
    {
        ingest_point(@row);
    }
}
print $markers_footer;


# Then, the observing sectors
print "," if $marker_printed_one;
my $polygon_printed_one = undef;
print $polygons_header;


sub ingest_wedge
{
    my ($lat,$lon,$distance_nm,$direction,$ev_id,$ev_year,$acft_make,$acft_model) = @_;

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

    return unless
      $lat0-$lat_r < $center_lat && $center_lat < $lat0+$lat_r &&
      $lon0-$lon_r < $center_lon && $center_lon < $lon0+$lon_r;

    print "," if $polygon_printed_one;
    $polygon_printed_one = 1;

    my $this =  $polygon_header =~ s/xxxxNAMExxxx/getname($ev_year,$acft_make,$acft_model)/er;
    $this =~ s/xxxxDESCRIPTIONxxxx/getdescription($ev_id)/e;
    print $this;

    write_point($lat, $lon, $clat, $distance_nm-0.5, $direction-0.5);
    print ",";
    write_point($lat, $lon, $clat, $distance_nm-0.5, $direction+0.5);
    print ",";
    write_point($lat, $lon, $clat, $distance_nm+0.5, $direction+0.5);
    print ",";
    write_point($lat, $lon, $clat, $distance_nm+0.5, $direction-0.5);
    print ",";
    write_point($lat, $lon, $clat, $distance_nm-0.5, $direction-0.5);
    print $polygon_footer;
}



if($input_filename =~ /vnl$/)
{
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

        my $lat         = $d->{lat_observing};
        my $lon         = $d->{lon_observing};
        my $distance_nm = $d->{wx_obs_dist};
        my $direction   = $d->{wx_obs_dir};

        next unless defined($lat) && defined($lon)   &&
          defined($distance_nm)                      &&
          defined($direction)                        &&
          defined($distance_nm);
        ingest_wedge($lat,$lon,$distance_nm,$direction,$d->{ev_id},$d->{ev_year},$d->{acft_make},$d->{acft_model});
    }
    close $fd;
}
else
{
    # I'm already connected to a database, so I reuse $dbh

    # This looks at lat/lon OBSERVING, not the real one, so I use a larger
    # radius window to throw away records that clearly don't apply
    my $sql =
      'SELECT lat_observing,lon_observing,wx_obs_dist,wx_obs_dir,ev_id,ev_year,acft_make,acft_model ' .
      "FROM 'table' WHERE " .
      "lat_observing IS NOT NULL AND " .
      "lon_observing IS NOT NULL AND " .
      "wx_obs_dist   IS NOT NULL AND " .
      "wx_obs_dir    IS NOT NULL AND " .
      "$lat0-($lat_r+1.0) < lat_observing AND lat_observing < $lat0+($lat_r+1.0) AND " .
      "$lon0-($lon_r+1.0) < lon_observing AND lon_observing < $lon0+($lon_r+1.0) AND " .
      "$lat0-($lat_r+1.0) < lat_observing AND lat_observing < $lat0+($lat_r+1.0) AND " .
      "$lon0-($lon_r+1.0) < lon_observing AND lon_observing < $lon0+($lon_r+1.0);";
    my $sth = $dbh->prepare($sql);
    $sth->execute();
    while (my @row = $sth->fetchrow_array)
    {
        ingest_wedge(@row);
    }
}
print $polygons_footer;

print $document_footer;

sub getname
{
    my ($ev_year,$acft_make,$acft_model) = @_;

    my $year      =  $ev_year    // '';
    my $make      =  $acft_make  // '';
    my $model     =  $acft_model // '';
    return "$year $make $model" =~ s/&/&amp;/gr;
}

sub getdescription
{
    my ($id) = @_;
    return "http://ntsb.secretsauce.net/$id";

    # The above contains these 3 links:
    # "Summary: https://app.ntsb.gov/pdfgenerator/ReportGeneratorFile.ashx?EventID=$id&amp;AKey=1&amp;RType=HTML&amp;IType=CA\n" .
    # "Brief:   https://www.ntsb.gov/_layouts/ntsb.aviation/brief.aspx?ev_id=$id&amp;key=1\n" .
    # "Full:    https://www.ntsb.gov/investigations/_layouts/ntsb.aviation/brief2.aspx?ev_id=$id&amp;akey=1";
    #
    # Caltopo currently doesn't make it possible to create 3 usable links

}
