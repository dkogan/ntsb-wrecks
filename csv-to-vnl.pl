#!/usr/bin/perl
use strict;
use warnings;
use feature ':5.10';
use Text::CSV;

my $csv = Text::CSV->new ( { binary => 1 } )
  or die 'Cannot use CSV: '.Text::CSV->error_diag ();

my $header = $csv->getline( *STDIN );
say '# ' . join(' ', @$header);

while ( my $row = $csv->getline( *STDIN ) )
{
    map { s/^\s*(.*?)\s*$/$1/;     # remove outer whitespace
          $_ = '-' if length == 0; # set NULL fields
          s/\s/_/g;                # remove interstitial whitespace
          s/\\/_/g;                # remove interstitial \
      } @$row;
    say join(' ', @$row);
}
