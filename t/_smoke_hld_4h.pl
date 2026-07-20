use strict;
use warnings;
use lib '.';
use Market::MarketData;
use Market::Indicators::HLD;

my $md = Market::MarketData->new();
$md->set_base_timeframe('15m');
my $path = 'Data/tv_nq1_15m.csv';
$path = 'C:/Users/bryan/Downloads/CME_MINI_DL_NQ1!, 15.csv' unless -f $path;
open my $fh, '<', $path or die "no csv $path: $!";
<$fh>;
while (<$fh>) {
    chomp;
    s/\r//g;
    my @c = split /,/;
    next if @c < 5;
    my $vol = ( defined $c[5] && $c[5] =~ /^-?\d/ ) ? 0 + $c[5] : 0;
    $md->add_candle( [ @c[ 0 .. 4 ], $vol ] );
}
close $fh;
$md->ensure_timeframe('4h');
$md->set_timeframe('4h');
my $n = $md->size();
print "4h bars=$n last=", $md->get_timestamp( $n - 1 ), " close=",
  $md->get_candle( $n - 1 )->[4], "\n";

my $ind = Market::Indicators::HLD->new();
my $r   = $ind->compute( $md, tf => '4h', end_index => $n - 1 );
if ( !$r->{ok} ) {
    print "HLD fail: $r->{reason}\n";
    exit;
}
my $age   = $r->{age_bars};
my $hours = $age * 4;
my $days  = $hours / 24;
printf
  "CURRENT pick: anchor_index=%d end=%d age_bars=%d (~%.1f hours / ~%.2f days)\n",
  $r->{anchor_index}, $r->{end_index}, $age, $hours, $days;
print "anchor_ts=$r->{anchor_ts}\n";
print "P=$r->{price} R=$r->{resistance} S=$r->{support} in_range=$r->{in_range}\n";
print "nearest=$r->{nearest_ohlc}{field} @ $r->{nearest_ohlc}{value}\n";

my $P         = $r->{price};
my $last_cand = $n - 2;
print "\nin-range candidates (most recent first, max 15):\n";
my $cnt = 0;
for my $i ( reverse 0 .. $last_cand ) {
    my $c = $md->get_candle($i);
    next unless $c->[3] <= $P && $P <= $c->[2];
    my $a = ( $n - 1 ) - $i;
    printf "  age=%2d bars (~%3dh / %.1fd) %s  H=%.2f L=%.2f\n",
      $a, $a * 4, $a * 4 / 24, $c->[0], $c->[2], $c->[3];
    last if ++$cnt >= 15;
}
