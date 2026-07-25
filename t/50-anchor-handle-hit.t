#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib '.';

use Market::ChartEngine;
use Market::Panels::Scales;

# Escala de precio mínima para value_to_y (y=0 → max, y=height → min).
my $yscale = Market::Panels::Scales->new( min_y => 100, max_y => 200, bars => 10 );
$yscale->{width}  = 200;
$yscale->{height} = 100;

my $chart = bless {
    price_canvas         => undef,
    ctrl_zoom_x_shift    => 0,
    _last_price_scale    => $yscale,
}, 'Market::ChartEngine';

no warnings 'redefine';
*Market::ChartEngine::compute_window = sub { return ( 0, 9 ) };
*Market::ChartEngine::_current_right_margin = sub { 0 };
*Market::ChartEngine::_canvas_width = sub { 200 };

# Ancla en índice 5 → centro X = 5*20 + 10 = 110; precio 150 → y medio = 50
my $ax = 110;
my $ay = $yscale->value_to_y(150);

ok( $chart->_anchor_handle_hit( $ax, $ay, 5, 150 ),
    'hit en el centro del handle' );
ok( $chart->_anchor_handle_hit( $ax + 5, $ay + 5, 5, 150 ),
    'hit dentro del radio (~8px)' );
ok( !$chart->_anchor_handle_hit( $ax, $ay + 40, 5, 150 ),
    'NO hit: misma X pero Y lejos (antes era columna vertical)' );
ok( !$chart->_anchor_handle_hit( $ax + 30, $ay, 5, 150 ),
    'NO hit: X fuera del círculo' );
ok( !$chart->_anchor_handle_hit( $ax, $ay, 5, undef ),
    'NO hit sin precio' );

done_testing();
