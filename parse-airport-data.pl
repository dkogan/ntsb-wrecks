#!/usr/bin/perl
use strict;
use warnings;
use Data::Dumper;

use feature ':5.10';
use autodie;


my $fd_in;
open $fd_in, '<', 'airport-codes_csv.csv';

say '# code lat lon';

while(<$fd_in>)
{
    next if $. == 1;

    s/#//g;
    s/"(.*?)"/ $1 =~ s{,}{_}gr /ge;
    my @F = split(',');

    my %ids;
    accept_id(\%ids, $F[0]);
    accept_id(\%ids, $F[8]);
    accept_id(\%ids, $F[9]);
    accept_id(\%ids, $F[10]);

    my ($lon,$lat) = $F[11] =~ /^([-0-9\.]+) *_ *([-0-9\.]+)/;

    next unless defined $lat && defined $lon;

    for my $id (keys %ids)
    {
        say "$id $lat $lon" if length($id);
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
