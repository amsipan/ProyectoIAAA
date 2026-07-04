use strict;
use warnings;
use Test::More;

use lib '.';
use Market::MarketData;
use Market::Indicators::Strategy_Builder;
use Market::Overlays::Strategy_Builder;
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
        [11, 15, 10, 14, 100],
        [14, 18, 13, 17, 100],
        [17, 22, 16, 21, 500], # Volume expansion
        [21, 25, 20, 24, 100],
    );
    my $md = build_ohlc(\@c);
    my $sb = Market::Indicators::Strategy_Builder->new();

    for my $i (0 .. $md->last_index) {
        $sb->update_last($md, $i);
    }

    my $vals = $sb->get_values();
    ok(defined $vals->{supertrend}, 'SuperTrend computed');
    ok(defined $vals->{halftrend},  'HalfTrend computed');
    ok(defined $vals->{rangefilter},'RangeFilter computed');
    is(scalar(@{ $vals->{supertrend} }), 5, '5 SuperTrend values');
}

{
    package SBTestCanvas;
    sub new { bless { ops => [] }, shift }
    sub delete { return }
    sub createLine {
        my ($s, @a) = @_;
        push @{ $s->{ops} }, [ createLine => @a ];
        return scalar @{ $s->{ops} };
    }
    sub createRectangle {
        my ($s, @a) = @_;
        push @{ $s->{ops} }, [ createRectangle => @a ];
        return scalar @{ $s->{ops} };
    }

    package SBTestIndicator;
    sub new {
        bless {
            supertrend => [
                { value => 10, dir => 1 },
                { value => 12, dir => 1 },
                { value => 8,  dir => -1 },
                { value => 7,  dir => -1 },
                { value => 6,  dir => -1 },
            ],
            halftrend => [
                { value => 10, dir => 1 },
                { value => 11, dir => 1 },
                { value => 9,  dir => -1 },
                { value => 8,  dir => -1 },
                { value => 7,  dir => -1 },
            ],
            rangefilter => [
                { value => 10, dir => 1 },
                { value => 11, dir => 1 },
                { value => 9,  dir => -1 },
                { value => 8,  dir => -1 },
                { value => 7,  dir => -1 },
            ],
            supply_zones => [],
            demand_zones => [],
        }, shift;
    }
    sub get_values { shift }
}

# --- task 0039: overlay render (SuperTrend flip, toggles HT/RF) ---
{
    package main;
    my $ind = SBTestIndicator->new();
    my $ov  = Market::Overlays::Strategy_Builder->new(indicator => $ind, visible => 1);
    my $canvas = SBTestCanvas->new();
    my $scales = Market::Panels::Scales->new(min_y => 5, max_y => 25, bars => 5, right_margin => 0);
    $scales->{width} = 500;
    $scales->{height} = 400;

    $ov->set_element_visible('HALFTREND', 0);
    $ov->set_element_visible('RANGEFILTER', 0);
    $ov->set_element_visible('SUPPLY_DEMAND', 0);
    $ov->compute_visible(undef, $ind, 0, 4);
    $ov->draw($canvas, $scales);
    my @st_lines = grep { $_->[0] eq 'createLine' } @{ $canvas->{ops} };
    is(scalar(@st_lines), 3, 'SuperTrend: rompe en flip (3 segmentos, no 4)');

    $canvas->{ops} = [];
    $ov->set_element_visible('SUPERTREND', 0);
    $ov->set_element_visible('HALFTREND', 1);
    $ov->set_element_visible('RANGEFILTER', 0);
    $ov->draw($canvas, $scales);
    my @ht_lines = grep { $_->[0] eq 'createLine' } @{ $canvas->{ops} };
    ok(scalar(@ht_lines) >= 1, 'HALFTREND toggle: dibuja lineas');

    $canvas->{ops} = [];
    $ov->set_element_visible('HALFTREND', 0);
    $ov->set_element_visible('RANGEFILTER', 1);
    $ov->draw($canvas, $scales);
    my @rf_lines = grep { $_->[0] eq 'createLine' } @{ $canvas->{ops} };
    ok(scalar(@rf_lines) >= 1, 'RANGEFILTER toggle: dibuja lineas');
    is(scalar(grep { $_->[0] eq 'createLine' } @{ $canvas->{ops} }), scalar(@rf_lines),
       'SUPERTREND+HALFTREND off: solo RangeFilter');
}

done_testing();
