#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib '.';

use Market::Indicators::SMC_Pro;

# Defaults demo profe: ambos ámbitos ON (Neon era Int ON / Swing OFF).
{
    my $ind = Market::Indicators::SMC_Pro->new();
    ok( $ind->{show_internal_ob}, 'default show_internal_ob=1 (demo; Neon Int ON)' );
    ok( $ind->{show_swing_ob},    'default show_swing_ob=1 (demo; Neon Swing OFF)' );

    my $neon = Market::Indicators::SMC_Pro->new(
        show_internal_ob => 1,
        show_swing_ob    => 0,
    );
    ok( $neon->{show_internal_ob},  'args permiten default Neon: Int ON' );
    ok( !$neon->{show_swing_ob},    'args permiten default Neon: Swing OFF' );
}

# get_order_blocks respeta scope + flags (sin reinventar mitigación).
{
    my $ind = Market::Indicators::SMC_Pro->new(
        show_internal_ob => 1,
        show_swing_ob    => 1,
    );
    $ind->{_obs} = [
        {
            index  => 10, hi => 110, lo => 100, bias => 'bull',
            scope  => 'internal', active => 1, created_at => 12,
        },
        {
            index  => 20, hi => 120, lo => 115, bias => 'bear',
            scope  => 'swing', active => 1, created_at => 25,
        },
        {
            index  => 30, hi => 130, lo => 125, bias => 'bull',
            scope  => 'swing', active => 0, created_at => 35,
        },
    ];

    my $obs = $ind->get_order_blocks();
    my @int = grep { ( $_->{scope} // '' ) eq 'internal' } @$obs;
    my @sw  = grep { ( $_->{scope} // '' ) eq 'swing' } @$obs;
    is( scalar(@int), 1, 'incluye 1 OB internal activo' );
    is( scalar(@sw),  1, 'incluye 1 OB swing activo (mitigado excluido)' );
    is( $int[0]{index}, 10, 'internal scope correcto' );
    is( $sw[0]{index},  20, 'swing scope correcto' );

    $ind->{show_internal_ob} = 0;
    $obs = $ind->get_order_blocks();
    is( scalar( grep { ( $_->{scope} // '' ) eq 'internal' } @$obs ), 0,
        'show_internal_ob=0 oculta internos' );
    ok( scalar( grep { ( $_->{scope} // '' ) eq 'swing' } @$obs ) >= 1,
        'swing sigue visible' );

    $ind->{show_internal_ob} = 1;
    $ind->{show_swing_ob}    = 0;
    $obs = $ind->get_order_blocks();
    ok( scalar( grep { ( $_->{scope} // '' ) eq 'internal' } @$obs ) >= 1,
        'internal vuelve al reactivar flag' );
    is( scalar( grep { ( $_->{scope} // '' ) eq 'swing' } @$obs ), 0,
        'show_swing_ob=0 oculta swing' );

    # Anti-flicker OB: apagar flag no borra _obs (solo el getter).
    is( scalar( @{ $ind->{_obs} } ), 3, '_obs intacto tras hide OB (sin reset)' );
    $ind->{show_swing_ob} = 1;
    ok( scalar( grep { ( $_->{scope} // '' ) eq 'swing' && ( $_->{active} // 1 ) } @{ $ind->get_order_blocks() } ) >= 1,
        'reactivar OB swing sin recalcular' );
}

# Mitigación gradual: achica la caja; solo borra al consumirse por completo.
{
    my $ind = Market::Indicators::SMC_Pro->new();
    # Inyectamos series y llamamos _mitigate_order_blocks directo.
    $ind->{_h} = [];
    $ind->{_l} = [];
    $ind->{_obs} = [
        {
            index => 0, hi => 110, lo => 100, bias => 'bull',
            scope => 'swing', active => 1, created_at => 0,
        },
    ];

    # Vela 1: low=105 entra en la zona (100–110) → hi baja a 105; sigue vivo.
    $ind->{_h}[1] = 108;
    $ind->{_l}[1] = 105;
    $ind->_mitigate_order_blocks(1);
    my $obs = $ind->get_order_blocks();
    is( scalar(@$obs), 1, 'bull OB sobrevive mitigación parcial' );
    is( sprintf( '%.2f', $obs->[0]{hi} ), '105.00', 'bull: hi se reduce al low que lo come' );
    is( sprintf( '%.2f', $obs->[0]{lo} ), '100.00', 'bull: lo intacto tras parcial' );
    ok( $obs->[0]{mitig}, 'marca mitig=1 tras parcial' );
    is( $obs->[0]{last_mitig_index}, 1, 'last_mitig_index = vela del corte' );
    is( sprintf( '%.2f', $obs->[0]{orig_hi} ), '110.00',
        'orig_hi conserva el rango original (tramo grueso)' );
    is( sprintf( '%.2f', $obs->[0]{orig_lo} ), '100.00', 'orig_lo intacto' );

    # Vela 2: low=102 → hi=102
    $ind->{_h}[2] = 106;
    $ind->{_l}[2] = 102;
    $ind->_mitigate_order_blocks(2);
    $obs = $ind->get_order_blocks();
    is( sprintf( '%.2f', $obs->[0]{hi} ), '102.00', 'bull: sigue achicándose' );

    # Vela 3: low=99 <= lo → consumo total
    $ind->{_h}[3] = 103;
    $ind->{_l}[3] = 99;
    $ind->_mitigate_order_blocks(3);
    $obs = $ind->get_order_blocks();
    is( scalar(@$obs), 0, 'bull OB desaparece al consumirse del todo' );

    # Bear: high come desde abajo (lo↑); high>=hi elimina.
    $ind->{_obs} = [
        {
            index => 0, hi => 200, lo => 190, bias => 'bear',
            scope => 'internal', active => 1, created_at => 0,
        },
    ];
    $ind->{_h}[1] = 195;
    $ind->{_l}[1] = 192;
    $ind->_mitigate_order_blocks(1);
    $obs = $ind->get_order_blocks();
    is( scalar(@$obs), 1, 'bear OB sobrevive parcial' );
    is( sprintf( '%.2f', $obs->[0]{lo} ), '195.00', 'bear: lo sube al high que lo come' );
    is( sprintf( '%.2f', $obs->[0]{hi} ), '200.00', 'bear: hi intacto tras parcial' );

    $ind->{_h}[2] = 201;
    $ind->{_l}[2] = 198;
    $ind->_mitigate_order_blocks(2);
    $obs = $ind->get_order_blocks();
    is( scalar(@$obs), 0, 'bear OB desaparece al cruzar hi (consumo total)' );

    # No mitigar en created_at
    $ind->{_obs} = [
        {
            index => 5, hi => 50, lo => 40, bias => 'bull',
            scope => 'swing', active => 1, created_at => 5,
        },
    ];
    $ind->{_h}[5] = 55;
    $ind->{_l}[5] = 35;
    $ind->_mitigate_order_blocks(5);
    $obs = $ind->get_order_blocks();
    is( scalar(@$obs), 1, 'no mitiga en la vela de creación' );
    is( sprintf( '%.2f', $obs->[0]{hi} ), '50.00', 'hi intacto en created_at' );
}

# Feedback §5: get_events / get_eqhl respetan show_internal / show_swing / show_eqhl.
{
    my $ind = Market::Indicators::SMC_Pro->new();
    ok( $ind->{show_internal}, 'default show_internal=1' );
    ok( $ind->{show_swing},    'default show_swing=1' );
    ok( $ind->{show_eqhl},     'default show_eqhl=1' );

    $ind->{_events} = [
        {
            index => 10, type => 'BOS', dir => 'up', price => 100,
            start_index => 5, scope => 'internal',
        },
        {
            index => 20, type => 'CHoCH', dir => 'down', price => 90,
            start_index => 15, scope => 'swing',
        },
    ];
    $ind->{_eqhl} = [
        { index => 12, type => 'EQH', price => 105, prev_index => 8, prev_price => 104.5 },
        { index => 18, type => 'EQL', price => 88,  prev_index => 14, prev_price => 88.2 },
    ];

    my $ev = $ind->get_events();
    is( scalar(@$ev), 2, 'ambos scopes BOS visibles con defaults ON' );
    is( scalar( @{ $ind->get_eqhl() } ), 2, 'EQH/EQL visibles con show_eqhl=1' );

    $ind->{show_internal} = 0;
    $ev = $ind->get_events();
    is( scalar(@$ev), 1, 'show_internal=0 oculta BOS int' );
    is( $ev->[0]{scope}, 'swing', 'queda solo swing/externo' );

    $ind->{show_swing} = 0;
    $ev = $ind->get_events();
    is( scalar(@$ev), 0, 'ambos BOS OFF → sin eventos' );

    $ind->{show_internal} = 1;
    $ind->{show_swing}    = 1;
    $ind->{show_eqhl}     = 0;
    is( scalar( @{ $ind->get_eqhl() } ), 0, 'show_eqhl=0 oculta EQH/EQL' );
    is( scalar( @{ $ind->get_events() } ), 2, 'BOS no afectados por show_eqhl' );

    # Anti-flicker: apagar flag no borra el almacén interno (solo el getter).
    is( scalar( @{ $ind->{_events} } ), 2, '_events intacto tras hide (sin reset)' );
    is( scalar( @{ $ind->{_eqhl} } ),   2, '_eqhl intacto tras show_eqhl=0' );
    $ind->{show_eqhl} = 1;
    is( scalar( @{ $ind->get_eqhl() } ), 2, 'reactivar EQH/EQL sin recalcular' );
}

done_testing();
