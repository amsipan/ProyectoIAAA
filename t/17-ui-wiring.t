use strict;
use warnings;
use Test::More;

use lib '.';
use Market::UI::Callbacks;
use Market::UI::ReplayPanel;
use Market::UI::ReplayGotoMenu;
use Market::ReplayController;

# =============================================================================
# Task 0004: cableado de la barra de controles de Fase 2 (spec 0010).
#
# La UI Tk no se testa headless (`use Tk; MainWindow->new` requiere servidor
# gráfico). Pero las ACCIONES de la barra están factorizadas en
# Market::UI::Callbacks (sin Tk), así que aquí verificamos con mocks que cada
# callback invoca exactamente al método correcto del ChartEngine /
# ReplayController / OverlayManager / overlay de liquidez, sin abrir ventana.
#
# Estrategia: un MockChart que registra cada llamada (método + argumentos) y
# delega el ReplayController a un controlador REAL sobre un MarketData mock,
# para probar también el cableado start/step/play/pause/exit. El mock $mw
# ejecuta `after($ms,$cb)` inmediatamente (loop de un tick) para que play/
# fast_fwd recorran su path de reprogramación.
#
# Lo que verifica este test (criterios de aceptación de la task):
#   1. timeframes() retorna exactamente las 8 TF en orden (1m..W).
#   2. Los callbacks de TF invocan $chart->set_timeframe($tf) con el valor
#      correcto para las 8 temporalidades y sincronizan active_tf.
#   3. Los 7 botones de Replay invocan el método correcto del ReplayController
#      (start/play/pause/step_forward/step_backward/fast_forward/exit) y
#      disparan request_render (re-render tras cada acción).
#   4. Play/Fast Fwd usan after() sobre $mw (el mock lo registra).
#   5. Cada toggle de overlay invoca overlay_manager->set_visible($name,$on)
#      sin afectar a los demás.
#   6. Cada toggle de elemento de liquidez invoca liq_overlay->set_element_visible.
#   7. El toggle HTF alterna su estado ($htf_enabled) y pide re-render.
# =============================================================================

# Canvas stub: request_render programa after(20) — sin servidor grafico, no-op.
{
    package StubAfterCanvas;
    sub after { return }
}

# --- MockMarketData: dataset sintético de N velas 1m ---
{
    package MockMarketData;
    sub new {
        my ($class, $n) = @_;
        my @data;
        for my $i (0 .. $n - 1) {
            push @data, [sprintf('2026-04-01T00:%02d:00-05:00', $i % 60),
                         100 + $i, 110 + $i, 95 + $i, 105 + $i, 100];
        }
        return bless { data => \@data }, $class;
    }
    sub size { scalar @{ shift->{data} } }
    sub get_candle { my ($s, $i) = @_; return $s->{data}->[$i] }
    sub get_slice {
        my ($self, $s, $e) = @_;
        my @out;
        for my $i ($s .. $e) {
            push @out, ($i >= 0 && $i < $self->size) ? $self->{data}->[$i] : undef;
        }
        return \@out;
    }
}

# --- MockLiqOverlay: registra set_element_visible / set_visible ---
{
    package MockLiqOverlay;
    sub new {
        my ($class) = @_;
        return bless { elem_calls => [], visible => 1, elem => {} }, $class;
    }
    sub set_visible { my ($s,$b) = @_; $s->{visible} = $b ? 1 : 0; $s }
    sub set_element_visible {
        my ($s, $elem, $bool) = @_;
        push @{ $s->{elem_calls} }, [ $elem, $bool ? 1 : 0 ];
        $s->{elem}{$elem} = $bool ? 1 : 0;
        return $s;
    }
}

# --- MockOverlayManager: registra set_visible por nombre ---
{
    package MockOverlayManager;
    sub new { bless { vis_calls => [], states => {} }, shift }
    sub set_visible {
        my ($s, $name, $bool) = @_;
        push @{ $s->{vis_calls} }, [ $name, $bool ? 1 : 0 ];
        $s->{states}{$name} = $bool ? 1 : 0;
        return $s;
    }
}

# --- MockMW: MainWindow stub. after($ms,$cb) ejecuta el callback un número
# limitado de veces (simula N ticks del loop) y registra las llamadas. El límite
# evita recursión infinita cuando el callback se reprograma a sí mismo (play). ---
{
    package MockMW;
    sub new {
        my ($class, $max) = @_;
        return bless { after_calls => 0, fired => 0, max => $max // 1 }, $class;
    }
    sub after {
        my ($s, $ms, $cb) = @_;
        $s->{after_calls}++;
        $s->{last_ms} = $ms;
        return if $s->{fired} >= $s->{max};
        return unless ref($cb) eq 'CODE';
        $s->{fired}++;
        $cb->();   # tick inmediato (limitado a max)
        return;
    }
    sub afterCancel { return }
}

# --- MockChart: registra set_timeframe / request_render; expone el
# ReplayController REAL + managers mock + liq_overlay mock + market_data mock.
# visible_bars fijo para que el cálculo del índice inicial de replay sea
# determinista. ---
{
    package MockChart;
    sub new {
        my ($class, %a) = @_;
        my $md = $a{market_data} || MockMarketData->new(100);
        return bless {
            market_data       => $md,
            replay_controller => Market::ReplayController->new(market_data => $md),
            overlay_manager   => $a{overlay_manager} || MockOverlayManager->new(),
            liq_overlay       => $a{liq_overlay} || MockLiqOverlay->new(),
            mxwll_overlay     => $a{mxwll_overlay} || MockLiqOverlay->new(),
            visible_bars      => $a{visible_bars} || 20,
            _calls            => [],
            _tf               => [],
        }, $class;
    }
    sub set_timeframe {
        my ($s, $tf) = @_;
        push @{ $s->{_tf} }, $tf;
        push @{ $s->{_calls} }, [ set_timeframe => $tf ];
        return;
    }
    sub request_render {
        my ($s) = @_;
        push @{ $s->{_calls} }, [ 'request_render' ];
        return;
    }
    sub tf_calls    { shift->{_tf} }
    sub render_count { scalar grep { $_->[0] eq 'request_render' } @{ shift->{_calls} } }
    sub clear_replay_select_state {
        my ($s) = @_;
        delete $s->{_selected_bar};
        $s->{_replay_select_mode} = 0;
        return $s;
    }
    sub selected_bar { shift->{_selected_bar} }
    sub set_replay_select_mode {
        my ($s, $on) = @_;
        $s->{_replay_select_mode} = $on ? 1 : 0;
        push @{ $s->{_calls} }, [ set_replay_select_mode => $on ? 1 : 0 ];
        return $s;
    }
    sub is_replay_select_mode {
        my ($s) = @_;
        return $s->{_replay_select_mode} ? 1 : 0;
    }
    sub clear_replay_select_mode {
        my ($s) = @_;
        $s->{_replay_select_mode} = 0;
        return $s;
    }
    sub frame_replay_view_at { shift }
    sub replay_start_index {
        my ($s) = @_;
        my $last = $s->{market_data}->size() - 1;
        my $vis = $s->{visible_bars} || 20;
        my $start = $last - $vis;
        return $start < 0 ? 0 : $start;
    }
}

# Helper: un MockMW que NO ejecuta el callback (para probar que play/fast_fwd
# SÍ llaman after sin disparar efectos secundarios no deseados en otras aserciones).
{
    package MockMWNoop;
    sub new { bless { after_calls => 0 }, shift }
    sub after { shift->{after_calls}++; return }
}

# =============================================================================
# Test 1: timeframes() retorna exactamente las 8 TF en orden.
# =============================================================================
is_deeply([ Market::UI::Callbacks->timeframes() ],
          [qw(1m 5m 15m 1h 2h 4h D W)],
          'timeframes() retorna las 8 TF en orden (1m..W)');
is(scalar(Market::UI::Callbacks->timeframes()), 8, 'son exactamente 8 TF');

# =============================================================================
# Test 2: callbacks de TF invocan set_timeframe con el valor correcto para las 8
# y sincronizan $active_tf compartido.
# =============================================================================
{
    my $chart   = MockChart->new();
    my $active_tf = '1m';
    my %vars = ( active_tf => \$active_tf );

    for my $tf (Market::UI::Callbacks->timeframes()) {
        my $cb = Market::UI::Callbacks->make_tf_callback($chart, $tf, \%vars);
        $cb->();
    }
    is_deeply($chart->tf_calls(),
              [qw(1m 5m 15m 1h 2h 4h D W)],
              'los 8 callbacks de TF llaman set_timeframe con los valores correctos en orden');
    is($active_tf, 'W',
       'make_tf_callback sincroniza $active_tf con el último TF seleccionado (W)');
}

# =============================================================================
# Test 2b (task 0040-D): cambio de TF con Play activo detiene Play y limpia estado.
# =============================================================================
{
    my $chart = MockChart->new(market_data => MockMarketData->new(100));
    my $replay_on = 1;
    my $replay_select_mode = 1;
    my $active_tf = '1m';
    my %vars = (
        replay_on          => \$replay_on,
        replay_select_mode => \$replay_select_mode,
        active_tf          => \$active_tf,
    );
    my $rc = $chart->{replay_controller};

    $rc->start(50);
    $rc->{playing} = 1;
    $chart->{_selected_bar} = 50;
    $chart->{_replay_select_mode} = 1;

    ok($rc->{playing}, '0040-D: Play activo antes de TF');
    ok($rc->is_active(), '0040-D: replay activo antes de TF');

    my $cb = Market::UI::Callbacks->make_tf_callback($chart, '5m', \%vars);
    $cb->();

    ok(!$rc->{playing}, '0040-D: TF detiene Play');
    ok(!$rc->is_active(), '0040-D: TF sale de Replay');
    ok(!defined $chart->selected_bar(), '0040-D: TF limpia selected_bar');
    is($replay_on, 0, '0040-D: replay_on=0');
    is($replay_select_mode, 0, '0040-D: replay_select_mode=0');
    is($active_tf, '5m', '0040-D: active_tf actualizado');
    is($chart->tf_calls()->[-1], '5m', '0040-D: set_timeframe invocado');
}

# =============================================================================
# Test 3: Inicio Replay invoca replay_controller->start y dispara re-render.
# =============================================================================
{
    my $chart   = MockChart->new(market_data => MockMarketData->new(100));
    my $replay_on = 0;
    my %vars = ( replay_on => \$replay_on );
    my $rc = $chart->{replay_controller};

    ok(!$rc->is_active(), 'replay inactivo antes de Inicio');
    my $cb = Market::UI::Callbacks->make_replay_start($chart, \%vars);
    $cb->();

    ok($rc->is_active(), 'Inicio Replay activa el controlador');
    ok(defined $rc->current_index(), 'Inicio fija un replay_idx');
    is($replay_on, 1, 'Inicio marca replay_on=1');
    ok($chart->render_count() >= 1, 'Inicio dispara re-render');

    # Índice inicial esperado = last(99) - visible_bars(20) = 79.
    is($rc->current_index(), 79, 'Inicio arranca en last - visible_bars = 79');
}

# =============================================================================
# Test 4: Play invoca replay_controller->play y usa after() sobre $mw; el tick
# hace step_forward + re-render. Verifica además que Pause detiene.
# =============================================================================
{
    my $chart   = MockChart->new(market_data => MockMarketData->new(100));
    my $mw    = MockMW->new();        # after ejecuta el callback (un tick)
    my $replay_on = 0;
    my %vars = ( replay_on => \$replay_on );
    my $rc = $chart->{replay_controller};

    # Arrancamos primero (Play arranca solo si no está activo, pero para
    # aislar el efecto de play medimos desde un idx conocido).
    $rc->start(50);
    my $before = $rc->current_index();
    is($before, 50, 'replay parado en idx 50 antes de Play');

    my $cb = Market::UI::Callbacks->make_replay_play($chart, $mw, \%vars);
    $cb->();

    ok($rc->{playing}, 'Play deja el controlador en playing=1');
    ok($mw->{after_calls} >= 1, 'Play programa al menos un after() sobre $mw');
    # El mock MockMW ejecuta el tick inmediato → step_forward avanza 1.
    is($rc->current_index(), 51, 'el tick de Play avanza 1 vela (50->51)');
    ok($chart->render_count() >= 1, 'Play dispara re-render');

    # Pause detiene la reproducción.
    my $pause = Market::UI::Callbacks->make_replay_pause($chart, \%vars);
    $pause->();
    ok(!$rc->{playing}, 'Pause deja playing=0');
}

# =============================================================================
# Test 4b (task 0045): Play usa tick_ms() del ReplayController (no 80ms fijo).
# =============================================================================
{
    my $chart = MockChart->new(market_data => MockMarketData->new(100));
    my $mw    = MockMW->new();
    my $rc    = $chart->{replay_controller};
    $rc->start(50);
    $rc->set_speed_label('5x');
    Market::UI::Callbacks->make_replay_play($chart, $mw, {})->();
    is($mw->{last_ms}, 200, '0045: Play programa after con tick_ms 5x = 200ms');
}

# =============================================================================
# Test 5: Pause invoca pause y re-render (sin $mw).
# =============================================================================
{
    my $chart = MockChart->new(market_data => MockMarketData->new(100));
    my $rc = $chart->{replay_controller};
    $rc->start(10);
    $rc->{playing} = 1;
    my $render_before = $chart->render_count();
    my $cb = Market::UI::Callbacks->make_replay_pause($chart, {});
    $cb->();
    ok(!$rc->{playing}, 'Pause detiene playing');
    ok($chart->render_count() > $render_before, 'Pause dispara re-render');
}

# =============================================================================
# Test 6: Step Forward avanza exactamente 1 y re-render.
# =============================================================================
{
    my $chart = MockChart->new(market_data => MockMarketData->new(100));
    my $rc = $chart->{replay_controller};
    $rc->start(40);
    my $cb = Market::UI::Callbacks->make_replay_step_fwd($chart);
    $cb->();
    is($rc->current_index(), 41, 'Step > avanza exactamente 1 (40->41)');
    ok($chart->render_count() >= 1, 'Step > dispara re-render');

    # Step funciona aunque el replay no estuviera activo (lo arranca).
    $rc->exit();
    ok(!$rc->is_active(), 'replay inactivo tras exit');
    $cb->();
    ok($rc->is_active(), 'Step > arranca el replay si no estaba activo');
}

# =============================================================================
# Test 7: Step Back retrocede exactamente 1 y re-render.
# =============================================================================
{
    my $chart = MockChart->new(market_data => MockMarketData->new(100));
    my $rc = $chart->{replay_controller};
    $rc->start(40);
    my $cb = Market::UI::Callbacks->make_replay_step_back($chart);
    $cb->();
    is($rc->current_index(), 39, 'Step < retrocede exactamente 1 (40->39)');
    ok($chart->render_count() >= 1, 'Step < dispara re-render');
}

# =============================================================================
# Test 8: Fast Fwd avanza N velas (default 10), usa after(), re-render, clamp.
# =============================================================================
{
    my $chart = MockChart->new(market_data => MockMarketData->new(100));
    my $mw    = MockMWNoop->new();   # no ejecuta tick: solo verifica after()
    my $rc = $chart->{replay_controller};
    $rc->start(10);
    my $cb = Market::UI::Callbacks->make_replay_fast_fwd($chart, $mw, {});
    $cb->();
    is($rc->current_index(), 20, 'Fast >> avanza 10 velas (10->20)');
    ok($chart->render_count() >= 1, 'Fast >> dispara re-render');

    # Clamp al último índice: start(95) + fast(10) => clamp a 99.
    $rc->start(95);
    $cb->();
    is($rc->current_index(), 99, 'Fast >> clampa al último índice (95+10->99)');
}

# =============================================================================
# Test 9: Exit Replay desactiva el controlador (tope = last) y re-render, y
# sincroniza replay_on=0.
# =============================================================================
{
    my $chart = MockChart->new(market_data => MockMarketData->new(100));
    my $replay_on = 1;
    my %vars = ( replay_on => \$replay_on );
    my $rc = $chart->{replay_controller};
    $rc->start(50);
    ok($rc->is_active(), 'replay activo antes de Exit');
    my $cb = Market::UI::Callbacks->make_replay_exit($chart, \%vars);
    $cb->();
    ok(!$rc->is_active(), 'Exit desactiva el controlador');
    is($rc->current_index(), undef, 'Exit deja current_index undef (tope = last)');
    is($replay_on, 0, 'Exit marca replay_on=0');
    ok($chart->render_count() >= 1, 'Exit dispara re-render');
}

# =============================================================================
# Test 10: cada toggle de overlay invoca overlay_manager->set_visible($name,$on)
# sin afectar a los demás overlays (aislamiento).
# =============================================================================
{
    my $mgr   = MockOverlayManager->new();
    my $chart = MockChart->new(overlay_manager => $mgr, market_data => MockMarketData->new(50));

    # SMC off
    my $smc_cb = Market::UI::Callbacks->make_overlay_toggle($chart, 'smc');
    $smc_cb->(0);
    # Liq on
    my $liq_cb = Market::UI::Callbacks->make_overlay_toggle($chart, 'liq');
    $liq_cb->(1);
    # SMC on de nuevo
    $smc_cb->(1);

    is_deeply($mgr->{vis_calls},
              [ ['smc', 0], ['liq', 1], ['smc', 1] ],
              'overlay_manager->set_visible recibe (nombre, bool) en orden');
    is($mgr->{states}{smc}, 1, 'estado final smc = on (no afectado por liq)');
    is($mgr->{states}{liq}, 1, 'estado final liq = on (no afectado por smc)');
    ok($chart->render_count() >= 3, 'cada toggle de overlay dispara re-render');
}

# =============================================================================
# Test 11: cada toggle de elemento de liquidez invoca
# liq_overlay->set_element_visible($elem,$on) para los 7 elementos.
# =============================================================================
{
    my $liq   = MockLiqOverlay->new();
    my $chart = MockChart->new(liq_overlay => $liq, market_data => MockMarketData->new(50));

    my @elems = qw(BSL SSL EQH EQL SWEEP GRAB RUN);
    for my $elem (@elems) {
        my $cb = Market::UI::Callbacks->make_liq_element_toggle($chart, $elem);
        $cb->(1);
    }
    # Desactivar BSL y SWEEP para comprobar aisamiento por elemento.
    Market::UI::Callbacks->make_liq_element_toggle($chart, 'BSL')->(0);
    Market::UI::Callbacks->make_liq_element_toggle($chart, 'SWEEP')->(0);

    my @seen = map { $_->[0] } @{ $liq->{elem_calls} };
    my %uniq; $uniq{$_}++ for @seen;
    for my $elem (@elems) {
        ok(exists $uniq{$elem}, "toggle de elemento $elem llama set_element_visible");
    }
    is($liq->{elem}{BSL},   0, 'BSL desactivado de forma aislada');
    is($liq->{elem}{SWEEP}, 0, 'SWEEP desactivado de forma aislada');
    is($liq->{elem}{SSL},   1, 'SSL no afectado por BSL/SWEEP');
    is($liq->{elem}{RUN},   1, 'RUN no afectado por BSL/SWEEP');
    ok($chart->render_count() >= 1, 'toggle de elemento dispara re-render');
}

# =============================================================================
# Test 11b (ORDEN 9 / task 0021 I): cada toggle de elemento Mxwll invoca
# mxwll_overlay->set_element_visible($elem,$on) para los 6 elementos.
# =============================================================================
{
    my $mx    = MockLiqOverlay->new();   # mismo contrato set_element_visible
    my $chart = MockChart->new(mxwll_overlay => $mx, market_data => MockMarketData->new(50));

    my @elems = qw(STRUCTURE SWINGS OB FVG AOE FIBS);
    for my $elem (@elems) {
        Market::UI::Callbacks->make_mxwll_element_toggle($chart, $elem)->(1);
    }
    Market::UI::Callbacks->make_mxwll_element_toggle($chart, 'FVG')->(0);
    Market::UI::Callbacks->make_mxwll_element_toggle($chart, 'AOE')->(0);

    my %uniq; $uniq{$_->[0]}++ for @{ $mx->{elem_calls} };
    for my $elem (@elems) {
        ok(exists $uniq{$elem}, "Mxwll: toggle de $elem llama set_element_visible");
    }
    is($mx->{elem}{FVG}, 0, 'Mxwll: FVG desactivado de forma aislada');
    is($mx->{elem}{AOE}, 0, 'Mxwll: AOE desactivado de forma aislada');
    is($mx->{elem}{STRUCTURE}, 1, 'Mxwll: STRUCTURE no afectado');
    ok($chart->render_count() >= 1, 'Mxwll: toggle de elemento dispara re-render');
}

# =============================================================================
# Test 12: toggle HTF alterna $htf_enabled y pide re-render (cableado preparado).
# =============================================================================
{
    my $chart = MockChart->new(market_data => MockMarketData->new(50));
    my $htf_enabled = 0;
    my %vars = ( htf_enabled => \$htf_enabled );
    my $cb = Market::UI::Callbacks->make_htf_toggle($chart, \%vars);

    $cb->(1);
    is($htf_enabled, 1, 'HTF on => htf_enabled=1');
    ok($chart->render_count() >= 1, 'HTF on dispara re-render');

    $cb->(0);
    is($htf_enabled, 0, 'HTF off => htf_enabled=0');
}

# =============================================================================
# task 0062: market.pl expone slider de densidad de liquidez (Tk::Scale).
# =============================================================================
{
    open my $fh, '<', 'market.pl' or die "market.pl: $!";
    my $src = do { local $/; <$fh> };
    close $fh;
    like($src, qr/Densidad:/, '0064: market.pl muestra densidad siempre visible en la fila superior');
    like($src, qr/Por\s+tipo/, '0063: market.pl agrupa densidad por tipo');
    like($src, qr/my \$liq_density_pct = 20;/, '0063: densidad inicial de la app es baja para exposición');
    like($src, qr/my \$smc_density_pct = 35;/, '0064: densidad SMC inicial baja');
    like($src, qr/my \$mxwll_density_pct = 35;/, '0064: densidad Mxwll inicial baja');
    like($src, qr/my \$zigzag_density_pct = 35;/, '0064: densidad ZigZag inicial baja');
    like($src, qr/\[ 'Liq',\s+\\\$liq_density_pct,\s+'liq_overlay'/, '0064: control persistente Liq');
    like($src, qr/\[ 'SMC',\s+\\\$smc_density_pct,\s+'smc_overlay'/, '0064: control persistente SMC');
    like($src, qr/\[ 'Mxwll',\s+\\\$mxwll_density_pct,\s+'mxwll_overlay'/, '0064: control persistente Mxwll');
    like($src, qr/\[ 'ZigZag',\s+\\\$zigzag_density_pct,\s+'zigzag_overlay'/, '0064: control persistente ZigZag');
    like($src, qr/->Scale\b/, '0062: market.pl usa Tk::Scale');
    like($src, qr/set_density_pct/, '0062/0064: market.pl cablea set_density_pct global por categoría');
    like($src, qr/set_element_density_pct/, '0063: market.pl cablea set_element_density_pct por familia');
    like($src, qr/enable_liquidity_background_feed\(chunk_size\s*=>\s*300,\s*after_ms\s*=>\s*40\)/,
         '0063: market.pl habilita precalculo no bloqueante de Liquidez');
    like($src, qr/request_render/, '0062: slider dispara request_render');
}

# =============================================================================
# Test 13: las factorías validan sus argumentos (no crean callbacks sin $chart).
# Protege contra un cableado olvidado en market.pl.
# =============================================================================
{
    eval { Market::UI::Callbacks->make_tf_callback(undef, '1m', {}); };
    like($@, qr'requiere \$chart', 'make_tf_callback sin $chart muere claro')
        or diag("got: $@");
    eval { Market::UI::Callbacks->make_overlay_toggle(MockChart->new(), undef); };
    like($@, qr'requiere \$name', 'make_overlay_toggle sin $name muere claro')
        or diag("got: $@");
    eval { Market::UI::Callbacks->make_replay_play(undef); };
    like($@, qr'requiere \$chart', 'make_replay_play sin $chart muere claro')
        or diag("got: $@");
}

# =============================================================================
# Test 14 (task 0043): factorías del panel flotante Replay existen y son CODE.
# =============================================================================
{
    my $chart = MockChart->new();
    my $cbs = Market::UI::ReplayPanel::callback_factories($chart, undef, {});
    my @keys = qw(select_bar goto_menu play step_fwd step_back speed_menu interval_menu jump_real exit);
    for my $k (@keys) {
        ok(exists $cbs->{$k}, "0043: callback_factories tiene $k");
        ok(ref($cbs->{$k}) eq 'CODE', "0043: $k es CODE");
    }
    ok(ref(Market::UI::Callbacks->make_replay_activate($chart, {})) eq 'CODE',
       '0043: make_replay_activate es CODE');
    ok(ref(Market::UI::Callbacks->make_replay_goto_menu_stub($chart, {})) eq 'CODE',
       '0043: make_replay_goto_menu_stub es CODE');
    for my $factory (qw(make_replay_goto_bar make_replay_goto_first make_replay_goto_random)) {
        ok(ref(Market::UI::Callbacks->$factory($chart, {})) eq 'CODE',
           "0044: $factory es CODE");
    }
    ok(ref(Market::UI::Callbacks->make_replay_toggle_play($chart, undef, {})) eq 'CODE',
       '0046: make_replay_toggle_play es CODE');
    ok(ref(Market::UI::Callbacks->make_replay_jump_real($chart, {})) eq 'CODE',
       '0046: make_replay_jump_real es CODE');
    ok(ref(Market::UI::Callbacks->make_replay_goto_date($chart, undef, {})) eq 'CODE',
       '0044: make_replay_goto_date es CODE');
    is_deeply([ Market::UI::ReplayGotoMenu::expected_menu_labels() ],
              [ 'SELECT STARTING POINT', '|< Bar', 'Date...', 'First available date', 'Random bar' ],
              '0044: etiquetas ASCII del menu Go-to');
    ok(ref(Market::UI::Callbacks->make_replay_speed_menu_stub($chart, {})) eq 'CODE',
       '0043: make_replay_speed_menu_stub es CODE');
    ok(ref(Market::UI::Callbacks->make_replay_interval_menu_stub($chart, {})) eq 'CODE',
       '0043: make_replay_interval_menu_stub es CODE');
}

# =============================================================================
# Test 15 (task 0043): smoke build del panel; activate/exit show/hide.
# =============================================================================
{
    package MockReplayPanel;
    sub new { bless { visible => 0 }, shift }
    sub show { my ($s) = @_; $s->{visible} = 1; return $s }
    sub hide { my ($s) = @_; $s->{visible} = 0; return $s }
    sub is_visible { shift->{visible} ? 1 : 0 }

    package MockTkParent;
    sub new { bless { children => [] }, shift }
    sub Frame {
        my ($p, %o) = @_;
        my $f = bless { parent => $p, opts => \%o, children => [], placed => 0 }, 'MockTkFrame';
        push @{ $p->{children} }, $f;
        return $f;
    }
    sub idletasks { return }
    sub reqheight { return 120 }
    sub rootx { return 0 }
    sub rooty { return 0 }
    sub exists { return 1 }
    sub containing { return undef }
    sub pointerx { return 0 }
    sub pointery { return 0 }
    {
        no strict 'refs';
        *{'MockTkParent::Tk::bind'} = sub { return };
    }

    package MockTkFrame;
    sub Frame {
        my ($p, %o) = @_;
        my $f = bless { parent => $p, opts => \%o, children => [], placed => 0 }, 'MockTkFrame';
        push @{ $p->{children} }, $f;
        return $f;
    }
    sub Label {
        my ($p, %o) = @_;
        my $w = bless { parent => $p, opts => \%o, kind => 'Label' }, 'MockTkWidget';
        push @{ $p->{children} }, $w;
        return $w;
    }
    sub Button {
        my ($p, %o) = @_;
        my $w = bless { parent => $p, opts => \%o, kind => 'Button' }, 'MockTkWidget';
        push @{ $p->{children} }, $w;
        return $w;
    }
    sub Checkbutton {
        my ($p, %o) = @_;
        my $w = bless { parent => $p, opts => \%o, kind => 'Checkbutton' }, 'MockTkWidget';
        push @{ $p->{children} }, $w;
        return $w;
    }
    sub Canvas {
        my ($p, %o) = @_;
        my $w = bless { parent => $p, opts => \%o, kind => 'Canvas', items => [] }, 'MockTkWidget';
        push @{ $p->{children} }, $w;
        return $w;
    }
    sub pack { return shift }
    sub lower { return shift }
    sub raise { return shift }
    sub place {
        my ($s, %o) = @_;
        $s->{placed} = 1;
        $s->{place_opts} = \%o;
        return $s;
    }
    sub placeForget { my ($s) = @_; $s->{placed} = 0; return $s }
    sub idletasks { return }
    sub reqheight { return 120 }
    sub rootx { return 0 }
    sub rooty { return 0 }
    sub exists { return 1 }
    sub containing { return undef }
    sub pointerx { return 0 }
    sub pointery { return 0 }
    {
        no strict 'refs';
        *{'MockTkFrame::Tk::bind'} = sub { return };
    }

    package MockTkWidget;
    sub pack { return shift }
    sub bind { return shift }
    sub place { return shift }
    sub lower { return shift }
    sub raise { return shift }
    sub createPolygon { my ($s) = @_; push @{ $s->{items} }, 'polygon'; return 'icon' }
    sub createRectangle { my ($s) = @_; push @{ $s->{items} }, 'rect'; return 'icon' }
    sub createLine { my ($s) = @_; push @{ $s->{items} }, 'line'; return 'icon' }
    sub configure { my ($s, %o) = @_; $s->{opts} = { %{ $s->{opts} || {} }, %o }; return $s }
    sub exists { return 1 }

    package main;

    my $chart = MockChart->new();
    my $built_panel;
    my %build_vars = ( replay_panel => \$built_panel );

    my $mock_parent = MockTkParent->new();
    my $built = Market::UI::ReplayPanel->new(
        parent      => $mock_parent,
        menu_parent => $mock_parent,
        chart       => $chart,
        ui_vars     => \%build_vars,
    );
    ok($built, '0043: ReplayPanel->new smoke sin error');
    ok(!$built->is_visible(), '0043: panel oculto tras build');
    ok(ref($built->callbacks()) eq 'HASH', '0043: panel expone callbacks');
    $built->show();
    ok($built->is_visible(), '0043: show() marca visible');
    $built->hide();
    ok(!$built->is_visible(), '0043: hide() marca oculto');

    my $replay_on = 0;
    my $replay_select_mode = 0;
    my $panel_obj = MockReplayPanel->new();
    my $tab_switched = 0;
    my %vars = (
        replay_on          => \$replay_on,
        replay_select_mode => \$replay_select_mode,
        replay_panel       => \$panel_obj,
        show_replay_tab    => sub { $tab_switched = 1 },
    );

    Market::UI::Callbacks->make_replay_activate($chart, \%vars)->();
    is($replay_on, 1, '0043: activate marca replay_on=1');
    is($replay_select_mode, 1, '0043: activate entra en select mode');
    ok($tab_switched, '0045: activate cambia a pestaña Replay');

    Market::UI::Callbacks->make_replay_exit($chart, \%vars)->();
    is($replay_on, 0, '0043: exit marca replay_on=0');
}

# =============================================================================
# Test 16 (task 0048): etiquetas del panel son ASCII legibles (sin mojibake).
# =============================================================================
{
    package MockTkParent48;
    sub new { bless { children => [] }, shift }
    sub Frame {
        my ($p, %o) = @_;
        my $f = bless { parent => $p, opts => \%o, children => [], placed => 0 }, 'MockTkFrame48';
        push @{ $p->{children} }, $f;
        return $f;
    }
    sub bind { return }
    sub unbind { return }
    sub pointerx { return 0 }
    sub pointery { return 0 }
    sub containing { return undef }
    sub winfo_containing { return undef }
    sub winfo_exists { return 1 }
    sub exists { return 1 }
    sub idletasks { return }
    sub reqheight { return 120 }
    sub rootx { return 0 }
    sub rooty { return 0 }
    {
        no strict 'refs';
        *{'MockTkParent48::Tk::bind'} = sub { return };
    }

    package MockTkFrame48;
    sub Frame {
        my ($p, %o) = @_;
        my $f = bless { parent => $p, opts => \%o, children => [], placed => 0 }, 'MockTkFrame48';
        push @{ $p->{children} }, $f;
        return $f;
    }
    sub Label {
        my ($p, %o) = @_;
        my $w = bless { parent => $p, opts => \%o, kind => 'Label' }, 'MockTkWidget48';
        push @{ $p->{children} }, $w;
        return $w;
    }
    sub Button {
        my ($p, %o) = @_;
        my $w = bless { parent => $p, opts => \%o, kind => 'Button' }, 'MockTkWidget48';
        push @{ $p->{children} }, $w;
        return $w;
    }
    sub Canvas {
        my ($p, %o) = @_;
        my $w = bless { parent => $p, opts => \%o, kind => 'Canvas', items => [] }, 'MockTkCanvas48';
        push @{ $p->{children} }, $w;
        return $w;
    }
    sub Checkbutton {
        my ($p, %o) = @_;
        my $w = bless { parent => $p, opts => \%o, kind => 'Checkbutton' }, 'MockTkWidget48';
        push @{ $p->{children} }, $w;
        return $w;
    }
    sub pack { return shift }
    sub lower { return shift }
    sub raise { return shift }
    sub place { my ($s) = @_; $s->{placed} = 1; return $s }
    sub placeForget { my ($s) = @_; $s->{placed} = 0; return $s }
    sub update_idletasks { return }
    sub reqheight { return 120 }
    sub winfo_rootx { return 100 }
    sub winfo_rooty { return 500 }
    sub winfo_exists { return 1 }
    sub Parent { my ($s) = @_; return $s->{parent} }
    sub bind { return }
    sub unbind { return }
    sub pointerx { return 0 }
    sub pointery { return 0 }
    sub winfo_containing { return undef }

    package MockTkCanvas48;
    sub pack { return shift }
    sub bind { return shift }
    sub place { return shift }
    sub lower { return shift }
    sub raise { return shift }
    sub createPolygon {
        my ($s, @coords) = @_;
        push @{ $s->{items} }, { type => 'polygon', coords => \@coords };
        return 'icon';
    }
    sub createRectangle {
        my ($s) = @_;
        push @{ $s->{items} }, { type => 'rect' };
        return 'icon';
    }
    sub createLine {
        my ($s) = @_;
        push @{ $s->{items} }, { type => 'line' };
        return 'icon';
    }

    package MockTkWidget48;
    sub pack { return shift }
    sub bind { return shift }
    sub place { return shift }
    sub configure { my ($s, %o) = @_; $s->{opts} = { %{ $s->{opts} || {} }, %o }; return $s }
    sub exists { return 1 }
    sub winfo_exists { return 1 }

    package main;

    sub _collect_button_texts {
        my ($node) = @_;
        my @out;
        return @out unless ref $node;
        if ((($node->{kind} // '') eq 'Button' || ($node->{kind} // '') eq 'Label')
            && ref $node->{opts} eq 'HASH') {
            push @out, $node->{opts}{-text}
                if defined $node->{opts}{-text} && length $node->{opts}{-text};
        }
        for my $ch (@{ $node->{children} // [] }) {
            push @out, _collect_button_texts($ch);
        }
        return @out;
    }

    my $parent = MockTkParent48->new();
    my $built_panel;
    my $built = Market::UI::ReplayPanel->new(
        parent      => $parent,
        menu_parent => $parent,
        chart       => MockChart->new(),
        ui_vars     => { replay_panel => \$built_panel },
    );

    my @texts = _collect_button_texts($built->frame);
    is_deeply(\@texts, [ Market::UI::ReplayPanel::expected_text_button_labels() ],
        '0048: etiquetas texto del panel (Select bar/1x/D/Mark) coinciden con ASCII esperado');

    for my $t (@texts) {
        ok($t !~ /[^\x00-\x7F]/, "0048: etiqueta '$t' es ASCII puro");
        ok($t !~ /â/, "0048: etiqueta '$t' sin mojibake latin-1");
    }

    ok(Market::UI::ReplayPanel::has_play_icon_button(), '0046-prep: panel usa botones multimedia');
    my $icon_canvases = 0;
    my $walk;
    $walk = sub {
        my ($node) = @_;
        return unless ref $node;
        if (($node->{kind} // '') eq 'Canvas' && @{ $node->{items} // [] }) {
            $icon_canvases++;
        }
        $walk->($_) for @{ $node->{children} // [] };
    };
    $walk->($built->frame);
    is($icon_canvases, Market::UI::ReplayPanel::expected_media_icon_count(),
        '0046-prep: canvas con iconos multimedia (goto/transport/jump/exit)');
}

# =============================================================================
# Test 17 (task 0046): toggle Play/Pause, jump-to-real-time, marca de agua.
# =============================================================================
{
    use Market::ChartEngine;

    my $chart = MockChart->new(market_data => MockMarketData->new(100));
    my $mw    = MockMW->new();
    my $replay_on = 1;
    my %vars = ( replay_on => \$replay_on );
    my $rc = $chart->{replay_controller};
    $rc->start(40);

    my $toggle = Market::UI::Callbacks->make_replay_toggle_play($chart, $mw, \%vars);
    $toggle->();
    ok($rc->{playing}, '0046: toggle arranca playing=1');
    $toggle->();
    ok(!$rc->{playing}, '0046: segundo toggle pausa playing=0');

    $rc->start(30);
    my $replay_select_mode = 0;
    %vars = ( replay_on => \$replay_on, replay_select_mode => \$replay_select_mode );
    my $jump = Market::UI::Callbacks->make_replay_jump_real($chart, \%vars);
    $jump->();
    ok(!$rc->is_active(), '0046: jump-to-real-time desactiva truncado replay');
    is($rc->current_index(), undef, '0046: jump deja current_index undef (chart vivo)');
    is($replay_on, 1, '0046-TV: jump mantiene replay_on=1 (sesion Replay)');
    is($replay_select_mode, 1, '0046-TV: jump re-entra Select Bar');
    ok($chart->is_replay_select_mode(), '0046-TV: jump activa modo tijeras en chart');

    my $wm_on = 1;
    my $ce = bless {
        replay_controller       => $rc,
        replay_watermark_on_ref => \$wm_on,
    }, 'Market::ChartEngine';
    $rc->start(50);
    ok($ce->_replay_watermark_visible(), '0046: watermark visible (replay ON, flag ON)');
    $wm_on = 0;
    ok(!$ce->_replay_watermark_visible(), '0046: watermark oculta con flag OFF');
    $rc->exit();
    ok(!$ce->_replay_watermark_visible(), '0046: watermark oculta sin replay activo');
}

# =============================================================================
# Test 18 (task 0050): atajos TV Shift+Down toggle, Shift+Right precedencia.
# =============================================================================
{
    use Market::ChartEngine;

    my $md    = MockMarketData->new(100);
    my $rc    = Market::ReplayController->new(market_data => $md);
    my $chart = bless {
        market_data       => $md,
        replay_controller => $rc,
        visible_bars      => 20,
        _replay_select_mode => 0,
        _selected_bar     => undef,
        price_canvas      => bless({}, 'StubAfterCanvas'),
        ctrl_zoom_x_shift => 0,
        offset            => 0,
    }, 'Market::ChartEngine';

    my $step_fwd = Market::UI::Callbacks->make_replay_step_fwd($chart);
    $chart->{replay_keyboard_callbacks} = { step_fwd => $step_fwd };

    $rc->start(40);
    $chart->_replay_shift_right_key();
    is($rc->current_index(), 41, '0050: Shift+Right avanza replay activo (step_fwd real)');

    $rc->exit();
    $chart->set_replay_select_mode(1);
    $chart->{_selected_bar} = 50;
    $chart->{replay_keyboard_callbacks}{step_fwd} = sub { die 'step_fwd no debe llamarse en select' };
    $chart->_replay_shift_right_key();
    is($chart->selected_bar(), 51, '0050: Shift+Right mueve seleccion en Select Bar');
    ok(!$chart->is_replay_select_mode(), '0050: Shift+Right en select no invoca step_fwd');

    $rc->start(30);
    my $mw = MockMW->new();
    $chart->{replay_keyboard_callbacks}{toggle_play} =
        Market::UI::Callbacks->make_replay_toggle_play($chart, $mw, {});
    $chart->_replay_shift_down_key();
    ok($rc->{playing}, '0050: Shift+Down toggle play con replay activo');
    $chart->_replay_shift_down_key();
    ok(!$rc->{playing}, '0050: Shift+Down toggle pause');

    $rc->exit();
    ok(!$rc->is_active(), '0050: replay inactivo tras exit');
    eval { $chart->_replay_shift_down_key() };
    ok(!$@, '0050: Shift+Down sin replay activo no hace nada');
    ok(!$rc->{playing}, '0050: Shift+Down sin replay no arranca play');
}

# =============================================================================
# Test 19 (task 0051): Shift+Left precedencia, toggle watermark, Key-m, Escape.
# =============================================================================
{
    use Market::ChartEngine;

    my $md    = MockMarketData->new(100);
    my $rc    = Market::ReplayController->new(market_data => $md);
    my $chart = bless {
        market_data       => $md,
        replay_controller => $rc,
        visible_bars      => 20,
        _replay_select_mode => 0,
        _selected_bar     => undef,
        price_canvas      => bless({}, 'StubAfterCanvas'),
        is_auto_scale     => 1,
        ctrl_zoom_x_shift => 0,
        offset            => 0,
    }, 'Market::ChartEngine';

    my $step_back = Market::UI::Callbacks->make_replay_step_back($chart);
    $chart->{replay_keyboard_callbacks} = { step_back => $step_back };

    $rc->start(40);
    $chart->_replay_shift_left_key();
    is($rc->current_index(), 39, '0051: Shift+Left retrocede replay activo (step_back real)');

    $rc->exit();
    $chart->set_replay_select_mode(1);
    $chart->{_selected_bar} = 50;
    $chart->{replay_keyboard_callbacks}{step_back} = sub { die 'step_back no debe llamarse en select' };
    $chart->_replay_shift_left_key();
    is($chart->selected_bar(), 49, '0051: Shift+Left mueve seleccion en Select Bar');

    my $wm_on = 1;
    my $mark_panel = bless {}, 'Market::UI::ReplayPanel';
    my $mark_text;
    no warnings 'redefine';
    *Market::UI::ReplayPanel::sync_mark_button = sub {
        my ($self, $on) = @_;
        $mark_text = $on ? 'Mark: on' : 'Mark: off';
        return $self;
    };
    my %vars = (
        replay_watermark_on => \$wm_on,
        replay_panel        => \$mark_panel,
    );
    my $toggle_wm = Market::UI::Callbacks->make_replay_toggle_watermark($chart, \%vars);
    ok(ref($toggle_wm) eq 'CODE', '0051: make_replay_toggle_watermark es CODE');
    $toggle_wm->();
    is($wm_on, 0, '0051: toggle watermark apaga flag');
    is($mark_text, 'Mark: off', '0051: toggle sincroniza texto Mark');
    $toggle_wm->();
    is($wm_on, 1, '0051: toggle watermark enciende flag');

    $rc->start(40);
    $chart->{replay_keyboard_callbacks}{toggle_watermark} = $toggle_wm;
    $chart->_replay_key_m('price');
    is($wm_on, 0, '0051: tecla M en replay conmuta marca');

    $rc->exit();
    ok($chart->{is_auto_scale}, '0051: escala auto antes de M fuera replay');
    $chart->_replay_key_m('price');
    ok(!$chart->{is_auto_scale}, '0051: M fuera replay pone escala manual precio');

    $rc->start(50);
    my $replay_on = 1;
    %vars = ( replay_on => \$replay_on );
    $chart->{replay_keyboard_callbacks}{exit} =
        Market::UI::Callbacks->make_replay_exit($chart, \%vars);
    $chart->_replay_escape_key();
    ok(!$rc->is_active(), '0051: Escape sale del replay (is_active==0)');
    is($replay_on, 0, '0051: Escape marca replay_on=0');
}

{
    package StubCursorCanvas;
    sub configure { my ($s, %o) = @_; $s->{cursor} = $o{-cursor} if exists $o{-cursor}; return $s }
    sub cget { my ($s, $k) = @_; return $s->{cursor} if $k eq '-cursor'; return }
    sub after { return }
}

# =============================================================================
# Test 21 (UX): Escape en Select Bar (sin replay activo) + pestaña Capas.
# =============================================================================
{
    use Market::ChartEngine;

    my $md = MockMarketData->new(100);
    my $rc = Market::ReplayController->new(market_data => $md);
    my $chart = bless {
        market_data       => $md,
        replay_controller => $rc,
        visible_bars      => 20,
        _replay_select_mode => 0,
        price_canvas      => bless({ cursor => 'crosshair' }, 'StubCursorCanvas'),
        atr_canvas        => bless({ cursor => 'crosshair' }, 'StubCursorCanvas'),
    }, 'Market::ChartEngine';

    my $replay_on = 1;
    my $replay_select_mode = 1;
    my $active_tab = 'Replay';
    my %vars = (
        replay_on          => \$replay_on,
        replay_select_mode => \$replay_select_mode,
        show_default_tab   => sub { $active_tab = 'Capas' },
    );
    $chart->set_replay_select_mode(1);
    $chart->{replay_keyboard_callbacks}{exit} =
        Market::UI::Callbacks->make_replay_exit($chart, \%vars);
    $chart->_replay_escape_key();
    ok(!$chart->is_replay_select_mode(), 'UX: Escape en select bar apaga modo tijeras');
    ok(!$rc->is_active(), 'UX: Escape en select bar no deja replay activo');
    is($replay_on, 0, 'UX: Escape en select bar marca replay_on=0');
    is($replay_select_mode, 0, 'UX: Escape sincroniza replay_select_mode=0');
    is($active_tab, 'Capas', 'UX: Escape vuelve a pestaña Capas');
}

# =============================================================================
# Test 20 (task 0052): atajos replay via bind all en ventana (no solo handler directo).
# =============================================================================
{
    use Market::ChartEngine;

    {
        package MockBindMW;
        sub new { bless { binds => {} }, shift }
        sub bind {
            my ($self, $target, $seq, $cb) = @_;
            return unless !ref($target) && $target eq 'all';
            $self->{binds}{$seq} = $cb;
            return;
        }
    }

    my $md    = MockMarketData->new(100);
    my $rc    = Market::ReplayController->new(market_data => $md);
    my $chart = bless {
        market_data       => $md,
        replay_controller => $rc,
        visible_bars      => 20,
        price_canvas      => bless({}, 'StubAfterCanvas'),
        ctrl_zoom_x_shift => 0,
        offset            => 0,
    }, 'Market::ChartEngine';

    my $mw = MockBindMW->new();
    $chart->bind_replay_window_shortcuts($mw);

    my @seqs = @{ $chart->replay_window_shortcut_sequences() };
    ok((grep { $_ eq '<Shift-Down>' } @seqs), '0052: bind all Shift-Down en ventana');
    ok((grep { $_ eq '<Key-m>' } @seqs), '0052: bind all Key-m en ventana');
    ok(ref($mw->{binds}{'<Shift-Down>'}) eq 'CODE', '0052: callback ventana es CODE');

    $rc->start(40);
    my $mw2 = MockMW->new();
    $chart->{replay_keyboard_callbacks}{toggle_play} =
        Market::UI::Callbacks->make_replay_toggle_play($chart, $mw2, {});
    $mw->{binds}{'<Shift-Down>'}->();
    ok($rc->{playing}, '0052: Shift+Down via bind ventana arranca play');
}

done_testing();
