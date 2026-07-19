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
print "bars=$n first=", $md->get_timestamp(0), " last=", $md->get_timestamp($n-1), "\n";

# Find Jul 16 17:15 and nearby
my ($i_1715, $i_1700);
for my $i (0 .. $n - 1) {
    my $ts = $md->get_timestamp($i) // next;
    $i_1700 = $i if $ts =~ /2026-07-16T17:00/;
    $i_1715 = $i if $ts =~ /2026-07-16T17:15/;
}
print "idx 17:00=", ($i_1700 // 'NA'), " 17:15=", ($i_1715 // 'NA'), "\n";

# Print OHLC around 16 Jul 17:00-20:00
print "\n--- OHLC 16-jul tarde ---\n";
for my $i ( ($i_1715 // 0) - 5 .. ($i_1715 // 0) + 20 ) {
    next if $i < 0 || $i >= $n;
    my $c = $md->get_candle($i);
    printf "i=%d %s O=%.2f H=%.2f L=%.2f C=%.2f\n",
        $i, $c->[0], $c->[1], $c->[2], $c->[3], $c->[4];
}

# Run full indicator and track FVG lifecycle
my $ind = Market::Indicators::SMC_Structures_FVG->new();
my @created;
my @killed;

# Monkey-patch via wrap: reimplement process with logging by subclassing...
# Just feed all and inspect active; also re-scan for any bar that should create bearish near 17:15

for my $i (0 .. $n - 1) {
    my $before = scalar @{ $ind->{_fvgs} || [] };
    my @snap = map { { %$_ } } @{ $ind->{_fvgs} || [] };
    $ind->update_last($md, $i);
    my $after = scalar @{ $ind->{_fvgs} || [] };

    # Detect new FVGs
    for my $f (@{ $ind->{_fvgs} || [] }) {
        if (($f->{index} // -1) == $i && ($f->{left} // -1) >= 0) {
            # newly created this bar (index == i)
            push @created, {
                bar => $i,
                ts  => $md->get_timestamp($i),
                type => $f->{type},
                left => $f->{left},
                left_ts => $md->get_timestamp($f->{left}),
                hi => $f->{hi},
                lo => $f->{lo},
            } if !grep { $_->{bar} == $i && $_->{type} eq $f->{type} && $_->{left} == $f->{left} } @created;
        }
    }

    # Detect removed (in snap but not in current by left+type+hi)
    for my $old (@snap) {
        my $still = 0;
        for my $f (@{ $ind->{_fvgs} || [] }) {
            if (($f->{left} // -2) == ($old->{left} // -3)
                && ($f->{type} // '') eq ($old->{type} // 'x')
                && abs(($f->{hi} // 0) - ($old->{hi} // 0)) < 0.01) {
                $still = 1;
                last;
            }
        }
        if (!$still && ($old->{left_ts} // $md->get_timestamp($old->{left} // 0) // '') =~ /2026-07-16/
            || ($old->{left} // -1) >= (($i_1715 // 0) - 10) && ($old->{left} // -1) <= (($i_1715 // 0) + 30)) {
            push @killed, {
                at => $i,
                at_ts => $md->get_timestamp($i),
                type => $old->{type},
                left => $old->{left},
                left_ts => $md->get_timestamp($old->{left} // 0),
                hi => $old->{hi},
                lo => $old->{lo},
                mitig => $old->{mitig},
            };
        }
    }
}

print "\n--- FVGs created near 16-jul (left in 16-17 jul) ---\n";
for my $cr (@created) {
    my $near = (($cr->{left_ts} // '') =~ /2026-07-1[67]/)
            || (($cr->{ts} // '') =~ /2026-07-1[67]/);
    next unless $near;
    printf "create bar=%d %s type=%s left=%d(%s) hi=%.2f lo=%.2f\n",
        $cr->{bar}, $cr->{ts}, $cr->{type}, $cr->{left}, $cr->{left_ts} // '?', $cr->{hi}, $cr->{lo};
}

print "\n--- Active FVGs at end ---\n";
for my $f (@{ $ind->get_fvg() || [] }) {
    my $lts = $md->get_timestamp($f->{left} // 0);
    my $rts = $md->get_timestamp($f->{right} // 0);
    printf "type=%s left=%d(%s) right=%d(%s) hi=%.2f lo=%.2f mitig=%d\n",
        $f->{type}, $f->{left}, $lts // '?', $f->{right}, $rts // '?',
        $f->{hi}, $f->{lo}, $f->{mitig} // 0;
}

print "\n--- Manual scan: bearish FVG conditions Jul 16 16:00 - Jul 17 20:00 ---\n";
my $start = $i_1715 // int($n * 0.98);
$start = $start - 20 if $start > 20;
for my $i ($start .. $n - 1) {
    next if $i < 3;
    my $h3 = $md->get_candle($i - 3)->[2];
    my $l3 = $md->get_candle($i - 3)->[3];
    my $h1 = $md->get_candle($i - 1)->[2];
    my $l1 = $md->get_candle($i - 1)->[3];
    my $bear = $l3 > $h1;
    my $bull = $h3 < $l1;
    next unless $bear || $bull;
    printf "i=%d %s bear=%d (l3=%.2f > h1=%.2f) bull=%d (h3=%.2f < l1=%.2f) left=%s\n",
        $i, $md->get_timestamp($i),
        $bear ? 1 : 0, $l3, $h1,
        $bull ? 1 : 0, $h3, $l1,
        $md->get_timestamp($i - 2);
}

print "\n--- Total created all series: ", scalar(@created), " final active: ", scalar(@{ $ind->get_fvg() || [] }), "\n";
