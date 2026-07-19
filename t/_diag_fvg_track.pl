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
    chomp; s/\r//g;
    my @c = split /,/;
    next if @c < 5;
    my $vol = (defined $c[5] && $c[5] =~ /^-?\d/) ? 0 + $c[5] : 0;
    $md->add_candle([ @c[0..4], $vol ]);
}
close $fh;
$md->set_timeframe('15m');
my $n = $md->size();

my $ind = Market::Indicators::SMC_Structures_FVG->new();
my $TARGET_LEFT = 20669;  # 17:15

for my $i (0 .. $n - 1) {
    my @before = @{ $ind->{_fvgs} || [] };
    my $had = grep { ($_->{left} // -1) == $TARGET_LEFT && ($_->{type} // '') eq 'bear' } @before;
    $ind->update_last($md, $i);
    my @after = @{ $ind->{_fvgs} || [] };
    my $has = grep { ($_->{left} // -1) == $TARGET_LEFT && ($_->{type} // '') eq 'bear' } @after;

    if (!$had && $has) {
        my ($f) = grep { ($_->{left} // -1) == $TARGET_LEFT } @after;
        printf "APPEAR at i=%d %s hi=%.2f lo=%.2f n_fvg=%d\n",
            $i, $md->get_timestamp($i), $f->{hi}, $f->{lo}, scalar(@after);
    }
    if ($had && !$has) {
        my ($old) = grep { ($_->{left} // -1) == $TARGET_LEFT } @before;
        # Was it full mitigate or trim?
        my $high = $md->get_candle($i)->[2];
        my $reason = ($high >= ($old->{hi} // 1e99)) ? 'FULL_MITIGATE' : 'TRIM_OR_OTHER';
        printf "GONE at i=%d %s reason=%s barH=%.2f fvg_hi=%.2f fvg_lo=%.2f n_before=%d n_after=%d\n",
            $i, $md->get_timestamp($i), $reason, $high, $old->{hi}, $old->{lo},
            scalar(@before), scalar(@after);
        print "  remaining lefts: ", join(', ', map {
            sprintf('%s@%s', $_->{type}, $md->get_timestamp($_->{left}//0)//'?')
        } @after), "\n";
    }
}

# Also: list last 15 bars of FVG set membership for target window
print "\n--- Compare Pine trim: fvgHistoryNbr+1 vs strict 5 ---\n";
print "Also check if TV big box matches a DIFFERENT left (maybe earlier gap)\n";

# Find any bear FVG with left near 17:00-18:00 that had large height
$ind = Market::Indicators::SMC_Structures_FVG->new();
my @big;
for my $i (0 .. $n - 1) {
    $ind->update_last($md, $i);
    for my $f (@{ $ind->{_fvgs} || [] }) {
        next unless ($f->{type} // '') eq 'bear';
        my $h = ($f->{hi} // 0) - ($f->{lo} // 0);
        next if $h < 20;  # only "thick" gaps
        my $lts = $md->get_timestamp($f->{left} // 0) // '';
        next unless $lts =~ /2026-07-16T1[5-9]|2026-07-16T2/;
        push @big, {
            i => $i, ts => $md->get_timestamp($i), left => $f->{left}, lts => $lts,
            hi => $f->{hi}, lo => $f->{lo}, h => $h,
        } unless grep { $_->{left} == $f->{left} && abs($_->{hi} - $f->{hi}) < 0.01 } @big;
    }
}
for my $b (@big) {
    printf "thick bear left=%s hi=%.2f lo=%.2f height=%.2f (seen at %s)\n",
        $b->{lts}, $b->{hi}, $b->{lo}, $b->{h}, $b->{ts};
}

# Dump OHLC for classic 3-bar FVG around left of big TV box
# User says starts 17:15 - maybe they mean left edge of box = that bar
print "\n--- Pine offsets at detect bar for left=17:15 ---\n";
# if left = i-2 = 17:15, then i = 17:45
my $i = 20671;
printf "detect i=%d %s\n", $i, $md->get_timestamp($i);
for my $off (0 .. 3) {
    my $c = $md->get_candle($i - $off);
    printf "  [%d] %s H=%.2f L=%.2f\n", $off, $c->[0], $c->[2], $c->[3];
}
print "bearish: low[3]=", $md->get_candle($i-3)->[3], " high[1]=", $md->get_candle($i-1)->[2], "\n";
