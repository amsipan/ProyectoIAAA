package Market::Indicators::HLD;
use strict;
use warnings;

# HLD High/Low de vela HTF (profesor ~40:00 46:30). Sin Pine TV.

use constant {
    MAX_LOOKBACK_DAYS => 4,
    BARS_4H_PER_DAY   => 6,
    MIN_AGE_4H        => 4,
    MIN_AGE_D         => 1,
};

my %TF_RANK = (
    '1m' => 1, '5m' => 5, '10m' => 10, '15m' => 15, '1h' => 60,
    '2h' => 120, '4h' => 240, 'D' => 1440, 'W' => 10080,
);

sub tf_rank {
    my ( $self_or_tf, $tf ) = @_;
    $tf = $self_or_tf if !defined $tf;
    return $TF_RANK{$tf} if defined $tf && exists $TF_RANK{$tf};
    return int($tf) if defined $tf && $tf =~ /^\d+$/;
    return 0;
}

# chart_tf < source_tf (misma o inferior).
sub chart_tf_allowed {
    my ( $self, $chart_tf, $source_tf ) = @_;
    my $rc = tf_rank($chart_tf);
    my $rs = tf_rank($source_tf);
    return 0 if $rc <= 0 || $rs <= 0;
    return $rc <= $rs ? 1 : 0;
}

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
        _ath_max          => {},
    };
    bless $self, $class;
    return $self;
}

sub reset {
    my ($self) = @_;
    $self->{_result}  = undef;
    $self->{_ath_max} = {};
    return $self;
}

sub get_result { $_[0]->{_result} }

# compute($md, %opts)
sub compute {
    my ( $self, $md, %opts ) = @_;
    $self->{_result} = undef;
    return $self->_fail('no_data') unless $md;

    my $source_tf = $opts{source_tf} // $opts{tf} // '';
    unless ( $source_tf eq '4h' || $source_tf eq 'D' ) {
        return $self->_fail( 'wrong_tf', tf => $source_tf );
    }

    my $chart_tf = $opts{chart_tf} // ( $md->{active_tf} // '' );
    if ( length($chart_tf)
        && !$self->chart_tf_allowed( $chart_tf, $source_tf ) )
    {
        return $self->_fail(
            'chart_tf_too_high',
            tf        => $chart_tf,
            source_tf => $source_tf,
        );
    }

    $md->ensure_timeframe($source_tf) if $md->can('ensure_timeframe');
    my $series = $md->{data}{$source_tf} || [];
    my $n = scalar @$series;
    return $self->_fail('no_data') if $n < 2;

    my $end = $opts{end_index};
    my $P   = $opts{price};

    if ( defined $opts{chart_end_index} ) {
        my $chart_end = $opts{chart_end_index};
        my $mapped =
          $self->map_chart_index_to_source( $md, $chart_tf, $chart_end,
            $source_tf );
        $end = $mapped if defined $mapped;
        if ( !defined $P ) {
            my $chart_arr = $md->{data}{ $chart_tf || $md->{active_tf} } || [];
            my $cc = $chart_arr->[$chart_end] if $chart_end >= 0;
            $P = $cc->[4] if $cc;
        }
    }

    $end = $n - 1 if !defined $end;
    $end = 0      if $end < 0;
    $end = $n - 1 if $end > $n - 1;

    my $last = $series->[$end];
    $P = $last->[4] if !defined $P && $last;
    return $self->_fail('no_data') if !defined $P;

    my $last_cand = $end - 1;
    return $self->_fail('no_data') if $last_cand < 0;

    my $days = $self->{max_lookback_days} // MAX_LOOKBACK_DAYS;
    $days = 4 if $days < 1;
    my $pref_bars =
      $source_tf eq '4h' ? ( $days * BARS_4H_PER_DAY ) : $days;

    # ATH: max_high incremental por serie (Play avanza last_cand de a poco)
    my $ath  = ( $self->{_ath_max} //= {} );
    my $athc = $ath->{$source_tf};
    if ( !$athc || $athc->{series} ne "$series" || $athc->{upto} > $last_cand )
    {
        $athc = { series => "$series", upto => -1, max => undef };
    }
    for my $i ( $athc->{upto} + 1 .. $last_cand ) {
        my $c = $series->[$i];
        next unless $c;
        my $h = $c->[2];
        $athc->{max} = $h if !defined $athc->{max} || $h > $athc->{max};
    }
    $athc->{upto} = $last_cand;
    $ath->{$source_tf} = $athc;
    my $max_high = $athc->{max};
    if ( defined $max_high && $P >= $max_high - 1e-12 ) {
        return $self->_fail( 'ath_no_ref', price => $P, max_high => $max_high );
    }

    my $min_age =
        $source_tf eq '4h'
      ? ( $self->{min_age_4h} // MIN_AGE_4H )
      : ( $self->{min_age_d}  // MIN_AGE_D );
    $min_age = 1 if $min_age < 1;

    my $anchor_i =
      $self->_pick_anchor( $series, $P, $end, $last_cand, $pref_bars,
        $min_age );
    return $self->_fail( 'no_data', price => $P ) if !defined $anchor_i;

    my $ac = $series->[$anchor_i];
    my ( $o, $h, $l, $cl ) = ( $ac->[1], $ac->[2], $ac->[3], $ac->[4] );
    my $in_range = ( $l <= $P && $P <= $h ) ? 1 : 0;
    my $nearest  = $self->_nearest_ohlc( $P, $o, $h, $l, $cl );

    # Índices en TF del chart para dibujar (precio Y es TF agnóstico).
    my ( $chart_anchor, $chart_end_draw );
    if ( length($chart_tf) && $chart_tf ne $source_tf ) {
        $chart_anchor =
          $self->map_source_index_to_chart( $md, $source_tf, $anchor_i,
            $chart_tf );
        $chart_end_draw = $opts{chart_end_index};
        if ( !defined $chart_end_draw ) {
            my $carr = $md->{data}{$chart_tf} || [];
            $chart_end_draw = $#$carr if @$carr;
        }
    }
    else {
        $chart_anchor   = $anchor_i;
        $chart_end_draw = $end;
    }

    $self->{_result} = {
        ok                 => 1,
        reason             => 'ok',
        tf                 => $source_tf,
        source_tf          => $source_tf,
        chart_tf           => $chart_tf,
        price              => $P,
        end_index          => $end,
        anchor_index       => $anchor_i,
        chart_anchor_index => $chart_anchor,
        chart_end_index    => $chart_end_draw,
        anchor_ts          => $ac->[0],
        age_bars           => $end - $anchor_i,
        min_age            => $min_age,
        pref_lookback      => $pref_bars,
        in_range           => $in_range,
        open               => $o,
        high               => $h,
        low                => $l,
        close              => $cl,
        resistance         => $h,
        support            => $l,
        nearest_ohlc       => $nearest,
        show_nearest       => $self->{show_nearest_level} ? 1 : 0,
    };

    return $self->{_result};
}

# Última vela fuente cuyo bucket cubre el tope del chart (ts / base_index).
sub map_chart_index_to_source {
    my ( $self, $md, $chart_tf, $chart_i, $source_tf ) = @_;
    return undef unless $md && defined $chart_i && $chart_i >= 0;
    $chart_tf  //= $md->{active_tf};
    $source_tf //= '';
    my $chart_arr  = $md->{data}{$chart_tf}  || [];
    my $source_arr = $md->{data}{$source_tf} || [];
    return undef unless @$chart_arr && @$source_arr;
    return $chart_i if $chart_tf eq $source_tf;

    my $cc = $chart_arr->[$chart_i];
    return undef unless $cc;

    # base_index del chart → última fuente con base_index < chart_base
    my $chart_base = $cc->[6];
    if ( !defined $chart_base && $chart_tf eq ( $md->base_timeframe() // '' ) )
    {
        $chart_base = $chart_i;
    }
    if ( defined $chart_base ) {
        # Binaria en MarketData ([6] monótono); 1 ninguna fuente cerró aún
        my $mi = $md->index_for_base_index( $source_tf, $chart_base );
        return $mi if $mi >= 0;
    }

    # Fallback: timestamp chart → última fuente con ts < chart_ts
    my $ts = $cc->[0];
    return undef unless defined $ts;
    my $best;
    for my $i ( 0 .. $#$source_arr ) {
        my $sts = $source_arr->[$i][0];
        next unless defined $sts;
        last if $sts gt $ts;
        $best = $i;
    }
    return $best;
}

# Índice chart correspondiente al inicio de la vela fuente (para X de dibujo).
sub map_source_index_to_chart {
    my ( $self, $md, $source_tf, $source_i, $chart_tf ) = @_;
    return undef unless $md && defined $source_i && $source_i >= 0;
    my $source_arr = $md->{data}{$source_tf} || [];
    my $chart_arr  = $md->{data}{$chart_tf}  || [];
    return undef unless @$source_arr && @$chart_arr;
    return $source_i if $source_tf eq $chart_tf;

    my $sc = $source_arr->[$source_i];
    return undef unless $sc;
    my $ts = $sc->[0];
    return undef unless defined $ts;

    # Primera vela chart con ts > bucket fuente (binaria; ts monótono)
    my ( $lo, $hi ) = ( 0, $#$chart_arr );
    my $first_ge;
    while ( $lo <= $hi ) {
        my $mid = ( $lo + $hi ) >> 1;
        my $cts = $chart_arr->[$mid][0];
        if ( defined $cts && $cts ge $ts ) { $first_ge = $mid; $hi = $mid - 1; }
        else                               { $lo = $mid + 1; }
    }
    return $first_ge if defined $first_ge;

    # Ninguna alcanza el bucket: última vela con ts definido (caso raro)
    for my $i ( reverse 0 .. $#$chart_arr ) {
        return $i if defined $chart_arr->[$i][0];
    }
    return undef;
}

sub _fail {
    my ( $self, $reason, %extra ) = @_;
    $self->{_result} = { ok => 0, reason => $reason, %extra };
    return $self->{_result};
}

sub _pick_anchor {
    my ( $self, $series, $P, $end, $last_cand, $pref_bars, $min_age ) = @_;
    $min_age //= 1;

    my $max_i = $end - $min_age;
    $max_i = $last_cand if $max_i > $last_cand;
    if ( $max_i < 0 ) {
        $max_i = $last_cand;
    }

    my $pref_min = $end - $pref_bars;
    $pref_min = 0 if $pref_min < 0;
    my $pref_last  = $max_i;
    my $pref_first = $pref_min;
    $pref_first = 0 if $pref_first < 0;

    my $i =
      $self->_most_recent_in_range( $series, $P, $pref_first, $pref_last );
    return $i if defined $i;

    $i = $self->_most_recent_in_range( $series, $P, 0, $max_i );
    return $i if defined $i;

    $i = $self->_pick_by_ohlc_dist( $series, $P, 0, $max_i );
    return $i if defined $i;

    return $self->_pick_by_ohlc_dist( $series, $P, 0, $last_cand );
}

sub _most_recent_in_range {
    my ( $self, $series, $P, $first, $last ) = @_;
    return undef if $last < $first;
    for my $i ( reverse $first .. $last ) {
        my $c = $series->[$i];
        next unless $c;
        return $i if $c->[3] <= $P && $P <= $c->[2];
    }
    return undef;
}

sub _pick_by_ohlc_dist {
    my ( $self, $series, $P, $first, $last ) = @_;
    return undef if $last < $first;
    my ( $best_i, $best_d );
    for my $i ( $first .. $last ) {
        my $c = $series->[$i];
        next unless $c;
        my $d =
          $self->_min_ohlc_dist( $P, $c->[1], $c->[2], $c->[3], $c->[4] );
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
