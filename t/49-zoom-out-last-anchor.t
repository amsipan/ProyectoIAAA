#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib '.';

use Market::ChartEngine;

{
    package ZoomAnchorMD;
    sub new {
        my ( $class, $n ) = @_;
        return bless { n => $n }, $class;
    }
    sub size { $_[0]{n} }
    sub last_index { $_[0]{n} - 1 }
}

# Zoom-out con rueda (sin Ctrl): si había hueco derecho (offset<0),
# debe volver a offset=0 para fijar la última vela al borde.
{
    my $md = ZoomAnchorMD->new(500);
    my $eng = bless {
        market_data         => $md,
        replay_controller   => undef,
        visible_bars        => 60,
        offset              => -10,    # hueco “futuro” a la derecha
        ctrl_zoom_x_shift   => 0,
        price_canvas        => undef,
        render_pending      => 0,
    }, 'Market::ChartEngine';

    no warnings 'redefine';
    local *Market::ChartEngine::request_render = sub {
        my ($self) = @_;
        $self->{render_pending} = 0;
        return $self;
    };
    local *Market::ChartEngine::_canvas_width = sub { 800 };

    $eng->_horizontal_zoom( 20, undef );    # zoom-out, ancla última vela
    is( $eng->{offset}, 0, 'zoom-out rueda: offset vuelve a 0 (última vela al borde)' );
    is( $eng->{visible_bars}, 80, 'zoom-out rueda: visible_bars aumenta' );
}

{
    my $md = ZoomAnchorMD->new(500);
    my $eng = bless {
        market_data       => $md,
        replay_controller => undef,
        visible_bars      => 60,
        offset            => 0,
        ctrl_zoom_x_shift => 0,
        price_canvas      => undef,
        render_pending    => 0,
    }, 'Market::ChartEngine';

    no warnings 'redefine';
    local *Market::ChartEngine::request_render = sub { $_[0] };
    local *Market::ChartEngine::_canvas_width = sub { 800 };

    $eng->_horizontal_zoom( 50, undef );
    is( $eng->{offset}, 0, 'zoom-out desde offset 0: sigue en 0' );
}

# En medio del historial: rueda sin Ctrl conserva offset (misma end).
{
    my $md = ZoomAnchorMD->new(500);
    my $eng = bless {
        market_data       => $md,
        replay_controller => undef,
        visible_bars      => 60,
        offset            => 120,
        ctrl_zoom_x_shift => 3,
        price_canvas      => undef,
        render_pending    => 0,
    }, 'Market::ChartEngine';

    no warnings 'redefine';
    local *Market::ChartEngine::request_render = sub { $_[0] };
    local *Market::ChartEngine::_canvas_width = sub { 800 };

    $eng->_horizontal_zoom( 40, undef );
    is( $eng->{offset}, 120, 'zoom-out en medio: offset (end) se conserva' );
    is( $eng->{visible_bars}, 100, 'zoom-out en medio: visible_bars aumenta' );
    is( $eng->{ctrl_zoom_x_shift}, 0, 'zoom-out en medio: limpia x_shift' );
}

done_testing();
