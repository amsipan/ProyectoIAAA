#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib '.';

use Market::Drawing::TrendLine;
use Market::Overlays::TrendLine;

# ---------------------------------------------------------------------------
# 1. Contrato básico del drawing + overlay
# ---------------------------------------------------------------------------
{
    my $d = Market::Drawing::TrendLine->new();
    ok( $d, 'Instanciación del drawing TrendLine ok' );
    ok( !$d->is_tool_active(), 'tool inactivo por defecto' );
    is( $d->line_count(), 0, 'sin líneas al inicio' );

    my $ov = Market::Overlays::TrendLine->new( drawing => $d, visible => 0 );
    ok( $ov, 'Instanciación del overlay ok' );
    is( $ov->tag(), 'draw_trend', 'tag correcto' );
    ok( !$ov->is_visible(), 'oculto por defecto' );
    $ov->set_visible(1);
    ok( $ov->is_visible(), 'visibilidad activable' );
}

# ---------------------------------------------------------------------------
# 2. Colocar una línea con 2 clics
# ---------------------------------------------------------------------------
{
    my $d = Market::Drawing::TrendLine->new();
    $d->start_tool();
    ok( $d->is_tool_active(), 'start_tool activa el modo' );

    is( $d->add_point( { index => 10, price => 100 } ), 'draft', '1.er clic → draft' );
    is( $d->draft_count(), 1, 'draft tiene 1 punto' );
    is( $d->add_point( { index => 20, price => 110 } ), 'done', '2.º clic → done (commit)' );
    is( $d->line_count(), 1, 'se creó 1 línea' );
    is( $d->draft_count(), 0, 'draft vacío tras commit' );

    my $ln = $d->lines->[0];
    is( $ln->{p1}{index}, 10, 'p1 index' );
    is( $ln->{p1}{price}, 100, 'p1 price' );
    is( $ln->{p2}{index}, 20, 'p2 index' );
    is( $ln->{p2}{price}, 110, 'p2 price' );

    ok( !$d->is_tool_active(), 'tool se apaga tras commit (TV: 2 clics y sale del modo)' );
}

# ---------------------------------------------------------------------------
# 3. Varias líneas: hay que re-activar el tool por cada línea (estilo TV)
# ---------------------------------------------------------------------------
{
    my $d = Market::Drawing::TrendLine->new();
    $d->start_tool();
    $d->add_point( { index => 0,  price => 50 } );
    $d->add_point( { index => 5,  price => 60 } );   # commit → tool off
    is( $d->line_count(), 1, 'primera línea creada' );
    # sin re-activar, el siguiente clic se ignora
    is( $d->add_point( { index => 8, price => 55 } ), undef, 'clic ignorado con tool off' );
    is( $d->line_count(), 1, 'no se añadió línea sin re-activar' );
    # re-activar para la segunda línea
    $d->start_tool();
    $d->add_point( { index => 8,  price => 55 } );
    $d->add_point( { index => 12, price => 70 } );
    is( $d->line_count(), 2, 'segunda línea tras re-activar el tool' );
}

# ---------------------------------------------------------------------------
# 4. Mover un extremo (set_point)
# ---------------------------------------------------------------------------
{
    my $d = Market::Drawing::TrendLine->new();
    $d->start_tool();
    $d->add_point( { index => 10, price => 100 } );
    $d->add_point( { index => 20, price => 110 } );

    $d->set_point( 0, 'p2', { index => 25, price => 130 } );
    my $ln = $d->lines->[0];
    is( $ln->{p2}{index}, 25, 'p2 movido en índice' );
    is( $ln->{p2}{price}, 130, 'p2 movido en precio' );
    is( $ln->{p1}{index}, 10, 'p1 intacto' );

    # set_point sobre línea inexistente no revienta
    $d->set_point( 99, 'p1', { index => 1, price => 1 } );
    is( $d->line_count(), 1, 'set_point en índice inválido es no-op' );
}

# ---------------------------------------------------------------------------
# 5. Borrar última / todas
# ---------------------------------------------------------------------------
{
    my $d = Market::Drawing::TrendLine->new();
    $d->start_tool();
    $d->add_point( { index => 0, price => 1 } ); $d->add_point( { index => 1, price => 2 } );
    $d->start_tool();
    $d->add_point( { index => 2, price => 3 } ); $d->add_point( { index => 3, price => 4 } );
    is( $d->line_count(), 2, 'dos líneas colocadas' );

    $d->clear_last();
    is( $d->line_count(), 1, 'clear_last borra solo la última' );

    $d->clear_all();
    is( $d->line_count(), 0, 'clear_all borra todo' );
}

# ---------------------------------------------------------------------------
# 5b. move_line traslada ambos extremos por un delta (arrastrar el cuerpo)
# ---------------------------------------------------------------------------
{
    my $d = Market::Drawing::TrendLine->new();
    $d->start_tool();
    $d->add_point( { index => 10, price => 100 } );
    $d->add_point( { index => 20, price => 110 } );
    $d->move_line( 0, 5, -3 );
    my $ln = $d->lines->[0];
    is( $ln->{p1}{index}, 15, 'move_line: p1 index +5' );
    is( $ln->{p1}{price}, 97, 'move_line: p1 price -3' );
    is( $ln->{p2}{index}, 25, 'move_line: p2 index +5' );
    is( $ln->{p2}{price}, 107, 'move_line: p2 price -3' );
}

# ---------------------------------------------------------------------------
# 6. hit_test del overlay (mock de scales)
# ---------------------------------------------------------------------------
{
    package MockScale;
    sub new { bless {}, shift }
    # índice→x lineal (x = index*10), precio→y invertido (y = 500 - price)
    sub index_to_center_x { my ($s,$i)=@_; return $i*10; }
    sub value_to_y        { my ($s,$p)=@_; return 500 - $p; }
}
{
    my $d = Market::Drawing::TrendLine->new();
    $d->start_tool();
    $d->add_point( { index => 10, price => 100 } );  # x=100, y=400
    $d->add_point( { index => 20, price => 110 } );  # x=200, y=390
    my $ov = Market::Overlays::TrendLine->new( drawing => $d, visible => 1 );
    my $scale = MockScale->new();

    # win_start=0: clic justo sobre p1 (100,400)
    is( $ov->hit_test( 100, 400, $scale, 0 ), '0:p1', 'hit_test detecta p1' );
    is( $ov->hit_test( 200, 390, $scale, 0 ), '0:p2', 'hit_test detecta p2' );
    is( $ov->hit_test( 300, 300, $scale, 0 ), undef,  'hit_test lejos = undef' );
}

done_testing();
