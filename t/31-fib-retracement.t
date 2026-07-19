use strict;
use warnings;
use Test::More;

use lib '.';
use Market::Drawing::FibRetracement;
use Market::Overlays::FibRetracement;

# Canvas headless
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
    sub createPolygon {
        my ( $s, @a ) = @_;
        push @{ $s->{ops} }, [ createPolygon => @a ];
        return scalar @{ $s->{ops} };
    }
}

# 1. Fórmula TV: 0 en p2, 1 en p1 (captura usuario ~30000 / 28408)
{
    my $p1 = { index => 10, price => 30000 };
    my $p2 = { index => 100, price => 28408 };
    my $mid = Market::Drawing::FibRetracement->price_at_level( $p1, $p2, 0.5 );
    ok( abs( $mid - ( 28408 + 0.5 * ( 30000 - 28408 ) ) ) < 1e-6, '0.5 mid' );
    my $r618 = Market::Drawing::FibRetracement->price_at_level( $p1, $p2, 0.618 );
    ok( abs( $r618 - ( 28408 + 0.618 * 1592 ) ) < 0.02, '0.618 ≈ captura TV' );
    is(
        Market::Drawing::FibRetracement->price_at_level( $p1, $p2, 0 ),
        28408, 'nivel 0 = p2'
    );
    is(
        Market::Drawing::FibRetracement->price_at_level( $p1, $p2, 1 ),
        30000, 'nivel 1 = p1'
    );
}

# 2. Defaults: 7 niveles 0…1
{
    my $lv = Market::Drawing::FibRetracement::default_levels();
    is( scalar @$lv, 7, '7 niveles default' );
    is_deeply(
        [ map { $_->{ratio} } @$lv ],
        [ 0, 0.236, 0.382, 0.5, 0.618, 0.786, 1 ],
        'ratios profe + 0/1 captura'
    );
}

# 3. Tool 2 clics → commit
{
    my $d = Market::Drawing::FibRetracement->new();
    $d->start_tool();
    is( $d->add_point( { index => 5,  price => 30000 } ), 'draft', 'clic 1 draft' );
    is( $d->add_point( { index => 50, price => 28408 } ), 'done',  'clic 2 done' );
    ok( !$d->is_tool_active(), 'tool off tras commit' );
    my $fib = $d->get_fib();
    ok( $fib, 'fib creado' );
    is( $fib->{p1}{price}, 30000, 'p1' );
    is( $fib->{p2}{price}, 28408, 'p2' );
    my $prices = $d->level_prices();
    is( scalar @$prices, 7, '7 level prices' );
}

# 4. Extend + mover anclas / bordes
{
    my $d = Market::Drawing::FibRetracement->new();
    $d->set_from_points(
        { index => 10, price => 100 },
        { index => 40, price => 200 },
    );
    $d->set_extend_right(1);
    ok( $d->get_fib()->{extend_right}, 'extend right' );
    $d->set_p1( { index => 12, price => 110 } );
    is( $d->get_fib()->{p1}{price}, 110, 'move p1' );
    $d->set_left_index(0);
    is( $d->get_fib()->{left_index}, 0, 'left edge' );
    $d->set_right_index(80);
    is( $d->get_fib()->{right_index}, 80, 'right edge' );
    $d->clear_fib();
    ok( !$d->get_fib(), 'clear' );
}

# 5. Overlay draw: fills + lines + labels + handles
{
    my $d = Market::Drawing::FibRetracement->new();
    $d->set_from_points(
        { index => 10, price => 30000 },
        { index => 90, price => 28408 },
    );
    my $ov = Market::Overlays::FibRetracement->new( drawing => $d );
    $ov->set_visible(1);
    $ov->compute_visible( undef, undef, 0, 100 );
    $ov->{_data_end} = 100;

    my $canvas = FibTestCanvas->new();
    my $scales = bless {
        width  => 400,
        height => 300,
        bars   => 101,
    }, 'FakeScales';
    {
        package FakeScales;
        sub index_to_center_x {
            my ( $s, $i ) = @_;
            return 10 + ( $i // 0 ) * 3;
        }
        sub value_to_y {
            my ( $s, $p ) = @_;
            # map 28000..30100 → 280..20
            return 300 - ( ( $p - 28000 ) / 2100 ) * 280;
        }
    }

    $ov->draw( $canvas, $scales );
    my @rects = grep { $_->[0] eq 'createRectangle' } @{ $canvas->{ops} };
    my @lines = grep { $_->[0] eq 'createLine' } @{ $canvas->{ops} };
    my @texts = grep { $_->[0] eq 'createText' } @{ $canvas->{ops} };
    my @ovals = grep { $_->[0] eq 'createOval' } @{ $canvas->{ops} };
    ok( @rects >= 6, 'draw: bandas (fills) entre niveles' );
    is( scalar @lines, 7, 'draw: 7 líneas de nivel' );
    is( scalar @texts, 7, 'draw: 7 labels' );
    ok( @ovals >= 2, 'draw: handles p1/p2' );
}

done_testing();
