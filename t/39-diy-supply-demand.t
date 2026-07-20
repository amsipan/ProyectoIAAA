#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib '.';

use Market::MarketData;
use Market::Indicators::DIY;
use Market::Overlays::DIY;

# 1. Carga básica y contrato de Overlay
{
    my $ind = Market::Indicators::DIY->new(
        swing_length  => 5,
        history_to_keep => 10,
        box_width     => 2.0,
    );
    ok( $ind, 'Instanciación de DIY indicador ok' );
    
    my $ov = Market::Overlays::DIY->new( indicator => $ind, visible => 0 );
    ok( $ov, 'Instanciación de DIY overlay ok' );
    is( $ov->tag(), 'ov_diy', 'Tag correcto para DIY overlay' );
    ok( !$ov->is_visible(), 'Oculto por defecto' );
    $ov->set_visible(1);
    ok( $ov->is_visible(), 'Activación de visibilidad ok' );
}

# 2. Test unitario de Supply Zone y mitigación por cierre
{
    my $md = Market::MarketData->new();
    $md->set_base_timeframe('15m');

    # Llenar datos planos
    for my $i ( 0 .. 9 ) {
        $md->add_candle( [ sprintf('t%02d', $i), 100, 102, 98, 100, 100 ] );
    }

    # Pivote alto (Swing High) en el índice 10
    # swing_length = 5. Vecindad j en [10-10, 10] (es decir [0, 10] y [11, 20])
    $md->add_candle( [ 't10', 100, 120, 99, 105, 100 ] ); # Swing High (120)

    # Llenar velas post-pivote. La vela 15 confirma el pivote de la vela 10 (10 + 5)
    for my $i ( 11 .. 14 ) {
        $md->add_candle( [ sprintf('t%02d', $i), 105, 108, 100, 104, 100 ] );
    }
    $md->add_candle( [ 't15', 104, 107, 101, 103, 100 ] ); # Aquí se confirma!

    # Inicializar indicador con swing_length = 5
    my $ind = Market::Indicators::DIY->new(
        swing_length    => 5,
        history_to_keep => 5,
        box_width       => 2.0,
        atr_length      => 10, # Corto para test sintético
    );

    # Alimentar velas
    for my $i ( 0 .. 15 ) {
        $ind->update_last($md, $i);
    }

    my $vals = $ind->get_values();
    my $active_supply = $vals->{active_supply};
    is( scalar @$active_supply, 1, 'Se creó exactamente una Supply Zone activa' );
    
    if (@$active_supply) {
        my $box = $active_supply->[0];
        is( $box->{left}, 10, 'El inicio de la caja (left) es la vela del pivote (10)' );
        is( $box->{right}, 15, 'El final de la caja (right) es la vela actual de confirmación (15)' );
        is( $box->{top}, 120, 'El techo de la caja (top) es el precio del Swing High (120)' );
        ok( $box->{bottom} < 120, 'El fondo de la caja (bottom) está por debajo del Swing High' );
        ok( $box->{poi} < 120 && $box->{poi} > $box->{bottom}, 'El POI se encuentra al centro' );
    }

    # Seguir alimentando velas sin romper
    for my $i ( 16 .. 20 ) {
        $md->add_candle( [ sprintf('t%02d', $i), 103, 105, 100, 103, 100 ] );
        $ind->update_last($md, $i);
    }
    
    $vals = $ind->get_values();
    is( scalar @{ $vals->{active_supply} }, 1, 'Sigue activa antes de la mitigación' );
    is( $vals->{active_supply}->[0]->{right}, 20, 'Se extiende automáticamente al índice actual' );

    # Romper la zona con un Close por encima de top (120) en el índice 21
    $md->add_candle( [ 'break', 103, 125, 100, 122, 100 ] ); # Close = 122 >= 120
    $ind->update_last($md, 21);

    $vals = $ind->get_values();
    is( scalar @{ $vals->{active_supply} }, 0, 'La zona activa fue eliminada' );
    my $broken_supply = $vals->{broken_supply};
    is( scalar @$broken_supply, 1, 'La zona rota se movió a broken_supply' );
    
    if (@$broken_supply) {
        my $box = $broken_supply->[0];
        is( $box->{broken}, 1, 'Marcada como broken' );
        is( $box->{break_idx}, 21, 'Ruptura en el índice 21' );
        is( $box->{right}, 21, 'El endpoint derecho se congeló en la ruptura (21)' );
    }
}

# 3. Test de no superposición (Overlapping)
{
    my $md = Market::MarketData->new();
    $md->set_base_timeframe('15m');

    # Llenar velas con dos pivotes altos idénticos seguidos
    for my $i ( 0 .. 9 ) {
        $md->add_candle( [ "f$i", 100, 102, 98, 100, 100 ] );
    }
    $md->add_candle( [ 'f10', 100, 120, 99, 105, 100 ] ); # Primer SH (120)
    for my $i ( 11 .. 19 ) {
        $md->add_candle( [ "f$i", 100, 102, 98, 100, 100 ] );
    }
    $md->add_candle( [ 'f20', 100, 120.1, 99, 105, 100 ] ); # Segundo SH (120.1) - muy cercano
    for my $i ( 21 .. 30 ) {
        $md->add_candle( [ "f$i", 100, 102, 98, 100, 100 ] );
    }

    my $ind = Market::Indicators::DIY->new(
        swing_length    => 5,
        history_to_keep => 5,
        box_width       => 2.0,
        atr_length      => 10,
    );
    for my $i ( 0 .. 30 ) {
        $ind->update_last($md, $i);
    }

    my $vals = $ind->get_values();
    is( scalar @{ $vals->{active_supply} }, 1, 'El segundo pivote fue ignorado por superposición (overlapping rule)' );
}

# 4. Test del Overlay y filtrado por Viewport (compute_visible)
{
    my $ind = Market::Indicators::DIY->new(swing_length => 2);
    my $ov = Market::Overlays::DIY->new(indicator => $ind, visible => 1);
    
    # Crear un active_supply ficticio directamente para probar compute_visible
    push @{ $ind->{_supply_queue} }, {
        left      => 5,
        right     => 15,
        top       => 100,
        bottom    => 90,
        poi       => 95,
        broken    => 0,
        break_idx => undef,
    };

    my $md = Market::MarketData->new();
    $md->set_base_timeframe('15m');
    
    # Rango visible: [0, 4] -> no solapa
    $ov->compute_visible($md, $ind, 0, 4);
    is( scalar @{ $ov->{_active_supply} }, 0, 'No detectado fuera del viewport' );

    # Rango visible: [10, 20] -> solapa
    $ov->compute_visible($md, $ind, 10, 20);
    is( scalar @{ $ov->{_active_supply} }, 1, 'Detectado dentro del viewport' );
}

done_testing();
