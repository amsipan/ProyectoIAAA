#!/usr/bin/env perl
use strict;
use warnings;
use lib '.';
use Market::MarketData;
use Market::Indicators::SMC_Structures_FVG;

# Monkey-patch trim to Pine: keep fvg_history + 1
{
    no warnings 'redefine';
    *Market::Indicators::SMC_Structures_FVG::_trim_fvgs = sub {
        my ($self) = @_;
        my $max = ($self->{fvg_history} // 5) + 1;  # Pine: > history+1
        $max = 1 if $max < 1;
        while (@{ $self->{_fvgs} } > $max) {
            shift @{ $self->{_fvgs} };
        }
    };
}

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
my $ind = Market::Indicators::SMC_Structures_FVG->new(fvg_history => 5);
my $TARGET = 20669;
my ($appeared, $gone);
for my $i (0 .. $n - 1) {
    my $had = grep { ($_->{left}//-1)==$TARGET && ($_->{type}//'') eq 'bear' } @{$ind->{_fvgs}||[]};
    $ind->update_last($md, $i);
    my $has = grep { ($_->{left}//-1)==$TARGET && ($_->{type}//'') eq 'bear' } @{$ind->{_fvgs}||[]};
    $appeared = $i if !$had && $has;
    if ($had && !$has) {
        $gone = $i;
        printf "GONE (pine+1) at %s n=%d\n", $md->get_timestamp($i), scalar @{$ind->{_fvgs}};
    }
}
print "appeared=", $appeared // 'no', " gone=", $gone // 'still alive', "\n";
print "final active:\n";
for my $f (@{$ind->get_fvg||[]}) {
    printf "  %s left=%s hi=%.2f lo=%.2f right=%s\n",
        $f->{type}, $md->get_timestamp($f->{left}), $f->{hi}, $f->{lo},
        $md->get_timestamp($f->{right});
}
print "count=", scalar(@{$ind->get_fvg||[]}), "\n";

# Also: does our thin FVG look like TV's thick top box? Probably not height-wise.
# Look at TV - big box is near the HIGH of the left candles. 
# At 17:15 area prices ~29200. Thin gap is 29166-29159 - that's near the body of the drop.
# Looking at TV image, the big pink is at the TOP of the left structure, roughly
# at the high of the green candle before the drop. That might be a MUCH earlier FVG
# that was created days ago and extended?

print "\n--- At end of Jul 16 17:45, what FVGs are active (strict 5)? ---\n";
$ind = Market::Indicators::SMC_Structures_FVG->new(fvg_history => 5);
# restore strict trim? redefine again to strict
{
    no warnings 'redefine';
    *Market::Indicators::SMC_Structures_FVG::_trim_fvgs = sub {
        my ($self) = @_;
        my $max = $self->{fvg_history} // 5;
        while (@{ $self->{_fvgs} } > $max) { shift @{ $self->{_fvgs} }; }
    };
}
for my $i (0 .. 20671) { $ind->update_last($md, $i); }
for my $f (@{$ind->{_fvgs}||[]}) {
    printf "  %s left=%s hi=%.2f lo=%.2f h=%.2f\n",
        $f->{type}, $md->get_timestamp($f->{left}), $f->{hi}, $f->{lo},
        ($f->{hi}-$f->{lo});
}
