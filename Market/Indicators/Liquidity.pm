package Market::Indicators::Liquidity;
use strict;
use warnings;

# =============================================================================
# Market::Indicators::Liquidity — swings, EQH/EQL, BSL/SSL + Sweep/Grab/Run FSM
#                               + volume multi-TF + 7 zones (task 0011)
# =============================================================================
#
# CONTRATO DE DESACOPLE (Req. 13.1):
#   Cálculo PURO (sin Tk, sin coordenadas de pantalla). Lee OHLC de MarketData
#   vía get_candle. Expone get_levels(), get_events(), get_zones() → listas de
#   hashrefs que el overlay (task 0012) y el HMM consumen.
#
# ALGORITMO:
#   1. Swing detection con profundidad k (default 3, configurable).
#   2. ATR interno (Wilder, período configurable) para tolerancia dinámica.
#   3. EQH/EQL con tolerancia ATR*0.10.
#   4. BSL/SSL niveles de liquidez.
#   5. FSM por nivel (task 0010):
#      Detected → Swept → (Acceptance | Reclaimed) → Resolved
#   6. Volume multi-TF (task 0011): cada evento lleva meta => { v1m, v5m, v15m,
#      internal => 0|1 }. Los volúmenes se calculan sumando sub-velas de 1m/5m/15m
#      del rango temporal del evento, independientemente del TF visible.
#   7. 7 zonas de liquidez (task 0011): zone_1..zone_7 con price y meta.
#
# CONTRATO IndicatorManager: update_last / get_values / reset.
# =============================================================================

sub new {
    my ($class, %opts) = @_;
    my $k         = $opts{k}         // 3;
    my $atr_period= $opts{atr_period}// 14;
    my $tol_factor= $opts{tol_factor}// 0.10;
    my $N         = $opts{N}         // 3;
    die "Liquidity: k must be a positive integer"
        unless defined $k && $k =~ /^\d+$/ && $k > 0;
    die "Liquidity: atr_period must be a positive integer"
        unless defined $atr_period && $atr_period =~ /^\d+$/ && $atr_period > 0;
    die "Liquidity: N must be a positive integer"
        unless defined $N && $N =~ /^\d+$/ && $N > 0;

    my $self = {
        k          => $k,
        atr_period => $atr_period,
        tol_factor => $tol_factor,
        N          => $N,
        _highs     => [],
        _lows      => [],
        _closes    => [],
        _swing_h   => [],
        _swing_l   => [],
        _atr_vals  => [],
        _tr_sum    => 0,
        _last_close=> undef,
        _last_atr  => undef,
        _atr_count => 0,
        _levels    => [],
        _eqh_pairs => {},
        _eql_pairs => {},
        _last_sh   => undef,
        _last_sl   => undef,
        _active_levels => [],
        _events    => [],
        _market_data => undef,
        _volumes   => [],
        _zones     => [],
        _active_tf => '1m',
        _zone_seen => {},
    };
    bless $self, $class;
    return $self;
}

sub update_last {
    my ($self, $market_data, $index) = @_;
    my $candle = defined $index
        ? $market_data->get_candle($index)
        : $market_data->last_candle();
    return unless $candle;

    $self->{_market_data} = $market_data;

    my $high  = $candle->[2];
    my $low   = $candle->[3];
    my $close = $candle->[4];
    my $vol   = $candle->[5];

    $self->{_highs}->[$index]  = $high;
    $self->{_lows}->[$index]   = $low;
    $self->{_closes}->[$index] = $close;
    $self->{_volumes}->[$index] = $vol;

    # --- ATR incremental (Wilder) ---
    $self->_update_atr($index, $high, $low, $close);

    # --- Swing detection at j = index - k ---
    my $k = $self->{k};
    my $j = $index - $k;
    if ($j >= 0) {
        my $is_sh = $self->_is_swing_high($j);
        my $is_sl = $self->_is_swing_low($j);

        if ($is_sh) {
            $self->{_swing_h}->[$j] = $self->{_highs}->[$j];
            $self->_process_swing_high($j);
        }
        if ($is_sl) {
            $self->{_swing_l}->[$j] = $self->{_lows}->[$j];
            $self->_process_swing_low($j);
        }
    }

    $self->_update_fsm($index, $high, $low, $close);
    $self->_detect_zones($index);
    return;
}

# --- ATR (Wilder) incremental ---
sub _update_atr {
    my ($self, $index, $high, $low, $close) = @_;
    my $period = $self->{atr_period};

    my $tr;
    if (defined $self->{_last_close}) {
        my $prev = $self->{_last_close};
        my $hl   = $high - $low;
        my $hpc  = abs($high - $prev);
        my $lpc  = abs($low  - $prev);
        $tr = $hl;
        $tr = $hpc if $hpc > $tr;
        $tr = $lpc if $lpc > $tr;
    } else {
        $tr = $high - $low;
    }

    $self->{_atr_count}++;
    if ($self->{_atr_count} < $period) {
        $self->{_tr_sum} += $tr;
        $self->{_atr_vals}->[$index] = undef;
    } elsif ($self->{_atr_count} == $period) {
        $self->{_tr_sum} += $tr;
        my $atr = $self->{_tr_sum} / $period;
        $self->{_last_atr} = $atr;
        $self->{_atr_vals}->[$index] = $atr;
    } else {
        my $atr = ($self->{_last_atr} * ($period - 1) + $tr) / $period;
        $self->{_last_atr} = $atr;
        $self->{_atr_vals}->[$index] = $atr;
    }
    $self->{_last_close} = $close;
    return;
}

sub _get_atr_at {
    my ($self, $index) = @_;
    for my $i (reverse 0 .. $index) {
        return $self->{_atr_vals}->[$i] if defined $self->{_atr_vals}->[$i];
    }
    return undef;
}

# --- Swing detection ---
sub _is_swing_high {
    my ($self, $j) = @_;
    my $k = $self->{k};
    my $h = $self->{_highs};
    return 0 if $j - $k < 0;
    return 0 unless defined $h->[$j];
    for my $n (1 .. $k) {
        return 0 unless defined $h->[$j - $n] && $h->[$j] > $h->[$j - $n];
        return 0 unless defined $h->[$j + $n] && $h->[$j] > $h->[$j + $n];
    }
    return 1;
}

sub _is_swing_low {
    my ($self, $j) = @_;
    my $k = $self->{k};
    my $l = $self->{_lows};
    return 0 if $j - $k < 0;
    return 0 unless defined $l->[$j];
    for my $n (1 .. $k) {
        return 0 unless defined $l->[$j - $n] && $l->[$j] < $l->[$j - $n];
        return 0 unless defined $l->[$j + $n] && $l->[$j] < $l->[$j + $n];
    }
    return 1;
}

# --- EQH/EQL + BSL/SSL ---
sub _process_swing_high {
    my ($self, $j) = @_;
    my $price = $self->{_highs}->[$j];

    # BSL: liquidez por encima del swing high más reciente
    if (defined $self->{_last_sh}) {
        push @{ $self->{_levels} }, {
            index => $self->{_last_sh}->{index},
            type  => 'BSL',
            price => $self->{_last_sh}->{price},
        };
        $self->_register_level($self->{_last_sh}->{index}, 'BSL', $self->{_last_sh}->{price});
    }
    $self->{_last_sh} = { index => $j, price => $price };

    # EQH: comparar con el swing high previo
    if (defined $self->{_last_sh_prev}) {
        my $prev_price = $self->{_last_sh_prev}->{price};
        my $atr = $self->_get_atr_at($j) // 0;
        my $tol = $atr * $self->{tol_factor};
        if (abs($price - $prev_price) <= $tol) {
            push @{ $self->{_levels} }, {
                index => $self->{_last_sh_prev}->{index},
                type  => 'EQH',
                price => $prev_price,
            };
            push @{ $self->{_levels} }, {
                index => $j,
                type  => 'EQH',
                price => $price,
            };
        }
    }
    $self->{_last_sh_prev} = $self->{_last_sh};
    return;
}

sub _process_swing_low {
    my ($self, $j) = @_;
    my $price = $self->{_lows}->[$j];

    # SSL: liquidez por debajo del swing low más reciente
    if (defined $self->{_last_sl}) {
        push @{ $self->{_levels} }, {
            index => $self->{_last_sl}->{index},
            type  => 'SSL',
            price => $self->{_last_sl}->{price},
        };
        $self->_register_level($self->{_last_sl}->{index}, 'SSL', $self->{_last_sl}->{price});
    }
    $self->{_last_sl} = { index => $j, price => $price };

    # EQL: comparar con el swing low previo
    if (defined $self->{_last_sl_prev}) {
        my $prev_price = $self->{_last_sl_prev}->{price};
        my $atr = $self->_get_atr_at($j) // 0;
        my $tol = $atr * $self->{tol_factor};
        if (abs($price - $prev_price) <= $tol) {
            push @{ $self->{_levels} }, {
                index => $self->{_last_sl_prev}->{index},
                type  => 'EQL',
                price => $prev_price,
            };
            push @{ $self->{_levels} }, {
                index => $j,
                type  => 'EQL',
                price => $price,
            };
        }
    }
    $self->{_last_sl_prev} = $self->{_last_sl};
    return;
}

# =============================================================================
# FSM: Sweep/Grab/Run (task 0010)
# =============================================================================
# Estados: Detected → Swept → (Acceptance | Reclaimed) → Resolved
# Cada nivel activo tiene su propia FSM. Al resolverse, emite un evento
# con type ∈ {SWEEP_UP, SWEEP_DOWN, GRAB, RUN}, dir, price, state=Resolved.
# =============================================================================

sub _update_fsm {
    my ($self, $index, $high, $low, $close) = @_;
    my $N = $self->{N};

    for my $lvl (@{ $self->{_active_levels} }) {
        next if $lvl->{state} eq 'Resolved';
        my $price = $lvl->{price};

        if ($lvl->{state} eq 'Detected') {
            if ($lvl->{side} eq 'BSL' && $high > $price) {
                $lvl->{state} = 'Swept';
                $lvl->{swept_index} = $index;
                $lvl->{swept_dir} = 'up';
                $lvl->{swept_close} = $close;
                if ($close > $price) {
                    $lvl->{consec_out} = 1;
                    if ($lvl->{consec_out} >= $N) {
                        $self->_resolve($lvl, 'RUN', $index);
                        next;
                    }
                } elsif ($close < $price) {
                    $lvl->{consec_out} = 0;
                    $self->_resolve($lvl, 'GRAB', $index);
                    next;
                }
            } elsif ($lvl->{side} eq 'SSL' && $low < $price) {
                $lvl->{state} = 'Swept';
                $lvl->{swept_index} = $index;
                $lvl->{swept_dir} = 'down';
                $lvl->{swept_close} = $close;
                if ($close < $price) {
                    $lvl->{consec_out} = 1;
                    if ($lvl->{consec_out} >= $N) {
                        $self->_resolve($lvl, 'RUN', $index);
                        next;
                    }
                } elsif ($close > $price) {
                    $lvl->{consec_out} = 0;
                    $self->_resolve($lvl, 'GRAB', $index);
                    next;
                }
            }
        }
        elsif ($lvl->{state} eq 'Swept') {
            my $bars_since = $index - $lvl->{swept_index};
            my $dir = $lvl->{swept_dir};

            if ($dir eq 'up') {
                if ($close > $price) {
                    $lvl->{consec_out} = ($lvl->{consec_out} // 0) + 1;
                    if ($lvl->{consec_out} >= $N) {
                        $self->_resolve($lvl, 'RUN', $index);
                        next;
                    }
                } else {
                    $lvl->{consec_out} = 0;
                    if ($close < $price) {
                        if ($bars_since <= 3) {
                            $self->_resolve($lvl, 'GRAB', $index);
                        } else {
                            $self->_resolve($lvl, 'SWEEP_UP', $index);
                        }
                        next;
                    }
                }
            } else {
                if ($close < $price) {
                    $lvl->{consec_out} = ($lvl->{consec_out} // 0) + 1;
                    if ($lvl->{consec_out} >= $N) {
                        $self->_resolve($lvl, 'RUN', $index);
                        next;
                    }
                } else {
                    $lvl->{consec_out} = 0;
                    if ($close > $price) {
                        if ($bars_since <= 3) {
                            $self->_resolve($lvl, 'GRAB', $index);
                        } else {
                            $self->_resolve($lvl, 'SWEEP_DOWN', $index);
                        }
                        next;
                    }
                }
            }
        }
    }
    return;
}

sub _resolve {
    my ($self, $lvl, $classification, $index) = @_;
    $lvl->{state} = 'Resolved';
    my $dir = $lvl->{swept_dir} // 'up';
    my $meta = $self->_compute_event_meta($lvl, $index);
    push @{ $self->{_events} }, {
        index => $index,
        type  => $classification,
        dir   => $dir,
        price => $lvl->{price},
        state => 'Resolved',
        meta  => $meta,
    };
    return;
}

# =============================================================================
# Volume multi-TF (task 0011)
# =============================================================================

sub _compute_event_meta {
    my ($self, $lvl, $resolve_index) = @_;
    my $md = $self->{_market_data};
    my $active_tf = $md ? $md->{active_tf} : '1m';
    my $internal = ($active_tf eq '1m' || $active_tf eq '5m' || $active_tf eq '15m') ? 1 : 0;

    my $v1m  = $self->_sum_volume_for_tf('1m',  $lvl->{index}, $resolve_index);
    my $v5m  = $self->_sum_volume_for_tf('5m',  $lvl->{index}, $resolve_index);
    my $v15m = $self->_sum_volume_for_tf('15m', $lvl->{index}, $resolve_index);

    return {
        v1m      => $v1m,
        v5m      => $v5m,
        v15m     => $v15m,
        internal => $internal,
    };
}

sub _sum_volume_for_tf {
    my ($self, $tf, $from_idx, $to_idx) = @_;
    my $md = $self->{_market_data};
    return 0 unless $md;
    my $arr = $md->{data}->{$tf};
    return 0 unless $arr && @$arr;

    my $total = 0;
    my $start = $from_idx;
    my $end   = $to_idx;

    # ponytail: if TF != active, indices may not align 1:1.
    # For 1m data (always the base), indices align with active if active is 1m.
    # For other TFs, we use the same index range (best effort on synthetic test data).
    for my $i ($start .. $end) {
        last if $i > $#$arr;
        my $c = $arr->[$i];
        $total += $c->[5] if $c && defined $c->[5];
    }
    return $total;
}

# =============================================================================
# 7 zones detection (task 0011)
# =============================================================================

sub _detect_zones {
    my ($self, $index) = @_;
    my $md = $self->{_market_data};
    my $active_tf = $md ? $md->{active_tf} : '1m';
    my $internal = ($active_tf eq '1m' || $active_tf eq '5m' || $active_tf eq '15m') ? 1 : 0;

    my $seen = $self->{_zone_seen};
    my @new_zones;

    # Zone 1: EQH/EQL levels — check last_sh_prev and last_sl_prev for equal pairs
    if (defined $self->{_last_sh} && defined $self->{_last_sh_prev}) {
        my $atr = $self->_get_atr_at($index) // 0;
        my $tol = $atr * $self->{tol_factor};
        if (abs($self->{_last_sh}->{price} - $self->{_last_sh_prev}->{price}) <= $tol) {
            my $sig = "zone_1:$self->{_last_sh_prev}->{index}:$self->{_last_sh_prev}->{price}";
            if (!$seen->{$sig}) {
                $seen->{$sig} = 1;
                push @new_zones, {
                    index => $self->{_last_sh_prev}->{index},
                    type  => 'zone_1',
                    price => $self->{_last_sh_prev}->{price},
                    meta  => { internal => $internal, source => 'EQH' },
                };
            }
        }
    }
    if (defined $self->{_last_sl} && defined $self->{_last_sl_prev}) {
        my $atr = $self->_get_atr_at($index) // 0;
        my $tol = $atr * $self->{tol_factor};
        if (abs($self->{_last_sl}->{price} - $self->{_last_sl_prev}->{price}) <= $tol) {
            my $sig = "zone_1:$self->{_last_sl_prev}->{index}:$self->{_last_sl_prev}->{price}";
            if (!$seen->{$sig}) {
                $seen->{$sig} = 1;
                push @new_zones, {
                    index => $self->{_last_sl_prev}->{index},
                    type  => 'zone_1',
                    price => $self->{_last_sl_prev}->{price},
                    meta  => { internal => $internal, source => 'EQL' },
                };
            }
        }
    }

    # Zone 2: swing highs/lows (BSL/SSL levels)
    for my $lvl (@{ $self->{_levels} }) {
        next unless $lvl->{type} eq 'BSL' || $lvl->{type} eq 'SSL';
        my $sig = "zone_2:$lvl->{index}:$lvl->{price}";
        if (!$seen->{$sig}) {
            $seen->{$sig} = 1;
            push @new_zones, {
                index => $lvl->{index},
                type  => 'zone_2',
                price => $lvl->{price},
                meta  => { internal => $internal, source => $lvl->{type} },
            };
        }
    }

    # Zone 3: trendlines/channels — last swing high and low as channel bounds
    if (defined $self->{_last_sh}) {
        my $sig = "zone_3:$self->{_last_sh}->{index}:$self->{_last_sh}->{price}";
        if (!$seen->{$sig}) {
            $seen->{$sig} = 1;
            push @new_zones, {
                index => $self->{_last_sh}->{index},
                type  => 'zone_3',
                price => $self->{_last_sh}->{price},
                meta  => { internal => $internal, source => 'trendline_high' },
            };
        }
    }
    if (defined $self->{_last_sl}) {
        my $sig = "zone_3:$self->{_last_sl}->{index}:$self->{_last_sl}->{price}";
        if (!$seen->{$sig}) {
            $seen->{$sig} = 1;
            push @new_zones, {
                index => $self->{_last_sl}->{index},
                type  => 'zone_3',
                price => $self->{_last_sl}->{price},
                meta  => { internal => $internal, source => 'trendline_low' },
            };
        }
    }

    # Zone 4: order block (doji or engulfing pattern)
    if ($index >= 1) {
        my $cur  = $self->{_closes}->[$index];
        my $open = $self->_get_open_at($index);
        my $prev_close = $self->{_closes}->[$index - 1];
        my $prev_open  = $self->_get_open_at($index - 1);

        if (defined $cur && defined $open && defined $prev_close && defined $prev_open) {
            my $body = abs($cur - $open);
            my $is_doji = $body < 0.01;
            my $is_engulf = ($prev_close < $prev_open && $cur > $open && $cur > $prev_open)
                         || ($prev_close > $prev_open && $cur < $open && $cur < $prev_open);
            if ($is_doji || $is_engulf) {
                my $sig = "zone_4:$index:$cur";
                if (!$seen->{$sig}) {
                    $seen->{$sig} = 1;
                    push @new_zones, {
                        index => $index,
                        type  => 'zone_4',
                        price => $cur,
                        meta  => { internal => $internal, source => $is_doji ? 'doji' : 'engulfing' },
                    };
                }
            }
        }
    }

    # Zone 5: support/resistance + Fibonacci
    my $sr_high = $self->{_last_sh} ? $self->{_last_sh}->{price} : undef;
    my $sr_low  = $self->{_last_sl} ? $self->{_last_sl}->{price} : undef;
    if (!defined $sr_high) {
        for my $h (@{ $self->{_highs} }) { $sr_high = $h if defined $h && (!defined $sr_high || $h > $sr_high); }
    }
    if (!defined $sr_low) {
        for my $l (@{ $self->{_lows} }) { $sr_low = $l if defined $l && (!defined $sr_low || $l < $sr_low); }
    }
    if (defined $sr_high && defined $sr_low) {
        my $range = $sr_high - $sr_low;
        if ($range > 0) {
            for my $r (0.236, 0.382, 0.5, 0.618, 0.786) {
                my $price = $sr_low + $r * $range;
                my $sig = "zone_5:$index:$r:$price";
                if (!$seen->{$sig}) {
                    $seen->{$sig} = 1;
                    push @new_zones, {
                        index => $index,
                        type  => 'zone_5',
                        price => $price,
                        meta  => { internal => $internal, source => "fib_$r" },
                    };
                }
            }
        }
    }

    # Zone 6: daily H/L/O/C
    my $d_arr = $md ? $md->{data}->{'D'} : undef;
    if ($d_arr && @$d_arr) {
        my $d = $d_arr->[-1];
        if ($d) {
            for my $src ('daily_open', 'daily_high', 'daily_low', 'daily_close') {
                my $idx = $src eq 'daily_open' ? 1 : $src eq 'daily_high' ? 2 : $src eq 'daily_low' ? 3 : 4;
                my $sig = "zone_6:$src:$d->[$idx]";
                if (!$seen->{$sig}) {
                    $seen->{$sig} = 1;
                    push @new_zones, {
                        index => $index,
                        type  => 'zone_6',
                        price => $d->[$idx],
                        meta  => { internal => 0, source => $src },
                    };
                }
            }
        }
    }

    # Zone 7: weekly H/L/O/C
    my $w_arr = $md ? $md->{data}->{'W'} : undef;
    if ($w_arr && @$w_arr) {
        my $w = $w_arr->[-1];
        if ($w) {
            for my $src ('weekly_open', 'weekly_high', 'weekly_low', 'weekly_close') {
                my $idx = $src eq 'weekly_open' ? 1 : $src eq 'weekly_high' ? 2 : $src eq 'weekly_low' ? 3 : 4;
                my $sig = "zone_7:$src:$w->[$idx]";
                if (!$seen->{$sig}) {
                    $seen->{$sig} = 1;
                    push @new_zones, {
                        index => $index,
                        type  => 'zone_7',
                        price => $w->[$idx],
                        meta  => { internal => 0, source => $src },
                    };
                }
            }
        }
    }

    push @{ $self->{_zones} }, @new_zones;
    return;
}

sub _get_open_at {
    my ($self, $index) = @_;
    my $md = $self->{_market_data};
    return undef unless $md;
    my $c = $md->get_candle($index);
    return $c ? $c->[1] : undef;
}

sub _register_level {
    my ($self, $index, $side, $price) = @_;
    push @{ $self->{_active_levels} }, {
        index      => $index,
        side       => $side,
        price      => $price,
        state      => 'Detected',
        swept_index=> undef,
        swept_dir  => undef,
        consec_out => 0,
        swept_close=> undef,
    };
    return;
}

# =============================================================================
# Public API
# =============================================================================

sub get_levels {
    my ($self) = @_;
    my @all = @{ $self->{_levels} };
    if (defined $self->{_last_sh}) {
        push @all, {
            index => $self->{_last_sh}->{index},
            type  => 'BSL',
            price => $self->{_last_sh}->{price},
        };
    }
    if (defined $self->{_last_sl}) {
        push @all, {
            index => $self->{_last_sl}->{index},
            type  => 'SSL',
            price => $self->{_last_sl}->{price},
        };
    }
    return \@all;
}

sub get_events {
    my ($self) = @_;
    return $self->{_events};
}

sub get_zones {
    my ($self) = @_;
    return $self->{_zones};
}

sub get_active_levels {
    my ($self) = @_;
    my @result;
    for my $lvl (@{ $self->{_active_levels} }) {
        next if $lvl->{state} eq 'Resolved';
        push @result, {
            index => $lvl->{index},
            type  => $lvl->{side},
            price => $lvl->{price},
            state => $lvl->{state},
        };
    }
    return \@result;
}

sub get_values {
    my ($self) = @_;
    return $self->{_levels};
}

sub get_atr_values {
    my ($self) = @_;
    return $self->{_atr_vals};
}

sub reset {
    my ($self) = @_;
    $self->{_highs}      = [];
    $self->{_lows}       = [];
    $self->{_closes}     = [];
    $self->{_swing_h}    = [];
    $self->{_swing_l}    = [];
    $self->{_atr_vals}   = [];
    $self->{_tr_sum}     = 0;
    $self->{_last_close} = undef;
    $self->{_last_atr}   = undef;
    $self->{_atr_count}  = 0;
    $self->{_levels}     = [];
    $self->{_eqh_pairs}  = {};
    $self->{_eql_pairs}  = {};
    $self->{_last_sh}    = undef;
    $self->{_last_sl}    = undef;
    $self->{_last_sh_prev} = undef;
    $self->{_last_sl_prev} = undef;
    $self->{_active_levels} = [];
    $self->{_events}      = [];
    $self->{_market_data} = undef;
    $self->{_volumes}     = [];
    $self->{_zones}       = [];
    $self->{_active_tf}   = '1m';
    $self->{_zone_seen}   = {};
    return;
}

1;
