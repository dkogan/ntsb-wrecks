#!/usr/bin/perl
use strict;
use warnings;
use Data::Dumper;

use feature ':5.10';
use autodie;


my $fd_in;
open $fd_in, '<', 'airport-codes_csv.csv';

my $fd_out;
open $fd_out, '>', 'airports.vnl';
say $fd_out '# code lat lon';

while(<$fd_in>)
{
    next if $. == 1;

    s/"(.*?)"/ $1 =~ s{,}{_}gr /ge;
    my @F = split(',');

    my %ids;
    $ids{$F[0]}  = 1;
    $ids{$F[8]}  = 1;
    $ids{$F[9]}  = 1;
    $ids{$F[10]} = 1;

    my ($lon,$lat) = $F[11] =~ /^([-0-9\.]+) *_ *([-0-9\.]+)/;

    next unless defined $lat && defined $lon;

    for my $id (keys %ids)
    {
        say $fd_out "$id $lat $lon" if length($id);
    }
}


__END__

# This is for airports.dat from
#   https://raw.githubusercontent.com/jpatokal/openflights/master/data/airports.dat
# That dataset isn't as complete as I need it to be


my $fd_in;
open $fd_in, '<', 'airports.dat';

my $fd_out;
open $fd_out, '>', 'airports.vnl';
say $fd_out '# code lat lon';

while(<$fd_in>)
{
    my @F = split(',');
    process($F[4],   $F[6],$F[7]);
    process($F[5],   $F[6],$F[7]);

    if( $F[5] =~ /^"K(.+)"/ )
    {
        process("\"$1\"",$F[6],$F[7]);
    }
}


sub process
{
    my ($id, $lat, $lon) = @_;

    return if $id eq "\\N";
    return if $id =~ / /;
    return if $lat =~ /[^-0-9\.]/ || $lon =~ /[^-0-9\.]/;

    $id =~ s/\"(.*)\"/$1/;
    $id = uc $id;
    say $fd_out "$id $lat $lon";
}

