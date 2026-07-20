#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib '.';

use Market::MarketData;
use Market::Indicators::VolumeProfile;
use Market::Overlays::VolumeProfile;

# 1. Carga básica y contrato de Overlay
{
    my $ind = Market::Indicators::VolumeProfile->new(
        row_size       => 20,
        value_area_pct => 70,
    );
    ok( $ind, 'Instanciación de VolumeProfile indicador ok' );
    
    my $ov = Market::Overlays::VolumeProfile->new( indicator => $ind, visible => 0 );
    ok( $ov, 'Instanciación de VolumeProfile overlay ok' );
    is( $ov->tag(), 'ov_vp', 'Tag correcto para VolumeProfile overlay' );
    ok( !$ov->is_visible(), 'Oculto por defecto' );
    $ov->set_visible(1);
    ok( $ov->is_visible(), 'Activación de visibilidad ok' );
}

# 2. Test unitario de cálculo de Bins, POC, VAH y VAL
{
    my $md = Market::MarketData->new();
    $md->set_base_timeframe('15m');

    # Crear 10 velas de prueba con volumen y rangos variados
    # [time, open, high, low, close, volume]
    $md->add_candle( [ 't0', 100, 105, 95, 102, 1000 ] );
    $md->add_candle( [ 't1', 102, 110, 100, 108, 2000 ] );
    $md->add_candle( [ 't2', 108, 115, 105, 112, 5000 ] ); # Mayor concentrado cerca de 110
    $md->add_candle( [ 't3', 112, 114, 108, 109, 3000 ] );
    $md->add_candle( [ 't4', 109, 112, 106, 110, 2000 ] );

    my $ind = Market::Indicators::VolumeProfile->new(
        row_size       => 10,
        value_area_pct => 70,
        anchor_idx     => 0,
    );

    for my $i ( 0 .. 4 ) {
        $ind->update_last($md, $i);
    }

    my $prof = $ind->get_values();
    ok( $prof, 'Perfil de volumen generado correctamente' );
    is( scalar @{ $prof->{bins} }, 10, 'Generó exactamente 10 bins según row_size' );
    ok( defined $prof->{poc}, 'POC definido' );
    ok( defined $prof->{vah}, 'VAH definido' );
    ok( defined $prof->{val}, 'VAL definido' );
    ok( $prof->{vah} >= $prof->{poc}, 'VAH >= POC' );
    ok( $prof->{val} <= $prof->{poc}, 'VAL <= POC' );
    ok( $prof->{total_vol} > 0, 'Volumen total calculado positivo' );

    # Verificar que el bin POC contenga el volumen máximo
    my $poc_idx = $prof->{poc_idx};
    my $poc_vol = $prof->{bins}->[$poc_idx]->{vol};
    for my $b (@{ $prof->{bins} }) {
        ok( $b->{vol} <= $poc_vol, 'Bin POC es el bin con mayor volumen' );
    }
}

# 3. Test de cambio dinámico de Ancla (set_anchor)
{
    my $md = Market::MarketData->new();
    $md->set_base_timeframe('15m');
    for my $i ( 0 .. 10 ) {
        $md->add_candle( [ "t$i", 100 + $i, 105 + $i, 95 + $i, 102 + $i, 1000 * ($i + 1) ] );
    }

    my $ind = Market::Indicators::VolumeProfile->new(row_size => 10);
    $ind->compute($md);

    my $prof1 = $ind->get_values();
    is( $ind->anchor_index(), undef, 'Ancla inicial sin definir (esperando selección por clic)' );

    $ind->set_anchor(5);
    my $prof2 = $ind->get_values();
    is( $prof2->{anchor_idx}, 5, 'Ancla actualizada correctamente al índice 5' );
    ok( $prof2->{min_p} >= 95 + 5, 'Rango de precio recalculado desde la nueva ancla' );
}

done_testing();
