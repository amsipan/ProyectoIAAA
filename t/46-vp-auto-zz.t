#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib '.';

use Market::MarketData;
use Market::ChartEngine;
use Market::Indicators::VolumeProfile2;
use Market::Overlays::VolumeProfile;
use Market::Drawing::FibRetracement;
use Market::ReplayController;

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
{
    package VpAutoCanvas;
    sub new { bless { ops => [] }, shift }
    sub after { return }
    sub delete { return }
    sub configure { return }
    sub createLine { return 1 }
    sub createText { return 1 }
    sub createRectangle { return 1 }
    sub createOval { return 1 }
    sub Width  { 800 }
    sub Height { 400 }
    sub width  { 800 }
    sub height { 400 }
    sub geometry { '800x400' }
}

{
    package VpAutoZigZag;
    # ZZ stub: a feed_to>=40 revela pierna1 consolidada (from=10);
    # a feed_to>=70 revela pierna2 consolidada (from=40) + tramo vivo.
    sub new { bless { last_i => -1, compute_external => 0 }, shift }
    sub reset {
        my ($s) = @_;
        $s->{last_i} = -1;
        return $s;
    }
    sub set_compute_external {
        my ( $s, $v ) = @_;
        $s->{compute_external} = $v ? 1 : 0;
        return $s;
    }
    sub update_last {
        my ( $s, $md, $i ) = @_;
        $s->{last_i} = $i if defined $i && $i > ( $s->{last_i} // -1 );
        return $s;
    }
    sub get_values {
        my ($s) = @_;
        my @segs;
        if ( ( $s->{last_i} // -1 ) >= 40 ) {
            push @segs, {
                from_index => 10, to_index => 40,
                from_price => 100, to_price => 130,
                dir => 'up', consolidated => 1,
            };
        }
        if ( ( $s->{last_i} // -1 ) >= 70 ) {
            push @segs, {
                from_index => 40, to_index => 70,
                from_price => 130, to_price => 110,
                dir => 'down', consolidated => 1,
            };
            push @segs, {
                from_index => 70, to_index => $s->{last_i},
                from_price => 110, to_price => 120,
                dir => 'up', consolidated => 0,    # tramo vivo: ignorar
            };
        }
        return { external_segments => \@segs };
    }
}

sub build_md {
    my ($n) = @_;
    $n ||= 90;
    my $md = Market::MarketData->new();
    $md->set_base_timeframe('1m');
    for my $i ( 0 .. $n - 1 ) {
        my $c = 100 + ( $i % 20 );
        my $h = $c + 2;
        my $l = $c - 2;
        my $ts = sprintf( '2026-07-01T%02d:%02d:00-05:00',
            int( $i / 60 ) % 24, $i % 60 );
        $md->add_candle( [ $ts, $c, $h, $l, $c, 50 + $i ] );
    }
    return $md;
}

sub make_chart {
    my ($md) = @_;
    my $vp = Market::Indicators::VolumeProfile2->new( row_size => 50 );
    my $ov = Market::Overlays::VolumeProfile->new(
        indicator => $vp,
        visible   => 0,
    );
    my $zz = VpAutoZigZag->new();
    my $rc = Market::ReplayController->new( market_data => $md );
    my $chart = bless {
        market_data       => $md,
        replay_controller => $rc,
        price_canvas      => VpAutoCanvas->new(),
        vp_indicator      => $vp,
        vp_overlay        => $ov,
        zigzag_indicator  => $zz,
        vp_mode           => 'off',
        _vp_fed_up_to     => -1,
        _zigzag_fed_up_to => -1,
        render_pending    => 0,
        _vp_select_mode   => 0,
    }, 'Market::ChartEngine';

    # Evitar Tk/render completo en unit test
    no warnings 'redefine';
    *Market::ChartEngine::request_render = sub {
        my ($self) = @_;
        $self->{render_pending} = 0;
        return $self;
    };
    *Market::ChartEngine::_clear_vp_select_hover  = sub { };
    *Market::ChartEngine::_clear_vp_select_banner = sub { };
    *Market::ChartEngine::_clear_chart_crosshair  = sub { };
    *Market::ChartEngine::_apply_select_mode_cursor = sub { };

    return $chart;
}

# ---------------------------------------------------------------------------
# 1. Overlay: show_handle apagable (modo Auto)
# ---------------------------------------------------------------------------
{
    my $ind = Market::Indicators::VolumeProfile2->new();
    my $ov  = Market::Overlays::VolumeProfile->new(
        indicator   => $ind,
        show_handle => 0,
        visible     => 1,
    );
    ok( !$ov->{show_handle}, 'Auto: overlay sin handle de drag' );
}

# ---------------------------------------------------------------------------
# 2. Helper ZZ: última pierna consolidada (ignora viva)
# ---------------------------------------------------------------------------
{
    my @segs = (
        {
            from_index => 10, to_index => 40,
            from_price => 100, to_price => 130,
            dir => 'up', consolidated => 1,
        },
        {
            from_index => 40, to_index => 70,
            from_price => 130, to_price => 110,
            dir => 'down', consolidated => 1,
        },
        {
            from_index => 70, to_index => 85,
            from_price => 110, to_price => 120,
            dir => 'up', consolidated => 0,
        },
    );
    my $leg = Market::Drawing::FibRetracement->last_consolidated_zz_segment( \@segs );
    ok( $leg, 'hay pierna consolidada' );
    is( $leg->{from_index}, 40, 'ancla = from_index del último swing consolidado' );
    isnt( $leg->{consolidated}, 0, 'elegida consolidada, no viva' );
}

# Activa modo Auto sin sincronizar al final del dataset (Replay controla head).
sub enable_vp_auto {
    my ($chart) = @_;
    $chart->{vp_mode} = 'auto';
    $chart->set_vp_select_mode(0);
    $chart->{_vp_drag_active} = undef;
    if ( $chart->{vp_overlay} ) {
        $chart->{vp_overlay}->set_visible(1);
        $chart->{vp_overlay}{show_handle} = 0;
    }
    return $chart;
}

# ---------------------------------------------------------------------------
# 3. Sync Auto: sin pierna consolidada → sin ancla inventada
# ---------------------------------------------------------------------------
{
    my $md    = build_md(30);
    my $chart = make_chart($md);
    enable_vp_auto($chart);
    # feed corto: stub ZZ aún no tiene piernas
    $chart->_sync_vp_auto_anchor(20);
    ok( !$chart->{vp_indicator}->has_anchor(),
        'sin impulso ZZ consolidado: no inventa ancla' );
}

# ---------------------------------------------------------------------------
# 4. Sync Auto: ancla al from_index de la 1ª pierna consolidada
# ---------------------------------------------------------------------------
{
    my $md    = build_md(90);
    my $chart = make_chart($md);
    enable_vp_auto($chart);
    $chart->{replay_controller}->start(50);
    $chart->_sync_vp_auto_anchor( $chart->_causal_end() );
    ok( $chart->{vp_indicator}->has_anchor(), 'con pierna consolidada hay ancla' );
    is( $chart->{vp_indicator}->anchor_index(), 10,
        'anchor_idx = from_index del swing consolidado (10)' );

    my $prof = $chart->{vp_indicator}->get_values();
    ok( $prof && defined $prof->{poc}, 'perfil produce POC' );
    ok( defined $prof->{vah} && defined $prof->{val}, 'perfil produce VAH/VAL' );
}

# ---------------------------------------------------------------------------
# 5. Al consolidarse nuevo impulso, el ancla salta al nuevo start
# ---------------------------------------------------------------------------
{
    my $md    = build_md(90);
    my $chart = make_chart($md);
    enable_vp_auto($chart);
    $chart->{replay_controller}->start(50);
    $chart->_sync_vp_auto_anchor(50);
    is( $chart->{vp_indicator}->anchor_index(), 10, 'antes: ancla en 10' );

    # Avance causal: nace segunda pierna consolidada
    $chart->{replay_controller}->start(80);
    $chart->_sync_vp_auto_anchor(80);
    is( $chart->{vp_indicator}->anchor_index(), 40,
        'tras nuevo impulso consolidado: ancla salta a 40' );
}

# ---------------------------------------------------------------------------
# 6. Manual no se pisa por sync Auto; confirm_vp_anchor bloqueado en Auto
# ---------------------------------------------------------------------------
{
    my $md    = build_md(90);
    my $chart = make_chart($md);
    $chart->set_vp_mode('manual');
    $chart->confirm_vp_anchor(5);
    is( $chart->{vp_indicator}->anchor_index(), 5, 'Manual: clic fija ancla 5' );

    enable_vp_auto($chart);
    $chart->{replay_controller}->start(50);
    $chart->_sync_vp_auto_anchor(50);
    is( $chart->{vp_indicator}->anchor_index(), 10, 'Auto re-ancla a ZZ' );

    $chart->confirm_vp_anchor(99);
    is( $chart->{vp_indicator}->anchor_index(), 10,
        'en Auto el clic manual no pisa el ancla ZZ' );
}

# ---------------------------------------------------------------------------
# 7. set_vp_mode(off) limpia ancla
# ---------------------------------------------------------------------------
{
    my $md    = build_md(90);
    my $chart = make_chart($md);
    enable_vp_auto($chart);
    $chart->_sync_vp_auto_anchor(50);
    ok( $chart->{vp_indicator}->has_anchor(), 'auto tenía ancla' );
    $chart->set_vp_mode('off');
    ok( !$chart->{vp_indicator}->has_anchor(), 'Off limpia ancla' );
    is( $chart->{vp_mode}, 'off', 'modo Off' );
}

done_testing();
