use strict;
use warnings;
use Test::More;

use lib '.';
use Market::ChartEngine;
use Market::ReplayController;
use Market::OverlayManager;

# =============================================================================
# Task 0015: truncado de indicadores SMC/Liquidity al tope de Replay.
#
# Bug del arquitecto: en ChartEngine::render los indicadores se alimentaban con
# update_last hasta el fin del dataset (size()-1) aunque Replay estuviera activo,
# confiando en que el filtro index<=end del overlay evitara la fuga de futuro.
# Eso es INCORRECTO: los indicadores son máquinas incrementales con estado, y
# sus atributos (FVG mitig, pivotes confirmados) se calculan viendo TODAS las
# velas alimentadas. Corrección (task 0015): alimentar hasta replay_idx cuando
# Replay está activo; hasta size()-1 cuando no lo está; con reset()+realimentación
# en retroceso.
#
# Este test ejerce el cableado vía ChartEngine->sync_overlay_indicators() (el
# método público que render() invoca para llevar SMC/Liquidity al tope efectivo)
# usando un MarketData sintético y un ChartEngine parcial (estilo t/12), sin UI.
# Para cada caso se compara el estado del indicador del chart contra un
# indicador independiente alimentado solo hasta el mismo índice. Deben coincidir.
# =============================================================================

# --- TestMarketData: dataset sintético con todos los TF (Liquidity accede a
# $md->{data}->{'D'}/'W'); aquí vacíos salvo 1m. active_tf = '1m'.
{
    package TestMarketData;
    sub new {
        my ($class, $arr) = @_;
        return bless {
            data => {
                '1m'  => $arr, '5m' => [], '15m' => [], '1h' => [],
                '2h'  => [], '4h' => [], 'D'  => [], 'W'   => [],
            },
            _arr      => $arr,
            active_tf => '1m',
        }, $class;
    }
    sub size { scalar @{ shift->{_arr} } }
    sub get_candle { my ($s, $i) = @_; return $s->{_arr}->[$i]; }
    sub get_timestamp {
        my ($s, $i) = @_; my $r = $s->{_arr}->[$i];
        return $r ? $r->[0] : undef;
    }
}

# --- Helper: construir un ChartEngine parcial con overlay_manager + indicadores
# SMC/Liquidity + ReplayController reales, listo para llamar a
# sync_overlay_indicators(). Estilo t/12 (bless directo, sin UI/Tk).
sub build_chart {
    my ($md) = @_;
    my $smc = Market::Indicators::SMC_Structures->new(k => 3);
    my $liq = Market::Indicators::Liquidity->new(k => 3);
    return bless {
        market_data       => $md,
        smc_indicator     => $smc,
        _smc_fed_up_to    => -1,
        liq_indicator     => $liq,
        _liq_fed_up_to    => -1,
        overlay_manager   => Market::OverlayManager->new(),
        replay_controller => Market::ReplayController->new(market_data => $md),
    }, 'Market::ChartEngine';
}

# --- Helper: resumen determinista de los items de un indicador SMC (pivotes,
# eventos) para comparar. Se serializa por (index, type[, dir, price]).
sub smc_signature {
    my ($smc) = @_;
    my @parts;
    for my $p (@{ $smc->get_pivots() }) {
        push @parts, sprintf("P:%d:%s:%s", $p->{index}, $p->{type}, $p->{price});
    }
    for my $e (@{ $smc->get_events() }) {
        my $s = sprintf("E:%d:%s", $e->{index}, $e->{type});
        $s .= ":$e->{dir}" if defined $e->{dir};
        $s .= ":$e->{price}" if defined $e->{price};
        push @parts, $s;
    }
    return join(" | ", sort @parts);
}

# --- Helper: localiza el FVG del indicador por index (o undef si no existe).
sub find_fvg_at {
    my ($smc, $idx) = @_;
    for my $f (@{ $smc->get_fvg() }) {
        return $f if $f->{index} == $idx;
    }
    return undef;
}

# =============================================================================
# Test 1: No-fuga de FVG/mitigación (PDF §3).
# Dataset donde un FVG_up se forma en index=I=5 y una vela futura (idx=6) lo
# mitiga parcialmente. Con replay_idx=I (parado justo en la formación), el
# indicador del chart debe reportar ese FVG SIN mitigar (mitig==0, hi/lo
# originales). Comparar contra un indicador independiente alimentado solo 0..I.
# CON EL CABLEADO VIEJO (alimentar hasta size()-1) el FVG aparecería mitigado
# (mitig=0.3, hi recortado) -> el test fallaría. Ver "CONFIRMACIÓN" más abajo.
# =============================================================================
{
    my @d;
    for my $i (0..10) {
        # velas de fondo planas (200) para no generar ruido
        push @d, [sprintf("2026-04-01T00:%02d:00-05:00", $i), 200, 200, 200, 200, 100];
    }
    # idx=3: high=100 (prev_high del gap). low=99.
    $d[3] = ["2026-04-01T00:03:00-05:00", 100, 100, 99, 100, 100];
    # idx=5: low=110, high=111 -> gap [100,110] (FVG_up anclado en idx=5).
    $d[5] = ["2026-04-01T00:05:00-05:00", 110, 111, 110, 111, 100];
    # idx=6: low=107 (< 110) mitiga parcialmente: hi 110->107, no desactiva.
    # gap pasa a [100,107]; mitig = 1 - (107-100)/(110-100) = 0.3.
    $d[6] = ["2026-04-01T00:06:00-05:00", 210, 210, 107, 210, 100];

    my $md    = TestMarketData->new(\@d);
    my $chart = build_chart($md);

    # Replay parado en la formación del FVG (idx=5).
    $chart->{replay_controller}->start(5);
    my $feed_to = $chart->sync_overlay_indicators();
    is($feed_to, 5, 'Test1: feed_to = replay_idx = 5 (cableado nuevo)');

    my $fvg = find_fvg_at($chart->{smc_indicator}, 5);
    ok(defined $fvg, 'Test1: el FVG idx=5 existe con replay=5');

    # Atributos SIN mitigar (lo que vería un operador parado en la formación).
    is($fvg->{mitig}, 0,    'Test1: FVG mitig==0 (no hay velas futuras que mitiguen)');
    is($fvg->{hi},    110,  'Test1: FVG hi original = 110 (next_low de la formación)');
    is($fvg->{lo},    100,  'Test1: FVG lo original = 100 (prev_high de la formación)');

    # Referencia independiente: indicador alimentado solo 0..5 desde cero.
    my $ref = Market::Indicators::SMC_Structures->new(k => 3);
    for my $i (0..5) { $ref->update_last($md, $i); }
    my $ref_fvg = find_fvg_at($ref, 5);
    ok(defined $ref_fvg, 'Test1: la referencia 0..5 también tiene el FVG idx=5');
    is($fvg->{mitig}, $ref_fvg->{mitig}, 'Test1: chart.mitig == referencia.mitig (0)');
    is($fvg->{hi},    $ref_fvg->{hi},    'Test1: chart.hi == referencia.hi (110)');
    is($fvg->{lo},    $ref_fvg->{lo},    'Test1: chart.lo == referencia.lo (100)');

    # CONFIRMACIÓN de que el cableado viejo fallaría: alimentar hasta size()-1
    # (lo que hacía el código pre-0015) debe producir mitig != 0.
    # Sin filtro de cercanía: este caso compara mitigación futura, no vigencia por precio.
    my $old = Market::Indicators::SMC_Structures->new(k => 3, fvg_near_atr => 0);
    for my $i (0..$md->size() - 1) { $old->update_last($md, $i); }
    my $old_fvg = find_fvg_at($old, 5);
    ok(defined $old_fvg, 'Test1 (cable viejo): alimentar hasta size()-1 deja el FVG idx=5');
    isnt($old_fvg->{mitig}, 0,
         'Test1 (cable viejo): alimentar hasta el final filtra futuro (mitig != 0)');
    is($old_fvg->{mitig}, "0.3",
       'Test1 (cable viejo): mitig = 0.3 (la vela idx=6 recorta hi 110->107)');
    isnt($old_fvg->{hi}, $fvg->{hi},
         'Test1: chart(replay).hi (110) != chart(cable viejo).hi (107) -> el bug existía');
}

# =============================================================================
# Test 2: No-fuga de pivotes/eventos. Con replay_idx=R, los pivotes/eventos del
# indicador del chart == los de un indicador alimentado solo 0..R.
# Dataset con un pico alto en idx=6. Con k=3, el swing en j=6 se confirma al
# alimentar la vela 6+3=9. Antes de R=9 el pivote NO debe existir.
# =============================================================================
{
    my @d;
    for my $i (0..14) {
        push @d, [sprintf("2026-04-01T00:%02d:00-05:00", $i), 10, 10, 9, 10, 100];
    }
    $d[6] = ["2026-04-01T00:06:00-05:00", 10, 50, 9, 10, 100];  # pico en idx=6

    my $md    = TestMarketData->new(\@d);
    my $chart = build_chart($md);

    # R=6: el pivote idx=6 no está confirmado (necesita velas 7,8,9).
    $chart->{replay_controller}->start(6);
    $chart->sync_overlay_indicators();
    my $sig_chart_r6 = smc_signature($chart->{smc_indicator});

    my $ref6 = Market::Indicators::SMC_Structures->new(k => 3);
    for my $i (0..6) { $ref6->update_last($md, $i); }
    is($sig_chart_r6, smc_signature($ref6),
       'Test2: con replay=6, pivotes/eventos del chart == referencia 0..6 (sin pivote idx=6)');
    my @piv_r6 = @{ $chart->{smc_indicator}->get_pivots() };
    is(scalar(@piv_r6), 0, 'Test2: ningún pivote confirmado a replay=6');

    # R=9: ahora el pivote idx=6 (HH) y el trailing idx=9 (LL) están confirmados.
    $chart->{replay_controller}->start(9);
    $chart->sync_overlay_indicators();
    my $sig_chart_r9 = smc_signature($chart->{smc_indicator});

    my $ref9 = Market::Indicators::SMC_Structures->new(k => 3);
    for my $i (0..9) { $ref9->update_last($md, $i); }
    is($sig_chart_r9, smc_signature($ref9),
       'Test2: con replay=9, pivotes/eventos del chart == referencia 0..9');
    my @piv_r9 = @{ $chart->{smc_indicator}->get_pivots() };
    ok(scalar(@piv_r9) >= 1, 'Test2: a replay=9 hay al menos un pivote confirmado');

    # CONFIRMACIÓN cable viejo: alimentar 0..14 produce pivotes que R=6 no debería ver.
    my $old = Market::Indicators::SMC_Structures->new(k => 3);
    for my $i (0..14) { $old->update_last($md, $i); }
    my @piv_old = @{ $old->get_pivots() };
    ok(scalar(@piv_old) > 0, 'Test2 (cable viejo): alimentar hasta el final confirma pivotes');
    isnt(scalar(@piv_old), scalar(@piv_r6),
         'Test2: el cable viejo confirma pivotes que R=6 (correcto) aún no debería ver');
}

# =============================================================================
# Test 3: Step-backward. Avanzar replay a R2 y retroceder a R1<R2: el estado
# del indicador debe ser idéntico a alimentar 0..R1 desde cero. Verifica que el
# cursor _smc_fed_up_to se resetea+realimenta al retroceder (no queda adelantado).
# =============================================================================
{
    my @d;
    for my $i (0..14) {
        push @d, [sprintf("2026-04-01T00:%02d:00-05:00", $i), 10, 10, 9, 10, 100];
    }
    $d[6] = ["2026-04-01T00:06:00-05:00", 10, 50, 9, 10, 100];

    my $md    = TestMarketData->new(\@d);
    my $chart = build_chart($md);

    # Avanzar a R2=9 (confirma pivotes), luego retroceder a R1=6 (los oculta).
    $chart->{replay_controller}->start(9);
    $chart->sync_overlay_indicators();
    ok(scalar(@{ $chart->{smc_indicator}->get_pivots() }) > 0,
       'Test3: a R2=9 hay pivotes confirmados');

    $chart->{replay_controller}->start(6);  # step-backward (via start directo)
    my $feed_to = $chart->sync_overlay_indicators();
    is($feed_to, 6, 'Test3: tras retroceder, feed_to = 6');

    my $sig_after_back = smc_signature($chart->{smc_indicator});

    # Referencia: alimentar 0..6 desde cero.
    my $ref = Market::Indicators::SMC_Structures->new(k => 3);
    for my $i (0..6) { $ref->update_last($md, $i); }
    is($sig_after_back, smc_signature($ref),
       'Test3: tras retroceder R2->R1, el estado == referencia 0..6 desde cero');
    is(scalar(@{ $chart->{smc_indicator}->get_pivots() }), 0,
       'Test3: tras retroceder, los pivotes de R2=9 ya no aparecen (no hay fuga)');
    is($chart->{_smc_fed_up_to}, 6, 'Test3: cursor _smc_fed_up_to retrocedió a 6');

    # Mismo chequeo para Liquidity (mismo cableado vía _feed_indicator_to).
    my @liq_after = @{ $chart->{liq_indicator}->get_levels() };
    my $ref_liq = Market::Indicators::Liquidity->new(k => 3);
    for my $i (0..6) { $ref_liq->update_last($md, $i); }
    my @liq_ref = @{ $ref_liq->get_levels() };
    is(scalar(@liq_after), scalar(@liq_ref),
       'Test3: Liquidity tras retroceder tiene el mismo nº de niveles que 0..6');
    is($chart->{_liq_fed_up_to}, 6, 'Test3: cursor _liq_fed_up_to retrocedió a 6');
}

# =============================================================================
# Test 4: Sin Replay, el indicador se alimenta hasta size()-1 (vista normal).
# El cableado nuevo NO debe alterar el comportamiento fuera de Replay.
# =============================================================================
{
    my @d;
    for my $i (0..10) {
        push @d, [sprintf("2026-04-01T00:%02d:00-05:00", $i), 200, 200, 200, 200, 100];
    }
    $d[3] = ["2026-04-01T00:03:00-05:00", 100, 100, 99, 100, 100];
    $d[5] = ["2026-04-01T00:05:00-05:00", 110, 111, 110, 111, 100];
    $d[6] = ["2026-04-01T00:06:00-05:00", 210, 210, 107, 210, 100];

    my $md    = TestMarketData->new(\@d);
    my $chart = build_chart($md);

    ok(!$chart->{replay_controller}->is_active(),
       'Test4: Replay inactivo por defecto');

    my $feed_to = $chart->sync_overlay_indicators();
    is($feed_to, $md->size() - 1,
       'Test4: sin Replay, feed_to = size()-1 (vista normal intacta)');
    is($chart->{_smc_fed_up_to}, $md->size() - 1,
       'Test4: cursor SMC alimentado hasta size()-1');
    is($chart->{_liq_fed_up_to}, $md->size() - 1,
       'Test4: cursor Liquidity alimentado hasta size()-1');

    # En vista normal el FVG idx=5 SÍ aparece mitigado (la vela 6 es visible).
    # Eso es correcto: aquí NO hay Replay y todas las velas son legítimas.
    my $fvg = find_fvg_at($chart->{smc_indicator}, 5);
    ok(defined $fvg, 'Test4: sin Replay el FVG idx=5 existe');
    is($fvg->{mitig}, "0.3", 'Test4: sin Replay el FVG está mitigado (vela 6 visible es legítima)');
}

# =============================================================================
# Test 5: task 0063 — el modo no bloqueante de Liquidity debe terminar con el
# MISMO estado que el cálculo completo. La primera versión por chunks alimentaba
# SMC y Liquidity en lockstep; eso podía cambiar resultados porque SMC confirma
# pivotes con retraso. El contrato correcto es: SMC por chunks hasta target,
# luego Liquidity por chunks con todos los pivotes SMC válidos hasta target.
# =============================================================================
sub liquidity_signature {
    my ($liq) = @_;
    my @parts;
    for my $l (@{ $liq->get_levels() }) {
        push @parts, join(':', 'L', map { defined $l->{$_} ? $l->{$_} : '' } qw(index type price));
    }
    for my $e (@{ $liq->get_events() }) {
        push @parts, join(':', 'E', map { defined $e->{$_} ? $e->{$_} : '' } qw(index type price dir magnitude));
    }
    for my $z (@{ $liq->get_zones() }) {
        push @parts, join(':', 'Z', map { defined $z->{$_} ? $z->{$_} : '' } qw(index type lo hi price));
    }
    return join(' | ', sort @parts);
}

sub build_external_liq_chart {
    my ($md) = @_;
    my $smc = Market::Indicators::SMC_Structures->new(k => 2, swing_atr_factor => 0);
    my $liq = Market::Indicators::Liquidity->new(k => 2, level_atr_factor => 0);
    $liq->use_external_pivots(1);
    return bless {
        market_data       => $md,
        smc_indicator     => $smc,
        _smc_fed_up_to    => -1,
        liq_indicator     => $liq,
        _liq_fed_up_to    => -1,
        overlay_manager   => Market::OverlayManager->new(),
        replay_controller => Market::ReplayController->new(market_data => $md),
    }, 'Market::ChartEngine';
}

{
    my @d;
    my @close = qw(100 102 105 103 99 96 98 104 108 106 101 97 94 99 105 111 109 104 98 93 96 103 110 116 112 106 101 95 99 107 114 118 113 108 102 97 100 106 112 109);
    for my $i (0 .. $#close) {
        my $c = $close[$i];
        push @d, [sprintf('2026-04-01T00:%02d:00-05:00', $i), $c - 1, $c + 2, $c - 3, $c, 100 + $i];
    }
    my $md = TestMarketData->new(\@d);
    my $last = $md->size() - 1;

    my $full = build_external_liq_chart($md);
    ok($full->_feed_liquidity_stack_to($last), 'Test5: alimentación completa devuelve done');

    my $chunked = build_external_liq_chart($md);
    my $done_first = $chunked->_feed_liquidity_stack_chunk($last, 4);
    ok(!$done_first, 'Test5: primer chunk no completa todo el cálculo');
    is($chunked->{_smc_fed_up_to}, 3, 'Test5: primer chunk solo avanzó SMC hasta 3');
    is($chunked->{_liq_fed_up_to}, -1, 'Test5: primer chunk aún no alimenta Liquidity');

    my $guard = 0;
    until ($chunked->_feed_liquidity_stack_chunk($last, 4)) {
        die 'Test5: loop de chunks no termina' if ++$guard > 100;
    }
    is($chunked->{_smc_fed_up_to}, $last, 'Test5: chunks terminaron SMC en target');
    is($chunked->{_liq_fed_up_to}, $last, 'Test5: chunks terminaron Liquidity en target');
    is(liquidity_signature($chunked->{liq_indicator}), liquidity_signature($full->{liq_indicator}),
       'Test5: Liquidity por chunks == Liquidity completa (niveles/eventos/zonas)');
}

done_testing();
