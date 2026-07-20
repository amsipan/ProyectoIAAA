package Market::Indicators::Liquidity;
use strict;
use warnings;

# =============================================================================
# Market::Indicators::Liquidity — Liquidity v2 (desde cero, sin legacy)
#
# PDF 2ª fase §4 + clase profe 16-jun + IndicacionesExaProy:
#   BSL / SSL / EQH / EQL + FSM Detected → Swept → Acceptance|Reclaimed → Resolved
#   Sweep (≤2 velas regresa) | Grab (3..grab_max regresa) | Run (N cierres fuera)
#
# Contrato ChartEngine: new / update_last($md,$i) / reset / get_values
# Export hacia modelos: export_liquidity_events / get_observation_stream
# Sin Tk.
# =============================================================================

use constant {
    DEFAULT_K              => 3,
    DEFAULT_ATR_PERIOD     => 14,
    DEFAULT_EQ_ATR_MULT    => 0.10,
    DEFAULT_RUN_ACCEPT     => 3,
    DEFAULT_SWEEP_MAX      => 2,
    DEFAULT_GRAB_MAX       => 8,
    DEFAULT_MAX_LIVE       => 24,
    DEFAULT_MAX_EVENTS     => 500,
};

sub new {
    my ( $class, %opts ) = @_;
    my $self = {
        k              => $opts{k}              // DEFAULT_K,
        atr_period     => $opts{atr_period}     // DEFAULT_ATR_PERIOD,
        eq_atr_mult    => $opts{eq_atr_mult}    // DEFAULT_EQ_ATR_MULT,
        run_accept_n   => $opts{run_accept_n}   // DEFAULT_RUN_ACCEPT,
        sweep_max_bars => $opts{sweep_max_bars} // DEFAULT_SWEEP_MAX,
        grab_max_bars  => $opts{grab_max_bars}  // DEFAULT_GRAB_MAX,
        max_live       => $opts{max_live}       // 12,    # menos ruido (QA profe)
        max_events     => $opts{max_events}     // DEFAULT_MAX_EVENTS,
        # Prefer ZZ/SMC pivots. History buffer survives ZZ trim (15 segs visual).
        # k-swing solo si no hay ningún pivote externo acumulado.
        _external_pivots => undef,
        _pivot_history   => {},    # "index:side" => { index, price, side }
        _registered_ext  => {},    # "index:side" => 1
    };
    bless $self, $class;
    $self->reset();
    return $self;
}

sub reset {
    my ($self) = @_;
    $self->{_highs}       = [];
    $self->{_lows}        = [];
    $self->{_closes}      = [];
    $self->{_opens}       = [];
    $self->{_vols}        = [];
    $self->{_times}       = [];
    $self->{_atr}         = [];
    $self->{_tr_sum}      = 0;
    $self->{_last_atr}    = undef;
    $self->{_atr_count}   = 0;
    $self->{_prev_close}  = undef;
    $self->{_swings_high} = [];    # { index, price }
    $self->{_swings_low}  = [];
    $self->{_levels}      = [];    # live + resolved (kept for HISTORY draw)
    $self->{_events}      = [];    # resolved only
    $self->{_next_id}     = 1;
    $self->{_last_i}      = -1;
    $self->{_registered_ext} = {};
    # _pivot_history se limpia solo con reset_full (cambio TF / dataset)
    return $self;
}

# Reset total (cambio de TF o nuevo dataset): también borra pivotes acumulados.
sub reset_full {
    my ($self) = @_;
    $self->reset();
    $self->{_pivot_history}   = {};
    $self->{_external_pivots} = undef;
    return $self;
}

# Reset para rebobinar replay: limpia niveles/eventos pero conserva pivotes ZZ.
sub reset_soft {
    my ($self) = @_;
    my $hist = $self->{_pivot_history} || {};
    $self->reset();
    $self->{_pivot_history} = $hist;
    $self->_rebuild_external_from_history();
    return $self;
}

# Fusiona pivotes nuevos (ZZ/SMC) sin borrar los antiguos (arregla "mayo vacío").
# Devuelve cuántos pivotes NUEVOS se añadieron (ChartEngine puede refeed si >0).
sub absorb_pivots {
    my ( $self, $pivots ) = @_;
    return 0 unless $pivots && ref($pivots) eq 'ARRAY' && @$pivots;

    my $added = 0;
    for my $p (@$pivots) {
        next unless defined $p->{index} && defined $p->{price} && $p->{side};
        my $key = $p->{index} . ':' . $p->{side};
        next if $self->{_pivot_history}{$key};
        $self->{_pivot_history}{$key} = {
            index => $p->{index} + 0,
            price => $p->{price} + 0,
            side  => $p->{side},
        };
        $added++;
    }
    $self->_rebuild_external_from_history() if $added;
    return $added;
}

sub set_external_pivots {
    my ( $self, $pivots ) = @_;
    # Compat: reemplazo total solo si se llama set_external_pivots (tests).
    # Runtime debe preferir absorb_pivots.
    $self->{_pivot_history}   = {};
    $self->{_registered_ext}  = {};
    if ( defined $pivots && ref($pivots) eq 'ARRAY' && @$pivots ) {
        for my $p (@$pivots) {
            next unless defined $p->{index} && defined $p->{price} && $p->{side};
            my $key = $p->{index} . ':' . $p->{side};
            $self->{_pivot_history}{$key} = {
                index => $p->{index} + 0,
                price => $p->{price} + 0,
                side  => $p->{side},
            };
        }
        $self->_rebuild_external_from_history();
    }
    else {
        $self->{_external_pivots} = undef;
    }
    return $self;
}

sub _rebuild_external_from_history {
    my ($self) = @_;
    my @list =
      sort { $a->{index} <=> $b->{index} || $a->{side} cmp $b->{side} }
      values %{ $self->{_pivot_history} || {} };
    $self->{_external_pivots} = @list ? \@list : undef;
    return $self;
}

sub update_last {
    my ( $self, $md, $i ) = @_;
    return $self unless $md && defined $i && $i >= 0;

    my $c = $md->get_candle($i);
    return $self unless $c;

    my ( $ts, $o, $h, $l, $cl, $v ) =
      ( $c->[0], $c->[1], $c->[2], $c->[3], $c->[4], $c->[5] // 0 );

    $self->{_times}[$i]  = $ts;
    $self->{_opens}[$i]  = $o;
    $self->{_highs}[$i]  = $h;
    $self->{_lows}[$i]   = $l;
    $self->{_closes}[$i] = $cl;
    $self->{_vols}[$i]   = $v;

    $self->_update_atr( $i, $h, $l, $cl );
    $self->_detect_swings_at($i);
    $self->_advance_levels($i);

    $self->{_last_i} = $i;
    return $self;
}

sub get_values {
    my ($self) = @_;
    return {
        levels => [ map { {%$_} } @{ $self->{_levels} } ],
        events => [ map { {%$_} } @{ $self->{_events} } ],
        swings_high => [ map { {%$_} } @{ $self->{_swings_high} } ],
        swings_low  => [ map { {%$_} } @{ $self->{_swings_low} } ],
        last_index  => $self->{_last_i},
        pivot_count => scalar keys %{ $self->{_pivot_history} || {} },
    };
}

sub pivot_history_count {
    my ($self) = @_;
    return scalar keys %{ $self->{_pivot_history} || {} };
}

sub get_levels {
    my ($self) = @_;
    return [ map { {%$_} } @{ $self->{_levels} } ];
}

sub get_events {
    my ($self) = @_;
    return [ map { {%$_} } @{ $self->{_events} } ];
}

# Filas candidatas para la tablota t-SNE/GMM (metadato time/event_id aparte).
sub export_liquidity_events {
    my ($self) = @_;
    my @out;
    for my $ev ( @{ $self->{_events} } ) {
        push @out, {
            event_id    => $ev->{id},
            time        => $ev->{time},
            index       => $ev->{resolve_index},
            level_kind  => $ev->{level_kind},
            level_price => $ev->{price},
            side        => $ev->{side},
            kind        => $ev->{kind} // undef,
            event       => $ev->{resolution},    # sweep|grab|run
            pivot_index => $ev->{pivot_index},
            sweep_index => $ev->{sweep_index},
            bars_to_resolve => $ev->{bars_to_resolve},
            features    => {
                dist_pips_placeholder => 0,     # fase modelos: convertir a pips
                atr_at_sweep => $ev->{atr_at_sweep},
                vol_at_sweep => $ev->{vol_at_sweep},
            },
        };
    }
    return \@out;
}

# Serie densa por vela (etiquetas para HMM).
sub get_observation_stream {
    my ($self) = @_;
    my $last = $self->{_last_i};
    return [] if $last < 0;

    my @stream;
    for my $i ( 0 .. $last ) {
        my @labels;
        for my $lv ( @{ $self->{_levels} } ) {
            next unless defined $lv->{pivot_index} && $lv->{pivot_index} <= $i;
            if ( ( $lv->{state} // '' ) eq 'detected' || ( $lv->{state} // '' ) eq 'swept' ) {
                push @labels, uc( $lv->{kind} ) if $lv->{kind};
            }
            if ( defined $lv->{resolve_index} && $lv->{resolve_index} == $i && $lv->{resolution} ) {
                push @labels, uc( $lv->{resolution} );
            }
        }
        for my $ev ( @{ $self->{_events} } ) {
            if ( defined $ev->{resolve_index} && $ev->{resolve_index} == $i ) {
                push @labels, uc( $ev->{resolution} ) if $ev->{resolution};
                push @labels, uc( $ev->{level_kind} ) if $ev->{level_kind};
            }
            if ( defined $ev->{sweep_index} && $ev->{sweep_index} == $i ) {
                push @labels, 'SWEPT';
            }
        }
        # dedupe
        my %seen;
        @labels = grep { !$seen{$_}++ } @labels;
        push @stream, {
            index  => $i,
            labels => \@labels,
            kind   => undef,    # internal|external en v1.5
        };
    }
    return \@stream;
}

# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

sub _update_atr {
    my ( $self, $i, $h, $l, $cl ) = @_;
    my $period = $self->{atr_period} // DEFAULT_ATR_PERIOD;
    my $tr;
    if ( !defined $self->{_prev_close} ) {
        $tr = $h - $l;
    }
    else {
        my $pc = $self->{_prev_close};
        my $a  = $h - $l;
        my $b  = abs( $h - $pc );
        my $c  = abs( $l - $pc );
        $tr = $a;
        $tr = $b if $b > $tr;
        $tr = $c if $c > $tr;
    }
    $self->{_prev_close} = $cl;
    $self->{_atr_count}++;
    my $n = $self->{_atr_count};
    if ( $n < $period ) {
        $self->{_tr_sum} += $tr;
        $self->{_atr}[$i] = undef;
    }
    elsif ( $n == $period ) {
        $self->{_tr_sum} += $tr;
        $self->{_last_atr} = $self->{_tr_sum} / $period;
        $self->{_atr}[$i]  = $self->{_last_atr};
    }
    else {
        $self->{_last_atr} =
          ( $self->{_last_atr} * ( $period - 1 ) + $tr ) / $period;
        $self->{_atr}[$i] = $self->{_last_atr};
    }
    return;
}

sub _atr_at {
    my ( $self, $i ) = @_;
    return $self->{_last_atr}
      if !defined $i || $i < 0 || !defined $self->{_atr}[$i];
    return $self->{_atr}[$i] // $self->{_last_atr};
}

sub _detect_swings_at {
    my ( $self, $i ) = @_;
    my $k = $self->{k} // DEFAULT_K;
    return if $i < 2 * $k;

    # Pivot candidate index confirmed at bar i: pivot = i - k
    my $p = $i - $k;
    return if $p < $k;

    if ( $self->{_external_pivots} ) {
        # Pivotes ya confirmados (ZZ/SMC): registrar al llegar a su índice (no i-k).
        for my $pv ( @{ $self->{_external_pivots} } ) {
            my $ix   = $pv->{index};
            my $side = $pv->{side} // '';
            next unless defined $ix && $ix == $i;
            my $key = $ix . ':' . $side;
            next if $self->{_registered_ext}{$key}++;
            if ( $side eq 'high' ) {
                $self->_register_swing_high( $ix, $pv->{price} );
            }
            elsif ( $side eq 'low' ) {
                $self->_register_swing_low( $ix, $pv->{price} );
            }
        }
        return;
    }

    my $h = $self->{_highs};
    my $l = $self->{_lows};
    my $hp = $h->[$p];
    my $lp = $l->[$p];
    return unless defined $hp && defined $lp;

    my $is_sh = 1;
    my $is_sl = 1;
    for my $j ( 1 .. $k ) {
        my $hl = $h->[ $p - $j ];
        my $hr = $h->[ $p + $j ];
        my $ll = $l->[ $p - $j ];
        my $lr = $l->[ $p + $j ];
        $is_sh = 0 if !defined $hl || !defined $hr || $hp < $hl || $hp < $hr;
        $is_sl = 0 if !defined $ll || !defined $lr || $lp > $ll || $lp > $lr;
        last if !$is_sh && !$is_sl;
    }

    $self->_register_swing_high( $p, $hp ) if $is_sh;
    $self->_register_swing_low( $p, $lp )  if $is_sl;
    return;
}

sub _register_swing_high {
    my ( $self, $idx, $price ) = @_;
    return unless defined $idx && defined $price;
    for my $s ( @{ $self->{_swings_high} } ) {
        return if $s->{index} == $idx;
    }
    push @{ $self->{_swings_high} }, { index => $idx, price => $price };
    $self->_add_level(
        kind        => 'BSL',
        price       => $price,
        pivot_index => $idx,
        side        => 'bear',    # stops above highs → buy-side liquidity
    );
    $self->_try_equal_highs( $idx, $price );
    return;
}

sub _register_swing_low {
    my ( $self, $idx, $price ) = @_;
    return unless defined $idx && defined $price;
    for my $s ( @{ $self->{_swings_low} } ) {
        return if $s->{index} == $idx;
    }
    push @{ $self->{_swings_low} }, { index => $idx, price => $price };
    $self->_add_level(
        kind        => 'SSL',
        price       => $price,
        pivot_index => $idx,
        side        => 'bull',
    );
    $self->_try_equal_lows( $idx, $price );
    return;
}

sub _tolerance {
    my ( $self, $i ) = @_;
    my $atr = $self->_atr_at($i);
    my $mult = $self->{eq_atr_mult} // DEFAULT_EQ_ATR_MULT;
    return ( defined $atr && $atr > 0 ) ? ( $atr * $mult ) : 0;
}

sub _try_equal_highs {
    my ( $self, $idx, $price ) = @_;
    my $tol = $self->_tolerance($idx);
    return if $tol <= 0;
    my @sh = @{ $self->{_swings_high} };
    return if @sh < 2;
    my $prev;
    for my $s ( reverse @sh ) {
        next if $s->{index} == $idx;
        if ( abs( $s->{price} - $price ) <= $tol ) {
            $prev = $s;
            last;
        }
    }
    return unless $prev;
    $self->_add_level(
        kind        => 'EQH',
        price       => ( $prev->{price} + $price ) / 2,
        pivot_index => $idx,
        pair_index  => $prev->{index},
        pair_price  => $prev->{price},
        side        => 'bear',
    );
    return;
}

sub _try_equal_lows {
    my ( $self, $idx, $price ) = @_;
    my $tol = $self->_tolerance($idx);
    return if $tol <= 0;
    my @sl = @{ $self->{_swings_low} };
    return if @sl < 2;
    my $prev;
    for my $s ( reverse @sl ) {
        next if $s->{index} == $idx;
        if ( abs( $s->{price} - $price ) <= $tol ) {
            $prev = $s;
            last;
        }
    }
    return unless $prev;
    $self->_add_level(
        kind        => 'EQL',
        price       => ( $prev->{price} + $price ) / 2,
        pivot_index => $idx,
        pair_index  => $prev->{index},
        pair_price  => $prev->{price},
        side        => 'bull',
    );
    return;
}

sub _add_level {
    my ( $self, %a ) = @_;
    my $kind  = $a{kind}  // '';
    my $price = $a{price};
    return unless defined $price;

    my $tol = $self->_tolerance( $a{pivot_index} // $self->{_last_i} );
    $tol = abs($price) * 1e-4 + 1e-6 if $tol <= 0;

    # No spamear BSL/SSL si ya hay un nivel vivo en la misma zona de precio.
    for my $lv ( @{ $self->{_levels} } ) {
        next if ( $lv->{state} // '' ) eq 'resolved';
        next unless defined $lv->{price};
        next if abs( $lv->{price} - $price ) > $tol;

        my $lk = $lv->{kind} // '';
        # EQH/EQL tiene prioridad: no añadir BSL/SSL encima
        if ( ( $kind eq 'BSL' || $kind eq 'SSL' )
            && ( $lk eq 'EQH' || $lk eq 'EQL' || $lk eq $kind ) )
        {
            return;
        }
        # No duplicar EQ del mismo par/zona
        if ( ( $kind eq 'EQH' || $kind eq 'EQL' ) && $lk eq $kind ) {
            return;
        }
    }

    my $id = $self->{_next_id}++;
    my $lv = {
        id               => $id,
        kind             => $kind,
        price            => $price,
        pivot_index      => $a{pivot_index},
        pair_index       => $a{pair_index},
        pair_price       => $a{pair_price},
        side             => $a{side},
        state            => 'detected',
        sweep_index      => undef,
        resolve_index    => undef,
        resolution       => undef,
        outside_streak   => 0,
        bars_since_sweep => 0,
        atr_at_sweep     => undef,
        vol_at_sweep     => undef,
        kind_liq         => undef,
    };
    push @{ $self->{_levels} }, $lv;

    # Si nace EQH/EQL, archivar BSL/SSL vivos en la misma zona (evita doble label)
    if ( $kind eq 'EQH' || $kind eq 'EQL' ) {
        my $want = $kind eq 'EQH' ? 'BSL' : 'SSL';
        for my $other ( @{ $self->{_levels} } ) {
            next if $other->{id} == $id;
            next if ( $other->{state} // '' ) eq 'resolved';
            next unless ( $other->{kind} // '' ) eq $want;
            next unless defined $other->{price};
            next if abs( $other->{price} - $price ) > $tol;
            $other->{state} = 'resolved';
            $other->{resolution} = 'superseded_by_eq';
            $other->{resolve_index} = $a{pivot_index};
        }
    }

    $self->_trim_live_levels();
    return $lv;
}

sub _trim_live_levels {
    my ($self) = @_;
    my $max = $self->{max_live} // DEFAULT_MAX_LIVE;
    my @live =
      grep { ( $_->{state} // '' ) eq 'detected' || ( $_->{state} // '' ) eq 'swept' }
      @{ $self->{_levels} };
    return if @live <= $max;

    # Drop oldest detected first (keep recent + all swept)
    my @detected = sort { $a->{pivot_index} <=> $b->{pivot_index} }
      grep { ( $_->{state} // '' ) eq 'detected' } @live;
    my $over = @live - $max;
    my %drop;
    for my $i ( 0 .. $over - 1 ) {
        last if $i > $#detected;
        $drop{ $detected[$i]{id} } = 1;
    }
    @{ $self->{_levels} } = grep { !$drop{ $_->{id} } } @{ $self->{_levels} };
    return;
}

sub _advance_levels {
    my ( $self, $i ) = @_;
    my $h  = $self->{_highs}[$i];
    my $l  = $self->{_lows}[$i];
    my $cl = $self->{_closes}[$i];
    return unless defined $h && defined $l && defined $cl;

    my $run_n    = $self->{run_accept_n}   // DEFAULT_RUN_ACCEPT;
    my $sweep_mx = $self->{sweep_max_bars} // DEFAULT_SWEEP_MAX;
    my $grab_mx  = $self->{grab_max_bars}  // DEFAULT_GRAB_MAX;

    for my $lv ( @{ $self->{_levels} } ) {
        next if ( $lv->{state} // '' ) eq 'resolved';
        my $price = $lv->{price};
        next unless defined $price;

        my $is_buy_side =
             ( $lv->{kind} // '' ) eq 'BSL'
          || ( $lv->{kind} // '' ) eq 'EQH'
          || ( ( $lv->{side} // '' ) eq 'bear' );

        if ( ( $lv->{state} // '' ) eq 'detected' ) {
            my $swept = $is_buy_side ? ( $h > $price ) : ( $l < $price );
            if ($swept) {
                $lv->{state}       = 'swept';
                $lv->{sweep_index} = $i;
                $lv->{bars_since_sweep} = 0;
                $lv->{outside_streak}   = 0;
                $lv->{atr_at_sweep}     = $self->_atr_at($i);
                $lv->{vol_at_sweep}     = $self->{_vols}[$i];
                # Same-bar reclaim? (classic PDF sweep on single candle)
                my $reclaimed =
                  $is_buy_side ? ( $cl < $price ) : ( $cl > $price );
                if ($reclaimed) {
                    $self->_resolve( $lv, $i, 'sweep' );
                }
                else {
                    my $outside =
                      $is_buy_side ? ( $cl > $price ) : ( $cl < $price );
                    $lv->{outside_streak} = $outside ? 1 : 0;
                }
            }
            next;
        }

        if ( ( $lv->{state} // '' ) eq 'swept' ) {
            $lv->{bars_since_sweep} =
              $i - ( $lv->{sweep_index} // $i );
            my $reclaimed =
              $is_buy_side ? ( $cl < $price ) : ( $cl > $price );
            my $outside =
              $is_buy_side ? ( $cl > $price ) : ( $cl < $price );

            if ($outside) {
                $lv->{outside_streak} = ( $lv->{outside_streak} // 0 ) + 1;
            }
            else {
                $lv->{outside_streak} = 0;
            }

            if ( ( $lv->{outside_streak} // 0 ) >= $run_n ) {
                $self->_resolve( $lv, $i, 'run' );
                next;
            }

            if ($reclaimed) {
                my $bars = $lv->{bars_since_sweep} // 0;
                # bars_since_sweep: 0 = same bar (already handled); 1 = next bar
                my $elapsed = $bars;    # bars after sweep bar
                if ( $elapsed <= $sweep_mx ) {
                    $self->_resolve( $lv, $i, 'sweep' );
                }
                elsif ( $elapsed <= $grab_mx ) {
                    $self->_resolve( $lv, $i, 'grab' );
                }
                else {
                    # Late reclaim → still grab-like rejection per audio spirit
                    $self->_resolve( $lv, $i, 'grab' );
                }
                next;
            }
        }
    }
    return;
}

sub _resolve {
    my ( $self, $lv, $i, $resolution ) = @_;
    return if ( $lv->{state} // '' ) eq 'resolved';
    $lv->{state}         = 'resolved';
    $lv->{resolution}    = $resolution;
    $lv->{resolve_index} = $i;
    $lv->{bars_to_resolve} =
      defined $lv->{sweep_index} ? ( $i - $lv->{sweep_index} ) : 0;

    my $ev = {
        id            => $lv->{id},
        level_kind    => $lv->{kind},
        price         => $lv->{price},
        side          => $lv->{side},
        kind          => $lv->{kind_liq},
        pivot_index   => $lv->{pivot_index},
        pair_index    => $lv->{pair_index},
        sweep_index   => $lv->{sweep_index},
        resolve_index => $i,
        resolution    => $resolution,
        bars_to_resolve => $lv->{bars_to_resolve},
        atr_at_sweep  => $lv->{atr_at_sweep},
        vol_at_sweep  => $lv->{vol_at_sweep},
        time          => $self->{_times}[$i],
    };
    push @{ $self->{_events} }, $ev;

    my $max_e = $self->{max_events} // DEFAULT_MAX_EVENTS;
    while ( @{ $self->{_events} } > $max_e ) {
        shift @{ $self->{_events} };
    }
    return $ev;
}

1;
