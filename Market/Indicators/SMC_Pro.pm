package Market::Indicators::SMC_Pro;
use strict;
use warnings;

# =============================================================================
# Market::Indicators::SMC_Pro — paridad Smart Money Concepts Pro [Neon]
# =============================================================================
# Referencia: docs/reference_indicators/smc_pro_neon.txt (+ luxalgo_smc.txt)
# Config canónica: captura del profesor (NO defaults Pine si chocan).
#
# Defaults captura + TV Bryan:
#   internal size=5, swing length=50, swing labels ON, strong/weak ON
#   internal structure ON, swing structure ON
#   internal OB OFF, swing OB ON count=5, ATR filter (parsed HVOL), mit High/Low
#   EQH/EQL ON bars=3 thr=0.1*ATR(200)
#   FVG Pro OFF; MTF Daily/Weekly/Monthly OFF (TV Bryan; profe viejo ON)
# Pine indicator(): max_labels_count=500, max_lines_count=500, max_boxes_count=500
# =============================================================================

use constant {
    BULLISH_LEG => 1,
    BEARISH_LEG => 0,
    BULLISH     => 1,
    BEARISH     => -1,
    # Paridad Pine indicator(..., max_lines_count=500, max_labels_count=500)
    MAX_LINES   => 500,
    MAX_LABELS  => 500,
};

sub new {
    my ($class, %opts) = @_;
    my $self = {
        # --- captura ---
        display_mode        => $opts{display_mode} // 'Historical',
        show_swing_labels   => exists $opts{show_swing_labels} ? ($opts{show_swing_labels} ? 1 : 0) : 1,
        show_strong_weak    => exists $opts{show_strong_weak} ? ($opts{show_strong_weak} ? 1 : 0) : 1,
        show_internal       => exists $opts{show_internal} ? ($opts{show_internal} ? 1 : 0) : 1,
        show_swing          => exists $opts{show_swing} ? ($opts{show_swing} ? 1 : 0) : 1,
        internal_size       => $opts{internal_size} // 5,
        swing_length        => $opts{swing_length} // 50,
        show_internal_ob    => exists $opts{show_internal_ob} ? ($opts{show_internal_ob} ? 1 : 0) : 0,
        show_swing_ob       => exists $opts{show_swing_ob} ? ($opts{show_swing_ob} ? 1 : 0) : 1,
        int_ob_count        => $opts{int_ob_count} // 5,
        sw_ob_count         => $opts{sw_ob_count} // 5,
        show_eqhl           => exists $opts{show_eqhl} ? ($opts{show_eqhl} ? 1 : 0) : 1,
        eqhl_size           => $opts{eqhl_size} // 3,
        eqhl_thr            => defined $opts{eqhl_thr} ? $opts{eqhl_thr} : 0.1,
        atr_len             => $opts{atr_len} // 200,
        # TV actual Bryan: Daily/Weekly/Monthly OFF (capturas 2026). Profe viejo ON.
        show_mtf_hl         => exists $opts{show_mtf_hl} ? ($opts{show_mtf_hl} ? 1 : 0) : 0,
        # FVG Pro: captura OFF
        show_fvg_pro        => 0,

        # OHLC series
        _o => [], _h => [], _l => [], _c => [], _t => [],
        _last_index => -1,

        # ATR(200) Wilder-ish
        _atr => undef,
        _tr_sum => 0,
        _atr_vals => [],

        # leg state per size key
        _leg => {},          # size => 0|1
        # pivots: swing / internal / equal
        _sw_hi => { level => undef, last => undef, crossed => 0, bar => undef },
        _sw_lo => { level => undef, last => undef, crossed => 0, bar => undef },
        _in_hi => { level => undef, last => undef, crossed => 0, bar => undef },
        _in_lo => { level => undef, last => undef, crossed => 0, bar => undef },
        _eq_hi => { level => undef, last => undef, crossed => 0, bar => undef },
        _eq_lo => { level => undef, last => undef, crossed => 0, bar => undef },
        _sw_trend => 0,   # BULLISH=1 BEARISH=-1
        _in_trend => 0,

        # trailing extremes for strong/weak
        _trail_top => undef,
        _trail_bot => undef,
        _trail_top_bar => undef,
        _trail_bot_bar => undef,

        # outputs
        _pivots  => [],   # HH/HL/LH/LL swing labels
        _events  => [],   # BOS/CHoCH internal|swing
        _eqhl    => [],   # EQH/EQL
        _obs     => [],   # order blocks (swing primarily)
        _strong_weak => [],
        _mtf_levels  => [],
        _values  => [],
    };
    bless $self, $class;
    return $self;
}

# Pine max_lines_count / max_labels_count: al superar, caen los más antiguos.
sub _push_capped {
    my ($self, $arr_key, $item, $max) = @_;
    return unless ref($item) eq 'HASH';
    my $arr = $self->{$arr_key};
    unless (ref($arr) eq 'ARRAY') {
        $arr = [];
        $self->{$arr_key} = $arr;
    }
    push @$arr, $item;
    my $n = @$arr;
    if ($n > $max) {
        splice @$arr, 0, $n - $max;
    }
    return;
}

# Presupuesto compartido de LÍNEAS (eventos BOS/CHoCH + EQ) = max_lines_count.
# Las etiquetas de pivote van en MAX_LABELS por separado.
# Recorte estable (shift del más antiguo). NO usar merge+sort sobre el buffer:
# reventaba Tk ("Not a HASH reference") en series largas y abortaba el draw.
sub _push_line_item {
    my ($self, $arr_key, $item) = @_;
    return unless ref($item) eq 'HASH';
    $self->{$arr_key} = [] unless ref($self->{$arr_key}) eq 'ARRAY';
    $self->{_events}  = [] unless ref($self->{_events}) eq 'ARRAY';
    $self->{_eqhl}    = [] unless ref($self->{_eqhl}) eq 'ARRAY';

    push @{ $self->{$arr_key} }, $item;

    my $total = @{ $self->{_events} } + @{ $self->{_eqhl} };
    while ($total > MAX_LINES) {
        my $e0 = $self->{_events}[0];
        my $q0 = $self->{_eqhl}[0];
        # Saltar basura no-hash si la hubiera
        if (defined $e0 && ref($e0) ne 'HASH') {
            shift @{ $self->{_events} };
            $total = @{ $self->{_events} } + @{ $self->{_eqhl} };
            next;
        }
        if (defined $q0 && ref($q0) ne 'HASH') {
            shift @{ $self->{_eqhl} };
            $total = @{ $self->{_events} } + @{ $self->{_eqhl} };
            next;
        }
        my $use_ev = !defined $q0;
        if (defined $e0 && defined $q0) {
            my $ei = $e0->{index} // 0;
            my $qi = $q0->{index} // 0;
            $use_ev = $ei <= $qi;
        }
        if ($use_ev && @{ $self->{_events} }) {
            shift @{ $self->{_events} };
        } elsif (@{ $self->{_eqhl} }) {
            shift @{ $self->{_eqhl} };
        } else {
            last;
        }
        $total = @{ $self->{_events} } + @{ $self->{_eqhl} };
    }
    return;
}

sub reset {
    my ($self) = @_;
    my $class = ref $self;
    my %keep = map { $_ => $self->{$_} } qw(
        display_mode show_swing_labels show_strong_weak show_internal show_swing
        internal_size swing_length show_internal_ob show_swing_ob int_ob_count sw_ob_count
        show_eqhl eqhl_size eqhl_thr atr_len show_mtf_hl show_fvg_pro
    );
    %$self = %{ $class->new(%keep) };
    return $self;
}

sub update_last {
    my ($self, $market_data, $index) = @_;
    my $candle = defined $index
        ? $market_data->get_candle($index)
        : $market_data->last_candle();
    return unless $candle;

    my ($ts, $o, $h, $l, $c) = ($candle->[0], $candle->[1], $candle->[2], $candle->[3], $candle->[4]);
    $self->{_o}[$index] = $o;
    $self->{_h}[$index] = $h;
    $self->{_l}[$index] = $l;
    $self->{_c}[$index] = $c;
    $self->{_t}[$index] = $ts;
    $self->{_last_index} = $index;
    $self->{_values}[$index] = undef;

    $self->_update_atr($index, $h, $l, $c);
    $self->_update_parsed($index, $h, $l);

    # Structure pivots: swing then internal then EQ
    $self->_get_current_structure($index, $self->{swing_length}, 0, 0);
    $self->_get_current_structure($index, $self->{internal_size}, 0, 1);
    if ($self->{show_eqhl}) {
        $self->_get_current_structure($index, $self->{eqhl_size}, 1, 0);
    }

    # Detect BOS/CHoCH + store OBs
    if ($self->{show_internal} || $self->{show_internal_ob}) {
        $self->_display_structure($index, 1);
    }
    if ($self->{show_swing} || $self->{show_swing_ob} || $self->{show_strong_weak}) {
        $self->_display_structure($index, 0);
    }

    # Mitigate OBs
    $self->_mitigate_order_blocks($index);

    # Strong / weak trailing
    if ($self->{show_strong_weak}) {
        $self->_update_trailing($index, $h, $l);
        $self->_refresh_strong_weak($index);
    }

    # MTF H/L (best-effort from timestamps)
    if ($self->{show_mtf_hl}) {
        $self->_update_mtf_levels($index);
    }

    return;
}

# --- ATR ---
sub _update_atr {
    my ($self, $i, $h, $l, $c) = @_;
    my $p = $self->{atr_len};
    my $tr = $h - $l;
    if ($i > 0 && defined $self->{_c}[$i - 1]) {
        my $pc = $self->{_c}[$i - 1];
        my $a = abs($h - $pc);
        my $b = abs($l - $pc);
        $tr = $a if $a > $tr;
        $tr = $b if $b > $tr;
    }
    if ($i < $p) {
        $self->{_tr_sum} += $tr;
        $self->{_atr} = $self->{_tr_sum} / ($i + 1);
    } else {
        my $prev = $self->{_atr} // $tr;
        $self->{_atr} = ($prev * ($p - 1) + $tr) / $p;
    }
    $self->{_atr_vals}[$i] = $self->{_atr};
}

# Pine: highVolatilityBar = (high-low) >= 2*ATR → swap high/low for OB extremes
sub _update_parsed {
    my ($self, $i, $h, $l) = @_;
    my $atr = $self->{_atr} // 0;
    my $range = $h - $l;
    my $high_vol = ($atr > 0 && $range >= 2 * $atr) ? 1 : 0;
    # high-vol: parsedHigh=low, parsedLow=high (Neon/LuxAlgo)
    if ($high_vol) {
        $self->{_ph}[$i] = $l;
        $self->{_pl}[$i] = $h;
    } else {
        $self->{_ph}[$i] = $h;
        $self->{_pl}[$i] = $l;
    }
}

sub _highest {
    my ($self, $from, $to) = @_;
    my $mx;
    for my $i ($from .. $to) {
        next unless defined $self->{_h}[$i];
        $mx = $self->{_h}[$i] if !defined $mx || $self->{_h}[$i] > $mx;
    }
    return $mx;
}

sub _lowest {
    my ($self, $from, $to) = @_;
    my $mn;
    for my $i ($from .. $to) {
        next unless defined $self->{_l}[$i];
        $mn = $self->{_l}[$i] if !defined $mn || $self->{_l}[$i] < $mn;
    }
    return $mn;
}

# leg(size) at bar i: pivot candidate at i-size (LuxAlgo/Neon).
# newHigh: high[i-size] > max(high[i-size+1 .. i])  → start of bearish leg (pivot high)
# newLow:  low[i-size]  < min(low[i-size+1 .. i])   → start of bullish leg (pivot low)
# Only emits when leg state *changes* (ta.change != 0).
# Pine: var legState = 0 (BEARISH). Primer newHigh es 0→0 → sin pivote.
sub _leg_at {
    my ($self, $i, $size) = @_;
    return (0, 0, 0) if $i < $size;
    my $pivot_i = $i - $size;
    my $hh = $self->_highest($pivot_i + 1, $i);
    my $ll = $self->_lowest($pivot_i + 1, $i);
    my $ph = $self->{_h}[$pivot_i];
    my $pl = $self->{_l}[$pivot_i];

    my $new_leg;
    my $is_high = 0;
    my $is_low  = 0;
    if (defined $ph && defined $hh && $ph > $hh) {
        $new_leg = BEARISH_LEG;
        $is_high = 1;
    } elsif (defined $pl && defined $ll && $pl < $ll) {
        $new_leg = BULLISH_LEG;
        $is_low = 1;
    } else {
        return (0, 0, 0);
    }

    # Pine legState inicia en BEARISH (0). Si aún no hay estado, sembrar 0
    # sin emitir pivote en el primer newHigh (change == 0).
    my $prev = $self->{_leg}{$size};
    if (!defined $prev) {
        $self->{_leg}{$size} = BEARISH_LEG;
        $prev = BEARISH_LEG;
    }
    if ($prev == $new_leg) {
        return (0, 0, 0);
    }
    $self->{_leg}{$size} = $new_leg;
    return (1, $is_high, $is_low);
}

sub _get_current_structure {
    my ($self, $i, $size, $equal_hl, $internal) = @_;
    return if $i < $size;
    my ($new_pivot, $is_high, $is_low) = $self->_leg_at($i, $size);
    return unless $new_pivot;

    my $pivot_i = $i - $size;
    my $atr = $self->{_atr} // 0;

    if ($is_low) {
        my $price = $self->{_l}[$pivot_i];
        my $p = $equal_hl ? $self->{_eq_lo} : $internal ? $self->{_in_lo} : $self->{_sw_lo};
        if ($equal_hl && defined $p->{level} && $atr > 0
            && abs($p->{level} - $price) < $self->{eqhl_thr} * $atr) {
            $self->_push_line_item('_eqhl', {
                index => $pivot_i,
                type  => 'EQL',
                price => $price,
                prev_price => $p->{level},
                prev_index => $p->{bar},
            });
        }
        $p->{last}    = $p->{level};
        $p->{level}   = $price;
        $p->{crossed} = 0;
        $p->{bar}     = $pivot_i;

        if (!$equal_hl && !$internal) {
            $self->{_trail_bot} = $price;
            $self->{_trail_bot_bar} = $pivot_i;
            if ($self->{show_swing_labels}) {
                my $label = (!defined $p->{last} || $price < $p->{last}) ? 'LL' : 'HL';
                # fix: last was already overwritten — use previous last before assign
            }
            # re-compute label from stored last before overwrite... we already overwrote.
            # Use: if last was undef first pivot skip; else compare price to last_level we saved
            my $prev_lvl = $p->{last};
            my $label = (!defined $prev_lvl || $price < $prev_lvl) ? 'LL' : 'HL';
            # Wait we set last = old level then level = price, so last is previous. Good.
            $label = (!defined $prev_lvl) ? 'LL' : ($price < $prev_lvl ? 'LL' : 'HL');
            if ($self->{show_swing_labels} && defined $prev_lvl) {
                $self->_push_capped('_pivots', {
                    index => $pivot_i, type => $label, price => $price, scope => 'swing',
                }, MAX_LABELS);
                $self->{_values}[$pivot_i] = $label;
            } elsif ($self->{show_swing_labels} && !defined $prev_lvl) {
                # Pine first low: current < last con last=na → falso → HL (no LL)
                $self->_push_capped('_pivots', {
                    index => $pivot_i, type => 'HL', price => $price, scope => 'swing',
                }, MAX_LABELS);
                $self->{_values}[$pivot_i] = 'HL';
            }
        }
    } else {
        # high pivot
        my $price = $self->{_h}[$pivot_i];
        my $p = $equal_hl ? $self->{_eq_hi} : $internal ? $self->{_in_hi} : $self->{_sw_hi};
        if ($equal_hl && defined $p->{level} && $atr > 0
            && abs($p->{level} - $price) < $self->{eqhl_thr} * $atr) {
            $self->_push_line_item('_eqhl', {
                index => $pivot_i,
                type  => 'EQH',
                price => $price,
                prev_price => $p->{level},
                prev_index => $p->{bar},
            });
        }
        $p->{last}    = $p->{level};
        $p->{level}   = $price;
        $p->{crossed} = 0;
        $p->{bar}     = $pivot_i;

        if (!$equal_hl && !$internal) {
            $self->{_trail_top} = $price;
            $self->{_trail_top_bar} = $pivot_i;
            my $prev_lvl = $p->{last};
            if ($self->{show_swing_labels}) {
                # Pine: current > last ? HH : LH; con last=na la comp. es falsa → LH
                my $label = (defined $prev_lvl && $price > $prev_lvl) ? 'HH' : 'LH';
                $self->_push_capped('_pivots', {
                    index => $pivot_i, type => $label, price => $price, scope => 'swing',
                }, MAX_LABELS);
                $self->{_values}[$pivot_i] = $label;
            }
        }
    }
}

# Primera vela j en (from, to] con cruce alcista de close sobre level (paridad ta.crossover).
sub _first_cross_up {
    my ($self, $from, $to, $level) = @_;
    return undef unless defined $level && defined $to;
    $from = -1 if !defined $from || $from < -1;
    my $start = $from + 1;
    $start = 0 if $start < 0;
    for my $j ($start .. $to) {
        my $c1 = $self->{_c}[$j];
        next unless defined $c1;
        my $c0 = $j > 0 ? $self->{_c}[$j - 1] : undef;
        # ta.crossover: prev <= level y actual > level (si no hay prev, solo actual > level)
        if ($c1 > $level && (!defined $c0 || $c0 <= $level)) {
            return $j;
        }
    }
    return undef;
}

# Primera vela j en (from, to] con cruce bajista (paridad ta.crossunder).
sub _first_cross_down {
    my ($self, $from, $to, $level) = @_;
    return undef unless defined $level && defined $to;
    $from = -1 if !defined $from || $from < -1;
    my $start = $from + 1;
    $start = 0 if $start < 0;
    for my $j ($start .. $to) {
        my $c1 = $self->{_c}[$j];
        next unless defined $c1;
        my $c0 = $j > 0 ? $self->{_c}[$j - 1] : undef;
        if ($c1 < $level && (!defined $c0 || $c0 >= $level)) {
            return $j;
        }
    }
    return undef;
}

sub _display_structure {
    my ($self, $i, $internal) = @_;
    my $close = $self->{_c}[$i];
    return unless defined $close;

    my $hi = $internal ? $self->{_in_hi} : $self->{_sw_hi};
    my $lo = $internal ? $self->{_in_lo} : $self->{_sw_lo};
    my $trend_key = $internal ? '_in_trend' : '_sw_trend';
    my $scope = $internal ? 'internal' : 'swing';
    my $show = $internal ? $self->{show_internal} : $self->{show_swing};
    my $show_ob = $internal ? $self->{show_internal_ob} : $self->{show_swing_ob};

    # Pine displayStructure: internal solo si nivel != swing (extraBull/extraBear).
    # Confluence filter del profe = OFF → bullishBar/bearishBar siempre true.
    # Si extra es false: NO marcar crossed ni cambiar trend (paridad Neon/LuxAlgo).
    my $extra_bull = 1;
    my $extra_bear = 1;
    if ($internal) {
        my $sw_hi = $self->{_sw_hi}{level};
        my $sw_lo = $self->{_sw_lo}{level};
        $extra_bull = !(defined $hi->{level} && defined $sw_hi && $hi->{level} == $sw_hi);
        $extra_bear = !(defined $lo->{level} && defined $sw_lo && $lo->{level} == $sw_lo);
    }

    # Bullish break: ta.crossover(close, level) en la barra actual (Pine).
    # Requiere close[i-1] definido (como series de TV); no "catch-up" histórico.
    if (defined $hi->{level} && !$hi->{crossed} && $extra_bull && $i > 0) {
        my $prev_c = $self->{_c}[$i - 1];
        my $is_cross = defined $prev_c
            && $prev_c <= $hi->{level}
            && $close > $hi->{level};
        if ($is_cross) {
            my $pivot_bar = $hi->{bar} // ($i - 1);
            my $end_i     = $i;
            my $bias = $self->{$trend_key};
            my $tag  = ($bias == BEARISH) ? 'CHoCH' : 'BOS';
            $hi->{crossed} = 1;
            $self->{$trend_key} = BULLISH;
            if ($show) {
                $self->_push_line_item('_events', {
                    index       => $end_i,
                    type        => $tag,
                    dir         => 'up',
                    price       => $hi->{level},
                    start_index => $pivot_bar,
                    scope       => $scope,
                    true        => 1,
                });
            }
            if ($show_ob) {
                $self->_store_order_block($end_i, $hi, BULLISH, $internal);
            }
        }
    }

    # Bearish break: ta.crossunder(close, level) en la barra actual
    if (defined $lo->{level} && !$lo->{crossed} && $extra_bear && $i > 0) {
        my $prev_c = $self->{_c}[$i - 1];
        my $is_cross = defined $prev_c
            && $prev_c >= $lo->{level}
            && $close < $lo->{level};
        if ($is_cross) {
            my $pivot_bar = $lo->{bar} // ($i - 1);
            my $end_i     = $i;
            my $bias = $self->{$trend_key};
            my $tag  = ($bias == BULLISH) ? 'CHoCH' : 'BOS';
            $lo->{crossed} = 1;
            $self->{$trend_key} = BEARISH;
            if ($show) {
                $self->_push_line_item('_events', {
                    index       => $end_i,
                    type        => $tag,
                    dir         => 'down',
                    price       => $lo->{level},
                    start_index => $pivot_bar,
                    scope       => $scope,
                    true        => 1,
                });
            }
            if ($show_ob) {
                $self->_store_order_block($end_i, $lo, BEARISH, $internal);
            }
        }
    }
}

sub _store_order_block {
    my ($self, $i, $pivot, $bias, $internal) = @_;
    # Captura: Internal OB OFF — no crear internos aunque se llame por error
    return if $internal && !$self->{show_internal_ob};
    return if !$internal && !$self->{show_swing_ob};

    my $from = $pivot->{bar};
    return unless defined $from && defined $i;

    # Pine storeOrderBlock (Neon / LuxAlgo):
    #   arr := parsedLows.slice(p.barIndex, bar_index)   # end EXCLUSIVO
    #   idx := p.barIndex + arr.indexof(arr.min())       # PRIMERA ocurrencia
    #   ob  := parsedHighs/Lows de esa barra
    # OB Volatility Filter = ATR → highVolatilityBar = (H-L) >= 2*ATR
    #   parsedHigh = HVOL ? low  : high
    #   parsedLow  = HVOL ? high : low
    # (_update_parsed rellena _ph/_pl). NO usar raw H/L: rompería paridad source.
    my $to = $i - 1;
    return if $to < $from;

    my ($best_ph, $best_pl, $best_i);
    for my $j ($from .. $to) {
        my $ph = $self->{_ph}[$j];
        my $pl = $self->{_pl}[$j];
        # Fallback solo si parsed no existe (barra sin update_parsed)
        $ph = $self->{_h}[$j] if !defined $ph;
        $pl = $self->{_l}[$j] if !defined $pl;
        next unless defined $ph && defined $pl;
        if ($bias == BEARISH) {
            if (!defined $best_ph || $ph > $best_ph) {
                $best_ph = $ph;
                $best_pl = $pl;
                $best_i  = $j;
            }
        } else {
            if (!defined $best_pl || $pl < $best_pl) {
                $best_ph = $ph;
                $best_pl = $pl;
                $best_i  = $j;
            }
        }
    }
    return unless defined $best_i && defined $best_ph && defined $best_pl;

    unshift @{ $self->{_obs} }, {
        index  => $best_i,
        hi     => $best_ph,
        lo     => $best_pl,
        bias   => $bias == BULLISH ? 'bull' : 'bear',
        scope  => $internal ? 'internal' : 'swing',
        active => 1,
        created_at => $i,
    };
    # Buffer acotado; get_order_blocks aplica count de captura (5)
    if (@{ $self->{_obs} } > 80) {
        $#{ $self->{_obs} } = 79;
    }
}

sub _mitigate_order_blocks {
    my ($self, $i) = @_;
    my $h = $self->{_h}[$i];
    my $l = $self->{_l}[$i];
    return unless defined $h && defined $l;
    # Mitigation source High/Low (captura Neon)
    for my $ob (@{ $self->{_obs} }) {
        next unless $ob->{active};
        # No mitigar en la misma vela de creación
        next if defined $ob->{created_at} && $ob->{created_at} >= $i;
        if ($ob->{bias} eq 'bear' && $h > $ob->{hi}) {
            $ob->{active} = 0;
        } elsif ($ob->{bias} eq 'bull' && $l < $ob->{lo}) {
            $ob->{active} = 0;
        }
    }
    # Podar inactivos para no crecer sin límite
    $self->{_obs} = [ grep { $_->{active} } @{ $self->{_obs} } ];
}

sub _update_trailing {
    my ($self, $i, $h, $l) = @_;
    if (!defined $self->{_trail_top} || $h >= $self->{_trail_top}) {
        $self->{_trail_top} = $h;
        $self->{_trail_top_bar} = $i;
    }
    if (!defined $self->{_trail_bot} || $l <= $self->{_trail_bot}) {
        $self->{_trail_bot} = $l;
        $self->{_trail_bot_bar} = $i;
    }
}

sub _refresh_strong_weak {
    my ($self, $i) = @_;
    return unless defined $self->{_trail_top} && defined $self->{_trail_bot};
    my $bias = $self->{_sw_trend};
    $self->{_strong_weak} = [
        {
            index => $self->{_trail_top_bar} // $i,
            price => $self->{_trail_top},
            type  => ($bias == BEARISH ? 'Strong High' : 'Weak High'),
            side  => 'high',
        },
        {
            index => $self->{_trail_bot_bar} // $i,
            price => $self->{_trail_bot},
            type  => ($bias == BULLISH ? 'Strong Low' : 'Weak Low'),
            side  => 'low',
        },
    ];
}

sub _parse_ts_epoch {
    my ($ts) = @_;
    return undef unless defined $ts && length $ts;
    # Accept "2026-07-06T09:30:00-05:00" or similar
    if ($ts =~ /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})/) {
        require Time::Local;
        my ($Y, $M, $D, $h, $m, $s) = ($1, $2, $3, $4, $5, $6);
        return Time::Local::timegm($s, $m, $h, $D, $M - 1, $Y - 1900);
    }
    return undef;
}

sub _update_mtf_levels {
    my ($self, $i) = @_;
    # Previous completed day/week/month H/L from loaded series (best-effort).
    my $ts = $self->{_t}[$i];
    my $epoch = _parse_ts_epoch($ts);
    return unless defined $epoch;

    my ($sec, $min, $hour, $mday, $mon, $year, $wday) = gmtime($epoch);
    my $day_key   = sprintf('%04d-%02d-%02d', $year + 1900, $mon + 1, $mday);
    my $month_key = sprintf('%04d-%02d', $year + 1900, $mon + 1);
    # ISO-ish week: year-week
    my $week_key  = sprintf('%04d-W%02d', $year + 1900, int(($mday + 6) / 7));

    $self->{_mtf_acc} //= {};
    for my $bucket (
        [ 'D', $day_key ],
        [ 'W', $week_key ],
        [ 'M', $month_key ],
    ) {
        my ($tf, $key) = @$bucket;
        my $acc = $self->{_mtf_acc}{$tf};
        if (!$acc || $acc->{key} ne $key) {
            # close previous bucket as previous H/L
            if ($acc && defined $acc->{hi}) {
                $self->{_mtf_prev}{$tf} = {
                    hi => $acc->{hi}, lo => $acc->{lo},
                    hi_index => $acc->{hi_i}, lo_index => $acc->{lo_i},
                    key => $acc->{key},
                };
            }
            $self->{_mtf_acc}{$tf} = {
                key => $key,
                hi => $self->{_h}[$i], lo => $self->{_l}[$i],
                hi_i => $i, lo_i => $i,
            };
        } else {
            if ($self->{_h}[$i] > $acc->{hi}) {
                $acc->{hi} = $self->{_h}[$i];
                $acc->{hi_i} = $i;
            }
            if ($self->{_l}[$i] < $acc->{lo}) {
                $acc->{lo} = $self->{_l}[$i];
                $acc->{lo_i} = $i;
            }
        }
    }

    my @levels;
    for my $tf (qw(D W M)) {
        my $prev = $self->{_mtf_prev}{$tf} or next;
        push @levels, {
            tf => $tf, side => 'H', price => $prev->{hi},
            index => $prev->{hi_index} // 0, label => "P${tf}H",
        };
        push @levels, {
            tf => $tf, side => 'L', price => $prev->{lo},
            index => $prev->{lo_index} // 0, label => "P${tf}L",
        };
    }
    $self->{_mtf_levels} = \@levels;
}

# --- Public getters (non-mutating) ---

sub get_pivots {
    my ($self) = @_;
    return [ @{ $self->{_pivots} } ];
}

sub get_events {
    my ($self) = @_;
    # Historical: all; Present would keep last only — captura Historical
    return [ @{ $self->{_events} } ];
}

sub get_eqhl {
    my ($self) = @_;
    return [ @{ $self->{_eqhl} } ];
}

sub get_order_blocks {
    my ($self) = @_;
    my @active = grep { $_->{active} } @{ $self->{_obs} };
    my @swing  = grep { ($_->{scope} // '') eq 'swing' } @active;
    my @int    = grep { ($_->{scope} // '') eq 'internal' } @active;
    my $max_s = $self->{sw_ob_count};
    my $max_i = $self->{int_ob_count};
    @swing = @swing[0 .. ($max_s - 1)] if @swing > $max_s;
    @int   = @int[0 .. ($max_i - 1)] if @int > $max_i;
    my @out;
    push @out, @swing if $self->{show_swing_ob};
    push @out, @int   if $self->{show_internal_ob};
    return \@out;
}

sub get_strong_weak {
    my ($self) = @_;
    return [ @{ $self->{_strong_weak} // [] } ];
}

sub get_mtf_levels {
    my ($self) = @_;
    return [ @{ $self->{_mtf_levels} // [] } ];
}

# Compatibility for Liquidity external pivots (HH/HL/LH/LL swing)
sub get_major {
    my ($self) = @_;
    my @out;
    if (defined $self->{_trail_top}) {
        push @out, { index => $self->{_trail_top_bar} // 0, type => 'major_high', price => $self->{_trail_top} };
    }
    if (defined $self->{_trail_bot}) {
        push @out, { index => $self->{_trail_bot_bar} // 0, type => 'major_low', price => $self->{_trail_bot} };
    }
    return \@out;
}

sub get_fvg {
    # Pro FVG off
    return [];
}

sub get_fibonacci {
    return [];
}

sub get_all_items {
    my ($self) = @_;
    return {
        pivots => $self->get_pivots(),
        events => $self->get_events(),
        eqhl   => $self->get_eqhl(),
        obs    => $self->get_order_blocks(),
        strong_weak => $self->get_strong_weak(),
        mtf    => $self->get_mtf_levels(),
    };
}

sub get_values {
    my ($self) = @_;
    return [ @{ $self->{_values} } ];
}

1;
