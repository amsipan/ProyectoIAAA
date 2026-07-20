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

done_testing();
