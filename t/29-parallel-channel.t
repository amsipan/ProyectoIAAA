#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib '.';

use Market::Drawing::ParallelChannel;

{
    my $d = Market::Drawing::ParallelChannel->new( extend_right => 1 );
    ok( !$d->is_tool_active, 'tool off al crear' );
    $d->start_tool();
    ok( $d->is_tool_active, 'tool on' );

    is( $d->add_point( { index => 10, price => 100 } ), 'draft', 'punto 1' );
    is( $d->add_point( { index => 20, price => 110 } ), 'draft', 'punto 2' );
    is( $d->add_point( { index => 15, price => 90 } ),  'done',  'punto 3 cierra canal' );
    ok( !$d->is_tool_active, 'tool off tras 3 puntos' );

    my $ch = $d->get_channel();
    ok( $ch, 'canal creado' );
    ok( $d->slopes_equal($ch), 'L0 y L1 paralelas (offset constante)' );

    my $geo = $d->geometry_for( $ch, data_end => 50 );
    ok( $geo, 'geometry_for' );
    is( $geo->{i_max}, 50, 'extend_right hasta data_end' );
    ok( abs( $geo->{m} - 1 ) < 1e-9, 'pendiente m=(110-100)/(20-10)=1' );
}

{
    my $d = Market::Drawing::ParallelChannel->new();
    $d->start_tool();
    $d->add_point( { index => 0,  price => 0 } );
    $d->add_point( { index => 10, price => 10 } );
    $d->add_point( { index => 5,  price => 0 } );
    my $ch1 = $d->get_channel();
    $d->start_tool();
    $d->add_point( { index => 1,  price => 1 } );
    $d->add_point( { index => 11, price => 11 } );
    $d->add_point( { index => 6,  price => 1 } );
    my $ch2 = $d->get_channel();
    isnt( $ch1->{p1}{index}, $ch2->{p1}{index}, 'segundo canal reemplaza al primero (1 activo)' );
}

{
    my $d = Market::Drawing::ParallelChannel->new();
    $d->start_tool();
    $d->add_point( { index => 0, price => 100 } );
    $d->cancel_tool();
    ok( !$d->is_tool_active, 'cancel limpia tool' );
    is( $d->draft_count(), 0, 'draft vacío' );
    $d->start_tool();
    $d->add_point( { index => 0,  price => 100 } );
    $d->add_point( { index => 10, price => 100 } );
    $d->add_point( { index => 5,  price => 90 } );
    $d->clear_channel();
    ok( !defined $d->get_channel(), 'clear_channel' );
}

{
    # Overlay contract
    require Market::Overlays::ParallelChannel;
    my $d  = Market::Drawing::ParallelChannel->new();
    my $ov = Market::Overlays::ParallelChannel->new( drawing => $d, visible => 1 );
    is( $ov->tag(), 'draw_pchan', 'tag aislado de SMC' );
    ok( $ov->is_visible, 'visible' );
}

done_testing();
