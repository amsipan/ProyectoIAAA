#!/usr/bin/env perl
use strict;
use warnings;
use lib '.';
use Market::MarketData;
use Market::Indicators::SMC_Structures_FVG;

my $md = Market::MarketData->new();
$md->set_base_timeframe('15m');
open my $fh, '<', 'Data/tv_nq1_15m.csv' or die $!;
<$fh>;
while (<$fh>) {
    chomp;
    s/\r//g;
    my @c = split /,/;
    next if @c < 5;
    my $vol = 0;
    if ( defined $c[5] && $c[5] =~ /^-?\d/ ) {
        $vol = 0 + $c[5];
    }
    $md->add_candle( [ @c[ 0 .. 4 ], $vol ] );
}
close $fh;
$md->set_timeframe('1h');
my $n = $md->size();
print "1h bars=$n\n";

my $ind = Market::Indicators::SMC_Structures_FVG->new();
for my $i ( 0 .. $n - 1 ) {
    $ind->update_last( $md, $i );
}

print "--- Active FVGs ---\n";
for my $f ( @{ $ind->get_fvg() || [] } ) {
    my $left_i = $f->{left};
    $left_i = 0 if !defined $left_i;
    my $lts = $md->get_timestamp($left_i);
    $lts = '?' if !defined $lts;
    my $mit = $f->{mitig} ? 1 : 0;
    my $col = $mit ? 'GRAY' : 'COLORED';
    my $hi  = $f->{hi} // 0;
    my $lo  = $f->{lo} // 0;
    my $ty  = $f->{type} // '?';
    print "type=$ty mitig=$mit left=$lts hi=$hi lo=$lo -> $col\n";
}
