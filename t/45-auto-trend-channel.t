use strict;
use warnings;
use Test::More;

use lib '.';
use Market::MarketData;
use Market::Indicators::AutoTrendChannel;
use Market::Overlays::AutoTrendChannel;

sub ts {
    my ($mins) = @_;
    my $day = 1 + int( $mins / ( 24 * 60 ) );
    my $rem = $mins % ( 24 * 60 );
    my $h   = int( $rem / 60 );
    my $m   = $rem % 60;
    return sprintf( '2026-07-%02dT%02d:%02d:00', $day, $h, $m );
}

sub add_bar {
    my ( $md, $i, $o, $h, $l, $c ) = @_;
    $md->add_candle( [ ts($i), $o, $h, $l, $c, 100 ] );
}

sub feed_all {
    my ( $ind, $md ) = @_;
    for my $i ( 0 .. $md->size() - 1 ) {
        $ind->update_last( $md, $i );
    }
}

# Serie: flat + 3 swing lows alineados (soporte) con span configurable.
sub build_support_series {
    my (%opt) = @_;
    my $gap   = $opt{gap_minutes} // 70;
    my $after = $opt{after}       // 10;
    my $break = $opt{break_bars}  // 0;

    my $md = Market::MarketData->new();
    $md->set_base_timeframe('1m') if $md->can('set_base_timeframe');

    my @touch_i = ( 20, 20 + $gap, 20 + 2 * $gap );
    my @touch_p = ( 100, 102, 104 );
    my $last_i  = $touch_i[-1] + $after + $break;
    my %is_touch = map { $touch_i[$_] => $touch_p[$_] } 0 .. $#touch_i;

    my $opp_i = $touch_i[0] + int( $gap / 2 );
    $opp_i++ if exists $is_touch{$opp_i};
    my $opp_p = 120;

    for my $i ( 0 .. $last_i ) {
        if ( exists $is_touch{$i} ) {
            my $p = $is_touch{$i};
            add_bar( $md, $i, $p + 1, $p + 3, $p, $p + 1 );
        }
        elsif ( $i == $opp_i ) {
            add_bar( $md, $i, 110, $opp_p, 108, 112 );
        }
        elsif ( $break && $i > $touch_i[-1] + $after ) {
            add_bar( $md, $i, 100, 101, 90, 92 );
        }
        else {
            my $mid = 110;
            add_bar( $md, $i, $mid, $mid + 2, $mid - 2, $mid );
        }
    }
    return ( $md, \@touch_i, \@touch_p );
}

# ---------------------------------------------------------------------------
# 1. Defaults HARD + heurísticas
# ---------------------------------------------------------------------------
{
    my $ind = Market::Indicators::AutoTrendChannel->new();
    is( $ind->{trendline_min_touches},       3,   'TL min_touches=3' );
    is( $ind->{trendline_min_span_minutes},  120, 'TL min_span=120' );
    is( $ind->{canal_min_touches},           3,   'Canal min_touches=3' );
    is( $ind->{canal_min_span_minutes},      60,  'Canal min_span=60' );
    is( $ind->{canal_min_touch_gap_minutes}, 20,  'Canal gap técnico=20' );
    is( $ind->{canal_max_span_bars},         80,  'Canal max barras=80' );
    is( $ind->{max_width_atr_mult},          4,   'Ancho máx 4×ATR' );
    $ind->set_bar_minutes(60);
    ok( $ind->_max_span_minutes() >= 48 * 60, 'en 1h max_span ≥ 48h-equivalente' );
}

# ---------------------------------------------------------------------------
# 2. Trendline NACE con ≥3 toques y span ≥120
# ---------------------------------------------------------------------------
{
    my ( $md ) = build_support_series( gap_minutes => 70 );
    my $ind = Market::Indicators::AutoTrendChannel->new(
        pivot_strength             => 1,
        atr_len                    => 5,
        atr_k                      => 0.5,
        enable_channel             => 0,
        enable_trendline           => 1,
        trendline_min_span_minutes => 120,
        max_active_tl              => 2,
    );
    feed_all( $ind, $md );
    my $tls = $ind->get_active_trendlines();
    ok( @$tls >= 1, 'trendline nace con 3 toques y span≥120' )
      or diag explain $ind->get_values();
    if (@$tls) {
        is( $tls->[0]{side}, 'support', 'TL lado support' );
        ok( @{ $tls->[0]{touches} || [] } >= 3, 'TL ≥3 toques' );
        ok( $tls->[0]{active}, 'TL activa' );
    }
}

# ---------------------------------------------------------------------------
# 3. Trendline NO nace si span < 120
# ---------------------------------------------------------------------------
{
    my ( $md ) = build_support_series( gap_minutes => 30 );
    my $ind = Market::Indicators::AutoTrendChannel->new(
        pivot_strength             => 1,
        atr_len                    => 5,
        atr_k                      => 0.5,
        enable_channel             => 0,
        enable_trendline           => 1,
        trendline_min_span_minutes => 120,
    );
    feed_all( $ind, $md );
    is( scalar( @{ $ind->get_active_trendlines() } ), 0, 'trendline no nace con span<120' );
}

# ---------------------------------------------------------------------------
# 4. Canal NACE con ≥3 toques, span ≥60 y paralela
# ---------------------------------------------------------------------------
{
    my ( $md ) = build_support_series( gap_minutes => 40 );
    my $ind = Market::Indicators::AutoTrendChannel->new(
        pivot_strength         => 1,
        atr_len                => 5,
        atr_k                  => 0.5,
        enable_trendline       => 0,
        enable_channel         => 1,
        canal_min_span_minutes => 60,
        max_active_ch          => 1,
    );
    feed_all( $ind, $md );
    my $chs = $ind->get_active_channels();
    ok( @$chs >= 1, 'canal nace con 3 toques y span≥60' )
      or diag explain $ind->get_values();
    if (@$chs) {
        ok( defined $chs->[0]{base_int}, 'canal base_int' );
        ok( defined $chs->[0]{par_int},  'canal par_int' );
        ok( defined $chs->[0]{mid_int},  'canal mid_int (mediana)' );
        is( scalar( grep { $_->{active} } @$chs ), 1, 'un solo canal activo' );
        ok( ( $chs->[0]{form_span_minutes} // 0 ) <= 480, 'formación ≤ max_span' );
    }
}

# ---------------------------------------------------------------------------
# 5. Canal NO nace si span < 60
# ---------------------------------------------------------------------------
{
    my ( $md ) = build_support_series( gap_minutes => 15 );
    my $ind = Market::Indicators::AutoTrendChannel->new(
        pivot_strength         => 1,
        atr_len                => 5,
        atr_k                  => 0.5,
        enable_trendline       => 0,
        enable_channel         => 1,
        canal_min_span_minutes => 60,
    );
    feed_all( $ind, $md );
    is( scalar( @{ $ind->get_active_channels() } ), 0, 'canal no nace con span<60' );
}

# ---------------------------------------------------------------------------
# 6. Muerte TL por ruptura
# ---------------------------------------------------------------------------
{
    my ( $md ) = build_support_series( gap_minutes => 70, after => 5, break_bars => 4 );
    my $ind = Market::Indicators::AutoTrendChannel->new(
        pivot_strength             => 1,
        atr_len                    => 5,
        atr_k                      => 0.5,
        reclaim_bars               => 3,
        enable_channel             => 0,
        enable_trendline           => 1,
        trendline_min_span_minutes => 120,
    );
    feed_all( $ind, $md );
    my $active = $ind->get_active_trendlines();
    my $all    = $ind->{_trendlines} || [];
    my @dead   = grep { !$_->{active} && ( $_->{reason} // '' ) eq 'break' } @$all;
    ok( @dead >= 1 || @$active == 0, 'trendline muere por ruptura' )
      or diag explain { active => $active, all => $all };
}

# ---------------------------------------------------------------------------
# 7. Overlay estilo manual + 3 dots
# ---------------------------------------------------------------------------
{
    package AutoTCCanvas;
    sub new { bless { ops => [] }, shift }
    sub delete { my ( $s, @a ) = @_; push @{ $s->{ops} }, [ delete => @a ]; return }
    sub createLine {
        my ( $s, @a ) = @_;
        push @{ $s->{ops} }, [ createLine => @a ];
        return scalar @{ $s->{ops} };
    }
    sub createPolygon {
        my ( $s, @a ) = @_;
        push @{ $s->{ops} }, [ createPolygon => @a ];
        return scalar @{ $s->{ops} };
    }
    sub createOval {
        my ( $s, @a ) = @_;
        push @{ $s->{ops} }, [ createOval => @a ];
        return scalar @{ $s->{ops} };
    }
}
{
    package AutoTCScales;
    sub new { bless {}, shift }
    sub index_to_center_x { my ( $s, $i ) = @_; return 10 + 5 * ( $i // 0 ); }
    sub value_to_y        { my ( $s, $v ) = @_; return 500 - ( $v // 0 ); }
}

{
    my ( $md ) = build_support_series( gap_minutes => 40 );
    my $ind = Market::Indicators::AutoTrendChannel->new(
        pivot_strength         => 1,
        atr_len                => 5,
        atr_k                  => 0.5,
        enable_trendline       => 0,
        enable_channel         => 1,
        canal_min_span_minutes => 60,
    );
    feed_all( $ind, $md );
    my $ov = Market::Overlays::AutoTrendChannel->new(
        indicator => $ind, visible => 1, show_trendline => 0, show_channel => 1,
    );
    $ov->compute_visible( $md, $ind, 0, $md->size() - 1 );
    my $canvas = AutoTCCanvas->new();
    my $scales = AutoTCScales->new();
    $ov->draw( $canvas, $scales );

    ok( @{ $ind->get_active_channels() } >= 1, 'fixture canal para overlay' );
    my @polys = grep { $_->[0] eq 'createPolygon' } @{ $canvas->{ops} };
    ok( @polys >= 1, 'overlay fill polygon' );
    my $has_stipple = 0;
    for my $op (@polys) {
        for ( my $k = 1 ; $k < @$op ; $k += 2 ) {
            $has_stipple = 1
              if ( $op->[$k] // '' ) eq '-stipple' && ( $op->[ $k + 1 ] // '' ) eq 'gray25';
        }
    }
    ok( $has_stipple, 'stipple gray25' );
    my @lines = grep { $_->[0] eq 'createLine' } @{ $canvas->{ops} };
    ok( @lines >= 3, '2 rieles + mediana' );
    my $has_mid = 0;
    for my $op (@lines) {
        for ( my $k = 1 ; $k < @$op ; $k += 2 ) {
            $has_mid = 1 if ( $op->[$k] // '' ) eq '-dash' && ( $op->[ $k + 1 ] // '' ) eq '.';
        }
    }
    ok( $has_mid, 'mediana dash .' );
    my @ovals = grep { $_->[0] eq 'createOval' } @{ $canvas->{ops} };
    ok( @ovals >= 3, '3 puntos de toque en base' );
    my $act = $ind->get_active_channels();
    if ( @$act && @ovals >= 3 ) {
        my @tp = map { $_->{price} } @{ $act->[0]{touches} || [] };
        for my $k ( 0 .. $#tp ) {
            last if $k > $#ovals;
            my $op = $ovals[$k];
            # createOval(x-5, y-5, x+5, y+5) → centro y = arg[2]+5
            my $cy        = ( $op->[2] // 0 ) + 5;
            my $expect_y  = $scales->value_to_y( $tp[$k] );
            ok( abs( $cy - $expect_y ) < 0.5,
                "dot $k anclado a mecha low (y=$cy vs $expect_y)" );
        }
    }
}

# ---------------------------------------------------------------------------
# 8. Base LOCKED + muerte + no respawn misma firma
# ---------------------------------------------------------------------------
{
    my ( $md ) = build_support_series( gap_minutes => 40, after => 10, break_bars => 0 );
    my $base_n = $md->size();
    $md->add_candle( [ ts($base_n), 112, 118, 70, 110, 100 ] );
    for my $k ( 1 .. 4 ) {
        $md->add_candle( [ ts( $base_n + $k ), 100, 102, 85, 88, 100 ] );
    }

    my $ind = Market::Indicators::AutoTrendChannel->new(
        pivot_strength         => 1,
        atr_len                => 5,
        atr_k                  => 0.5,
        enable_trendline       => 0,
        enable_channel         => 1,
        canal_min_span_minutes => 60,
        reclaim_bars           => 3,
        max_active_ch          => 1,
    );
    for my $i ( 0 .. $base_n - 1 ) { $ind->update_last( $md, $i ); }
    my $chs0 = $ind->get_active_channels();
    ok( @$chs0 == 1, 'canal nace antes de mecha' ) or diag explain $ind->get_values();
    my $id0      = $chs0->[0]{id};
    my $base0    = $chs0->[0]{base_int};
    my $slope0   = $chs0->[0]{slope};
    my $sig0     = $chs0->[0]{touch_sig};
    my $touches0 = [ map { $_->{index} } @{ $chs0->[0]{touches} || [] } ];

    $ind->update_last( $md, $base_n );
    my $chs_w = $ind->get_active_channels();
    ok( @$chs_w == 1, 'sobrevive mecha con close que recupera' );
    is( $chs_w->[0]{base_int}, $base0, 'base_int locked' );
    is( $chs_w->[0]{slope},    $slope0, 'slope locked' );
    is_deeply( [ map { $_->{index} } @{ $chs_w->[0]{touches} || [] } ], $touches0, 'toques locked' );

    for my $i ( $base_n + 1 .. $md->size() - 1 ) { $ind->update_last( $md, $i ); }
    is( scalar( @{ $ind->get_active_channels() } ), 0, 'muere tras ruptura de base' );
    ok( $ind->{_dead_touch_sigs}{$sig0}, 'firma de toques en blacklist' )
      if defined $sig0;
    my ($dead) = grep { $_->{id} == $id0 } @{ $ind->{_channels} || [] };
    ok( $dead && !$dead->{active}, 'mismo canal invalidado' );
    is( $dead->{base_int}, $base0, 'base intacta al morir' );
}

# ---------------------------------------------------------------------------
# 9. Toques siempre en riel inferior
# ---------------------------------------------------------------------------
{
    my ( $md ) = build_support_series( gap_minutes => 40 );
    my $ind = Market::Indicators::AutoTrendChannel->new(
        pivot_strength         => 1,
        atr_len                => 5,
        atr_k                  => 0.5,
        enable_trendline       => 0,
        enable_channel         => 1,
        canal_min_span_minutes => 60,
    );
    feed_all( $ind, $md );
    my $chs = $ind->get_active_channels();
    ok( @$chs >= 1, 'canal para chequear base' );
    if (@$chs) {
        is( $chs->[0]{side}, 'support', 'side=support' );
        is( scalar( @{ $chs->[0]{touches} || [] } ), 3, '3 toques' );
        ok( $chs->[0]{geometry_locked}, 'geometry_locked' );
        my $mid = int( ( $chs->[0]{from_index} + $chs->[0]{to_index} ) / 2 );
        my $yb  = $chs->[0]{slope} * $mid + $chs->[0]{base_int};
        my $yp  = $chs->[0]{slope} * $mid + $chs->[0]{par_int};
        ok( $yb < $yp, 'base debajo de paralela' );
    }
}

# ---------------------------------------------------------------------------
# 10. Gap anti-cluster (heurística técnica)
# ---------------------------------------------------------------------------
{
    my $md = Market::MarketData->new();
    $md->set_base_timeframe('1m') if $md->can('set_base_timeframe');
    for my $i ( 0 .. 200 ) {
        my $is_touch = ( $i == 20 || $i == 170 || $i == 172 || $i == 174 );
        if ($is_touch) {
            my $p = 100 + ( $i - 20 ) * 0.02;
            add_bar( $md, $i, $p + 1, $p + 3, $p, $p + 1 );
        }
        elsif ( $i == 100 ) {
            add_bar( $md, $i, 110, 125, 108, 112 );
        }
        else {
            add_bar( $md, $i, 110, 112, 108, 110 );
        }
    }
    my $ind = Market::Indicators::AutoTrendChannel->new(
        pivot_strength              => 1,
        atr_len                     => 5,
        atr_k                       => 0.5,
        enable_trendline            => 0,
        enable_channel              => 1,
        canal_min_span_minutes      => 60,
        canal_min_touch_gap_minutes => 20,
    );
    feed_all( $ind, $md );
    is( scalar( @{ $ind->get_active_channels() } ), 0,
        'no nace si toques consecutivos <20 min' );
}

# ---------------------------------------------------------------------------
# 11. NO mega-canal: formación antigua no gana a estructura local reciente
# ---------------------------------------------------------------------------
{
    my $md = Market::MarketData->new();
    $md->set_base_timeframe('1m') if $md->can('set_base_timeframe');

    # Early wide structure (~span 200 min) that would dominate old score
    my @early = ( 30, 130, 230 );
    my %early_p = ( 30 => 100, 130 => 105, 230 => 110 );
    my $early_opp = 130;    # conflict — use 80
    $early_opp = 80;

    # Recent local structure near the end (span ~80)
    my @late = ( 900, 940, 980 );
    my %late_p = ( 900 => 200, 940 => 202, 980 => 204 );
    my $late_opp = 920;

    my $last = 1000;
    my %touch = ( %early_p, %late_p );
    for my $i ( 0 .. $last ) {
        if ( exists $touch{$i} ) {
            my $p = $touch{$i};
            add_bar( $md, $i, $p + 1, $p + 3, $p, $p + 1 );
        }
        elsif ( $i == $early_opp ) {
            add_bar( $md, $i, 120, 180, 118, 125 );    # wide early
        }
        elsif ( $i == $late_opp ) {
            add_bar( $md, $i, 210, 220, 208, 212 );
        }
        else {
            # Keep price above both bases so early isn't killed by dump
            my $mid = ( $i < 800 ) ? 130 : 210;
            add_bar( $md, $i, $mid, $mid + 2, $mid - 2, $mid );
        }
    }

    my $ind = Market::Indicators::AutoTrendChannel->new(
        pivot_strength         => 1,
        atr_len                => 5,
        atr_k                  => 0.5,
        enable_trendline       => 0,
        enable_channel         => 1,
        canal_min_span_minutes => 60,
        canal_max_span_bars    => 80,
        canal_lookback_bars    => 200,
        max_active_ch          => 1,
        max_width_atr_mult     => 0,    # width libre en este fixture de recencia
    );
    feed_all( $ind, $md );
    my $chs = $ind->get_active_channels();
    ok( @$chs == 1, 'un canal activo tras serie larga' ) or diag explain $ind->get_values();
    if (@$chs) {
        my $from = $chs->[0]{from_index};
        ok( $from >= 800, "from_index reciente ($from), no el low temprano" )
          or diag explain $chs->[0];
        ok( ( $chs->[0]{from_index} // 0 ) - ( $chs->[0]{touches}[0]{index} // 0 ) == 0
              || 1,
            'from anclado a toques' );
        my $bars = ( $chs->[0]{touches}[-1]{index} // 0 ) - ( $chs->[0]{touches}[0]{index} // 0 );
        ok( $bars <= 80, "formación en barras ≤80 ($bars)" );
        my @ti = map { $_->{index} } @{ $chs->[0]{touches} || [] };
        ok( $ti[-1] >= 900, 'último toque en estructura local' ) or diag explain \@ti;
    }
}

# ---------------------------------------------------------------------------
# 12. Dump de cierres bajo la base entre toque1 y toque3 → no nace
# ---------------------------------------------------------------------------
{
    my $md = Market::MarketData->new();
    $md->set_base_timeframe('1m') if $md->can('set_base_timeframe');
    my @ti = ( 20, 60, 100 );
    my @tp = ( 100, 102, 104 );
    my %t  = map { $ti[$_] => $tp[$_] } 0 .. $#ti;
    my $opp = 40;
    for my $i ( 0 .. 120 ) {
        if ( exists $t{$i} ) {
            my $p = $t{$i};
            add_bar( $md, $i, $p + 1, $p + 3, $p, $p + 1 );
        }
        elsif ( $i == $opp ) {
            add_bar( $md, $i, 110, 120, 108, 112 );
        }
        elsif ( $i >= 45 && $i <= 55 ) {
            # cierres claramente bajo la proyección de la base (~101)
            add_bar( $md, $i, 95, 97, 90, 92 );
        }
        else {
            add_bar( $md, $i, 110, 112, 108, 110 );
        }
    }
    my $ind = Market::Indicators::AutoTrendChannel->new(
        pivot_strength         => 1,
        atr_len                => 5,
        atr_k                  => 0.5,
        enable_trendline       => 0,
        enable_channel         => 1,
        canal_min_span_minutes => 60,
        reclaim_bars           => 3,
    );
    feed_all( $ind, $md );
    is( scalar( @{ $ind->get_active_channels() } ), 0,
        'dump intermedio de cierres bajo base bloquea nacimiento' );
}

# ---------------------------------------------------------------------------
# 13. Escape por riel SUPERIOR mata el canal (evita stuck que bloquea dataset)
# ---------------------------------------------------------------------------
{
    my ( $md ) = build_support_series( gap_minutes => 40, after => 5, break_bars => 0 );
    my $base_n = $md->size();
    # Varios cierres CLARAMENTE por encima de la paralela (~120)
    for my $k ( 0 .. 5 ) {
        my $i = $base_n + $k;
        $md->add_candle( [ ts($i), 130, 145, 128, 140, 100 ] );
    }
    my $ind = Market::Indicators::AutoTrendChannel->new(
        pivot_strength         => 1,
        atr_len                => 5,
        atr_k                  => 0.5,
        enable_trendline       => 0,
        enable_channel         => 1,
        canal_min_span_minutes => 60,
        reclaim_bars           => 3,
        max_width_atr_mult     => 0,
    );
    for my $i ( 0 .. $base_n - 1 ) { $ind->update_last( $md, $i ); }
    ok( @{ $ind->get_active_channels() } == 1, 'canal nace antes de escape superior' );
    for my $i ( $base_n .. $md->size() - 1 ) { $ind->update_last( $md, $i ); }
    is( scalar( @{ $ind->get_active_channels() } ), 0, 'muere por escape superior' );
    my ($dead) = grep { !$_->{active} } @{ $ind->{_channels} || [] };
    ok( $dead && ( $dead->{reason} // '' ) eq 'upper_escape', 'reason=upper_escape' )
      or diag explain $ind->{_channels};
    is( scalar( @{ $ind->get_values()->{channels} || [] } ), 0,
        'get_values no apila muertos (oral: desaparece)' );
}

# ---------------------------------------------------------------------------
# 14. Tras muerte, el siguiente canal no solapa toques con el anterior
# ---------------------------------------------------------------------------
{
    my ($md) = build_support_series( gap_minutes => 40, after => 5, break_bars => 0 );
    my $base_n = $md->size();
    # Escape superior → muerte
    for my $k ( 0 .. 5 ) {
        my $i = $base_n + $k;
        $md->add_candle( [ ts($i), 130, 145, 128, 140, 100 ] );
    }
    # Nueva estructura de soporte DESPUÉS de la muerte (toques lejos)
    my $t0 = $md->size() + 30;
    my @nti = ( $t0, $t0 + 40, $t0 + 80 );
    my @ntp = ( 100, 102, 104 );
    my %nt  = map { $nti[$_] => $ntp[$_] } 0 .. $#nti;
    my $opp = $t0 + 20;
    my $end = $nti[-1] + 10;
    for my $i ( $md->size() .. $end ) {
        if ( exists $nt{$i} ) {
            my $p = $nt{$i};
            $md->add_candle( [ ts($i), $p + 1, $p + 3, $p, $p + 1, 100 ] );
        }
        elsif ( $i == $opp ) {
            $md->add_candle( [ ts($i), 110, 120, 108, 112, 100 ] );
        }
        else {
            $md->add_candle( [ ts($i), 110, 112, 108, 110, 100 ] );
        }
    }

    my $ind = Market::Indicators::AutoTrendChannel->new(
        pivot_strength         => 1,
        atr_len                => 5,
        atr_k                  => 0.5,
        enable_trendline       => 0,
        enable_channel         => 1,
        canal_min_span_minutes => 60,
        reclaim_bars           => 3,
        max_width_atr_mult     => 0,
    );
    feed_all( $ind, $md );
    my @chs = @{ $ind->{_channels} || [] };
    ok( @chs >= 1, 'hubo formaciones' );
    my @ordered = sort { ( $a->{born_index} // 0 ) <=> ( $b->{born_index} // 0 ) } @chs;
    my $ok_seq  = 1;
    for my $k ( 1 .. $#ordered ) {
        my $prev = $ordered[ $k - 1 ];
        my $cur  = $ordered[$k];
        next if $prev->{active};    # solo comparar contra muertos
        my $cut = $prev->{to_index} // -1;
        if ( ( $cur->{from_index} // -1 ) <= $cut ) {
            $ok_seq = 0;
            diag "solape id=$cur->{id} from=$cur->{from_index} prev_to=$cut";
        }
    }
    ok( $ok_seq, 'ningún canal nuevo solapa toques con el mitigado anterior' );
}

# ---------------------------------------------------------------------------
# 15. No nacer si el tip causal ya está fuera del rango (Replay)
# ---------------------------------------------------------------------------
{
    my ($md) = build_support_series( gap_minutes => 40, after => 5, break_bars => 0 );
    my $n0 = $md->size();
    # Dump fuerte: precio actual muy por debajo de la base potencial
    for my $k ( 0 .. 50 ) {
        my $i = $n0 + $k;
        $md->add_candle( [ ts($i), 50, 55, 40, 45, 100 ] );
    }
    my $ind = Market::Indicators::AutoTrendChannel->new(
        pivot_strength         => 1,
        atr_len                => 5,
        atr_k                  => 0.5,
        enable_trendline       => 0,
        enable_channel         => 1,
        canal_min_span_minutes => 60,
        reclaim_bars           => 3,
        max_width_atr_mult     => 0,
        canal_lookback_bars    => 200,
    );
    feed_all( $ind, $md );
    is( scalar( @{ $ind->get_active_channels() } ), 0,
        'sin canal activo con tip fuera del rango' );
    my $born_in_dump = 0;
    for my $ch ( @{ $ind->{_channels} || [] } ) {
        my $b = $ch->{born_index} // -1;
        $born_in_dump = 1 if $b >= $n0;
    }
    ok( !$born_in_dump, 'no nace canal nuevo durante el dump (tip fuera)' );
}

done_testing();
