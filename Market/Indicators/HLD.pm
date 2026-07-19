package Market::Indicators::HLD;
use strict;
use warnings;

# HLD — High/Low de vela HTF (algoritmo del profesor, video ~40:00–46:30).
# Solo temporalidades 4h y D. Sin indicador TV de referencia: lógica de clase.
#
# 1) Precio actual P (close de end_index).
# 2) Elegir vela pasada: más reciente con low<=P<=high; si no, mínima distancia OHLC.
# 3) Resistencia = high, soporte = low; proyectar hasta end_index.
# 4) ATH (P >= max high pasado): no HLD (reason ath_no_ref → usar VWAP en fase 5).

sub new {
    my ( $class, %opts ) = @_;
    my $self = {
        show_nearest_level => exists $opts{show_nearest_level}
        ? ( $opts{show_nearest_level} ? 1 : 0 )
        : 1,
        _result => undef,
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

# compute($market_data, %opts)
#   opts: end_index (default last_index), price (default close end),
#         tf (default active_tf del market_data)
sub compute {
    my ( $self, $md, %opts ) = @_;
    $self->{_result} = undef;
    return $self->_fail('no_data') unless $md;

    my $tf = $opts{tf} // ( $md->{active_tf} // '' );
    unless ( $tf eq '4h' || $tf eq 'D' ) {
        return $self->_fail( 'wrong_tf', tf => $tf );
    }

    # Asegurar serie HTF
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
    $end = 0     if $end < 0;
    $end = $n - 1 if $end > $n - 1;

    my $last = $md->get_candle($end);
    my $P    = $opts{price};
    $P = $last->[4] if !defined $P && $last;    # close
    if ( !defined $P ) {
        $md->set_timeframe($prev_tf) if defined $prev_tf && $md->can('set_timeframe');
        return $self->_fail('no_data');
    }

    # Candidatas: solo pasado (no la vela end como ancla)
    my $last_cand = $end - 1;
    if ( $last_cand < 0 ) {
        $md->set_timeframe($prev_tf) if defined $prev_tf && $md->can('set_timeframe');
        return $self->_fail('no_data');
    }

    # ATH: precio en o sobre el máximo high del pasado → sin referencia
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

    my $anchor_i = $self->_pick_anchor( $md, $P, $last_cand );
    if ( !defined $anchor_i ) {
        $md->set_timeframe($prev_tf) if defined $prev_tf && $md->can('set_timeframe');
        return $self->_fail( 'no_data', price => $P );
    }

    my $c = $md->get_candle($anchor_i);
    my ( $o, $h, $l, $cl ) = ( $c->[1], $c->[2], $c->[3], $c->[4] );
    my $nearest = $self->_nearest_ohlc( $P, $o, $h, $l, $cl );

    $self->{_result} = {
        ok            => 1,
        reason        => 'ok',
        tf            => $tf,
        price         => $P,
        end_index     => $end,
        anchor_index  => $anchor_i,
        anchor_ts     => $c->[0],
        open          => $o,
        high          => $h,
        low           => $l,
        close         => $cl,
        resistance    => $h,
        support       => $l,
        nearest_ohlc  => $nearest,
        show_nearest  => $self->{show_nearest_level} ? 1 : 0,
    };

    $md->set_timeframe($prev_tf) if defined $prev_tf && $md->can('set_timeframe');
    return $self->{_result};
}

sub _fail {
    my ( $self, $reason, %extra ) = @_;
    $self->{_result} = { ok => 0, reason => $reason, %extra };
    return $self->{_result};
}

sub _pick_anchor {
    my ( $self, $md, $P, $last_cand ) = @_;

    # 1) Más reciente con precio dentro del rango high-low
    for my $i ( reverse 0 .. $last_cand ) {
        my $c = $md->get_candle($i);
        next unless $c;
        my ( $h, $l ) = ( $c->[2], $c->[3] );
        return $i if $l <= $P && $P <= $h;
    }

    # 2) Mínima distancia a algún OHLC; empate → más reciente
    my ( $best_i, $best_d );
    for my $i ( 0 .. $last_cand ) {
        my $c = $md->get_candle($i);
        next unless $c;
        my $d = $self->_min_ohlc_dist( $P, $c->[1], $c->[2], $c->[3], $c->[4] );
        if ( !defined $best_d || $d < $best_d - 1e-12 || ( abs( $d - $best_d ) < 1e-12 && $i > $best_i ) ) {
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

# update_last — no-op; HLD se recalcula en compute (HTF barato)
sub update_last { return $_[0] }

1;
