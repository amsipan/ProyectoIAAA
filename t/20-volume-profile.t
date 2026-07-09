use strict;
use warnings;
use Test::More;

use lib '.';
use Market::MarketData;
use Market::Indicators::VolumeProfile;
use Market::Overlays::VolumeProfile;
use Market::Panels::Scales;
use Market::UI::Callbacks;

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

sub feed_all {
    my ($vp, $md) = @_;
    $vp->update_last($md, $_) for 0 .. $md->last_index;
}

# ---------------------------------------------------------------------------
# Sin ancla: sin perfil
# ---------------------------------------------------------------------------
{
    my $md = build_ohlc([
        [10, 12, 9, 11, 100],
        [11, 15, 10, 14, 300],
        [14, 18, 13, 14, 500],
    ]);
    my $vp = Market::Indicators::VolumeProfile->new(row_size => 20);
    feed_all($vp, $md);
    ok(!$vp->has_anchor(), 'sin ancla al inicio');
    ok(!defined $vp->get_values(), 'sin perfil sin ancla');
}

# ---------------------------------------------------------------------------
# Ancla + POC/VAH/VAL + row_size
# ---------------------------------------------------------------------------
{
    my $md = build_ohlc([
        [10, 12, 9, 11, 100],
        [11, 15, 10, 14, 300],
        [14, 18, 13, 14, 500],
        [14, 16, 12, 14, 400],
        [14, 15, 13, 14, 200],
    ]);
    my $vp = Market::Indicators::VolumeProfile->new(row_size => 24, value_area_pct => 70);
    feed_all($vp, $md);
    $vp->set_anchor(1);

    my $vals = $vp->get_values();
    ok(defined $vals, 'perfil con ancla');
    is($vals->{anchor_idx}, 1, 'ancla = 1');
    ok(defined $vals->{poc}, 'POC');
    ok(defined $vals->{vah}, 'VAH');
    ok(defined $vals->{val}, 'VAL');
    ok($vals->{vah} >= $vals->{val}, 'VAH >= VAL');
    ok(defined $vals->{bins} && @{ $vals->{bins} } == 24, '24 filas (row_size)');
    ok($vals->{poc} >= $vals->{min_p} && $vals->{poc} <= $vals->{max_p}, 'POC en rango');

    $vp->set_row_size(10);
    my $v2 = $vp->get_values();
    is(scalar(@{ $v2->{bins} }), 10, 'cambiar row_size recalcula filas');

    $vp->set_value_area_pct(50);
    my $v3 = $vp->get_values();
    ok(defined $v3->{vah} && defined $v3->{val}, 'VA 50% sigue produciendo VAH/VAL');
}

# ---------------------------------------------------------------------------
# reset preserva ancla
# ---------------------------------------------------------------------------
{
    my $md = build_ohlc([
        [10, 12, 9, 11, 100],
        [14, 18, 13, 14, 500],
        [14, 16, 12, 14, 400],
    ]);
    my $vp = Market::Indicators::VolumeProfile->new(row_size => 12);
    feed_all($vp, $md);
    $vp->set_anchor(0);
    my $poc_before = $vp->get_values()->{poc};
    $vp->reset();
    is($vp->anchor_index(), 0, 'reset preserva ancla');
    feed_all($vp, $md);
    ok(defined $vp->get_values()->{poc}, 'perfil tras re-feed');
    ok(abs($vp->get_values()->{poc} - $poc_before) < 1e-6, 'mismo POC tras reset+feed');
}

# ---------------------------------------------------------------------------
# Overlay: histograma azul a la derecha, sin ancla no dibuja
# ---------------------------------------------------------------------------
{
    package VPTestCanvas;
    sub new { bless { ops => [] }, shift }
    sub delete { my ($s) = @_; $s->{ops} = []; return }
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
    sub lower { return 1 }
}

{
    package main;
    my $md = build_ohlc([
        [10, 12, 9, 11, 100],
        [11, 15, 10, 14, 300],
        [14, 18, 13, 14, 500],
        [14, 16, 12, 14, 400],
    ]);
    my $vp_ind = Market::Indicators::VolumeProfile->new(row_size => 16);
    feed_all($vp_ind, $md);

    my $ov = Market::Overlays::VolumeProfile->new(indicator => $vp_ind, visible => 1);
    my $canvas = VPTestCanvas->new();
    my $scales = Market::Panels::Scales->new(min_y => 9, max_y => 20, bars => 4, right_margin => 0);
    $scales->{width}  = 400;
    $scales->{height} = 300;

    $ov->compute_visible($md, $vp_ind, 0, 3);
    $ov->draw($canvas, $scales);
    is(scalar(@{ $canvas->{ops} }), 0, 'sin ancla: no dibuja');

    $vp_ind->set_anchor(1);
    $canvas->{ops} = [];
    $ov->draw($canvas, $scales);
    ok(scalar(@{ $canvas->{ops} }) > 3, 'con ancla: dibuja histograma/líneas');

    my $has_blue_hist = 0;
    my $has_poc_line  = 0;
    my $has_poc_label = 0;
    my @line_widths;
    for my $op (@{ $canvas->{ops} }) {
        for my $i (0 .. $#$op - 1) {
            if ($op->[$i] eq '-fill') {
                my $c = $op->[$i + 1];
                $has_blue_hist = 1 if $c && $c =~ /#4FC3F7|#29B6F6/i;
            }
            if ($op->[0] eq 'createLine' && $op->[$i] eq '-width') {
                push @line_widths, $op->[$i + 1];
            }
        }
        $has_poc_line  = 1 if $op->[0] eq 'createLine';
        $has_poc_label = 1 if $op->[0] eq 'createText';
    }
    ok($has_blue_hist, 'histograma azul cian (sin rojo up/down)');
    ok($has_poc_line,  'líneas horizontales (VA/POC)');
    ok(!$has_poc_label, 'sin etiqueta de precio POC');
    ok(@line_widths >= 3, 'al menos 3 líneas horizontales');
    ok((grep { $_ == 1 } @line_widths) == @line_widths, 'todas las líneas mismo grosor 1');

    $ov->set_element_visible('HISTOGRAM', 0);
    $canvas->{ops} = [];
    $ov->draw($canvas, $scales);
    my $hist_after = 0;
    for my $op (@{ $canvas->{ops} }) {
        next unless $op->[0] eq 'createRectangle';
        for my $i (0 .. $#$op - 1) {
            $hist_after = 1 if $op->[$i] eq '-fill'
                && $op->[$i + 1] && $op->[$i + 1] =~ /#4FC3F7|#29B6F6/i;
        }
    }
    # Puede quedar caja BOX; no debe haber barras de histograma del color del perfil
    ok(!$hist_after, 'HISTOGRAM off: sin barras de perfil');
}

# ---------------------------------------------------------------------------
# Callbacks settings
# ---------------------------------------------------------------------------
{
    package FakeChartVP;
    sub new {
        my ($c) = @_;
        my $ind = Market::Indicators::VolumeProfile->new(row_size => 20);
        bless {
            vp_indicator => $ind,
            price_canvas => undef,
            renders => 0,
        }, $c;
    }
    sub request_render { $_[0]{renders}++; return $_[0] }
}
{
    package main;
    my $chart = FakeChartVP->new();
    my $set = Market::UI::Callbacks->make_vp_settings_setter($chart);
    $set->(row_size => 50, value_area_pct => 80);
    is($chart->{vp_indicator}->row_size(), 50, 'set row_size');
    is($chart->{vp_indicator}->value_area_pct(), 80, 'set VA%');
}

done_testing();
