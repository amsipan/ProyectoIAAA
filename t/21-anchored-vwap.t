use strict;
use warnings;
use Test::More;

use lib '.';
use Market::MarketData;
use Market::Indicators::AnchoredVWAP;
use Market::Overlays::AnchoredVWAP;
use Market::Panels::Scales;

sub build_ohlc {
    my ($candles) = @_;
    my $md = Market::MarketData->new();
    for my $i (0 .. $#{$candles}) {
        my ($o, $h, $l, $c, $v) = @{ $candles->[$i] };
        $v //= 10;
        my $ts = sprintf("2026-04-06T00:%02d:00-05:00", $i);
        $md->add_candle([$ts, $o, $h, $l, $c, $v]);
    }
    return $md;
}

{
    my @c = (
        [10, 12, 9, 11, 100],
        [11, 15, 10, 14, 200],
        [14, 18, 13, 17, 300],
        [17, 22, 16, 21, 400],
    );
    my $md = build_ohlc(\@c);
    my $vwap = Market::Indicators::AnchoredVWAP->new();

    for my $i (0 .. $md->last_index) {
        $vwap->update_last($md, $i);
    }

    my $vals = $vwap->get_values();
    ok(defined $vals, 'AnchoredVWAP values defined');
    is(scalar(@$vals), 4, '4 VWAP values computed');
    ok($vals->[3]->{value} > 10, 'VWAP value is reasonable');
}

{
    package VWTestCanvas;
    sub new { bless { ops => [] }, shift }
    sub delete { return }
    sub createLine {
        my ($s, @a) = @_;
        push @{ $s->{ops} }, [ createLine => @a ];
        return 1;
    }
}

# --- task 0039: overlay VWAP_LINE toggle ---
{
    package main;
    my @c = (
        [10, 12, 9, 11, 100],
        [11, 15, 10, 14, 200],
        [14, 18, 13, 17, 300],
        [17, 22, 16, 21, 400],
    );
    my $md = build_ohlc(\@c);
    my $vwap_ind = Market::Indicators::AnchoredVWAP->new();
    $vwap_ind->update_last($md, $_) for 0 .. $md->last_index;

    my $ov = Market::Overlays::AnchoredVWAP->new(indicator => $vwap_ind, visible => 1);
    my $canvas = VWTestCanvas->new();
    my $scales = Market::Panels::Scales->new(min_y => 9, max_y => 25, bars => 4, right_margin => 0);
    $scales->{width} = 400;
    $scales->{height} = 300;

    $ov->compute_visible($md, $vwap_ind, 0, 3);
    $ov->draw($canvas, $scales);
    is(scalar(@{ $canvas->{ops} }), 3, 'VWAP_LINE on: dibuja segmentos');

    $ov->set_element_visible('VWAP_LINE', 0);
    $canvas->{ops} = [];
    $ov->draw($canvas, $scales);
    is(scalar(@{ $canvas->{ops} }), 0, 'VWAP_LINE off: sin segmentos');
}

done_testing();
