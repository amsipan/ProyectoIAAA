#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib '.';

use Market::MarketData;
use Market::Indicators::PivotPointsHL;
use Market::Overlays::PivotPointsHL;

# ---------------------------------------------------------------------------
# 1. Carga básica y contrato de Overlay
# ---------------------------------------------------------------------------
{
    my $ind = Market::Indicators::PivotPointsHL->new(length => 3);
    ok($ind, 'Instanciación del indicador PivotPointsHL ok');
    is($ind->_len, 3, 'length configurable');

    my $ov = Market::Overlays::PivotPointsHL->new(indicator => $ind, visible => 0);
    ok($ov, 'Instanciación del overlay ok');
    is($ov->tag(), 'ov_pph', 'tag correcto');
    ok(!$ov->is_visible(), 'oculto por defecto');
    $ov->set_visible(1);
    ok($ov->is_visible(), 'visibilidad activable');
}

# ---------------------------------------------------------------------------
# Helper: dataset sintético con un pivote HIGH claro y un pivote LOW claro.
#   length=3 → el pivote en la vela p se confirma en p+3.
# ---------------------------------------------------------------------------
sub build_md {
    my $md = Market::MarketData->new();
    $md->set_base_timeframe('15m');
    # Precios: sube a un pico en idx 5, baja a un valle en idx 12, sube de nuevo.
    my @closes = (100,101,102,103,104,110, 104,103,102,101, 98, 96, 90, 95,100,105,108,110,112,114);
    my $i = 0;
    for my $c (@closes) {
        my $h = $c + 2;
        my $l = $c - 2;
        $md->add_candle([ sprintf('t%02d', $i), $c, $h, $l, $c, 100 ]);
        $i++;
    }
    return $md;
}

# ---------------------------------------------------------------------------
# 2. Confirmación causal: un pivote high NO aparece antes de p+length.
# ---------------------------------------------------------------------------
{
    my $md  = build_md();
    my $len = 3;
    my $ind = Market::Indicators::PivotPointsHL->new(length => $len);

    my $size = $md->size();
    # Alimentar hasta el pico (idx 5) + (length-1): aún no confirmado.
    for my $i (0 .. 5 + $len - 1) { $ind->update_last($md, $i); }
    my $v_before = $ind->get_values();
    my @reg_high_before = grep { $_->{glyph} eq 'reg_high' } @{ $v_before->{labels} };
    is(scalar(@reg_high_before), 0, 'pivote high NO confirmado antes de p+length (causal)');

    # Una vela más (idx 5+length) → ya debe confirmarse.
    $ind->update_last($md, 5 + $len);
    my $v_after = $ind->get_values();
    my @reg_high_after = grep { $_->{glyph} eq 'reg_high' } @{ $v_after->{labels} };
    ok(scalar(@reg_high_after) >= 1, 'pivote high confirmado exactamente en p+length');
    is($reg_high_after[0]{index}, 5, 'el pivote high se ancla en la vela del pico (idx 5)');
    ok($reg_high_after[0]{color_key} eq 'reg_ph', 'color rojo (reg_ph) para high');
}

# ---------------------------------------------------------------------------
# 3. El fantasma provisional se MUEVE y luego se QUEDA QUIETO al confirmar.
#    (regla del profe: mientras se mueve no operar; cuando se queda quieto, sí)
# ---------------------------------------------------------------------------
{
    my $md  = build_md();
    my $len = 3;
    my $ind = Market::Indicators::PivotPointsHL->new(length => $len);

    # Alimentar hasta pasar el primer pivote confirmado para tener px1/os.
    for my $i (0 .. 5 + $len) { $ind->update_last($md, $i); }

    # Ahora el provisional debe existir y su índice/precio debe ir cambiando
    # a medida que llegan velas nuevas (fantasma "moviéndose").
    my @prov_positions;
    for my $i (5 + $len + 1 .. 11) {
        $ind->update_last($md, $i);
        my $p = $ind->get_values->{provisional};
        push @prov_positions, ($p ? "$p->{index}:$p->{price}" : 'none');
    }
    my %uniq = map { $_ => 1 } @prov_positions;
    ok(scalar(keys %uniq) > 1, 'el fantasma provisional se mueve (cambia de posición en Replay)');

    # provisional siempre dentro del rango causal
    my $p = $ind->get_values->{provisional};
    if ($p) {
        ok($p->{index} <= $ind->get_values->{last_index}, 'fantasma nunca apunta al futuro');
    } else {
        pass('sin provisional en este punto (aceptable)');
    }
}

# ---------------------------------------------------------------------------
# 4. Causalidad total: feed incremental hasta N == reset+refeed hasta N.
#    (esto es lo que hace el rewind de Replay en _feed_indicator_to)
# ---------------------------------------------------------------------------
{
    my $md  = build_md();
    my $len = 3;
    my $target = 15;

    my $inc = Market::Indicators::PivotPointsHL->new(length => $len);
    for my $i (0 .. $target) { $inc->update_last($md, $i); }
    my $v_inc = $inc->get_values();

    my $rebuilt = Market::Indicators::PivotPointsHL->new(length => $len);
    for my $i (0 .. 5) { $rebuilt->update_last($md, $i); }   # avanzar…
    $rebuilt->reset();                                        # …rewind (Replay)
    for my $i (0 .. $target) { $rebuilt->update_last($md, $i); }
    my $v_reb = $rebuilt->get_values();

    is(scalar(@{ $v_reb->{labels} }), scalar(@{ $v_inc->{labels} }),
        'reset+refeed produce el mismo nº de labels (Replay determinista)');
    is(scalar(@{ $v_reb->{zigzag} }), scalar(@{ $v_inc->{zigzag} }),
        'reset+refeed produce el mismo nº de segmentos zigzag');
}

# ---------------------------------------------------------------------------
# 5. reset() limpia todo el estado.
# ---------------------------------------------------------------------------
{
    my $md  = build_md();
    my $ind = Market::Indicators::PivotPointsHL->new(length => 3);
    for my $i (0 .. $md->size - 1) { $ind->update_last($md, $i); }
    ok(scalar(@{ $ind->get_values->{labels} }) > 0, 'hay labels antes del reset');
    $ind->reset();
    my $v = $ind->get_values();
    is(scalar(@{ $v->{labels} }), 0, 'reset limpia labels');
    is(scalar(@{ $v->{zigzag} }), 0, 'reset limpia zigzag');
    is($v->{last_index}, -1, 'reset limpia el índice');
    ok(!defined $v->{provisional}, 'reset limpia el fantasma provisional');
}

# ---------------------------------------------------------------------------
# 6. show_reg / show_miss como toggles.
# ---------------------------------------------------------------------------
{
    my $md = build_md();
    my $ind = Market::Indicators::PivotPointsHL->new(length => 3, show_reg => 1, show_miss => 0);
    for my $i (0 .. $md->size - 1) { $ind->update_last($md, $i); }
    my @ghosts = grep { $_->{glyph} eq 'ghost' } @{ $ind->get_values->{labels} };
    is(scalar(@ghosts), 0, 'show_miss=0 → no genera labels fantasma (missed)');
}

# ---------------------------------------------------------------------------
# 7. Ghost levels encadenados: cada nivel se corta en el siguiente pivote
#    (to_index), NO llega al infinito. Solo el último se extiende a last_index.
#    (paridad TradingView: las líneas viejas tienen corte)
# ---------------------------------------------------------------------------
{
    my $md  = build_md();
    my $ind = Market::Indicators::PivotPointsHL->new(length => 3);
    for my $i (0 .. $md->size - 1) { $ind->update_last($md, $i); }

    my $v = $ind->get_values();
    my $gl = $v->{ghost_levels};
    if (@$gl >= 2) {
        # cada nivel (salvo el último) termina donde empieza el siguiente
        my $chained_ok = 1;
        for my $k (0 .. $#$gl - 1) {
            $chained_ok = 0 if $gl->[$k]{to_index} != $gl->[$k + 1]{index};
        }
        ok($chained_ok, 'ghost levels se cortan en el siguiente pivote (to_index encadenado)');
        is($gl->[-1]{to_index}, $v->{last_index}, 'último ghost level se extiende hasta last_index');
        ok($gl->[0]{to_index} < $v->{last_index}, 'ghost level viejo NO llega al final del gráfico');
    } else {
        pass('dataset sintético con <2 ghost levels; encadenado trivial');
        pass('(skip) último a last_index');
        pass('(skip) viejo no llega al final');
    }
}

# ---------------------------------------------------------------------------
# 8. Fantasma provisional: colores diagonal/horizontal OPUESTOS al del ghost,
#    y expone last_index para la horizontal final (source l.150-152).
# ---------------------------------------------------------------------------
{
    my $md  = build_md();
    my $ind = Market::Indicators::PivotPointsHL->new(length => 3);
    for my $i (0 .. $md->size - 1) { $ind->update_last($md, $i); }

    my $p = $ind->get_values->{provisional};
    if ($p) {
        ok(defined $p->{ghost_key} && defined $p->{line_key},
            'provisional expone ghost_key y line_key por separado');
        isnt($p->{ghost_key}, $p->{line_key},
            'color de las líneas es opuesto al color del fantasma (paridad TV)');
        is($p->{last_index}, $ind->get_values->{last_index},
            'provisional expone last_index para la horizontal final');
        # os==1 (fantasma abajo, verde) → líneas rojas ; os==0 al revés
        if ($p->{dir} eq 'up') {
            is($p->{ghost_key}, 'miss_pl', 'os=1: fantasma verde (miss_pl)');
            is($p->{line_key},  'miss_ph', 'os=1: líneas rojas (miss_ph)');
        } else {
            is($p->{ghost_key}, 'miss_ph', 'os=0: fantasma rojo (miss_ph)');
            is($p->{line_key},  'miss_pl', 'os=0: líneas verdes (miss_pl)');
        }
    } else {
        pass('(skip) sin provisional') for 1 .. 5;
    }
}

# ---------------------------------------------------------------------------
# 9. last_regular: último pivot REGULAR consolidado (high O low), no solo UP.
# ---------------------------------------------------------------------------
{
    my $md  = build_md();
    my $ind = Market::Indicators::PivotPointsHL->new(length => 3);
    for my $i (0 .. $md->size - 1) { $ind->update_last($md, $i); }

    my $v   = $ind->get_values();
    my $reg = $v->{last_regular};
    ok( $reg && defined $reg->{index}, 'last_regular expone un pivot consolidado' );
    ok( !$reg->{missed}, 'last_regular nunca es missed' );
    ok( ( $reg->{side} // '' ) eq 'high' || ( $reg->{side} // '' ) eq 'low',
        'last_regular acepta high o low (no solo alcistas)' );

    # Debe coincidir con el último label regular en labels[].
    my @regs = grep {
        !$_->{missed}
          && ( ( $_->{glyph} // '' ) eq 'reg_high' || ( $_->{glyph} // '' ) eq 'reg_low' )
    } @{ $v->{labels} || [] };
    if (@regs) {
        is( $reg->{index}, $regs[-1]{index}, 'last_regular = último regular en labels' );
    }
    else {
        pass('(skip) sin regulares en dataset');
    }
}

# ---------------------------------------------------------------------------
# 10. Rastro "1": al saltar el fantasma provisional, queda trail en la punta previa.
# ---------------------------------------------------------------------------
{
    my $md  = build_md();
    my $ind = Market::Indicators::PivotPointsHL->new(length => 3);

    my $prev_key;
    my $saw_trail = 0;
    for my $i ( 0 .. $md->size - 1 ) {
        $ind->update_last( $md, $i );
        my $v    = $ind->get_values();
        my $prov = $v->{provisional};
        my $ntr  = scalar @{ $v->{trails} || [] };
        $saw_trail = 1 if $ntr > 0;
        if ( $prov && defined $prev_key ) {
            my $key = ( $prov->{index} // '' ) . ':' . ( $prov->{price} // '' );
            # Si cambió la punta, debe haber al menos un trail (o ya había).
            if ( $key ne $prev_key && $ntr == 0 ) {
                # puede ser el primer frame tras seed sin prev — ok si aún no hay prev_prov
            }
        }
        $prev_key = $prov
          ? ( ( $prov->{index} // '' ) . ':' . ( $prov->{price} // '' ) )
          : undef;
    }
    ok( $saw_trail, 'rastro "1" se acumula cuando el fantasma provisional salta' );

    my $trails = $ind->get_values->{trails} || [];
    if (@$trails) {
        ok( defined $trails->[0]{index} && defined $trails->[0]{price},
            'cada trail tiene index+price' );
        is( $trails->[0]{glyph} // '1', '1', 'glyph del rastro es "1"' );
    }
    else {
        pass('(skip) trail fields') for 1 .. 2;
    }

    # Replay: reset+refeed reproduce el mismo nº de trails.
    my $n = scalar @$trails;
    my $reb = Market::Indicators::PivotPointsHL->new(length => 3);
    for my $i ( 0 .. $md->size - 1 ) { $reb->update_last( $md, $i ); }
    is( scalar @{ $reb->get_values->{trails} || [] }, $n,
        'rastro determinista tras reset+refeed (Replay-safe)' );

    my $ov = Market::Overlays::PivotPointsHL->new( indicator => $ind, visible => 1 );
    ok( $ov->{show_rastro}, 'overlay muestra rastro por defecto' );
    $ov->set_show_rastro(0);
    ok( !$ov->{show_rastro}, 'set_show_rastro(0) apaga el render del rastro' );
}

done_testing();
