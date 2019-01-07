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



sub accept_id
{
    my ($ids, $id) = @_;
    if ($id =~ /[a-z]/i && length($id) > 1)
    {
        $ids->{$id} = 1;
    }
}
