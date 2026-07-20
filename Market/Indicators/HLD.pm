package Market::Indicators::HLD;
use strict;
use warnings;

# HLD — High/Low de vela HTF (profesor ~40:00–46:30). Sin Pine TV.
#
# Regla unificada (diario y 4h) — citas:
#   «vela del pasado que apunta a ese precio»
#   «más recién pasado en donde el precio está topando»
#   «o de dos días o tres o cuatro»
#   «4 horas … habrá más velas que considerar»  (= hay más barras en la serie,
#    no “salta 6 y ve 26 días atrás”)
#
# Algoritmo:
#   P = close(end)
#   Diario: más reciente i con age>=1 y P en [low,high] (día anterior OK)
#   4h: más reciente i con age>=4 (~16h) y P en [low,high]  — no solo la anterior
#   Si no hay en rango: OHLC más cercano (con el mismo min age; fallback sin min)
#   ATH → no HLD
#
# Ventana preferente (~4 días del profe) dentro de la cual se elige la más reciente
# que cumpla min_age; si no hay, se abre a todo el pasado (con min_age).

use constant {
    MAX_LOOKBACK_DAYS => 4,
    BARS_4H_PER_DAY   => 6,
    MIN_AGE_4H        => 4,    # mínimo 4 velas 4h atrás (criterio de producto)
    MIN_AGE_D         => 1,    # diario: puede ser el día anterior
};

sub new {
    my ( $class, %opts ) = @_;
    my $self = {
        show_nearest_level => exists $opts{show_nearest_level}
        ? ( $opts{show_nearest_level} ? 1 : 0 )
        : 1,
        max_lookback_days => $opts{max_lookback_days} // MAX_LOOKBACK_DAYS,
        min_age_4h        => $opts{min_age_4h} // MIN_AGE_4H,
        min_age_d         => $opts{min_age_d}  // MIN_AGE_D,
        _result           => undef,
    };
    bless $self, $class;
    return $self;
}

sub reset {
    my ($self) = @_;
    $self->{_result} = undef;
    return $self;
}

sub get_result { $_[0]->{_result} }

sub compute {
    my ( $self, $md, %opts ) = @_;
    $self->{_result} = undef;
    return $self->_fail('no_data') unless $md;

    my $tf = $opts{tf} // ( $md->{active_tf} // '' );
    unless ( $tf eq '4h' || $tf eq 'D' ) {
        return $self->_fail( 'wrong_tf', tf => $tf );
    }

    $md->ensure_timeframe($tf) if $md->can('ensure_timeframe');
    my $prev_tf = $md->{active_tf};
    $md->set_timeframe($tf) if $md->can('set_timeframe');

    my $n = $md->size() // 0;
    if ( $n < 2 ) {
        $md->set_timeframe($prev_tf) if defined $prev_tf && $md->can('set_timeframe');
        return $self->_fail('no_data');
    }

    my $end = $opts{end_index};
    $end = $n - 1 if !defined $end;
    $end = 0      if $end < 0;
    $end = $n - 1 if $end > $n - 1;

    my $last = $md->get_candle($end);
    my $P    = $opts{price};
    $P = $last->[4] if !defined $P && $last;
    if ( !defined $P ) {
        $md->set_timeframe($prev_tf) if defined $prev_tf && $md->can('set_timeframe');
        return $self->_fail('no_data');
    }

    my $last_cand = $end - 1;
    if ( $last_cand < 0 ) {
        $md->set_timeframe($prev_tf) if defined $prev_tf && $md->can('set_timeframe');
        return $self->_fail('no_data');
    }

    my $days = $self->{max_lookback_days} // MAX_LOOKBACK_DAYS;
    $days = 4 if $days < 1;
    my $pref_bars = $tf eq '4h' ? ( $days * BARS_4H_PER_DAY ) : $days;

    my $max_high;
    for my $i ( 0 .. $last_cand ) {
        my $c = $md->get_candle($i);
        next unless $c;
        my $h = $c->[2];
        $max_high = $h if !defined $max_high || $h > $max_high;
    }
    if ( defined $max_high && $P >= $max_high - 1e-12 ) {
        $md->set_timeframe($prev_tf) if defined $prev_tf && $md->can('set_timeframe');
        return $self->_fail( 'ath_no_ref', price => $P, max_high => $max_high );
    }

    my $min_age =
        $tf eq '4h'
      ? ( $self->{min_age_4h} // MIN_AGE_4H )
      : ( $self->{min_age_d}  // MIN_AGE_D );
    $min_age = 1 if $min_age < 1;

    my $anchor_i =
      $self->_pick_anchor( $md, $P, $end, $last_cand, $pref_bars, $min_age );
    if ( !defined $anchor_i ) {
        $md->set_timeframe($prev_tf) if defined $prev_tf && $md->can('set_timeframe');
        return $self->_fail( 'no_data', price => $P );
    }

    my $ac = $md->get_candle($anchor_i);
    my ( $o, $h, $l, $cl ) = ( $ac->[1], $ac->[2], $ac->[3], $ac->[4] );
    my $in_range = ( $l <= $P && $P <= $h ) ? 1 : 0;
    my $nearest  = $self->_nearest_ohlc( $P, $o, $h, $l, $cl );

    $self->{_result} = {
        ok             => 1,
        reason         => 'ok',
        tf             => $tf,
        price          => $P,
        end_index      => $end,
        anchor_index   => $anchor_i,
        anchor_ts      => $ac->[0],
        age_bars       => $end - $anchor_i,
        min_age        => $min_age,
        pref_lookback  => $pref_bars,
        in_range       => $in_range,
        open           => $o,
        high           => $h,
        low            => $l,
        close          => $cl,
        resistance     => $h,
        support        => $l,
        nearest_ohlc   => $nearest,
        show_nearest   => $self->{show_nearest_level} ? 1 : 0,
    };

    $md->set_timeframe($prev_tf) if defined $prev_tf && $md->can('set_timeframe');
    return $self->{_result};
}

sub _fail {
    my ( $self, $reason, %extra ) = @_;
    $self->{_result} = { ok => 0, reason => $reason, %extra };
    return $self->{_result};
}

# min_age: índice máximo de ancla = end - min_age
# 4h min_age=4 → no usa end-1, end-2 ni end-3
sub _pick_anchor {
    my ( $self, $md, $P, $end, $last_cand, $pref_bars, $min_age ) = @_;
    $min_age //= 1;

    my $max_i = $end - $min_age;
    $max_i = $last_cand if $max_i > $last_cand;
    if ( $max_i < 0 ) {
        # Serie corta: relajar a lo que haya en el pasado
        $max_i = $last_cand;
    }

    my $pref_min = $end - $pref_bars;
    $pref_min = 0 if $pref_min < 0;
    # no buscar “más nuevas” que max_i
    my $pref_last = $max_i;
    my $pref_first = $pref_min;
    $pref_first = 0 if $pref_first < 0;

    my $i = $self->_most_recent_in_range( $md, $P, $pref_first, $pref_last );
    return $i if defined $i;

    $i = $self->_most_recent_in_range( $md, $P, 0, $max_i );
    return $i if defined $i;

    # OHLC con min_age; si no hay, OHLC en todo el pasado
    $i = $self->_pick_by_ohlc_dist( $md, $P, 0, $max_i );
    return $i if defined $i;

    return $self->_pick_by_ohlc_dist( $md, $P, 0, $last_cand );
}

sub _most_recent_in_range {
    my ( $self, $md, $P, $first, $last ) = @_;
    return undef if $last < $first;
    for my $i ( reverse $first .. $last ) {
        my $c = $md->get_candle($i);
        next unless $c;
        return $i if $c->[3] <= $P && $P <= $c->[2];
    }
    return undef;
}

sub _pick_by_ohlc_dist {
    my ( $self, $md, $P, $first, $last ) = @_;
    return undef if $last < $first;
    my ( $best_i, $best_d );
    for my $i ( $first .. $last ) {
        my $c = $md->get_candle($i);
        next unless $c;
        my $d = $self->_min_ohlc_dist( $P, $c->[1], $c->[2], $c->[3], $c->[4] );
        if ( !defined $best_d
            || $d < $best_d - 1e-12
            || ( abs( $d - $best_d ) < 1e-12 && $i > $best_i ) )
        {
            $best_d = $d;
            $best_i = $i;
        }
    }
    return $best_i;
}

sub _min_ohlc_dist {
    my ( $self, $P, $o, $h, $l, $c ) = @_;
    my $d = abs( $o - $P );
    for my $v ( $h, $l, $c ) {
        my $dv = abs( $v - $P );
        $d = $dv if $dv < $d;
    }
    return $d;
}

sub _nearest_ohlc {
    my ( $self, $P, $o, $h, $l, $c ) = @_;
    my @pairs = (
        [ open  => $o ],
        [ high  => $h ],
        [ low   => $l ],
        [ close => $c ],
    );
    my ( $best_f, $best_v, $best_d );
    for my $p (@pairs) {
        my ( $f, $v ) = @$p;
        my $d = abs( $v - $P );
        if ( !defined $best_d || $d < $best_d ) {
            $best_d = $d;
            $best_f = $f;
            $best_v = $v;
        }
    }
    return { field => $best_f, value => $best_v, dist => $best_d };
}

sub update_last { return $_[0] }

1;
