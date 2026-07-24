use strict;
use warnings;
use Test::More;

use lib '.';
use Market::Drawing::FibRetracement;
use Market::Overlays::FibRetracement;

{
    package FibTestCanvas;
    sub new { bless { ops => [] }, shift }
    sub delete { my ( $s, @a ) = @_; push @{ $s->{ops} }, [ delete => @a ]; return }
    sub createLine {
        my ( $s, @a ) = @_;
        push @{ $s->{ops} }, [ createLine => @a ];
        return scalar @{ $s->{ops} };
    }
    sub createRectangle {
        my ( $s, @a ) = @_;
        push @{ $s->{ops} }, [ createRectangle => @a ];
        return scalar @{ $s->{ops} };
    }
    sub createText {
        my ( $s, @a ) = @_;
        push @{ $s->{ops} }, [ createText => @a ];
        return scalar @{ $s->{ops} };
    }
    sub createOval {
        my ( $s, @a ) = @_;
        push @{ $s->{ops} }, [ createOval => @a ];
        return scalar @{ $s->{ops} };
    }
}

# 1. Fórmula TV: 0 en p2, 1 en p1
{
    my $p1 = { index => 10,  price => 30000 };
    my $p2 = { index => 100, price => 28408 };
    is(
        Market::Drawing::FibRetracement->price_at_level( $p1, $p2, 0 ),
        28408, 'nivel 0 = p2'
    );
    is(
        Market::Drawing::FibRetracement->price_at_level( $p1, $p2, 1 ),
        30000, 'nivel 1 = p1'
    );
    my $r618 = Market::Drawing::FibRetracement->price_at_level( $p1, $p2, 0.618 );
    ok( abs( $r618 - ( 28408 + 0.618 * 1592 ) ) < 0.02, '0.618 TV' );
}

# 2. set_from_zz_leg: pierna bajista → 1 arriba (high), 0 abajo (low)
{
    my $d = Market::Drawing::FibRetracement->new();
    $d->set_from_zz_leg(
        {
            from_index => 10,
            from_price => 30000,
            to_index   => 90,
            to_price   => 28408,
            dir        => 'down',
            consolidated => 1,
        }
    );
    my $fib = $d->get_fib();
    is( $fib->{p1}{price}, 30000, 'ZZ leg bajista: p1=high=nivel 1' );
    is( $fib->{p2}{price}, 28408, 'ZZ leg bajista: p2=low=nivel 0' );
    my $lv = $d->level_prices();
    my ($one) = grep { abs( $_->{ratio} - 1 ) < 1e-9 } @$lv;
    my ($zero) = grep { abs( $_->{ratio} - 0 ) < 1e-9 } @$lv;
    is( $one->{price},  30000, 'ratio 1 en high' );
    is( $zero->{price}, 28408, 'ratio 0 en low' );
}

# 3. last_consolidated_zz_segment elige la última pierna cerrada
{
    my @segs = (
        {
            from_index => 0,  to_index => 20,
            from_price => 100, to_price => 200, dir => 'up', consolidated => 1,
        },
        {
            from_index => 20, to_index => 80,
            from_price => 30000, to_price => 28408, dir => 'down', consolidated => 1,
        },
        {
            from_index => 80, to_index => 95,
            from_price => 28408, to_price => 29100, dir => 'up', consolidated => 0,
        },
    );
    my $hit = Market::Drawing::FibRetracement->last_consolidated_zz_segment( \@segs );
    ok( $hit, 'last_consolidated encuentra pierna' );
    is( $hit->{from_price}, 30000, 'elige última cerrada, no el vivo' );
}

# 3b. last_impulse: solo última UP consolidada; si la última cerrada es DOWN, se queda en la UP previa
{
    # Caso captura: UP grande, DOWN, rebote UP chico vivo → Fib en UP grande
    my @segs = (
        {
            from_index => 16843, to_index => 17050,
            from_price => 28408.25, to_price => 29050.25, dir => 'up', consolidated => 1,
        },
        {
            from_index => 17050, to_index => 17293,
            from_price => 29050.25, to_price => 28709.75, dir => 'down', consolidated => 1,
        },
        {
            from_index => 17293, to_index => 17415,
            from_price => 28709.75, to_price => 28963.50, dir => 'up', consolidated => 0,
        },
    );
    my $hit = Market::Drawing::FibRetracement->last_impulse_zz_segment_for_fib( \@segs );
    ok( $hit, 'impulse encuentra UP' );
    is( $hit->{to_price}, 29050.25, 'con DOWN cerrada + vivo: mantiene UP previa (no la bajada)' );
}

{
    # Tras consolidar rebote chico, última cerrada UP → salta a esa UP (no a la bajada)
    my @segs = (
        {
            from_index => 16843, to_index => 17050,
            from_price => 28408.25, to_price => 29050.25, dir => 'up', consolidated => 1,
        },
        {
            from_index => 17050, to_index => 17293,
            from_price => 29050.25, to_price => 28709.75, dir => 'down', consolidated => 1,
        },
        {
            from_index => 17293, to_index => 17415,
            from_price => 28709.75, to_price => 28963.50, dir => 'up', consolidated => 1,
        },
        {
            from_index => 17415, to_index => 17500,
            from_price => 28963.50, to_price => 28850.00, dir => 'down', consolidated => 0,
        },
    );
    my $hit = Market::Drawing::FibRetracement->last_impulse_zz_segment_for_fib( \@segs );
    is( $hit->{to_price}, 28963.50, 'última cerrada UP: ancla en esa subida' );
}

{
    my @segs = (
        {
            from_index => 0, to_index => 40,
            from_price => 28000, to_price => 30000, dir => 'up', consolidated => 1,
        },
        {
            from_index => 40, to_index => 60,
            from_price => 30000, to_price => 29000, dir => 'down', consolidated => 0,
        },
    );
    my $hit = Market::Drawing::FibRetracement->last_impulse_zz_segment_for_fib( \@segs );
    is( $hit->{dir}, 'up', 'una sola UP cerrada' );
}

{
    my @segs = (
        {
            from_index => 0, to_index => 20,
            from_price => 30000, to_price => 28000, dir => 'down', consolidated => 1,
        },
        {
            from_index => 20, to_index => 30,
            from_price => 28000, to_price => 28500, dir => 'up', consolidated => 0,
        },
    );
    my $hit = Market::Drawing::FibRetracement->last_impulse_zz_segment_for_fib( \@segs );
    ok( !defined $hit, 'solo DOWN cerrada: sin ancla (esperar)' );
}

# 4. nearest_zz_segment elige la pierna correcta
{
    my @segs = (
        {
            from_index => 0,  to_index => 20,
            from_price => 100, to_price => 200, dir => 'up',
        },
        {
            from_index => 20, to_index => 80,
            from_price => 30000, to_price => 28408, dir => 'down',
        },
    );
    my $hit = Market::Drawing::FibRetracement->nearest_zz_segment( \@segs, 50, 29000 );
    ok( $hit, 'nearest encuentra pierna' );
    is( $hit->{from_price}, 30000, 'elige pierna bajista cercana' );
}

# 4b. zz_leg_signature estable para detectar cambio de impulso
{
    my $leg = {
        from_index => 20, to_index => 80,
        from_price => 30000, to_price => 28408,
    };
    is(
        Market::Drawing::FibRetracement->zz_leg_signature($leg),
        '20:80:30000:28408',
        'zz_leg_signature codifica extremos del impulso'
    );
}

# 5. Ancho = p1/p2; al mover p1 se mueve el borde de la caja
{
    my $d = Market::Drawing::FibRetracement->new();
    $d->set_from_points(
        { index => 10, price => 30000 },
        { index => 40, price => 28408 },
    );
    my $geo0 = $d->geometry_for( $d->get_fib(), data_end => 200, view_end => 100 );
    is( $geo0->{left_index},  10, 'left = min(p1,p2)' );
    is( $geo0->{right_index}, 40, 'right = max(p1,p2)' );

    $d->set_p1( { index => 5, price => 30100 } );
    my $geo1 = $d->geometry_for( $d->get_fib(), data_end => 200, view_end => 100 );
    is( $geo1->{left_index},  5,  'mover p1 a la izq mueve el inicio de la caja' );
    is( $geo1->{right_index}, 40, 'p2 sigue anclando el fin' );

    $d->set_p2( { index => 60, price => 28300 } );
    my $geo2 = $d->geometry_for( $d->get_fib(), data_end => 200, view_end => 100 );
    is( $geo2->{left_index},  5,  'left sigue en p1' );
    is( $geo2->{right_index}, 60, 'mover p2 mueve el fin de la caja' );

    $d->set_extend_to_last(1);
    my $geo3 = $d->geometry_for( $d->get_fib(), data_end => 200, view_end => 100 );
    is( $geo3->{right_index}, 200, 'extend_to_last → right=data_end' );
    is( $geo3->{left_index},  5,   'left sigue en anclas' );
}

# 6. Labels fuera: createText con anchor e (lado izquierdo)
{
    my $d = Market::Drawing::FibRetracement->new();
    $d->set_from_points(
        { index => 30, price => 30000 },
        { index => 90, price => 28408 },
    );
    my $ov = Market::Overlays::FibRetracement->new( drawing => $d );
    $ov->set_visible(1);
    $ov->compute_visible( undef, undef, 0, 100 );
    $ov->{_data_end} = 100;

    my $canvas = FibTestCanvas->new();
    my $scales = bless { width => 500, height => 300, bars => 101 }, 'FakeScales2';
    {
        package FakeScales2;
        sub index_to_center_x { my ( $s, $i ) = @_; return 50 + ( $i // 0 ) * 3; }
        sub value_to_y {
            my ( $s, $p ) = @_;
            return 300 - ( ( $p - 28000 ) / 2100 ) * 280;
        }
    }
    $ov->draw( $canvas, $scales );
    my @texts = grep { $_->[0] eq 'createText' } @{ $canvas->{ops} };
    is( scalar @texts, 7, '7 labels' );
    my $has_e = 0;
    for my $t (@texts) {
        my @a = @$t;
        for my $i ( 0 .. $#a - 1 ) {
            $has_e = 1 if $a[$i] eq '-anchor' && $a[ $i + 1 ] eq 'e';
        }
    }
    ok( $has_e, 'labels anclados a la derecha del texto (fuera a la izquierda de cajas)' );
    my @lines = grep { $_->[0] eq 'createLine' } @{ $canvas->{ops} };
    is( scalar @lines, 7, '7 líneas de nivel' );
}

done_testing();
