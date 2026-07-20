#!/usr/bin/env perl
use strict;
use warnings;
use lib '.';
use Market::MarketData;

my $md = Market::MarketData->new();
$md->set_base_timeframe('15m');
open my $fh, '<', 'Data/tv_nq1_15m.csv' or die $!;
my $h = <$fh>;
my ($n, $f, $l) = (0, undef, undef);
while (<$fh>) {
    chomp;
    s/\r//g;
    my @c = split /,/;
    next if @c < 5;
    my $vol = (defined $c[5] && $c[5] =~ /^-?\d/) ? 0 + $c[5] : 0;
    my $candle = [ @c[0 .. 4], $vol ];
    $f //= $candle->[0];
    $l = $candle->[0];
    $md->add_candle($candle);
    $n++;
}
close $fh;
$md->set_timeframe('15m');
print "n=$n size15=", $md->size(), " first=$f last=$l base=", $md->base_timeframe(), "\n";
$md->set_timeframe('1h');
print "size1h=", $md->size(), "\n";
$md->set_timeframe('2h');
print "size2h=", $md->size(), "\n";
$md->set_timeframe('1m');
print "size1m=", $md->size(), " (empty ok)\n";
$md->set_timeframe('15m');
print "back15=", $md->size(), "\n";
