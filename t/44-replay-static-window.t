#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib '.';

use Market::ChartEngine;
use Market::ReplayController;

# =============================================================================
# t/44 — Replay robusto: "velas estaticas siempre que sea posible".
#
# Modelo: replay_view_end (borde derecho LOGICO absoluto) es la unica fuente de
# verdad del viewport durante Replay. Auto-scroll por deteccion de borde
# (replay_prev_causal_end): la vista solo se desplaza cuando el head estaba
# EXACTAMENTE en el borde derecho y avanzo. Clamp min-visible siempre.
#
# Cubre los casos de fallo reportados:
#   A. Play con hueco -> velas estaticas, relleno del hueco, luego scroll.
#   B. Pausa + paneo + Play -> NO se desplaza todo el grafico.
#   C. Zoom out -> no rompe el estado; sigue estatico.
#   D. Retroceso (step_backward) -> conserva >= 2 velas reales en pantalla.
#   E. Salir y reentrar a Replay -> estado limpio, comportamiento correcto.
# =============================================================================

{
    package MiniMD;
    sub new { my ($c, $n) = @_; bless { n => $n }, $c }
    sub size { shift->{n} }
    sub get_candle {
        my ($s, $i) = @_;
        return undef if $i < 0 || $i >= $s->{n};
        return [ sprintf('2026-04-01T00:%02d:00-05:00', $i % 60),
                 100 + $i, 110 + $i, 95 + $i, 105 + $i, 100 ];
    }
    sub get_slice {
        my ($s, $from, $to) = @_;
        return [ map { $s->get_candle($_) } $from .. $to ];
    }
}

sub new_chart {
    my (%a) = @_;
    my $md = MiniMD->new($a{n} // 1000);
    my $rc = Market::ReplayController->new(market_data => $md);
    my $chart = bless {
        market_data       => $md,
        replay_controller => $rc,
        visible_bars      => $a{visible} // 60,
        offset            => 0,
        ctrl_zoom_x_shift => 0,
    }, 'Market::ChartEngine';
    return ($chart, $rc, $md);
}

# ---------------------------------------------------------------------------
# A. Play con hueco: velas estaticas -> relleno del hueco -> scroll al llegar.
# ---------------------------------------------------------------------------
{
    my ($chart, $rc) = new_chart(visible => 60, n => 1000);
    # Selecciona vela 500 con anchor (hueco a la derecha estilo Select Bar).
    $chart->frame_replay_view_at(500, { anchor => 1 });
    $rc->start(500);
    $chart->mark_replay_play_start();

    my ($s0, $e0) = $chart->compute_window();
    ok($e0 > 500, 'A: hay hueco a la derecha del head al iniciar play');
    my $frozen_end = $e0;

    # Avanza varias velas dentro del hueco: el borde NO se mueve (estatico).
    for my $step (1 .. 5) {
        $rc->step_forward();
        my ($s, $e) = $chart->compute_window();
        is($e, $frozen_end, "A: tick $step no mueve el borde (velas estaticas)");
        is($s, $s0, "A: tick $step no mueve el inicio (nada se desplaza)");
    }

    # Salta el head hasta el borde y una mas: ahora si debe seguir (scroll).
    $rc->{replay_idx} = $frozen_end;   # head llega al borde
    my ($sa, $ea) = $chart->compute_window();
    is($ea, $frozen_end, 'A: head en el borde, aun sin desplazar');
    $rc->step_forward();               # head supera el borde
    my ($sb, $eb) = $chart->compute_window();
    is($eb, $frozen_end + 1, 'A: al superar el borde la vista sigue al head');
    is($eb - $sb + 1, 60, 'A: el viewport conserva visible_bars al desplazar');
}

# ---------------------------------------------------------------------------
# B. Pausa + paneo + Play: NO se desplaza todo el grafico.
#    (El bug original: al re-dar play todo el grafico scrolleaba cada tick.)
# ---------------------------------------------------------------------------
{
    my ($chart, $rc) = new_chart(visible => 60, n => 1000);
    $chart->frame_replay_view_at(500, { anchor => 1 });
    $rc->start(500);
    $chart->mark_replay_play_start();

    # Simula paneo al pasado: el usuario mueve la vista atras (view_end baja).
    $chart->{replay_view_end} = 520;   # antes estaba ~511; ahora mira mas atras
    my ($sp, $ep) = $chart->compute_window();
    is($ep, 520, 'B: tras panear, el borde queda donde lo dejo el usuario');

    # Re-Play y avanza: como el head (500) NO esta en el borde (520), estatico.
    $chart->mark_replay_play_start();
    for my $step (1 .. 4) {
        $rc->step_forward();
        my ($s, $e) = $chart->compute_window();
        is($e, 520, "B: tick $step NO desplaza el grafico (head lejos del borde)");
    }
}

# ---------------------------------------------------------------------------
# C. Zoom out durante replay estatico: no rompe; sigue estatico.
# ---------------------------------------------------------------------------
{
    my ($chart, $rc) = new_chart(visible => 60, n => 1000);
    $chart->frame_replay_view_at(500, { anchor => 1 });
    $rc->start(500);
    $chart->mark_replay_play_start();
    my ($s0, $e0) = $chart->compute_window();

    # Zoom out simulado (mas velas visibles) conservando el borde absoluto.
    $chart->{visible_bars} = 200;
    my ($sz, $ez) = $chart->compute_window();
    is($ez, $e0, 'C: zoom out conserva el borde derecho absoluto');
    is($ez - $sz + 1, 200, 'C: zoom out aplica el nuevo visible_bars');

    # Avanzar sigue siendo estatico (head no estaba en el borde).
    $rc->step_forward();
    my ($s1, $e1) = $chart->compute_window();
    is($e1, $e0, 'C: tras zoom out, avanzar no desplaza el grafico');
}

# ---------------------------------------------------------------------------
# D. Retroceso: conserva >= MIN_VISIBLE_BARS velas reales en pantalla.
#    (El bug original: al retroceder el head se alejaba fuera del marco.)
# ---------------------------------------------------------------------------
{
    my ($chart, $rc) = new_chart(visible => 60, n => 1000);
    $chart->frame_replay_view_at(500);   # head pegado al borde
    $rc->start(500);
    $chart->mark_replay_play_start();

    # Retrocede muchas velas: el head baja; el viewport debe seguirlo para no
    # dejarlo salir por la derecha (siempre >= 2 velas reales visibles).
    for my $i (1 .. 400) { $rc->step_backward(); }
    my $head = $rc->current_index();
    my ($s, $e) = $chart->compute_window();
    my $causal = $chart->_causal_end();
    is($causal, $head, 'D: tope causal sigue al head tras retroceder');
    ok($e >= $s, 'D: viewport valido tras retroceso profundo');
    # Velas reales visibles = indices [max(s,0) .. min(e,causal)].
    my $real_from = $s < 0 ? 0 : $s;
    my $real_to   = $e < $causal ? $e : $causal;
    my $real_vis  = $real_to - $real_from + 1;
    ok($real_vis >= 2, "D: al menos 2 velas reales visibles (hay $real_vis)");
    ok($head <= $e, 'D: el head nunca queda fuera del marco por la derecha');
}

# ---------------------------------------------------------------------------
# D2. Retroceso hasta el inicio: no hay hueco en blanco a la izquierda.
# ---------------------------------------------------------------------------
{
    my ($chart, $rc) = new_chart(visible => 60, n => 1000);
    $chart->frame_replay_view_at(500);
    $rc->start(500);
    $chart->mark_replay_play_start();
    for my $i (1 .. 500) { $rc->step_backward(); }   # head -> 0
    my ($s, $e) = $chart->compute_window();
    ok($s >= 0, 'D2: sin hueco en blanco a la izquierda al llegar al inicio');
}

# ---------------------------------------------------------------------------
# E. Salir y reentrar: estado limpio; el segundo ciclo funciona igual.
# ---------------------------------------------------------------------------
{
    my ($chart, $rc) = new_chart(visible => 60, n => 1000);
    $chart->frame_replay_view_at(500, { anchor => 1 });
    $rc->start(500);
    $chart->mark_replay_play_start();
    $rc->step_forward() for 1 .. 3;

    # Salir de replay: estado absoluto debe quedar limpio.
    $rc->exit();
    $chart->restore_after_replay_exit();
    ok(!defined $chart->{replay_view_end}, 'E: replay_view_end limpio al salir');
    ok(!defined $chart->{replay_prev_causal_end}, 'E: edge-tracker limpio al salir');

    # Reentrar: segundo ciclo se comporta estatico igual que el primero.
    $chart->frame_replay_view_at(300, { anchor => 1 });
    $rc->start(300);
    $chart->mark_replay_play_start();
    my ($s0, $e0) = $chart->compute_window();
    $rc->step_forward();
    my ($s1, $e1) = $chart->compute_window();
    is($e1, $e0, 'E: segundo ciclo tambien mantiene velas estaticas');
}

# ---------------------------------------------------------------------------
# F. Causalidad intacta: el borde nunca obliga a leer velas futuras.
# ---------------------------------------------------------------------------
{
    my ($chart, $rc) = new_chart(visible => 60, n => 1000);
    $chart->frame_replay_view_at(500, { anchor => 1 });
    $rc->start(500);
    $chart->mark_replay_play_start();
    my ($s, $e) = $chart->compute_window();
    is($chart->_causal_end(), 500, 'F: tope causal = replay_idx (sin fuga futuro)');
    ok($e > $chart->_causal_end(), 'F: el hueco derecho son slots logicos vacios');
}

done_testing;
