#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib '.';

use Market::MarketData;
use Market::Indicators::PivotPointsHL;
use Market::Indicators::AnchoredVWAP;
use Market::Overlays::AnchoredVWAP;

# Dataset sintético (mismo patrón que t/42).
sub build_md {
    my $md = Market::MarketData->new();
    $md->set_base_timeframe('15m');
    my @closes = (100,101,102,103,104,110, 104,103,102,101, 98, 96, 90, 95,100,105,108,110,112,114);
    my $i = 0;
    for my $c (@closes) {
        my $h = $c + 2;
        my $l = $c - 2;
        $md->add_candle([ sprintf('t%02d', $i), $c, $h, $l, $c, 100 + $i * 10 ]);
        $i++;
    }
    return $md;
}

# ---------------------------------------------------------------------------
# 1. Overlay: tag configurable; handle TV blanco/azul; Auto también con handle
# ---------------------------------------------------------------------------
{
    my $ind = Market::Indicators::AnchoredVWAP->new();
    my $ov  = Market::Overlays::AnchoredVWAP->new(
        indicator   => $ind,
        tag         => 'ov_avwap_auto1',
        show_handle => 1,
        visible     => 0,
        color_vwap  => '#26A69A',
    );
    is( $ov->tag(), 'ov_avwap_auto1', 'tag configurable para Auto-1' );
    ok( $ov->{show_handle}, 'Auto muestra handle (estilo TV §8)' );
    is( $ov->{color_handle_fill}    // '', '#FFFFFF', 'handle fill blanco TV' );
    is( $ov->{color_handle_outline} // '', '#2962FF', 'handle outline azul TV' );
}

# ---------------------------------------------------------------------------
# 2. Auto-1 ancla en last_regular (high o low); Auto-2 en provisional.
# ---------------------------------------------------------------------------
{
    my $md  = build_md();
    my $pph = Market::Indicators::PivotPointsHL->new(length => 3);
    for my $i ( 0 .. $md->size - 1 ) { $pph->update_last( $md, $i ); }
    my $vals = $pph->get_values();

    my $reg  = $vals->{last_regular};
    my $prov = $vals->{provisional};
    ok( $reg && defined $reg->{index}, 'hay last_regular para Auto-1' );
    ok( $prov && defined $prov->{index}, 'hay provisional para Auto-2' );

    my $a1 = Market::Indicators::AnchoredVWAP->new();
    $a1->set_anchor( $reg->{index} );
    for my $i ( $reg->{index} .. $md->size - 1 ) { $a1->update_last( $md, $i ); }
    ok( $a1->has_anchor(), 'Auto-1 tiene ancla' );
    is( $a1->anchor_index(), $reg->{index}, 'Auto-1 anclado en pivot regular' );
    my $s1 = $a1->get_values();
    ok( $s1 && $s1->[ $reg->{index} ] && defined $s1->[ $reg->{index} ]{value},
        'Auto-1 produce VWAP desde el pivot' );

    my $a2 = Market::Indicators::AnchoredVWAP->new();
    $a2->set_anchor( $prov->{index} );
    for my $i ( $prov->{index} .. $md->size - 1 ) { $a2->update_last( $md, $i ); }
    is( $a2->anchor_index(), $prov->{index}, 'Auto-2 anclado en fantasma provisional' );

    # Re-anclar Auto-2 cuando salta el fantasma (simula sync).
    my $pph2 = Market::Indicators::PivotPointsHL->new(length => 3);
    my $prev_prov_idx;
    my $reanchors = 0;
    for my $i ( 0 .. $md->size - 1 ) {
        $pph2->update_last( $md, $i );
        my $p = $pph2->get_values->{provisional};
        next unless $p && defined $p->{index};
        if ( defined $prev_prov_idx && $prev_prov_idx != $p->{index} ) {
            $a2->set_anchor( $p->{index} );
            $reanchors++;
        }
        $prev_prov_idx = $p->{index};
    }
    ok( $reanchors >= 1, 'Auto-2 se re-ancla cuando el fantasma salta (x_last)' );
}

# ---------------------------------------------------------------------------
# 3. Límite de producto: 2 autos + 1 manual = hasta 3 (sin tope duro de 2 totales).
# ---------------------------------------------------------------------------
{
    my $manual = Market::Indicators::AnchoredVWAP->new();
    my $auto1  = Market::Indicators::AnchoredVWAP->new();
    my $auto2  = Market::Indicators::AnchoredVWAP->new();
    $manual->set_anchor(0);
    $auto1->set_anchor(1);
    $auto2->set_anchor(2);
    my $n = 0;
    $n++ if $manual->has_anchor();
    $n++ if $auto1->has_anchor();
    $n++ if $auto2->has_anchor();
    is( $n, 3, 'Manual+Auto puede mantener 3 anclas AVWAP simultáneas' );
}

# ---------------------------------------------------------------------------
# 4. Promoción Auto→Manual + sync UI; sync auto no-op tras promoción
# ---------------------------------------------------------------------------
{
    use Market::ChartEngine;
    use Market::ReplayController;

    package AvwapAutoCanvas;
    sub new { bless {}, shift }
    sub after { return }
    sub delete { return }
    sub configure { return }
    sub Width  { 800 }
    sub Height { 400 }
    sub width  { 800 }
    sub height { 400 }

    package main;

    my $md  = build_md();
    my $pph = Market::Indicators::PivotPointsHL->new( length => 3 );
    my $manual = Market::Indicators::AnchoredVWAP->new();
    my $a1     = Market::Indicators::AnchoredVWAP->new();
    my $a2     = Market::Indicators::AnchoredVWAP->new();
    my $ov_m = Market::Overlays::AnchoredVWAP->new(
        indicator => $manual, show_handle => 1, visible => 0
    );
    my $ov1 = Market::Overlays::AnchoredVWAP->new(
        indicator => $a1, tag => 'ov_avwap_auto1', show_handle => 1, visible => 0
    );
    my $ov2 = Market::Overlays::AnchoredVWAP->new(
        indicator => $a2, tag => 'ov_avwap_auto2', show_handle => 1, visible => 0
    );
    my $rc = Market::ReplayController->new( market_data => $md );
    my $chart = bless {
        market_data            => $md,
        replay_controller      => $rc,
        price_canvas           => AvwapAutoCanvas->new(),
        pph_indicator          => $pph,
        avwap_indicator        => $manual,
        avwap_overlay          => $ov_m,
        avwap_auto1_indicator  => $a1,
        avwap_auto1_overlay    => $ov1,
        avwap_auto2_indicator  => $a2,
        avwap_auto2_overlay    => $ov2,
        avwap_mode             => 'off',
        _avwap_fed_up_to       => -1,
        _avwap_auto1_fed_up_to => -1,
        _avwap_auto2_fed_up_to => -1,
        _pph_fed_up_to         => -1,
        render_pending         => 0,
        _vwap_select_mode      => 0,
    }, 'Market::ChartEngine';

    no warnings 'redefine';
    *Market::ChartEngine::request_render = sub {
        my ($self) = @_;
        $self->{render_pending} = 0;
        return $self;
    };
    *Market::ChartEngine::set_vwap_select_mode = sub {
        my ( $self, $on ) = @_;
        $self->{_vwap_select_mode} = $on ? 1 : 0;
        return $self;
    };
    *Market::ChartEngine::_feed_indicator_to = sub {
        my ( $self, $ind, $key, $to ) = @_;
        return $self unless $ind && defined $to;
        my $from = ( $self->{$key} // -1 ) + 1;
        $from = 0 if $from < 0;
        for my $i ( $from .. $to ) {
            $ind->update_last( $md, $i ) if $ind->can('update_last');
        }
        $self->{$key} = $to;
        return $self;
    };

    my $ui_mode;
    $chart->{avwap_mode_ui_sync} = sub { $ui_mode = $_[0] };

    $chart->set_avwap_mode('auto');
    is( $chart->{avwap_mode}, 'auto', 'set_avwap_mode auto' );
    ok( $ov1->{show_handle} && $ov2->{show_handle}, 'autos con show_handle ON' );

    $chart->_sync_avwap_auto_anchors( $md->size - 1 );
    ok( $a1->has_anchor() || $a2->has_anchor(), 'auto tenía alguna ancla' );
    my $from_idx = $a1->has_anchor() ? $a1->anchor_index() : $a2->anchor_index();

    $chart->_promote_avwap_auto_to_manual($from_idx);
    is( $chart->{avwap_mode}, 'manual', 'promoción: modo Manual' );
    is( $ui_mode, 'manual', 'avwap_mode_ui_sync notifica Manual' );
    is( $manual->anchor_index(), $from_idx, 'manual hereda ancla auto' );
    ok( !$a1->has_anchor() && !$a2->has_anchor(), 'autos limpios tras promoción' );

    my $frozen = $manual->anchor_index();
    $chart->_sync_avwap_auto_anchors( $md->size - 1 );
    is( $manual->anchor_index(), $frozen, 'sync auto no-op en modo manual' );
}

# ---------------------------------------------------------------------------
# 5. UI: market.pl registra avwap_mode_ui_sync
# ---------------------------------------------------------------------------
{
    open my $fh, '<', 'market.pl' or die "market.pl: $!";
    local $/;
    my $src = <$fh>;
    close $fh;
    like( $src, qr/avwap_mode_ui_sync/, 'market.pl registra avwap_mode_ui_sync' );
}

done_testing();
