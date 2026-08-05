#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib '.';

use Market::ChartEngine;

# Paridad de interacción en Replay respecto al modo normal:
# - Zoom con ancla (Ctrl+rueda / pinch) aplica el mismo pin de bordes: nunca
#   crea hueco a la derecha del head y el zoom-out total lo deja clavado.
# - Rueda simple conserva el borde derecho (replay_view_end intacto).
# - reset_view vuelve a auto y lo notifica a los callbacks de la UI.

{
    package ZoomParMD;
    sub new { my ( $c, $n ) = @_; bless { n => $n }, $c }
    sub size { $_[0]{n} }
    sub last_index { $_[0]{n} - 1 }
}
{
    package ZoomParRC;
    sub is_active     { $_[0]{active} }
    sub effective_end { $_[0]{idx} }
    sub current_index { $_[0]{idx} }
    sub closed_index  { $_[0]{idx} }
}

my $TOTAL   = 18658;
my $W       = 1400;
my $CAUSAL  = 500;

sub make_engine {
    my (%o) = @_;
    return bless {
        market_data             => ZoomParMD->new( $o{total} // $TOTAL ),
        replay_controller       => bless( { active => 1, idx => ( $o{causal} // $CAUSAL ) }, 'ZoomParRC' ),
        visible_bars            => $o{visible} // 60,
        offset                  => 0,
        ctrl_zoom_x_shift       => 0,
        is_auto_scale           => 1,
        price_canvas            => undef,
        render_pending          => 0,
        _last_price_canvas_w    => $W,
        replay_view_end         => $o{view_end},
        scale_mode_callback     => $o{scale_cb},
        atr_scale_mode_callback => $o{atr_cb},
    }, 'Market::ChartEngine';
}

no warnings 'redefine';
local *Market::ChartEngine::request_render = sub { $_[0] };
local *Market::ChartEngine::_canvas_width  = sub {$W};

my $ZSTEP = Market::ChartEngine::ZOOM_STEP();

# --- Replay Ctrl+zoom-out: nunca hueco a la derecha del head ---
for my $case ( [ 'ancla_der', 1350 ], [ 'ancla_ctr', 700 ], [ 'ancla_izq', 60 ] ) {
    my ( $tag, $ax ) = @$case;
    my $eng = make_engine( visible => 60, view_end => $CAUSAL );
    my $worst_blank = 0;
    for my $i ( 1 .. 120 ) {
        my $delta = $eng->_wheel_zoom_delta($ZSTEP);
        last if $delta == 0;
        $eng->_ctrl_horizontal_zoom( $delta, $ax );
        my ( undef, $e ) = $eng->compute_window();
        my $blank = $e - $CAUSAL;
        $worst_blank = $blank if $blank > $worst_blank;
    }
    is( $worst_blank, 0, "replay zoom-out $tag: nunca hueco a la derecha del head" );
    my ( undef, $e ) = $eng->compute_window();
    is( $e, $CAUSAL, "replay zoom-out $tag: head clavado al borde derecho" );
}

# --- Hueco previo (Select Bar / pan): el zoom nunca lo agranda ---
{
    my $eng = make_engine( visible => 60, view_end => $CAUSAL + 12 );
    my $worst = 12;
    for my $i ( 1 .. 120 ) {
        my $delta = $eng->_wheel_zoom_delta($ZSTEP);
        last if $delta == 0;
        $eng->_ctrl_horizontal_zoom( $delta, 700 );
        my ( undef, $e ) = $eng->compute_window();
        my $blank = $e - $CAUSAL;
        $worst = $blank if $blank > $worst;
    }
    ok( $worst <= 12, "replay zoom-out: hueco previo no crece ($worst <= 12)" );
    my ( undef, $e ) = $eng->compute_window();
    is( $e, $CAUSAL + 12, 'replay zoom-out total: hueco previo conservado' );
}

# --- Rueda simple en Replay: el borde derecho no se mueve ---
{
    my $eng = make_engine( visible => 60, view_end => $CAUSAL );
    my $moved = 0;
    for my $i ( 1 .. 120 ) {
        my $delta = $eng->_wheel_zoom_delta($ZSTEP);
        last if $delta == 0;
        $eng->_horizontal_zoom( $delta, undef );
        $moved++ if $eng->{replay_view_end} != $CAUSAL;
    }
    is( $moved, 0, 'rueda simple replay: view_end nunca se mueve con zoom-out' );
    is( $eng->{visible_bars}, Market::ChartEngine::MAX_VISIBLE_BARS(), 'rueda simple replay: zoom-out llegó al tope' );
    $moved = 0;
    for my $i ( 1 .. 200 ) {
        my $delta = $eng->_wheel_zoom_delta(-$ZSTEP);
        last if $delta == 0;
        $eng->_horizontal_zoom( $delta, undef );
        $moved++ if $eng->{replay_view_end} != $CAUSAL;
    }
    is( $moved, 0, 'rueda simple replay: view_end nunca se mueve con zoom-in' );
}

# --- Zoom-in con ancla tras zoom-out total: sin hueco derecho nuevo ---
{
    my $eng = make_engine( visible => 60, view_end => $CAUSAL );
    for my $i ( 1 .. 120 ) {
        my $delta = $eng->_wheel_zoom_delta($ZSTEP);
        last if $delta == 0;
        $eng->_ctrl_horizontal_zoom( $delta, 700 );
    }
    my $worst = 0;
    for my $i ( 1 .. 200 ) {
        my $delta = $eng->_wheel_zoom_delta(-$ZSTEP);
        last if $delta == 0;
        $eng->_ctrl_horizontal_zoom( $delta, 700 );
        my ( undef, $e ) = $eng->compute_window();
        my $blank = $e - $CAUSAL;
        $worst = $blank if $blank > $worst;
    }
    is( $worst, 0, 'replay zoom-in tras zoom-out: nunca hueco a la derecha del head' );
}

# --- reset_view: vuelve a auto y la UI se entera por ambos callbacks ---
{
    my @price_modes;
    my @atr_modes;
    my $eng = make_engine(
        view_end => $CAUSAL,
        scale_cb => sub { push @price_modes, $_[0] },
        atr_cb   => sub { push @atr_modes, $_[0] },
    );
    $eng->{is_auto_scale}     = 0;
    $eng->{manual_min_y}      = 100;
    $eng->{manual_max_y}      = 200;
    $eng->{is_atr_auto_scale} = 0;
    $eng->reset_view();
    is( $eng->{is_auto_scale}, 1, 'reset_view: escala de precio vuelve a auto' );
    is( $eng->{is_atr_auto_scale}, 1, 'reset_view: escala ATR vuelve a auto' );
    is_deeply( \@price_modes, ['auto'], 'reset_view: callback precio notifica auto (botón UI)' );
    is_deeply( \@atr_modes, ['auto'], 'reset_view: callback ATR notifica auto' );
    ok( !defined $eng->{manual_min_y}, 'reset_view: rango manual limpio' );
}

done_testing();
