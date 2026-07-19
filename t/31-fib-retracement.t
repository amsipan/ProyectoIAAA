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

# 3. nearest_zz_segment elige la pierna correcta
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

# 4. extend_to_last hasta data_end
{
    my $d = Market::Drawing::FibRetracement->new();
    $d->set_from_points(
        { index => 10, price => 30000 },
        { index => 40, price => 28408 },
    );
    $d->set_extend_to_last(1);
    my $geo = $d->geometry_for(
        $d->get_fib(),
        data_end   => 200,
        view_start => 0,
        view_end   => 100,
    );
    is( $geo->{right_index}, 200, 'extend_to_last → right=data_end' );
    ok( $geo->{left_index} <= 40, 'left sigue en anclas' );
}

# 5. Labels fuera: createText con anchor e (lado izquierdo)
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
