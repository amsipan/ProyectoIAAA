package Market::Indicators::Liquidity;
use strict;
use warnings;
use Time::Moment;

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
    my $k_explicit = exists $opts{k};
    my $k         = $opts{k}         // 3;
    my $atr_period= $opts{atr_period}// 14;
    my $tol_factor= $opts{tol_factor}// 0.10;
    my $N         = $opts{N}         // 3;
    # EQH/EQL (paridad LuxAlgo): deteccion de pivotes por "leg" con tamano propio
    # (equalHighsLowsLengthInput=3) y tolerancia = threshold(0.1) * ta.atr(200).
    my $eqhl_size       = $opts{eqhl_size}       // 3;
    my $eqhl_atr_period = $opts{eqhl_atr_period} // 200;
    # ORDEN 6 (task 0021 G): EQH/EQL internos vs externos con TEXTO LITERAL.
    #   - Externo (canonico, paridad LuxAlgo/TradingView): size = eqhl_size (3),
    #     etiquetas 'EQH' / 'EQL'.
    #   - Interno (mas granular, deteccion adicional): size = eqhl_int_size (2),
    #     etiquetas 'I-EQH' / 'I-EQL'.
    # eqhl_int_size=0 desactiva la deteccion interna (solo externos).
    my $eqhl_int_size = defined $opts{eqhl_int_size} ? $opts{eqhl_int_size} : 2;
    # ORDEN 4 (task 0021 F): relevancia de la toma de liquidez. Cada evento se
    # marca con `relevant` (0/1) segun si la magnitud del barrido (|extreme-nivel|)
    # es >= sweep_atr_factor * ATR local. El overlay puede filtrar por relevancia
    # para no saturar (5000 eventos en 1m). 0 desactiva (todo relevante).
    my $sweep_atr_factor = defined $opts{sweep_atr_factor} ? $opts{sweep_atr_factor} : 1.0;
    # task 0054: filtro BSL/SSL por recorrido vs pivote opuesto. Default 1.0 cuando k es el
    # default (3); con k explicito en opts (fixtures/regresion) default 0 para no romper tests.
    my $level_atr_factor = defined $opts{level_atr_factor}
        ? $opts{level_atr_factor}
        : ($k_explicit ? 0 : 1.0);
    die "Liquidity: k must be a positive integer"
        unless defined $k && $k =~ /^\d+$/ && $k > 0;
    die "Liquidity: atr_period must be a positive integer"
        unless defined $atr_period && $atr_period =~ /^\d+$/ && $atr_period > 0;
    die "Liquidity: N must be a positive integer"
        unless defined $N && $N =~ /^\d+$/ && $N > 0;
    die "Liquidity: eqhl_size must be a positive integer"
        unless defined $eqhl_size && $eqhl_size =~ /^\d+$/ && $eqhl_size > 0;
    die "Liquidity: eqhl_atr_period must be a positive integer"
        unless defined $eqhl_atr_period && $eqhl_atr_period =~ /^\d+$/ && $eqhl_atr_period > 0;

    my $self = {
        k          => $k,
        atr_period => $atr_period,
        tol_factor => $tol_factor,
        N          => $N,
        eqhl_size       => $eqhl_size,
        eqhl_int_size   => $eqhl_int_size,
        eqhl_atr_period => $eqhl_atr_period,
        sweep_atr_factor => $sweep_atr_factor,
        level_atr_factor => $level_atr_factor,
        # PROFE (clase liquidez): la ZONA 1 de liquidez es "arriba de los equal highs
        # y abajo de los equal lows"; por tanto un EQH/EQL puede ser barrido y debe
        # emitir sweep/grab/run igual que un swing BSL/SSL. Por defecto OFF para no
        # alterar los conteos exactos de los fixtures/tests existentes; ChartEngine
        # lo activa (opt-in) para que la app muestre EQ RUN/EQ GRAB.
        eqhl_liquidity => defined $opts{eqhl_liquidity} ? $opts{eqhl_liquidity} : 0,
        # QA/profe: evitar columnas de LQ GRAB/RUN casi idénticos. La deduplicación
        # se aplica a eventos resueltos cercanos en tiempo/precio, conservando el
        # más relevante/extremo. Es render/cálculo de señal, no cambia OHLC.
        event_dedupe_bars => defined $opts{event_dedupe_bars} ? $opts{event_dedupe_bars} : 3,
        event_dedupe_atr_factor => defined $opts{event_dedupe_atr_factor} ? $opts{event_dedupe_atr_factor} : 0.75,
        max_event_stack_per_index => defined $opts{max_event_stack_per_index} ? $opts{max_event_stack_per_index} : 1,
        # FSM "leg" de EQH/EQL (paridad LuxAlgo). leg: 0=BEARISH, 1=BULLISH.
        # Dos conjuntos de estado: 'ext' (externo, EQH/EQL) e 'int' (I-EQH/I-EQL).
        _eq_leg        => { ext => 0, int => 0 },
        _eq_high_level => { ext => undef, int => undef },
        _eq_high_bar   => { ext => undef, int => undef },
        _eq_high_have  => { ext => 0, int => 0 },
        _eq_low_level  => { ext => undef, int => undef },
        _eq_low_bar    => { ext => undef, int => undef },
        _eq_low_have   => { ext => 0, int => 0 },
        # ATR(200) propio para la tolerancia EQH/EQL (Wilder con seed de media movil).
        _eq_tr_sum  => 0,
        _eq_count   => 0,
        _eq_atr_last=> undef,
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
        # PERF (task 0016): highest index with a defined ATR value (O(1) _get_atr_at fast path).
        _last_defined_atr_idx => undef,
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
        # PERF (task 0016): incremental cursor into _levels for Zone-2 detection. Zone-2 is
        # protected by _zone_seen so previously-processed levels never re-emit; the old code
        # re-scanned the WHOLE _levels array every candle (O(N²)). This cursor processes only
        # the newly appended levels, producing byte-identical zone output.
        _zone2_cursor => 0,
        # task 0016 (perf): caches perezosas por TF para _sum_volume_for_tf.
        #   _epoch_cache{$tf}[i] = epoch de la vela i del array de TF (parseado 1 sola vez)
        #   _volsum_cache{$tf}[i] = suma de vol[0..i-1] (prefix-sum, [0]=0)
        #   _epoch_cache_size{$tf} = nº de velas cacheadas (invalidación por longitud)
        # Se invalidan en reset() y se reconstruyen cuando el array del TF crece.
        _epoch_cache      => {},
        _volsum_cache     => {},
        _epoch_cache_size => {},
        # task 0038: OHLC del día/semana en curso acumulado solo con velas <= index
        # (no leer $md->{data}{D/W}->[-1], que incluye futuro respecto a replay_idx).
        _daily_ohlc  => undef,
        _weekly_ohlc => undef,
        # task 0055: BSL/SSL desde pivotes SMC (opt-in; fractal propio si desactivado).
        _use_external_pivots  => 0,
        _external_pivots      => [],
        _external_pivot_seen  => {},
        _external_pivot_cursor => 0,
        _event_dedupe_slots   => {},
        _event_stack_slots    => {},
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

    # --- ATR(200) propio para tolerancia EQH/EQL (paridad LuxAlgo) ---
    $self->_update_eq_atr($index, $high, $low, $close);

    # --- EQH/EQL: deteccion de pivotes por "leg" (paridad LuxAlgo) ---
    # ORDEN 6 (task 0021 G): externo (EQH/EQL, size grande) + interno (I-EQH/I-EQL,
    # size pequeño), distinguidos por TEXTO LITERAL.
    $self->_update_eqhl_leg($index, 'ext', $self->{eqhl_size}, 'EQH', 'EQL', 'eqh');
    $self->_update_eqhl_leg($index, 'int', $self->{eqhl_int_size}, 'I-EQH', 'I-EQL', 'ieqh')
        if $self->{eqhl_int_size} && $self->{eqhl_int_size} > 0;

    # --- BSL/SSL: fractal propio o pivotes SMC externos (task 0055) ---
    unless ($self->{_use_external_pivots}) {
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
    } else {
        $self->_sync_external_pivots_upto($index);
    }

    $self->_update_fsm($index, $high, $low, $close);
    $self->_update_period_ohlc($index, $candle->[1], $high, $low, $close, $candle->[0]);
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
        # Seed phase: no defined ATR yet.
    } elsif ($self->{_atr_count} == $period) {
        $self->{_tr_sum} += $tr;
        my $atr = $self->{_tr_sum} / $period;
        $self->{_last_atr} = $atr;
        $self->{_atr_vals}->[$index] = $atr;
        # PERF (task 0016): track the highest index where an ATR is defined so _get_atr_at
        # can be O(1) in the common (sequential-feed) path instead of scanning back O(n).
        $self->{_last_defined_atr_idx} = $index;
    } else {
        my $atr = ($self->{_last_atr} * ($period - 1) + $tr) / $period;
        $self->{_last_atr} = $atr;
        $self->{_atr_vals}->[$index] = $atr;
        $self->{_last_defined_atr_idx} = $index;
    }
    $self->{_last_close} = $close;
    return;
}

# _get_atr_at($index) — the ATR value at or just before $index (Wilder ATR is forward-filled).
# PERF (task 0016): the old loop scanned back from $index every call, which is O(n) per swing
# and became a hotspot once the volume bottleneck was fixed. Because ATR is fed sequentially
# candle-by-candle and every candle past the seed phase has a defined ATR at its own index, the
# most-recent-defined ATR at or before $index is exactly the one cached here (or at $index itself
# during normal forward operation). We keep the O(n) fallback for the edge case where $index
# precedes the cached value (e.g. random-access lookups), which does not happen in production.
sub _get_atr_at {
    my ($self, $index) = @_;
    my $arr = $self->{_atr_vals};
    return undef unless defined $index && $index >= 0;
    my $v = $arr->[$index];
    return $v if defined $v;
    my $last = $self->{_last_defined_atr_idx};
    if (defined $last && $last < $index) {
        # $index is in the seed gap or after the last defined ATR (shouldn't happen post-seed).
        return $self->{_last_atr};
    }
    if (defined $last && $last <= $index) {
        return $self->{_atr_vals}->[$last];
    }
    # Fallback: scan back (preserves the original semantics exactly).
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

# _level_significant($price, $opposite_price, $index) — task 0054: un nivel BSL/SSL solo se
# registra si |price - pivote opuesto| >= level_atr_factor * ATR local. Factor 0, o sin ATR /
# pivote opuesto → significativo (no censurar al inicio del dataset).
sub _level_significant {
    my ($self, $price, $opposite_price, $index) = @_;
    my $factor = $self->{level_atr_factor} // 0;
    return 1 if $factor <= 0;
    my $atr = $self->_get_atr_at($index);
    return 1 unless defined $atr && $atr > 0 && defined $opposite_price;
    return (abs($price - $opposite_price) >= $factor * $atr) ? 1 : 0;
}

# --- EQH/EQL + BSL/SSL ---
sub _process_swing_high {
    my ($self, $j) = @_;
    my $price = $self->{_highs}->[$j];
    return unless defined $price;
    $self->_apply_swing_high($j, $price);
    return;
}

sub _process_swing_low {
    my ($self, $j) = @_;
    my $price = $self->{_lows}->[$j];
    return unless defined $price;
    $self->_apply_swing_low($j, $price);
    return;
}

sub _apply_swing_high {
    my ($self, $j, $price) = @_;

    if (defined $self->{_last_sh}) {
        my $prev_price = $self->{_last_sh}->{price};
        my $prev_index = $self->{_last_sh}->{index};
        my $opp = defined $self->{_last_sl} ? $self->{_last_sl}->{price} : undef;

        if ($self->_level_significant($prev_price, $opp, $j)) {
            my $lvl = {
                index => $prev_index,
                type  => 'BSL',
                price => $prev_price,
            };
            push @{ $self->{_levels} }, $lvl;
            $self->_register_level_ref($lvl);
        }
    }

    $self->{_last_sh_prev} = $self->{_last_sh};
    $self->{_last_sh}      = { index => $j, price => $price };
    return;
}

sub _apply_swing_low {
    my ($self, $j, $price) = @_;

    if (defined $self->{_last_sl}) {
        my $prev_price = $self->{_last_sl}->{price};
        my $prev_index = $self->{_last_sl}->{index};
        my $opp = defined $self->{_last_sh} ? $self->{_last_sh}->{price} : undef;

        if ($self->_level_significant($prev_price, $opp, $j)) {
            my $lvl = {
                index => $prev_index,
                type  => 'SSL',
                price => $prev_price,
            };
            push @{ $self->{_levels} }, $lvl;
            $self->_register_level_ref($lvl);
        }
    }

    $self->{_last_sl_prev} = $self->{_last_sl};
    $self->{_last_sl}      = { index => $j, price => $price };
    return;
}

# task 0055: clasificar pivote SMC (HH/LH = high; HL/LL = low).
sub _external_pivot_side {
    my ($self, $p) = @_;
    my $type = $p->{type} // $p->{kind} // '';
    return 'high' if $type =~ /^(?:HH|LH)$/;
    return 'low'  if $type =~ /^(?:HL|LL)$/;
    return 'high' if $type eq 'major_high';
    return 'low'  if $type eq 'major_low';
    return undef;
}

sub _sync_external_pivots_upto {
    my ($self, $upto_index) = @_;
    return unless $self->{_use_external_pivots};
    return unless defined $upto_index && $upto_index >= 0;

    my $pivots = $self->{_external_pivots} // [];
    my $seen   = $self->{_external_pivot_seen} //= {};
    my $cursor = $self->{_external_pivot_cursor} // 0;
    my $n = scalar(@$pivots);

    while ($cursor < $n) {
        my $p = $pivots->[$cursor];
        my $idx = $p->{index};
        last if defined $idx && $idx > $upto_index;
        $cursor++;
        next unless defined $idx;
        my $price = $p->{price};
        next unless defined $price;
        my $side = $self->_external_pivot_side($p);
        next unless defined $side;

        my $sig = "$side:$idx:$price";
        next if $seen->{$sig};
        $seen->{$sig} = 1;
        if ($side eq 'high') {
            $self->_apply_swing_high($idx, $price);
        } else {
            $self->_apply_swing_low($idx, $price);
        }
    }
    $self->{_external_pivot_cursor} = $cursor;
    return;
}

# =============================================================================
# EQH/EQL — paridad LuxAlgo (getCurrentStructure(size=3, equalHighLow=true))
# =============================================================================
# LuxAlgo detecta los pivotes de EQH/EQL con una FSM "leg" independiente del
# fractal usado para BSL/SSL:
#
#   leg(size):
#     newLegHigh = high[i-size] > highest(high, i-size+1 .. i)
#     newLegLow  = low[i-size]  < lowest(low,  i-size+1 .. i)
#     if newLegHigh -> leg = BEARISH(0)
#     elif newLegLow -> leg = BULLISH(1)
#
#   Cuando leg cambia 1->0 (startOfBearishLeg): pivote ALTO en bar (i-size),
#     precio high[i-size]. Si |prevEqualHigh - price| < tol -> EQH.
#   Cuando leg cambia 0->1 (startOfBullishLeg): pivote BAJO en bar (i-size),
#     precio low[i-size].  Si |prevEqualLow - price| < tol -> EQL.
#
#   tol = threshold(tol_factor, def 0.1) * atr(eqhl_atr_period, def 200).
#
# Esta deteccion alterna obligatoriamente high<->low (a diferencia del fractal),
# por eso captura pares EQH/EQL que el fractal estricto omite.
sub _update_eqhl_leg {
    my ($self, $index, $kind, $size, $label_hi, $label_lo, $prefix) = @_;
    $kind     //= 'ext';
    $size     //= $self->{eqhl_size};
    $label_hi //= 'EQH';
    $label_lo //= 'EQL';
    $prefix   //= 'eqh';
    return if $size <= 0;
    my $piv  = $index - $size;
    return if $piv < 0;

    my $H = $self->{_highs};
    my $L = $self->{_lows};
    my $hk = $H->[$piv];
    my $lk = $L->[$piv];
    return unless defined $hk && defined $lk;

    # highest/lowest sobre la ventana [i-size+1 .. i] (size barras, incl. actual).
    my ($mh, $ml);
    for my $jj ($index - $size + 1 .. $index) {
        my $h = $H->[$jj];
        my $l = $L->[$jj];
        next unless defined $h && defined $l;
        $mh = $h if !defined $mh || $h > $mh;
        $ml = $l if !defined $ml || $l < $ml;
    }
    return unless defined $mh && defined $ml;

    my $prev_leg = $self->{_eq_leg}{$kind};
    if    ($hk > $mh) { $self->{_eq_leg}{$kind} = 0; }  # BEARISH_LEG
    elsif ($lk < $ml) { $self->{_eq_leg}{$kind} = 1; }  # BULLISH_LEG
    my $leg = $self->{_eq_leg}{$kind};
    return if $leg == $prev_leg;  # solo en el cambio de leg

    my $atr = $self->{_eq_atr_last};
    my $tol = (defined $atr ? $atr : 0) * $self->{tol_factor};

    if ($leg == 0) {
        # Pivote alto confirmado en bar $piv (precio $hk).
        if ($self->{_eq_high_have}{$kind} && defined $tol
            && abs($self->{_eq_high_level}{$kind} - $hk) < $tol) {
            my $gid = "${prefix}h_" . $self->{_eq_high_bar}{$kind} . "_" . $piv;
            push @{ $self->{_levels} }, {
                index => $self->{_eq_high_bar}{$kind}, type => $label_hi,
                price => $self->{_eq_high_level}{$kind}, group_id => $gid,
            };
            push @{ $self->{_levels} }, {
                index => $piv, type => $label_hi, price => $hk, group_id => $gid,
            };
            # PROFE: sobre un EQH se acumula liquidez → registrar como nivel barrible
            # al alza (misma FSM que BSL) para que emita EQ SWEEP/GRAB/RUN. Solo el
            # par externo canónico (kind 'ext'); los internos I-EQH quedan como dibujo.
            $self->_register_eq_liquidity_level($piv, $hk, 'BSL', 'EQH')
                if $self->{eqhl_liquidity} && $kind eq 'ext';
        }
        $self->{_eq_high_level}{$kind} = $hk;
        $self->{_eq_high_bar}{$kind}   = $piv;
        $self->{_eq_high_have}{$kind}  = 1;
    } else {
        # Pivote bajo confirmado en bar $piv (precio $lk).
        if ($self->{_eq_low_have}{$kind} && defined $tol
            && abs($self->{_eq_low_level}{$kind} - $lk) < $tol) {
            my $gid = "${prefix}l_" . $self->{_eq_low_bar}{$kind} . "_" . $piv;
            push @{ $self->{_levels} }, {
                index => $self->{_eq_low_bar}{$kind}, type => $label_lo,
                price => $self->{_eq_low_level}{$kind}, group_id => $gid,
            };
            push @{ $self->{_levels} }, {
                index => $piv, type => $label_lo, price => $lk, group_id => $gid,
            };
            # PROFE: bajo un EQL se acumula liquidez → registrar como nivel barrible
            # a la baja (misma FSM que SSL) para que emita EQ SWEEP/GRAB/RUN.
            $self->_register_eq_liquidity_level($piv, $lk, 'SSL', 'EQL')
                if $self->{eqhl_liquidity} && $kind eq 'ext';
        }
        $self->{_eq_low_level}{$kind} = $lk;
        $self->{_eq_low_bar}{$kind}   = $piv;
        $self->{_eq_low_have}{$kind}  = 1;
    }
    return;
}

# ATR para la tolerancia EQH/EQL. Wilder con seed por media movil de los TR
# disponibles (asi hay tolerancia antes de completar el periodo, util porque
# nuestro CSV es corto frente al historial que tiene TradingView).
sub _update_eq_atr {
    my ($self, $index, $high, $low, $close) = @_;
    my $period = $self->{eqhl_atr_period};

    my $tr;
    if (defined $self->{_eq_last_close}) {
        my $prev = $self->{_eq_last_close};
        my $hl  = $high - $low;
        my $hpc = abs($high - $prev);
        my $lpc = abs($low  - $prev);
        $tr = $hl;
        $tr = $hpc if $hpc > $tr;
        $tr = $lpc if $lpc > $tr;
    } else {
        $tr = $high - $low;
    }

    $self->{_eq_count}++;
    if ($self->{_eq_count} < $period) {
        $self->{_eq_tr_sum} += $tr;
        $self->{_eq_atr_last} = $self->{_eq_tr_sum} / $self->{_eq_count};
    } elsif ($self->{_eq_count} == $period) {
        $self->{_eq_tr_sum} += $tr;
        $self->{_eq_atr_last} = $self->{_eq_tr_sum} / $period;
    } else {
        $self->{_eq_atr_last} =
            ($self->{_eq_atr_last} * ($period - 1) + $tr) / $period;
    }
    $self->{_eq_last_close} = $close;
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
                # ORDEN 4 (task 0021 F3): rastrear la PENETRACION MAXIMA real del
                # barrido (no el high/low de la vela de resolucion), para que el
                # marcador y la magnitud reflejen donde de verdad barrio el precio.
                $lvl->{swept_extreme} = $high;
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
                $lvl->{swept_extreme} = $low;
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

            # ORDEN 4 (task 0021 F3): actualizar la penetracion maxima del barrido
            # mientras sigue abierto, para reflejar el extremo real.
            if ($dir eq 'up') {
                $lvl->{swept_extreme} = $high
                    if !defined $lvl->{swept_extreme} || $high > $lvl->{swept_extreme};
            } else {
                $lvl->{swept_extreme} = $low
                    if !defined $lvl->{swept_extreme} || $low < $lvl->{swept_extreme};
            }

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

    # PERF (task 0016): prune Resolved levels from _active_levels so the FSM loop only
    # iterates live levels. A resolved level is never re-opened (its event is already in
    # _events); keeping it made the loop O(n²) on long datasets (1138 stale levels after
    # 6000 candles). get_active_levels() already filtered Resolved, so this is a pure
    # performance optimisation with identical external behaviour.
    if (grep { $_->{state} eq 'Resolved' } @{ $self->{_active_levels} }) {
        $self->{_active_levels} = [
            grep { $_->{state} ne 'Resolved' } @{ $self->{_active_levels} }
        ];
    }
    return;
}

sub _resolve {
    my ($self, $lvl, $classification, $index) = @_;
    $lvl->{state} = 'Resolved';
    my $dir = $lvl->{swept_dir} // 'up';
    my $meta = $self->_compute_event_meta($lvl, $index);
    my $c_high = $self->{_highs}->[$index] // $lvl->{price};
    my $c_low  = $self->{_lows}->[$index] // $lvl->{price};
    # ORDEN 4 (task 0021 F3): el extremo del evento es la PENETRACION MAXIMA real
    # del barrido (swept_extreme), no el high/low de la vela de resolucion, que
    # podia estar lejos del punto donde de verdad se barrio el nivel (causa de
    # RUN/marcadores "mal ubicados"). Fallback al extremo de la vela si no hubo
    # fase Swept registrada (resolucion inmediata en Detected).
    my $extreme = $dir eq 'up'
        ? ($lvl->{swept_extreme} // $c_high)
        : ($lvl->{swept_extreme} // $c_low);

    my $draw_index = $classification eq 'RUN'
        ? $self->_run_marker_index($lvl, $index, $dir)
        : $index;
    my $draw_high = $self->{_highs}->[$draw_index] // $c_high;
    my $draw_low  = $self->{_lows}->[$draw_index]  // $c_low;
    my $draw_extreme = $classification eq 'RUN'
        ? ($dir eq 'up' ? $draw_high : $draw_low)
        : $extreme;

    # ORDEN 4 (task 0021 F): magnitud del barrido y relevancia vs ATR local.
    # magnitude = cuanto penetro el precio mas alla del nivel (|extreme-nivel|).
    # relevant=1 si magnitude >= sweep_atr_factor * ATR; con factor 0, todo
    # relevante. El overlay usa `relevant` para mostrar solo las tomas grandes.
    my $magnitude = abs($extreme - $lvl->{price});
    my $factor    = $self->{sweep_atr_factor} // 0;
    my $atr       = $self->_get_atr_at($index);
    my $relevant  = 1;
    if ($factor > 0 && defined $atr && $atr > 0) {
        $relevant = ($magnitude >= $factor * $atr) ? 1 : 0;
    }

    my $event = {
        # index conserva la vela donde realmente se confirmo la señal.
        # marker_index es la vela de dibujo/recoloreo para RUN en el trayecto.
        index   => $index,
        confirm_index => $index,
        marker_index => $draw_index,
        type    => $classification,
        dir     => $dir,
        price   => $lvl->{price},
        extreme => $draw_extreme,
        swept_extreme => $extreme,
        state   => 'Resolved',
        meta    => $meta,
        magnitude => $magnitude,
        relevant  => $relevant,
        # ORDEN 3 (task 0021 F2/D): vincular la toma de liquidez a SU NIVEL.
        # El nivel barrido es un pivote swing (BSL = swing high, SSL = swing low),
        # i.e. los mismos HH/HL/LH/LL nombrados. Propagamos su indice/tipo/precio
        # para que el overlay pueda dibujar el ancla desde el nivel hasta el
        # punto de la toma (antes el evento no llevaba referencia al nivel).
        level_index => $lvl->{index},
        level_type  => $lvl->{side} // $lvl->{type},
        level_price => $lvl->{price},
        swept_index => $lvl->{swept_index},
        # PROFE: origen del nivel barrido. 'EQH'/'EQL' cuando la toma nace de equal
        # highs/lows (zona 1 de liquidez); undef para swings BSL/SSL normales.
        origin      => $lvl->{origin},
    };
    $self->_add_resolved_event($event);
    return;
}

# RUN se confirma al completar N cierres, pero visualmente representa continuacion
# del trayecto. Elegimos una vela intermedia entre sweep y confirmacion para evitar
# ubicar LQ RUN sobre el pico/HH/LL final. La confirmacion real queda en confirm_index.
sub _run_marker_index {
    my ($self, $lvl, $confirm_index, $dir) = @_;
    my $start = $lvl->{swept_index};
    return $confirm_index unless defined $start && $confirm_index > $start;

    my $from = $start + 1;
    my $to   = $confirm_index - 1;
    return $start if $from > $to;

    my $level = $lvl->{price};
    my @candidates;
    for my $i ($from .. $to) {
        my $close = $self->{_closes}->[$i];
        next unless defined $close;
        next if $dir eq 'up'   && $close <= $level;
        next if $dir eq 'down' && $close >= $level;
        my $high = $self->{_highs}->[$i] // $close;
        my $low  = $self->{_lows}->[$i]  // $close;
        push @candidates, {
            index => $i,
            dist_center => abs($i - (($start + $confirm_index) / 2)),
            extension => abs($close - $level),
            range => abs($high - $low),
        };
    }
    @candidates = map { $_->[0] }
                  sort {
                      $a->[1] <=> $b->[1]
                      || $a->[0]{dist_center} <=> $b->[0]{dist_center}
                      || $a->[0]{index} <=> $b->[0]{index}
                  }
                  map {
                      # Preferir trayecto, no vela extrema de oscilacion local.
                      my $is_pivot = (defined $self->{_swing_h}->[$_->{index}] || defined $self->{_swing_l}->[$_->{index}]) ? 1 : 0;
                      [ $_, $is_pivot ]
                  } @candidates;
    return $candidates[0]{index} if @candidates;
    return int(($start + $confirm_index) / 2);
}

sub _add_resolved_event {
    my ($self, $event) = @_;
    my $key = $self->_event_dedupe_key($event);
    if (defined $key && defined $self->{_event_dedupe_slots}{$key}) {
        my $idx = $self->{_event_dedupe_slots}{$key};
        my $old = $self->{_events}->[$idx];
        if ($self->_event_score($event) > $self->_event_score($old)) {
            $self->_unindex_event_stack($old);
            $self->{_events}->[$idx] = $event;
            $self->_index_event_stack($event, $idx);
        }
        return;
    }

    my $stack_key = $self->_event_stack_key($event);
    if (defined $stack_key) {
        my $limit = $self->{max_event_stack_per_index} // 1;
        my $slot = $self->{_event_stack_slots}{$stack_key} ||= [];
        if (@$slot >= $limit) {
            my ($worst_pos, $worst_idx, $worst_score) = (undef, undef, undef);
            for my $pos (0 .. $#$slot) {
                my $idx = $slot->[$pos];
                my $score = $self->_event_score($self->{_events}->[$idx]);
                if (!defined $worst_score || $score < $worst_score) {
                    ($worst_pos, $worst_idx, $worst_score) = ($pos, $idx, $score);
                }
            }
            return if defined $worst_score && $self->_event_score($event) <= $worst_score;
            my $old = $self->{_events}->[$worst_idx];
            my $old_key = $self->_event_dedupe_key($old);
            delete $self->{_event_dedupe_slots}{$old_key} if defined $old_key;
            $self->{_events}->[$worst_idx] = $event;
            $slot->[$worst_pos] = $worst_idx;
            $self->{_event_dedupe_slots}{$key} = $worst_idx if defined $key;
            return;
        }
    }

    push @{ $self->{_events} }, $event;
    my $idx = $#{ $self->{_events} };
    $self->{_event_dedupe_slots}{$key} = $idx if defined $key;
    $self->_index_event_stack($event, $idx);
    return;
}

sub _event_stack_key {
    my ($self, $event) = @_;
    return undef unless $event && ($event->{type} // '') =~ /^(?:GRAB|RUN)$/;
    return join ':', ($event->{type} // ''), ($event->{marker_index} // $event->{index} // '');
}

sub _index_event_stack {
    my ($self, $event, $idx) = @_;
    my $stack_key = $self->_event_stack_key($event);
    return unless defined $stack_key;
    push @{ $self->{_event_stack_slots}{$stack_key} ||= [] }, $idx;
    return;
}

sub _unindex_event_stack {
    my ($self, $event) = @_;
    my $stack_key = $self->_event_stack_key($event);
    return unless defined $stack_key && $self->{_event_stack_slots}{$stack_key};
    my @keep = grep { defined $self->{_events}->[$_] && $self->{_events}->[$_] ne $event } @{ $self->{_event_stack_slots}{$stack_key} };
    $self->{_event_stack_slots}{$stack_key} = \@keep;
    return;
}

sub _event_dedupe_key {
    my ($self, $event) = @_;
    return undef unless $event && ($event->{type} // '') =~ /^(?:GRAB|RUN)$/;
    my $bars = $self->{event_dedupe_bars} // 0;
    return undef if $bars <= 0;
    my $idx = $event->{marker_index} // $event->{index} // $event->{confirm_index};
    return undef unless defined $idx;
    my $atr = $self->_get_atr_at($event->{confirm_index} // $idx) // 0;
    my $tick = $atr * ($self->{event_dedupe_atr_factor} // 0.75);
    $tick = 1 if $tick < 1;
    my $time_bucket = int($idx / ($bars + 1));
    my $price = $event->{price} // 0;
    my $price_bucket = int(($price / $tick) + ($price >= 0 ? 0.5 : -0.5));
    return join ':', $event->{type}, ($event->{dir} // ''), $time_bucket, $price_bucket;
}

sub _event_score {
    my ($self, $event) = @_;
    return -1e9 unless $event;
    my $score = ($event->{magnitude} // 0) * 1000;
    $score += ($event->{confirm_index} // $event->{index} // 0) * 0.001;
    if (($event->{type} // '') eq 'GRAB') {
        my $ext = $event->{swept_extreme} // $event->{extreme} // $event->{price} // 0;
        $score += (($event->{dir} // '') eq 'up' ? $ext : -$ext) * 0.0001;
    }
    return $score;
}

# =============================================================================
# Volume multi-TF (task 0011)
# =============================================================================

sub _compute_event_meta {
    my ($self, $lvl, $resolve_index) = @_;
    my $md = $self->{_market_data};
    my $active_tf = $md ? $md->{active_tf} : '1m';
    my $internal = ($active_tf eq '1m' || $active_tf eq '5m' || $active_tf eq '15m') ? 1 : 0;

    my $ts_start = $md ? $md->get_timestamp($lvl->{index}) : undef;
    my $ts_end   = $md ? $md->get_timestamp($resolve_index) : undef;

    my $v1m  = ($ts_start && $ts_end) ? $self->_sum_volume_for_tf('1m',  $ts_start, $ts_end) : 0;
    my $v5m  = ($ts_start && $ts_end) ? $self->_sum_volume_for_tf('5m',  $ts_start, $ts_end) : 0;
    my $v15m = ($ts_start && $ts_end) ? $self->_sum_volume_for_tf('15m', $ts_start, $ts_end) : 0;

    return {
        v1m      => $v1m,
        v5m      => $v5m,
        v15m     => $v15m,
        internal => $internal,
    };
}

# _sum_volume_for_tf — Sums the volume for a specific timeframe within a temporal range.
#
# Arguments:
#   $tf: Target timeframe to sum volume for (e.g., '1m', '5m', '15m')
#   $ts_start_str: Start timestamp of the event range (inclusive)
#   $ts_end_str: End timestamp of the event range (the start timestamp of the resolving candle, inclusive)
#
# Upper boundary convention:
#   Since $ts_end_str is the start time of the resolving candle in the active TF, the event actually covers
#   until the end of that resolving candle. The end of the resolving candle is exactly when the next active
#   candle would start (ts_end_next).
#   We include any sub-candle of the target $tf whose bucket starts at or after $ts_start_str and strictly
#   before $ts_end_next (i.e. ts_start <= ts < ts_end_next).
#
# PERF (task 0016): the array of a TF can hold ~30000 candles, and this method is called once per resolved
# event per TF (~1086 calls in 2000 candles). The old implementation parsed Time::Moment->from_string on
# every candle in every call → O(events × candles) with a huge constant (96% of the runtime profiled).
# Now we:
#   1. Cache the epoch array per TF (parsed once), built lazily and reused across calls. Invalidation is by
#      array length (a growing array triggers a rebuild; arrays are append-only so old entries stay valid).
#   2. Cache a prefix-sum of volume per TF, so the sum over a sub-range is a single subtraction.
#   3. Binary-search the bounds [ts_start_epoch, ts_end_next_epoch) on the epoch array (chronologically
#      sorted by construction). Net: O(log n) per call instead of O(n).
# Semantics are byte-for-byte identical to the previous loop (same inclusivity, same upper boundary).
sub _sum_volume_for_tf {
    my ($self, $tf, $ts_start_str, $ts_end_str) = @_;
    my $md = $self->{_market_data};
    return 0 unless $md;
    my $arr = $md->{data}->{$tf};
    return 0 unless $arr && @$arr;

    my $tm_start = eval { Time::Moment->from_string($ts_start_str) };
    return 0 unless $tm_start;
    my $ts_start_epoch = $tm_start->epoch;

    my $tm_end = eval { Time::Moment->from_string($ts_end_str) };
    return 0 unless $tm_end;

    # Determine ts_end_next based on the active timeframe (active_tf) duration
    my $active_tf = $md->{active_tf} // '1m';
    my $tm_end_next;
    if ($active_tf eq '1m') {
        $tm_end_next = $tm_end->plus_minutes(1);
    } elsif ($active_tf eq '5m') {
        $tm_end_next = $tm_end->plus_minutes(5);
    } elsif ($active_tf eq '15m') {
        $tm_end_next = $tm_end->plus_minutes(15);
    } elsif ($active_tf eq '1h') {
        $tm_end_next = $tm_end->plus_hours(1);
    } elsif ($active_tf eq '2h') {
        $tm_end_next = $tm_end->plus_hours(2);
    } elsif ($active_tf eq '4h') {
        $tm_end_next = $tm_end->plus_hours(4);
    } elsif ($active_tf eq 'D') {
        $tm_end_next = $tm_end->plus_days(1);
    } elsif ($active_tf eq 'W') {
        $tm_end_next = $tm_end->plus_weeks(1);
    } else {
        $tm_end_next = $tm_end->plus_minutes(1);
    }
    my $ts_end_next_epoch = $tm_end_next->epoch;

    # Lazily build (or extend) the per-TF epoch + prefix-sum caches.
    # Arrays are append-only, so we extend the cache from the last cached length to the current length.
    my $epochs  = $self->{_epoch_cache}->{$tf};
    my $volsum  = $self->{_volsum_cache}->{$tf};
    my $cached_n = $self->{_epoch_cache_size}->{$tf} // 0;
    my $n = scalar(@$arr);
    if (!defined $epochs) {
        $epochs = [];
        $volsum = [0];
        $cached_n = 0;
    }
    if ($cached_n > $n) {
        # Defensive: array shrank (reset elsewhere); rebuild from scratch.
        $epochs = [];
        $volsum = [0];
        $cached_n = 0;
    }
    if ($cached_n < $n) {
        for my $i ($cached_n .. $n - 1) {
            my $c = $arr->[$i];
            my $tm = eval { defined($c) ? Time::Moment->from_string($c->[0]) : undef };
            my $ep = $tm ? $tm->epoch : undef;
            push @$epochs, $ep;
            my $prev = $volsum->[-1];
            # Match old behaviour: candles with unparseable timestamps are excluded from any range
            # (the old loop did `next unless $tm`), so they contribute 0 to the prefix-sum.
            my $vol  = (defined $ep && $c && defined $c->[5]) ? $c->[5] : 0;
            push @$volsum, $prev + $vol;
        }
        $self->{_epoch_cache}->{$tf}      = $epochs;
        $self->{_volsum_cache}->{$tf}     = $volsum;
        $self->{_epoch_cache_size}->{$tf} = $n;
    }

    # Binary search the inclusive lower bound: first index i where epoch[i] >= ts_start_epoch.
    # Candles with undefined epoch (unparseable) are treated as "before" any finite target; this matches
    # the old behaviour (next unless $tm) which skipped them.
    my ($lo, $hi_range) = (0, $n);
    while ($lo < $hi_range) {
        my $mid = ($lo + $hi_range) >> 1;
        my $em = $epochs->[$mid];
        if (defined $em && $em < $ts_start_epoch) {
            $lo = $mid + 1;
        } else {
            $hi_range = $mid;
        }
    }
    my $start_idx = $lo;

    # Binary search the exclusive upper bound: first index i where epoch[i] >= ts_end_next_epoch.
    ($lo, $hi_range) = (0, $n);
    while ($lo < $hi_range) {
        my $mid = ($lo + $hi_range) >> 1;
        my $em = $epochs->[$mid];
        if (defined $em && $em < $ts_end_next_epoch) {
            $lo = $mid + 1;
        } else {
            $hi_range = $mid;
        }
    }
    my $end_idx = $lo;  # exclusive

    if ($start_idx >= $end_idx) {
        return 0;  # empty range
    }
    # volsum[i] = sum(vol[0..i-1]); sum(vol[start_idx .. end_idx-1]) = volsum[end_idx] - volsum[start_idx].
    return $volsum->[$end_idx] - $volsum->[$start_idx];
}

# task 0038: acumula H/L/O/C del bucket daily/weekly vigente en $index sin leer
# los arrays D/W completos de MarketData (fuga de futuro en Replay).
sub _update_period_ohlc {
    my ($self, $index, $open, $high, $low, $close, $ts) = @_;
    my $md = $self->{_market_data};
    return unless $md && defined $ts;

    for my $spec (['D', '_daily_ohlc'], ['W', '_weekly_ohlc']) {
        my ($tf, $key) = @$spec;
        my $bucket_ts = eval { $md->_bucket_timestamp($ts, $tf) };
        next unless defined $bucket_ts;

        my $state = $self->{$key};
        if (!$state || !defined $state->{bucket_ts} || $state->{bucket_ts} ne $bucket_ts) {
            $self->{$key} = {
                bucket_ts => $bucket_ts,
                open      => $open,
                high      => $high,
                low       => $low,
                close     => $close,
            };
        } else {
            $state->{high} = $high
                if defined $high && (!defined $state->{high} || $high > $state->{high});
            $state->{low} = $low
                if defined $low && (!defined $state->{low} || $low < $state->{low});
            $state->{close} = $close if defined $close;
        }
    }
    return;
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

    # Zone 1 (EQH/EQL) + Zone 2 (BSL/SSL): ambas recorren _levels. PERF: un solo
    # escaneo incremental desde el cursor (_zone2_cursor), procesando solo los
    # niveles agregados desde la ultima invocacion. Cada nivel queda protegido por
    # _zone_seen, asi que procesarlo una vez equivale a procesarlo siempre: la
    # salida es identica byte a byte, pero el costo pasa de O(total_levels) por
    # vela (O(N^2) acumulado, antes el cuello de botella dominante) a O(nuevos).
    {
        my $levels = $self->{_levels};
        my $cursor = $self->{_zone2_cursor} // 0;
        my $n = scalar(@$levels);
        if ($cursor < $n) {
            for my $li ($cursor .. $n - 1) {
                my $lvl = $levels->[$li];
                my $type = $lvl->{type};
                if ($type eq 'EQH' || $type eq 'EQL') {
                    my $sig = "zone_1:$lvl->{index}:$lvl->{price}";
                    if (!$seen->{$sig}) {
                        $seen->{$sig} = 1;
                        push @new_zones, {
                            index => $lvl->{index},
                            type  => 'zone_1',
                            price => $lvl->{price},
                            meta  => { internal => $internal, source => $type },
                        };
                    }
                } elsif ($type eq 'BSL' || $type eq 'SSL') {
                    my $sig = "zone_2:$lvl->{index}:$lvl->{price}";
                    if (!$seen->{$sig}) {
                        $seen->{$sig} = 1;
                        push @new_zones, {
                            index => $lvl->{index},
                            type  => 'zone_2',
                            price => $lvl->{price},
                            meta  => { internal => $internal, source => $type },
                        };
                    }
                }
            }
            $self->{_zone2_cursor} = $n;
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

    # Zone 6: daily H/L/O/C (task 0038: solo bucket acumulado hasta $index)
    my $d = $self->{_daily_ohlc};
    if ($d) {
        for my $pair (
            ['daily_open',  $d->{open}],
            ['daily_high',  $d->{high}],
            ['daily_low',   $d->{low}],
            ['daily_close', $d->{close}],
        ) {
            my ($src, $price) = @$pair;
            next unless defined $price;
            my $sig = "zone_6:$src:$price";
            if (!$seen->{$sig}) {
                $seen->{$sig} = 1;
                push @new_zones, {
                    index => $index,
                    type  => 'zone_6',
                    price => $price,
                    meta  => { internal => 0, source => $src },
                };
            }
        }
    }

    # Zone 7: weekly H/L/O/C (task 0038: solo bucket acumulado hasta $index)
    my $w = $self->{_weekly_ohlc};
    if ($w) {
        for my $pair (
            ['weekly_open',  $w->{open}],
            ['weekly_high',  $w->{high}],
            ['weekly_low',   $w->{low}],
            ['weekly_close', $w->{close}],
        ) {
            my ($src, $price) = @$pair;
            next unless defined $price;
            my $sig = "zone_7:$src:$price";
            if (!$seen->{$sig}) {
                $seen->{$sig} = 1;
                push @new_zones, {
                    index => $index,
                    type  => 'zone_7',
                    price => $price,
                    meta  => { internal => 0, source => $src },
                };
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

sub _register_level_ref {
    my ($self, $lvl) = @_;
    $lvl->{side}        = $lvl->{type};
    $lvl->{state}       = 'Detected';
    $lvl->{swept_index} = undef;
    $lvl->{swept_dir}   = undef;
    $lvl->{consec_out}  = 0;
    $lvl->{swept_close} = undef;
    push @{ $self->{_active_levels} }, $lvl;
    return;
}

# PROFE: registra un nivel EQH/EQL como nivel de liquidez barrible en la FSM.
# $side = 'BSL' (EQH, barrido al alza) | 'SSL' (EQL, barrido a la baja).
# $origin_type = 'EQH'|'EQL' se propaga al evento (level_type) para que el overlay
# distinga las tomas que nacen de equal highs/lows de las de swings normales.
sub _register_eq_liquidity_level {
    my ($self, $index, $price, $side, $origin_type) = @_;
    return unless defined $index && defined $price;
    my $lvl = {
        index  => $index,
        type   => $side,
        price  => $price,
        origin => $origin_type,
    };
    $self->_register_level_ref($lvl);
    return;
}

# =============================================================================
# Public API
# =============================================================================

# task 0055: opt-in — BSL/SSL desde pivotes SMC en lugar del fractal interno.
sub use_external_pivots {
    my ($self, $on) = @_;
    $self->{_use_external_pivots} = $on ? 1 : 0;
    return $self;
}

sub set_external_pivots {
    my ($self, $pivots) = @_;
    my $old_n = scalar @{ $self->{_external_pivots} // [] };
    my @sorted = sort { ($a->{index} // 0) <=> ($b->{index} // 0) } @{ $pivots // [] };
    $self->{_external_pivots} = \@sorted;
    # Normalmente ChartEngine entrega prefijos crecientes; preservamos cursor/seen.
    # Si la lista se achica (cambio de replay/TF/reset externo), empezamos de cero.
    if (@sorted < $old_n) {
        $self->{_external_pivot_seen} = {};
        $self->{_external_pivot_cursor} = 0;
    }
    return $self;
}

sub sync_external_pivots {
    my ($self, $pivots, $max_index) = @_;
    $self->set_external_pivots($pivots) if defined $pivots;
    $self->use_external_pivots(1) unless $self->{_use_external_pivots};
    if (defined $max_index) {
        $self->_sync_external_pivots_upto($max_index);
    }
    return $self;
}

# current_atr — ATR(14) vigente para agrupación BSL/SSL en banda (task 0027).
sub current_atr {
    my ($self) = @_;
    return $self->{_last_atr};
}

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
    my %active_indices;

    # 1. BSL/SSL activos de _active_levels
    for my $lvl (@{ $self->{_active_levels} }) {
        next if $lvl->{state} eq 'Resolved';
        push @result, {
            index => $lvl->{index},
            type  => $lvl->{side},
            price => $lvl->{price},
            state => $lvl->{state},
        };
        $active_indices{$lvl->{side}}{$lvl->{index}} = 1;
    }

    # 2. El último SH/SL (aún no en _active_levels pero activos)
    if (defined $self->{_last_sh}) {
        push @result, {
            index => $self->{_last_sh}->{index},
            type  => 'BSL',
            price => $self->{_last_sh}->{price},
            state => 'Detected',
        };
        $active_indices{BSL}{$self->{_last_sh}->{index}} = 1;
    }
    if (defined $self->{_last_sl}) {
        push @result, {
            index => $self->{_last_sl}->{index},
            type  => 'SSL',
            price => $self->{_last_sl}->{price},
            state => 'Detected',
        };
        $active_indices{SSL}{$self->{_last_sl}->{index}} = 1;
    }

    # 3. EQH/EQL (paridad LuxAlgo): vienen de la FSM "leg", con indices propios
    #    desacoplados de los pivotes fractales de BSL/SSL. Un nivel de liquidez
    #    por encima del precio (EQH) sigue "activo" hasta que el precio cierra a
    #    traves de el; idem EQL por debajo. Usamos el ultimo close alimentado.
    my $last_close = $self->{_eq_last_close};
    for my $lvl (@{ $self->{_levels} }) {
        if ($lvl->{type} eq 'EQH') {
            next if defined $last_close && $last_close > $lvl->{price};
            push @result, $lvl;
        } elsif ($lvl->{type} eq 'EQL') {
            next if defined $last_close && $last_close < $lvl->{price};
            push @result, $lvl;
        }
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
    $self->{_last_defined_atr_idx} = undef;
    $self->{_levels}     = [];
    $self->{_eqh_pairs}  = {};
    $self->{_eql_pairs}  = {};
    # EQH/EQL leg state (paridad LuxAlgo). Dos conjuntos: ext + int (ORDEN 6).
    $self->{_eq_leg}        = { ext => 0, int => 0 };
    $self->{_eq_high_level} = { ext => undef, int => undef };
    $self->{_eq_high_bar}   = { ext => undef, int => undef };
    $self->{_eq_high_have}  = { ext => 0, int => 0 };
    $self->{_eq_low_level}  = { ext => undef, int => undef };
    $self->{_eq_low_bar}    = { ext => undef, int => undef };
    $self->{_eq_low_have}   = { ext => 0, int => 0 };
    $self->{_eq_tr_sum}     = 0;
    $self->{_eq_count}      = 0;
    $self->{_eq_atr_last}   = undef;
    $self->{_eq_last_close} = undef;
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
    $self->{_zone2_cursor} = 0;
    # task 0016 (perf): invalidate per-TF epoch/volsum caches so they rebuild from fresh data.
    $self->{_epoch_cache}      = {};
    $self->{_volsum_cache}     = {};
    $self->{_epoch_cache_size} = {};
    $self->{_daily_ohlc}  = undef;
    $self->{_weekly_ohlc} = undef;
    $self->{_external_pivots}      = [];
    $self->{_external_pivot_seen}  = {};
    $self->{_external_pivot_cursor} = 0;
    $self->{_event_dedupe_slots}   = {};
    $self->{_event_stack_slots}    = {};
    return;
}

1;
