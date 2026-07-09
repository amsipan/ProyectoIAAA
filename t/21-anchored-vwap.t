use strict;
use warnings;
use Test::More;

use lib '.';
use Market::MarketData;
use Market::Indicators::AnchoredVWAP;
use Market::Overlays::AnchoredVWAP;
use Market::Panels::Scales;
use Market::UI::Callbacks;

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
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
    my ($vwap, $md) = @_;
    $vwap->update_last($md, $_) for 0 .. $md->last_index;
}

# ---------------------------------------------------------------------------
# Sin ancla: no hay serie dibujable
# ---------------------------------------------------------------------------
{
    my @c = (
        [10, 12, 9, 11, 100],
        [11, 15, 10, 14, 200],
        [14, 18, 13, 17, 300],
    );
    my $md = build_ohlc(\@c);
    my $vwap = Market::Indicators::AnchoredVWAP->new();
    feed_all($vwap, $md);
    ok(!$vwap->has_anchor(), 'sin ancla al inicio');
    my $vals = $vwap->get_values();
    ok(!defined $vals->[0] && !defined $vals->[2], 'sin ancla no hay puntos de serie');
}

# ---------------------------------------------------------------------------
# Ancla manual + fórmula VWAP acumulado HLC3 (como TV / DIY ta.vwap)
# VWAP_t = sum(p*v)/sum(v) desde ancla
# ---------------------------------------------------------------------------
{
    # p0 = (12+9+11)/3 = 10.666..., v=100
    # p1 = (15+10+14)/3 = 13, v=200
    # p2 = (18+13+17)/3 = 16, v=300
    my @c = (
        [10, 12, 9, 11, 100],
        [11, 15, 10, 14, 200],
        [14, 18, 13, 17, 300],
    );
    my $md = build_ohlc(\@c);
    my $vwap = Market::Indicators::AnchoredVWAP->new();
    feed_all($vwap, $md);
    $vwap->set_anchor(1);  # nace en la vela 1

    is($vwap->anchor_index(), 1, 'ancla = 1');
    ok(!defined $vwap->get_point(0), 'antes de ancla: sin valor');

    my $p1 = (15 + 10 + 14) / 3;
    my $pt1 = $vwap->get_point(1);
    ok(defined $pt1, 'punto en ancla');
    ok(abs($pt1->{value} - $p1) < 1e-9, 'VWAP en ancla = HLC3 de esa vela');

    my $p2 = (18 + 13 + 17) / 3;
    my $exp2 = ($p1 * 200 + $p2 * 300) / (200 + 300);
    my $pt2 = $vwap->get_point(2);
    ok(defined $pt2, 'punto tras ancla');
    ok(abs($pt2->{value} - $exp2) < 1e-9, 'VWAP acumulado correcto en t=2');

    # Banda #1 (mult=1) activa por defecto; stdev en ancla (1 punto) = 0
    ok(defined $pt1->{upper1} && defined $pt1->{lower1}, 'banda 1 presente en ancla');
    ok(abs($pt1->{upper1} - $pt1->{value}) < 1e-9, 'en ancla stdev~0 => bandas = vwap');
    ok(!defined $pt1->{upper2}, 'banda 2 off por defecto (como TV captura)');
}

# ---------------------------------------------------------------------------
# Bandas σ: variance = E[p²]-vwap² ponderado por vol (modo Standard DIY/TV)
# ---------------------------------------------------------------------------
{
    my @c = (
        [10, 12, 8, 10, 100],  # hlc3=10
        [10, 14, 10, 12, 100], # hlc3=12
        [12, 16, 12, 14, 100], # hlc3=14
    );
    my $md = build_ohlc(\@c);
    my $vwap = Market::Indicators::AnchoredVWAP->new();
    feed_all($vwap, $md);
    $vwap->set_anchor(0);

    my $pt = $vwap->get_point(2);
    # sum_pv = 10*100+12*100+14*100 = 3600; sum_vol=300; vwap=12
    # sum_p2v = 100+144+196 = 440 *100 = 44000; E[p2]=146.666; var=146.666-144=2.666; stdev=sqrt(8/3)
    my $exp_vwap = 12;
    my $exp_var  = (100 * (100 + 144 + 196) / 300) - 144;  # = 44000/300 - 144
    my $exp_sd   = sqrt($exp_var);
    ok(abs($pt->{value} - $exp_vwap) < 1e-9, 'vwap medio 12');
    ok(abs($pt->{stdev} - $exp_sd) < 1e-9,   'stdev volume-weighted');
    ok(abs($pt->{upper1} - ($exp_vwap + $exp_sd)) < 1e-9, 'upper1 = vwap+1σ');
    ok(abs($pt->{lower1} - ($exp_vwap - $exp_sd)) < 1e-9, 'lower1 = vwap-1σ');

    $vwap->set_band(2, on => 1, mult => 2);
    $pt = $vwap->get_point(2);
    ok(defined $pt->{upper2}, 'banda 2 activable');
    ok(abs($pt->{upper2} - ($exp_vwap + 2 * $exp_sd)) < 1e-9, 'upper2 = vwap+2σ');
}

# ---------------------------------------------------------------------------
# reset preserva ancla (Replay step-back re-alimenta)
# ---------------------------------------------------------------------------
{
    my @c = (
        [10, 12, 9, 11, 100],
        [11, 15, 10, 14, 200],
        [14, 18, 13, 17, 300],
        [17, 22, 16, 21, 400],
    );
    my $md = build_ohlc(\@c);
    my $vwap = Market::Indicators::AnchoredVWAP->new();
    feed_all($vwap, $md);
    $vwap->set_anchor(1);
    my $before = $vwap->get_point(2)->{value};
    $vwap->reset();
    is($vwap->anchor_index(), 1, 'reset preserva ancla');
    feed_all($vwap, $md);
    ok(defined $vwap->get_point(2), 'tras re-feed hay puntos');
    ok(abs($vwap->get_point(2)->{value} - $before) < 1e-9, 'mismo VWAP tras reset+feed');
}

# ---------------------------------------------------------------------------
# Overlay: dibuja desde ancla; sin ancla no dibuja
# ---------------------------------------------------------------------------
{
    package VWTestCanvas;
    sub new { bless { ops => [] }, shift }
    sub delete { my ($s) = @_; $s->{ops} = []; return }
    sub createLine {
        my ($s, @a) = @_;
        push @{ $s->{ops} }, [ createLine => @a ];
        return 1;
    }
    sub createPolygon {
        my ($s, @a) = @_;
        push @{ $s->{ops} }, [ createPolygon => @a ];
        return 1;
    }
}

sub _ops_with_fill {
    my ($ops, $color) = @_;
    my $n = 0;
    for my $op (@$ops) {
        for my $i (0 .. $#$op - 1) {
            $n++ if $op->[$i] eq '-fill' && $op->[$i + 1] eq $color;
        }
    }
    return $n;
}

sub _line_widths {
    my ($ops) = @_;
    my @w;
    for my $op (@$ops) {
        next unless $op->[0] eq 'createLine';
        for my $i (0 .. $#$op - 1) {
            push @w, $op->[$i + 1] if $op->[$i] eq '-width';
        }
    }
    return @w;
}

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
    feed_all($vwap_ind, $md);

    my $ov = Market::Overlays::AnchoredVWAP->new(indicator => $vwap_ind, visible => 1);
    my $canvas = VWTestCanvas->new();
    my $scales = Market::Panels::Scales->new(min_y => 9, max_y => 25, bars => 4, right_margin => 0);
    $scales->{width}  = 400;
    $scales->{height} = 300;

    $ov->compute_visible($md, $vwap_ind, 0, 3);
    $ov->draw($canvas, $scales);
    is(scalar(@{ $canvas->{ops} }), 0, 'sin ancla: overlay no dibuja');

    $vwap_ind->set_anchor(1);
    $canvas->{ops} = [];
    $ov->draw($canvas, $scales);

    # 1 fill + 1 upper + 1 lower + 1 vwap (polilíneas únicas)
    my $lines = grep { $_->[0] eq 'createLine' } @{ $canvas->{ops} };
    my $polys = grep { $_->[0] eq 'createPolygon' } @{ $canvas->{ops} };
    is($lines, 3, '3 polilíneas: upper1, lower1, vwap central');
    is($polys, 1, '1 polígono de relleno entre bandas');

    is(_ops_with_fill($canvas->{ops}, '#2962FF'), 1, 'línea central azul');
    is(_ops_with_fill($canvas->{ops}, '#26A69A'), 2, '2 bandas verdes (líneas)');
    is(_ops_with_fill($canvas->{ops}, '#B2DFDB'), 1, 'fill verde claro semitransparente');

    my @widths = _line_widths($canvas->{ops});
    ok(@widths == 3, '3 anchos de línea registrados');
    ok((grep { $_ == 1 } @widths) == 3, 'todas las líneas grosor 1 (uniforme, fino)');

    # Polilínea central: coords x,y para 3 puntos (idx 1,2,3) => 6 números antes de opciones
    my ($vwap_line) = grep {
        $_->[0] eq 'createLine' && grep { $_ eq '#2962FF' } @$_
    } @{ $canvas->{ops} };
    ok($vwap_line, 'encontrada polilínea VWAP');
    # createLine x1 y1 x2 y2 x3 y3 -fill ... → al menos 6 coords
    my $coord_count = 0;
    for my $i (1 .. $#$vwap_line) {
        last if !ref($vwap_line->[$i]) && $vwap_line->[$i] =~ /^-/;
        $coord_count++ if $vwap_line->[$i] =~ /^-?\d/;
    }
    # Perl numbers may not match /^\d/ only - count until first option key
    $coord_count = 0;
    for my $i (1 .. $#$vwap_line) {
        last if defined $vwap_line->[$i] && !ref($vwap_line->[$i]) && $vwap_line->[$i] =~ /^-?[a-z]/;
        $coord_count++;
    }
    is($coord_count, 6, 'VWAP es una sola polilínea de 3 puntos (mismos vértices, no N segmentos)');

    $ov->set_element_visible('VWAP_LINE', 0);
    $canvas->{ops} = [];
    $ov->draw($canvas, $scales);
    is(_ops_with_fill($canvas->{ops}, '#2962FF'), 0, 'VWAP_LINE off: sin azul');
}

# ---------------------------------------------------------------------------
# Callbacks de UI: make_vwap_toggle
# ---------------------------------------------------------------------------
{
    package FakeChartVwap;
    sub new {
        my ($c) = @_;
        bless {
            overlay_manager => Market::OverlayManager->new(),
            vwap_indicator  => Market::Indicators::AnchoredVWAP->new(),
            vwap_overlay    => undef,
            began => 0, ended => 0, renders => 0,
        }, $c;
    }
    sub begin_vwap_placement { $_[0]{began}++; return $_[0] }
    sub end_vwap_overlay     { $_[0]{ended}++; return $_[0] }
    sub request_render       { $_[0]{renders}++; return $_[0] }
}
{
    package main;
    use Market::OverlayManager;
    my $chart = FakeChartVwap->new();
    my $cb = Market::UI::Callbacks->make_vwap_toggle($chart);
    $cb->(1);
    is($chart->{began}, 1, 'toggle ON → begin_vwap_placement');
    $cb->(0);
    is($chart->{ended}, 1, 'toggle OFF → end_vwap_overlay');
}

# ---------------------------------------------------------------------------
# Band setter (menú TV #1/#2/#3)
# ---------------------------------------------------------------------------
{
    package FakeChartVwapBands;
    sub new {
        my ($c) = @_;
        my $ind = Market::Indicators::AnchoredVWAP->new();
        my $ov  = Market::Overlays::AnchoredVWAP->new(indicator => $ind, visible => 1);
        bless {
            vwap_indicator => $ind,
            vwap_overlay   => $ov,
            renders        => 0,
        }, $c;
    }
    sub request_render { $_[0]{renders}++; return $_[0] }
}
{
    package main;
    my $chart = FakeChartVwapBands->new();
    my $ind = $chart->{vwap_indicator};
    # feed + anchor para que set_band recalcule
    my $md = build_ohlc([
        [10, 12, 8, 10, 100],
        [10, 14, 10, 12, 100],
        [12, 16, 12, 14, 100],
    ]);
    feed_all($ind, $md);
    $ind->set_anchor(0);

    my $set = Market::UI::Callbacks->make_vwap_band_setter($chart);
    ok(defined $ind->get_point(2)->{upper1}, 'default: banda 1 activa');
    ok(!defined $ind->get_point(2)->{upper2}, 'default: banda 2 off');

    $set->(2, on => 1, mult => 2);
    ok(defined $ind->get_point(2)->{upper2}, 'activar #2 crea upper2');
    ok($chart->{vwap_overlay}->is_element_visible('BAND_2'), 'overlay BAND_2 visible');

    $set->(1, on => 0);
    ok(!defined $ind->get_point(2)->{upper1}, 'apagar #1 quita upper1');
    ok(!$chart->{vwap_overlay}->is_element_visible('BAND_FILL'), 'fill off con banda 1 off');

    $set->(3, on => 1, mult => 3);
    my $pt = $ind->get_point(2);
    ok(defined $pt->{upper3}, 'banda #3 on');
    # upper3 = vwap + 3*stdev; upper2 was 2*stdev when on — check mult 3 vs value
    ok($pt->{upper3} > $pt->{value}, 'upper3 por encima del vwap');
    ok($chart->{renders} >= 3, 'cada set_band pide render');
}

# ---------------------------------------------------------------------------
# Re-anclar: guardar ancla, Esc restaura; feedback mode
# ---------------------------------------------------------------------------
{
    package FakeChartVwapReanchor;
    sub new {
        my ($c, %a) = @_;
        bless {
            market_data      => $a{md},
            vwap_indicator   => $a{ind},
            overlay_manager  => Market::OverlayManager->new(),
            vwap_overlay     => undef,
            _vwap_select_mode => 0,
            _vwap_anchor_before_select => undef,
            renders => 0,
            cancels => 0,
        }, $c;
    }
    # Minimal stubs used by ChartEngine methods we call via package injection...
}
# Probar API real de ChartEngine sin GUI: instanciar mínimo es pesado.
# Validamos cancel/restore y esc precedence con métodos del motor real vía
# un mock delgado que reutiliza las subs del package (no).
# En su lugar: probar el indicador + flujo de cancel vía ChartEngine methods
# con un objeto bendecido al package Market::ChartEngine parcialmente.
{
    package main;
    use Market::OverlayManager;
    use Market::ChartEngine;

    my $md = build_ohlc([
        [10, 12, 8, 10, 100],
        [10, 14, 10, 12, 100],
        [12, 16, 12, 14, 100],
        [14, 18, 14, 16, 100],
    ]);
    my $ind = Market::Indicators::AnchoredVWAP->new();
    feed_all($ind, $md);
    $ind->set_anchor(1);
    is($ind->anchor_index(), 1, 'ancla inicial 1');

    # Simular reanchor: guardar prev, clear, select mode
    my $prev = $ind->anchor_index();
    $ind->clear_anchor();
    ok(!$ind->has_anchor(), 're-anclar limpia ancla temporalmente');

    # Cancel (Esc): restaurar
    $ind->set_anchor($prev);
    is($ind->anchor_index(), 1, 'Esc restaura ancla previa');

    # ChartEngine::cancel_vwap_select_mode con stub mínimo
    my $eng = bless {
        market_data => $md,
        vwap_indicator => $ind,
        overlay_manager => Market::OverlayManager->new(),
        _vwap_select_mode => 1,
        _vwap_anchor_before_select => 2,
        price_canvas => undef,
        vwap_select_cancel_callback => sub { },
    }, 'Market::ChartEngine';
    # feed hasta 3 para set_anchor(2)
    $ind->clear_anchor();
    feed_all($ind, $md);
    $eng->{_vwap_select_mode} = 1;
    $eng->{_vwap_anchor_before_select} = 2;
    $eng->cancel_vwap_select_mode();
    ok(!$eng->is_vwap_select_mode(), 'cancel sale de select mode');
    is($ind->anchor_index(), 2, 'cancel restaura ancla guardada (2)');

    # Escape precedence: si vwap select, no necesita replay
    $eng->{_vwap_select_mode} = 1;
    $eng->{_vwap_anchor_before_select} = 1;
    $ind->clear_anchor();
    feed_all($ind, $md);
    $eng->_replay_escape_key();
    ok(!$eng->is_vwap_select_mode(), 'Escape cancela modo VWAP');
    is($ind->anchor_index(), 1, 'Escape restaura ancla 1');
}

done_testing();
