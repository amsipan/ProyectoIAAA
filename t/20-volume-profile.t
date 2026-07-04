use strict;
use warnings;
use Test::More;

use lib '.';
use Market::MarketData;
use Market::Indicators::VolumeProfile;
use Market::Overlays::VolumeProfile;
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
        [11, 15, 10, 14, 300],
        [14, 18, 13, 14, 500], # Highest volume around 14
        [14, 16, 12, 14, 400],
        [14, 15, 13, 14, 200],
    );
    my $md = build_ohlc(\@c);
    my $vp = Market::Indicators::VolumeProfile->new();

    for my $i (0 .. $md->last_index) {
        $vp->update_last($md, $i);
    }

    my $vals = $vp->get_values();
    ok(defined $vals, 'VolumeProfile values defined');
    ok(defined $vals->{poc}, 'POC computed');
    ok(defined $vals->{vah}, 'VAH computed');
    ok(defined $vals->{val}, 'VAL computed');
    ok($vals->{vah} >= $vals->{val}, 'VAH >= VAL');
}

{
    package VPTestCanvas;
    sub new { bless { ops => [] }, shift }
    sub delete { return }
    sub createLine {
        my ($s, @a) = @_;
        push @{ $s->{ops} }, [ createLine => @a ];
        return 1;
    }
    sub createRectangle {
        my ($s, @a) = @_;
        push @{ $s->{ops} }, [ createRectangle => @a ];
        return 1;
    }
    sub createText {
        my ($s, @a) = @_;
        push @{ $s->{ops} }, [ createText => @a ];
        return 1;
    }
}

# --- task 0039: overlay HISTOGRAM toggle ---
{
    package main;
    my @c = (
        [10, 12, 9, 11, 100],
        [11, 15, 10, 14, 300],
        [14, 18, 13, 14, 500],
        [14, 16, 12, 14, 400],
        [14, 15, 13, 14, 200],
    );
    my $md = build_ohlc(\@c);
    my $vp_ind = Market::Indicators::VolumeProfile->new();
    $vp_ind->update_last($md, $_) for 0 .. $md->last_index;

    my $ov = Market::Overlays::VolumeProfile->new(indicator => $vp_ind, visible => 1);
    my $canvas = VPTestCanvas->new();
    my $scales = Market::Panels::Scales->new(min_y => 9, max_y => 20, bars => 5, right_margin => 0);
    $scales->{width} = 400;
    $scales->{height} = 300;

    $ov->compute_visible($md, $vp_ind, 0, 4);
    $ov->draw($canvas, $scales);
    my @hist_on = grep { $_->[0] eq 'createRectangle' } @{ $canvas->{ops} };
    ok(scalar(@hist_on) >= 1, 'HISTOGRAM on: dibuja barras');

    $ov->set_element_visible('HISTOGRAM', 0);
    $canvas->{ops} = [];
    $ov->draw($canvas, $scales);
    my @hist_off = grep { $_->[0] eq 'createRectangle' } @{ $canvas->{ops} };
    is(scalar(@hist_off), 0, 'HISTOGRAM off: sin barras');
    ok(scalar(grep { $_->[0] eq 'createLine' } @{ $canvas->{ops} }) >= 1,
       'HISTOGRAM off: POC/VA siguen visibles');
}

done_testing();
