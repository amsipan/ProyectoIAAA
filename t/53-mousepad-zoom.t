#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib '.';

use Market::ChartEngine;

# Interacción mousepad/zoom estilo TradingView:
# - Zoom con ancla de cursor NUNCA agranda el hueco en blanco de un borde
#   (la última vela se clava al borde derecho al hacer zoom-out).
# - Rueda simple: borde derecho conservado (caracterización existente).
# - Pan por touchpad (Button-6/7): mueve offset/view_end en la dirección
#   correcta, con clamps.

{
    package ZoomTPMD;
    sub new { my ( $c, $n ) = @_; bless { n => $n }, $c }
    sub size { $_[0]{n} }
    sub last_index { $_[0]{n} - 1 }
}

my $TOTAL = 18658;
my $W     = 1400;

sub make_engine {
    my (%o) = @_;
    return bless {
        market_data          => ZoomTPMD->new( $o{total} // $TOTAL ),
        replay_controller    => $o{rc},
        visible_bars         => $o{visible} // 60,
        offset               => $o{offset}  // 0,
        ctrl_zoom_x_shift    => 0,
        price_canvas         => undef,
        render_pending       => 0,
        _last_price_canvas_w => $W,
        replay_view_end      => $o{replay_view_end},
    }, 'Market::ChartEngine';
}

no warnings 'redefine';
local *Market::ChartEngine::request_render = sub { $_[0] };
local *Market::ChartEngine::_canvas_width  = sub {$W};

my $ZSTEP = Market::ChartEngine::ZOOM_STEP();

sub zoom_out_anchor {
    my ( $eng, $anchor_x, $max ) = @_;
    for my $i ( 1 .. ( $max // 120 ) ) {
        my $delta = $eng->_wheel_zoom_delta($ZSTEP);
        last if $delta == 0;
        $eng->_ctrl_horizontal_zoom( $delta, $anchor_x );
    }
    return $eng;
}

# --- TV: zoom-out con ancla de cursor clava la última vela al borde ---
for my $case ( [ 'ancla_der', 1350 ], [ 'ancla_ctr', 700 ], [ 'ancla_izq', 60 ] )
{
    my ( $tag, $ax ) = @$case;
    my $eng = make_engine( visible => 60, offset => 0 );
    my $worst_blank = 0;
    for my $i ( 1 .. 120 ) {
        my $delta = $eng->_wheel_zoom_delta($ZSTEP);
        last if $delta == 0;
        $eng->_ctrl_horizontal_zoom( $delta, $ax );
        my ( $s, $e ) = $eng->compute_window();
        my $blank = $e - ( $TOTAL - 1 );
        $worst_blank = $blank if $blank > $worst_blank;
    }
    is( $worst_blank, 0, "zoom-out $tag: nunca hueco a la derecha" );
    my ( $s, $e ) = $eng->compute_window();
    is( $e, $TOTAL - 1, "zoom-out $tag: última vela clavada al tope" );
}

# --- Desde zoom-in máximo (visible=2): mismo contrato ---
{
    my $eng = make_engine( visible => 2, offset => 0 );
    zoom_out_anchor( $eng, 1350 );
    my ( $s, $e ) = $eng->compute_window();
    is( $e, $TOTAL - 1, 'desde visible=2: última vela clavada al tope' );
    is( $eng->{offset}, 0, 'desde visible=2: offset=0' );
}

# --- Hueco previo por pan (offset<0): el zoom NUNCA lo agranda ---
{
    my $eng = make_engine( visible => 60, offset => -30 );
    my $prev_blank = 30;
    my $worst = $prev_blank;
    for my $i ( 1 .. 120 ) {
        my $delta = $eng->_wheel_zoom_delta($ZSTEP);
        last if $delta == 0;
        $eng->_ctrl_horizontal_zoom( $delta, 700 );
        $worst = -$eng->{offset} if -$eng->{offset} > $worst;
    }
    ok( $worst <= $prev_blank, "hueco por pan previo no crece con zoom-out ($worst <= $prev_blank)" );
}

# --- Caracterización: rueda simple conserva borde derecho ---
{
    my $eng = make_engine( visible => 60, offset => 0 );
    for my $i ( 1 .. 120 ) {
        my $delta = $eng->_wheel_zoom_delta($ZSTEP);
        last if $delta == 0;
        $eng->_horizontal_zoom( $delta, undef );
    }
    is( $eng->{offset}, 0, 'rueda simple: offset=0 tras zoom-out total' );
    my ( $s, $e ) = $eng->compute_window();
    is( $e, $TOTAL - 1, 'rueda simple: end = última vela' );
}

# --- Zoom-in con ancla tras zoom-out: sin estados absurdos ---
{
    my $eng = make_engine( visible => 60, offset => 0 );
    zoom_out_anchor( $eng, 700 );
    for my $i ( 1 .. 60 ) {
        my $delta = $eng->_wheel_zoom_delta( -$ZSTEP );
        last if $delta == 0;
        $eng->_ctrl_horizontal_zoom( $delta, 700 );
        my ( $s, $e ) = $eng->compute_window();
        ok( $e <= $TOTAL - 1, "zoom-in n=$i: sin hueco derecho nuevo" ) if $e > $TOTAL - 1;
    }
    my ( $s, $e ) = $eng->compute_window();
    ok( $e <= $TOTAL - 1, 'zoom-in tras zoom-out: end nunca supera la última vela' );
    cmp_ok( $eng->{visible_bars}, '>=', Market::ChartEngine::MIN_VISIBLE_BARS(), 'visible >= MIN' );
}

# --- Pan touchpad: swipe derecha = ver pasado (offset sube), con clamps ---
{
    my $eng = make_engine( visible => 60, offset => 0 );
    $eng->_touchpad_hpan(1) for 1 .. 5;    # swipe derecha repetido
    cmp_ok( $eng->{offset}, '>', 0, 'pan swipe derecha: offset aumenta (pasado)' );
    my $off = $eng->{offset};
    $eng->_touchpad_hpan(-1) for 1 .. 10;  # swipe izquierda
    cmp_ok( $eng->{offset}, '<', $off, 'pan swipe izquierda: offset baja (futuro)' );
    $eng->_touchpad_hpan(-1) for 1 .. 200; # saturar hacia el futuro
    my $min_off = $eng->_min_offset_for_visible();
    cmp_ok( $eng->{offset}, '>=', $min_off, 'pan futuro: clamp en min_offset' );
    $eng->_touchpad_hpan(1) for 1 .. 5000; # saturar hacia el pasado
    my $max_off = $eng->_max_offset_for_visible();
    cmp_ok( $eng->{offset}, '<=', $max_off, 'pan pasado: clamp en max_offset' );
}

# --- Pan touchpad en Replay: gobernado por replay_view_end ---
{
    my $rc = bless {
        active => 1,
        idx    => 500,
    }, 'ZoomTPRC';
    {
        package ZoomTPRC;
        sub is_active { $_[0]{active} }
        sub effective_end { $_[0]{idx} }
        sub current_index { $_[0]{idx} }
        sub closed_index  { $_[0]{idx} }
    }
    my $eng = make_engine(
        visible => 60, offset => 0, rc => $rc, replay_view_end => 515 );
    $eng->_touchpad_hpan(1) for 1 .. 4;
    cmp_ok( $eng->{replay_view_end}, '<', 515, 'replay pan swipe derecha: view_end baja (pasado)' );
    $eng->_touchpad_hpan(-1) for 1 .. 8;
    cmp_ok( $eng->{replay_view_end}, '>=', 0, 'replay pan: view_end acotado' );
}

done_testing();
