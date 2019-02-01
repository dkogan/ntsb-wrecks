#!/usr/bin/perl
use strict;
use warnings;
use feature ':5.10';
use Vnlog::Parser;
use Getopt::Long;

my %options = (real    => [],
               integer => [],
               index   => [],
               name    => 'table');
GetOptions(\%options,
           'real=s@', 'integer=s@', 'index=s@',
           'name=s',
           'help') or exit 1;

if($options{help})
{
    say "$0 [--name TABLENAME] [--real FIELD1,FIELD2] [--integer FIELD3,FIELD4] [--index FIELD5]";
    exit 0;
}

# parse comma-separated lists of fields
for my $key (qw(real integer index))
{
    @{$options{$key}} = map split('\s*,\s*', $_), @{$options{$key}};
}

my %type_of_field_name = ();
my @is_string_of_field_index;
for my $t (qw(real integer))
{
    for my $key (@{$options{$t}})
    {
        set_type($key, $t);
    }
}

my $parser = Vnlog::Parser->new();
my $processed_header;
while (<>)
{
    if ( !$parser->parse($_) )
    {
        die "Error parsing vnlog line '$_': " . $parser->error();
    }

    my $values = $parser->getValues() // next;

    if(!$processed_header)
    {
        ingest_header($parser->getKeys());
        $processed_header = 1;
    }


    sub wrap_value
    {
        my ($is_string_of_field_index, $value) = @_;
        return "NULL" if !defined $value;
        return "'" . $value =~ s/'/''/gr . "'" if $is_string_of_field_index;
        return $value;
    }

    say "INSERT INTO '$options{name}' VALUES (" .
      join(',', map {wrap_value($is_string_of_field_index[$_], $values->[$_])} 0..$#$values) .
      ");";
}

if(@{$options{index}})
{
    say "CREATE INDEX 'index' ON '$options{name}' (" .
      join(',', @{$options{index}}) . ");";
}

say "END TRANSACTION;";




sub set_type
{
    my ($key, $type_this) = @_;
    if(defined $type_of_field_name{$key} && $type_of_field_name{$key} ne $type_this)
    {
        die "Type for key '$key' defined as both '$type_of_field_name{$key}' and '$type_this'";
    }
    $type_of_field_name{$key} = $type_this;
}

sub ingest_header
{
    my ($keys) = @_;

    say 'PRAGMA foreign_keys=OFF;';
    say 'BEGIN TRANSACTION;';

    sub make_field_def
    {
        my ($k) = @_;
        return "`$k` " . ($type_of_field_name{$k} // 'varchar');
    }

    @is_string_of_field_index = map {!defined $type_of_field_name{$_}} @$keys;

    say "CREATE TABLE `$options{name}` (" .
      join(',', map {make_field_def($_)} @$keys) .
      ");";
}
