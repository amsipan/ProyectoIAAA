package Market::Indicators::AutoTrendChannel;
use strict;
use warnings;

# =============================================================================
# Market::Indicators::AutoTrendChannel
#   Canal + Trendline automáticos (cálculo puro, sin Tk).
#   NO reemplaza Drawing::* ni ZigZag CHANNEL.
#
#   HARD (oral Lumina 20-jul / REQUISITOS §1.5):
#     * Canal: ≥3 toques en línea INFERIOR (lows); superior = paralela variable.
#     * Span formación ≥ 60 min (wall-clock). Trendline ≥ ~120 min.
#     * Un canal activo; extender a última vela causal mientras viva.
#     * Perforación menor con retorno → no mata.
#     * Toma de liquidez / ruptura → DESAPARECE (no apilar históricos).
#     * Replay: solo el canal vivo en esa punta causal.
#
#   Heurísticas técnicas (anti mega-canal / anti cluster; NO oral):
#     * Gap inter-toque ≥ 20 min.
#     * Span formación ≤ max(8h, 48×minutos_barra)  — en 1h no asfixiar.
#     * Span en BARRAS ≤ 80 (estructura local).
#     * Ancho ≤ 6×ATR (evita “cortina” que cubre el chart).
#     * Score = recencia − ancho (preferir canal reciente y ESTRECHO).
#     * Dump ≥ reclaim_bars cierres bajo base entre toques → no nace.
#     * Post-muerte: blacklist firma de toques.
# =============================================================================

sub new {
    my ( $class, %opts ) = @_;
    my $self = {
        trendline_min_touches      => $opts{trendline_min_touches} // 3,
        trendline_min_span_minutes => $opts{trendline_min_span_minutes} // 120,
        canal_min_touches          => $opts{canal_min_touches} // 3,
        canal_min_span_minutes     => $opts{canal_min_span_minutes} // 60,

        canal_min_touch_gap_minutes => $opts{canal_min_touch_gap_minutes} // 20,
        # Techo base en minutos; se amplía según TF (ver _max_span_minutes)
        canal_max_span_minutes_floor => $opts{canal_max_span_minutes_floor} // 480,
        canal_max_span_bars          => $opts{canal_max_span_bars} // 80,
        canal_lookback_bars          => $opts{canal_lookback_bars} // 120,
        max_width_atr_mult           => defined $opts{max_width_atr_mult}
          ? $opts{max_width_atr_mult}
          : 4,

        pivot_strength   => $opts{pivot_strength} // 2,
        atr_len          => $opts{atr_len} // 14,
        atr_k            => defined $opts{atr_k} ? $opts{atr_k} : 0.20,
        reclaim_bars     => $opts{reclaim_bars} // 3,
        max_active_tl    => $opts{max_active_tl} // 2,
        max_active_ch    => $opts{max_active_ch} // 1,
        max_outside_frac => defined $opts{max_outside_frac} ? $opts{max_outside_frac} : 0.12,

        # Minutos por vela del TF activo (lo actualiza ChartEngine / update)
        bar_minutes => $opts{bar_minutes} // 1,

        enable_trendline => exists $opts{enable_trendline} ? ( $opts{enable_trendline} ? 1 : 0 ) : 1,
        enable_channel   => exists $opts{enable_channel}   ? ( $opts{enable_channel}   ? 1 : 0 ) : 1,
    };
    bless $self, $class;
    $self->reset();
    return $self;
}

sub reset {
    my ($self) = @_;
    $self->{_o} = [];
    $self->{_h} = [];
    $self->{_l} = [];
    $self->{_c} = [];
    $self->{_t} = [];
    $self->{_epoch} = [];
    $self->{_atr} = [];
    $self->{_tr_sum} = 0;
    $self->{_last} = -1;
    $self->{_swing_highs} = [];
    $self->{_swing_lows}  = [];
    $self->{_trendlines} = [];
    $self->{_channels}   = [];
    $self->{_next_id}    = 1;
    $self->{_channel_dead_after} = { support => -1 };
    $self->{_dead_touch_sigs}    = {};
    $self->{_need_channel_birth} = 1;
    $self->{_tl_lows_seen}  = 0;
    $self->{_tl_highs_seen} = 0;
    return $self;
}

sub set_bar_minutes {
    my ( $self, $m ) = @_;
    $m = 1 unless defined $m && $m > 0;
    $self->{bar_minutes} = 0 + $m;
    return $self;
}

sub set_enable_trendline {
    my ( $self, $on ) = @_;
    $self->{enable_trendline} = $on ? 1 : 0;
    return $self;
}

sub set_enable_channel {
    my ( $self, $on ) = @_;
    $self->{enable_channel} = $on ? 1 : 0;
    return $self;
}

sub update_last {
    my ( $self, $md, $index ) = @_;
    return $self unless $md && defined $index && $index >= 0;
    my $c = $md->get_candle($index);
    return $self unless $c;

    my ( $ts, $o, $h, $l, $cl ) = @$c[ 0 .. 4 ];
    $self->{_o}[$index] = $o;
    $self->{_h}[$index] = $h;
    $self->{_l}[$index] = $l;
    $self->{_c}[$index] = $cl;
    $self->{_t}[$index] = $ts;
    $self->{_epoch}[$index] = _epoch_minutes($ts);
    $self->{_last} = $index;

    # Inferir minutos/barra del TF activo
    if ( $md && defined $md->{active_tf} ) {
        my $bm = _tf_to_minutes( $md->{active_tf} );
        $self->{bar_minutes} = $bm if $bm > 0;
    }

    my $lows_before  = scalar @{ $self->{_swing_lows} };
    my $highs_before = scalar @{ $self->{_swing_highs} };
    $self->_update_atr($index);
    $self->_detect_pivot($index);
    my $new_low_pivot  = ( scalar @{ $self->{_swing_lows} } > $lows_before )  ? 1 : 0;
    my $new_high_pivot = ( scalar @{ $self->{_swing_highs} } > $highs_before ) ? 1 : 0;

    $self->_extend_active($index);
    $self->_expand_outer_rail($index);    # solo superior (variable); slope locked
    my $had_active = scalar grep { $_->{active} } @{ $self->{_channels} };
    $self->_mitigate($index);
    my $has_active = scalar grep { $_->{active} } @{ $self->{_channels} };
    if ( $had_active && !$has_active ) {
        $self->{_need_channel_birth} = 1;    # reintentar tras muerte
    }
    # Nuevo low (toques) o high (ancla superior): reevaluar nacimiento.
    if ( $new_low_pivot || $new_high_pivot ) {
        $self->{_need_channel_birth} = 1;
    }

    # Trendline: solo cuando aparece pivote nuevo (barato vs cada barra).
    if ( $self->{enable_trendline} && ( $new_low_pivot || $new_high_pivot ) ) {
        my $tol = $self->_tol($index);
        $self->_try_birth_tl( 'support',    $self->{_swing_lows},  $tol, $index )
          if $new_low_pivot;
        $self->_try_birth_tl( 'resistance', $self->{_swing_highs}, $tol, $index )
          if $new_high_pivot;
    }

    # Canal: UN activo. Mientras no hay activo, reintentar en pivote/muerte
    # y también cada pocas barras (el ancla high puede confirmarse después).
    if ( $self->{enable_channel} && !$has_active ) {
        my $periodic = ( ( $index % 4 ) == 0 ) ? 1 : 0;
        if ( $self->{_need_channel_birth} || $periodic ) {
            $self->_try_birth_channel_bottom( $self->_tol($index), $index );
            $self->{_need_channel_birth} = 0;
        }
    }
    return $self;
}

sub get_values {
    my ($self) = @_;
    # REQUISITOS §1.5: UN canal activo extendido a la punta causal; al invalidar
    # desaparece por completo (no apilar históricos muertos en pantalla).
    return {
        trendlines => $self->get_active_trendlines(),
        channels   => $self->get_active_channels(),
        last_index => $self->{_last},
    };
}

sub get_active_trendlines {
    my ($self) = @_;
    return [ grep { $_->{active} } @{ $self->{_trendlines} } ];
}

sub get_active_channels {
    my ($self) = @_;
    return [ grep { $_->{active} } @{ $self->{_channels} } ];
}

# ---- helpers ---------------------------------------------------------------

sub _tf_to_minutes {
    my ($tf) = @_;
    return 1  unless defined $tf;
    return 1  if $tf eq '1m';
    return 5  if $tf eq '5m';
    return 15 if $tf eq '15m';
    return 60 if $tf eq '1h';
    return 120 if $tf eq '2h';
    return 240 if $tf eq '4h';
    return 1440 if $tf eq 'D';
    return 10080 if $tf eq 'W';
    return 0 + $1 if $tf =~ /^(\d+)m$/;
    return 0 + $1 * 60 if $tf =~ /^(\d+)h$/;
    return 1;
}

sub _max_span_minutes {
    my ($self) = @_;
    my $floor = $self->{canal_max_span_minutes_floor} // 480;
    my $bm    = $self->{bar_minutes} // 1;
    # En TF altos, 8h wall-clock no alcanza para 3 pivotes; usar ≥ 48 barras
    my $by_bars = 48 * $bm;
    return $floor > $by_bars ? $floor : $by_bars;
}

sub _epoch_minutes {
    my ($ts) = @_;
    return undef unless defined $ts && length $ts;
    if ( $ts =~ /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})/ ) {
        require Time::Local;
        my $sec = eval { Time::Local::timegm( 0, $5, $4, $3, $2 - 1, $1 - 1900 ) };
        return undef unless defined $sec;
        return int( $sec / 60 );
    }
    return undef;
}

sub _update_atr {
    my ( $self, $i ) = @_;
    my $h = $self->{_h}[$i];
    my $l = $self->{_l}[$i];
    return unless defined $h && defined $l;
    my $prev_c = $i > 0 ? $self->{_c}[ $i - 1 ] : undef;
    my $tr = $h - $l;
    if ( defined $prev_c ) {
        my $a = abs( $h - $prev_c );
        my $b = abs( $l - $prev_c );
        $tr = $a if $a > $tr;
        $tr = $b if $b > $tr;
    }
    my $len = $self->{atr_len};
    if ( $i + 1 < $len ) {
        $self->{_tr_sum} += $tr;
        $self->{_atr}[$i] = undef;
        return;
    }
    if ( $i + 1 == $len ) {
        $self->{_tr_sum} += $tr;
        $self->{_atr}[$i] = $self->{_tr_sum} / $len;
        return;
    }
    my $prev = $self->{_atr}[ $i - 1 ];
    return unless defined $prev;
    $self->{_atr}[$i] = ( $prev * ( $len - 1 ) + $tr ) / $len;
}

sub _tol {
    my ( $self, $i ) = @_;
    my $atr = $self->{_atr}[$i];
    $atr = $self->{_atr}[ $i - 1 ] if !defined $atr && $i > 0;
    return 1.0 unless defined $atr && $atr > 0;
    return $atr * $self->{atr_k};
}

sub _detect_pivot {
    my ( $self, $i ) = @_;
    my $s = $self->{pivot_strength};
    return if $i < 2 * $s;
    my $p  = $i - $s;
    my $hp = $self->{_h}[$p];
    my $lp = $self->{_l}[$p];
    return unless defined $hp && defined $lp;

    my $is_high = 1;
    my $is_low  = 1;
    for my $j ( $p - $s .. $p + $s ) {
        next if $j == $p;
        my $hj = $self->{_h}[$j];
        my $lj = $self->{_l}[$j];
        $is_high = 0 if !defined $hj || $hj >= $hp;
        $is_low  = 0 if !defined $lj || $lj <= $lp;
    }
    if ($is_high) {
        push @{ $self->{_swing_highs} }, {
            index => $p, price => $hp, epoch => $self->{_epoch}[$p],
        };
        shift @{ $self->{_swing_highs} } while @{ $self->{_swing_highs} } > 40;
    }
    if ($is_low) {
        push @{ $self->{_swing_lows} }, {
            index => $p, price => $lp, epoch => $self->{_epoch}[$p],
        };
        shift @{ $self->{_swing_lows} } while @{ $self->{_swing_lows} } > 40;
    }
}

sub _line_price {
    my ( $slope, $intercept, $idx ) = @_;
    return $slope * $idx + $intercept;
}

sub _fit_line {
    my ( $a, $b ) = @_;
    my $di = $b->{index} - $a->{index};
    return undef if !$di;
    my $slope     = ( $b->{price} - $a->{price} ) / $di;
    my $intercept = $a->{price} - $slope * $a->{index};
    return ( $slope, $intercept );
}

# Ajuste por mínimos cuadrados de ≥3 toques (lows reales) → la base pasa
# cerca de CADA mecha, no solo de extremos (evita punto medio “en el aire”).
sub _fit_line_ls {
    my ($pts) = @_;
    return undef unless $pts && @$pts >= 2;
    return _fit_line( $pts->[0], $pts->[-1] ) if @$pts == 2;
    my ( $n, $sx, $sy, $sxx, $sxy ) = ( 0, 0, 0, 0, 0 );
    for my $p (@$pts) {
        my $x = $p->{index};
        my $y = $p->{price};
        next unless defined $x && defined $y;
        $n++;
        $sx  += $x;
        $sy  += $y;
        $sxx += $x * $x;
        $sxy += $x * $y;
    }
    return undef if $n < 2;
    my $den = $n * $sxx - $sx * $sx;
    return undef if abs($den) < 1e-12;
    my $slope     = ( $n * $sxy - $sx * $sy ) / $den;
    my $intercept = ( $sy - $slope * $sx ) / $n;
    return ( $slope, $intercept );
}

sub _touches_on_wicks_ok {
    my ( $touches, $slope, $intercept, $tol ) = @_;
    return 0 unless $touches && @$touches >= 3;
    for my $t (@$touches) {
        return 0 unless defined $t->{index} && defined $t->{price};
        my $lp = _line_price( $slope, $intercept, $t->{index} );
        return 0 if abs( $t->{price} - $lp ) > $tol;
    }
    return 1;
}

sub _span_minutes {
    my ( $a, $b ) = @_;
    return undef unless defined $a->{epoch} && defined $b->{epoch};
    return abs( $b->{epoch} - $a->{epoch} );
}

sub _channel_width {
    my ( $base_int, $par_int ) = @_;
    return abs( ( $base_int // 0 ) - ( $par_int // 0 ) );
}

sub _count_touches {
    my ( $self, $swings, $ai, $bi, $slope, $intercept, $tol ) = @_;
    my @touches;
    for my $k ( $ai .. $bi ) {
        my $sw = $swings->[$k];
        my $lp = _line_price( $slope, $intercept, $sw->{index} );
        next if abs( $sw->{price} - $lp ) > $tol;
        push @touches, $sw;
    }
    return \@touches;
}

sub _outside_frac {
    my ( $self, $i0, $i1, $slope, $base_int, $par_int, $tol ) = @_;
    return 1 if $i1 <= $i0;
    my $out = 0;
    my $n   = 0;
    for my $j ( $i0 .. $i1 ) {
        my $cl = $self->{_c}[$j];
        next unless defined $cl;
        my $b = _line_price( $slope, $base_int, $j );
        my $p = _line_price( $slope, $par_int,  $j );
        my ( $bot, $top ) = $b < $p ? ( $b, $p ) : ( $p, $b );
        $n++;
        $out++ if $cl < $bot - $tol || $cl > $top + $tol;
    }
    return 1 unless $n;
    return $out / $n;
}

sub _max_consec_below_base {
    my ( $self, $i0, $i1, $slope, $base_int, $tol ) = @_;
    my $run = 0;
    my $max = 0;
    for my $j ( $i0 .. $i1 ) {
        my $cl = $self->{_c}[$j];
        next unless defined $cl;
        my $b = _line_price( $slope, $base_int, $j );
        if ( $cl < $b - $tol ) {
            $run++;
            $max = $run if $run > $max;
        }
        else {
            $run = 0;
        }
    }
    return $max;
}

sub _max_consec_above_par {
    my ( $self, $i0, $i1, $slope, $par_int, $tol ) = @_;
    my $run = 0;
    my $max = 0;
    return 0 if $i1 < $i0;
    for my $j ( $i0 .. $i1 ) {
        my $cl = $self->{_c}[$j];
        next unless defined $cl;
        my $p = _line_price( $slope, $par_int, $j );
        if ( $cl > $p + $tol ) {
            $run++;
            $max = $run if $run > $max;
        }
        else {
            $run = 0;
        }
    }
    return $max;
}

sub _touches_gap_ok {
    my ( $touches, $min_gap ) = @_;
    return 0 unless $touches && @$touches >= 2;
    for my $k ( 1 .. $#$touches ) {
        my $sp = _span_minutes( $touches->[ $k - 1 ], $touches->[$k] );
        return 0 unless defined $sp && $sp >= $min_gap;
    }
    return 1;
}

sub _touch_sig {
    my ($touches) = @_;
    return join( ',', map { $_->{index} // '' } @$touches );
}

sub _pick_three_touches {
    my ( $touches, $slope, $intercept ) = @_;
    return $touches if @$touches <= 3;
    my $first = $touches->[0];
    my $last  = $touches->[-1];
    my $best_mid;
    my $best_err = 1e99;
    for my $k ( 1 .. $#$touches - 1 ) {
        my $sw  = $touches->[$k];
        my $lp  = _line_price( $slope, $intercept, $sw->{index} );
        my $err = abs( $sw->{price} - $lp );
        if ( $err < $best_err ) {
            $best_err = $err;
            $best_mid = $sw;
        }
    }
    $best_mid //= $touches->[ int( $#$touches / 2 ) ];
    return [ $first, $best_mid, $last ];
}

# ---- birth -----------------------------------------------------------------

sub _try_birth {
    my ( $self, $i ) = @_;
    my $tol = $self->_tol($i);
    if ( $self->{enable_trendline} ) {
        $self->_try_birth_tl( 'support',    $self->{_swing_lows},  $tol, $i );
        $self->_try_birth_tl( 'resistance', $self->{_swing_highs}, $tol, $i );
    }
    if ( $self->{enable_channel} ) {
        # SIEMPRE riel inferior (lows). Nunca highs como base.
        $self->_try_birth_channel_bottom( $tol, $i );
    }
}

sub _already_similar_tl {
    my ( $self, $side, $slope, $intercept, $tol ) = @_;
    for my $tl ( @{ $self->{_trendlines} } ) {
        next unless $tl->{active} && ( $tl->{side} // '' ) eq $side;
        next if abs( ( $tl->{slope} // 0 ) - $slope ) > 1e-6;
        my $mid = int( ( ( $tl->{from_index} // 0 ) + ( $tl->{to_index} // 0 ) ) / 2 );
        my $y0  = _line_price( $tl->{slope}, $tl->{intercept}, $mid );
        my $y1  = _line_price( $slope, $intercept, $mid );
        return 1 if abs( $y0 - $y1 ) <= $tol * 2;
    }
    return 0;
}

sub _try_birth_tl {
    my ( $self, $side, $swings, $tol, $i ) = @_;
    my $need  = $self->{trendline_min_touches};
    my $spanm = $self->{trendline_min_span_minutes};
    my $n     = scalar @$swings;
    return if $n < $need;

    my $best;
    my $start = $n > 12 ? $n - 12 : 0;
    for my $a ( $start .. $n - $need ) {
        for my $b ( $a + $need - 1 .. $n - 1 ) {
            my ( $slope, $intercept ) = _fit_line( $swings->[$a], $swings->[$b] );
            next unless defined $slope;
            next if $side eq 'support'    && $slope < -0.05;
            next if $side eq 'resistance' && $slope > 0.05;
            my $touches = $self->_count_touches( $swings, $a, $b, $slope, $intercept, $tol );
            next if @$touches < $need;
            my $span = _span_minutes( $touches->[0], $touches->[-1] );
            next unless defined $span && $span >= $spanm;
            my $score = $touches->[-1]{index} * 1e3 + scalar(@$touches);
            if ( !defined $best || $score > $best->{score} ) {
                $best = {
                    score      => $score,
                    slope      => $slope,
                    intercept  => $intercept,
                    touches    => $touches,
                    from_index => $touches->[0]{index},
                    side       => $side,
                };
            }
        }
    }
    return unless $best;
    return if $self->_already_similar_tl( $side, $best->{slope}, $best->{intercept}, $tol );

    my $n_act = scalar grep { $_->{active} && $_->{side} eq $side } @{ $self->{_trendlines} };
    if ( $n_act >= $self->{max_active_tl} ) {
        for my $tl ( @{ $self->{_trendlines} } ) {
            if ( $tl->{active} && $tl->{side} eq $side ) {
                $tl->{active} = 0;
                $tl->{reason} = 'replaced';
                last;
            }
        }
    }

    push @{ $self->{_trendlines} }, {
        id         => $self->{_next_id}++,
        side       => $best->{side},
        slope      => $best->{slope},
        intercept  => $best->{intercept},
        from_index => $best->{from_index},
        to_index   => $i,
        born_index => $i,
        touches    => [ map { +{ index => $_->{index}, price => $_->{price} } } @{ $best->{touches} } ],
        active     => 1,
        kind       => 'trendline',
    };
}

sub _try_birth_channel_bottom {
    my ( $self, $tol, $i ) = @_;
    my $lows  = $self->{_swing_lows};
    my $highs = $self->{_swing_highs};
    my $need  = $self->{canal_min_touches};
    my $spanm = $self->{canal_min_span_minutes};
    my $spanx = $self->_max_span_minutes();
    my $max_b = $self->{canal_max_span_bars};
    my $gapm  = $self->{canal_min_touch_gap_minutes};
    my $n     = scalar @$lows;
    return if $n < $need;

    return if ( scalar grep { $_->{active} } @{ $self->{_channels} } ) >= $self->{max_active_ch};

    my $atr_now = $self->{_atr}[$i] // $self->{_atr}[ $i - 1 ];
    my $look_bars = $self->{canal_lookback_bars} // 120;

    my $best;
    my $start = $n > 16 ? $n - 16 : 0;
    for my $a ( $start .. $n - $need ) {
        for my $b ( $a + $need - 1 .. $n - 1 ) {
            my ( $slope, $intercept ) = _fit_line( $lows->[$a], $lows->[$b] );
            next unless defined $slope;

            my $touches = $self->_count_touches( $lows, $a, $b, $slope, $intercept, $tol );
            next if @$touches < $need;

            my $locked = _pick_three_touches( $touches, $slope, $intercept );
            next unless _touches_gap_ok( $locked, $gapm );

            my $span = _span_minutes( $locked->[0], $locked->[-1] );
            next unless defined $span && $span >= $spanm;
            next if $span > $spanx;

            my $i0 = $locked->[0]{index};
            my $i1 = $locked->[-1]{index};
            next if ( $i1 - $i0 ) > $max_b;          # anti mega en barras
            next if ( $i - $i1 ) > $look_bars;       # último toque reciente en barras

            # Tras invalidar: la NUEVA formación debe empezar DESPUÉS de la muerte.
            # Si solo exigíamos i1 > dead_after, el from_index podía solaparse con el
            # canal anterior (dos azules en la misma zona / “cambio de dirección”).
            my $dead_after = $self->{_channel_dead_after}{support} // -1;
            next if $i0 <= $dead_after;

            my $sig = _touch_sig($locked);
            next if $self->{_dead_touch_sigs}{$sig};

            # Base por LS de los 3 lows reales → cada punto queda sobre/near mecha.
            my ( $s2, $b2 ) = _fit_line_ls($locked);
            next unless defined $s2;
            next unless _touches_on_wicks_ok( $locked, $s2, $b2, $tol );

            my $anchor;
            for my $op (@$highs) {
                next if $op->{index} <= $i0 || $op->{index} >= $i1;
                $anchor = $op if !defined $anchor || $op->{price} > $anchor->{price};
            }
            next unless $anchor;

            my $par_int = $anchor->{price} - $s2 * $anchor->{index};
            my $mid     = int( ( $i0 + $i1 ) / 2 );
            my $y_base  = _line_price( $s2, $b2, $mid );
            my $y_par   = _line_price( $s2, $par_int, $mid );
            next if $y_par <= $y_base;

            my $width = _channel_width( $b2, $par_int );
            if ( defined $atr_now && $atr_now > 0 && $self->{max_width_atr_mult} > 0 ) {
                next if $width > $atr_now * $self->{max_width_atr_mult};
            }

            # Score barato ANTES de barridos O(span) — solo validar si puede ganar.
            my $score = $i1 * 1e6 - $width * 10;
            next if defined $best && $score <= $best->{score};

            my $frac = $self->_outside_frac( $i0, $i1, $s2, $b2, $par_int, $tol );
            next if $frac > $self->{max_outside_frac};

            my $consec = $self->_max_consec_below_base( $i0, $i1, $s2, $b2, $tol );
            next if $consec >= $self->{reclaim_bars};

            # HARD (Replay): no nacer si el precio ACTUAL (punta causal) ya está
            # fuera del rango. Evita que el canal “aparezca” tras un dump/escape.
            my $close_now = $self->{_c}[$i];
            next unless defined $close_now;
            my $base_now = _line_price( $s2, $b2, $i );
            my $par_now  = _line_price( $s2, $par_int, $i );
            my ( $bot_n, $top_n ) =
              $base_now < $par_now ? ( $base_now, $par_now ) : ( $par_now, $base_now );
            next if $close_now < $bot_n - $tol || $close_now > $top_n + $tol;

            # Tampoco si entre el último toque y la punta ya hubo dump/escape claro.
            my $post_dump = $self->_max_consec_below_base( $i1, $i, $s2, $b2, $tol );
            next if $post_dump >= $self->{reclaim_bars};
            my $post_up = $self->_max_consec_above_par( $i1, $i, $s2, $par_int, $tol );
            next if $post_up >= $self->{reclaim_bars};

            $best = {
                score      => $score,
                slope      => $s2,
                base_int   => $b2,
                par_int    => $par_int,
                width      => $width,
                touches    => $locked,
                from_index => $i0,
                form_span  => $span,
                touch_sig  => $sig,
            };
        }
    }
    return unless $best;

    my $mid_int = ( $best->{base_int} + $best->{par_int} ) / 2;
    push @{ $self->{_channels} }, {
        id                => $self->{_next_id}++,
        side              => 'support',
        slope             => $best->{slope},
        base_int          => $best->{base_int},
        par_int           => $best->{par_int},
        mid_int           => $mid_int,
        width             => $best->{width},
        from_index        => $best->{from_index},
        to_index          => $i,
        born_index        => $i,
        form_span_minutes => $best->{form_span},
        touch_sig         => $best->{touch_sig},
        touches => [ map { +{ index => $_->{index}, price => $_->{price} } } @{ $best->{touches} } ],
        geometry_locked => 1,
        break_tol       => $tol,
        active          => 1,
        kind            => 'channel',
    };
}

# ---- life / death ----------------------------------------------------------

sub _extend_active {
    my ( $self, $i ) = @_;
    for my $tl ( @{ $self->{_trendlines} } ) {
        $tl->{to_index} = $i if $tl->{active};
    }
    for my $ch ( @{ $self->{_channels} } ) {
        $ch->{to_index} = $i if $ch->{active};
    }
}

# Solo riel SUPERIOR ensancha. Base locked. Roce superior ≠ muerte.
sub _expand_outer_rail {
    my ( $self, $i ) = @_;
    my $high = $self->{_h}[$i];
    return unless defined $high;
    my $tol = $self->_tol($i);

    for my $ch ( @{ $self->{_channels} } ) {
        next unless $ch->{active};
        next unless ( $ch->{side} // '' ) eq 'support';
        my $par = _line_price( $ch->{slope}, $ch->{par_int}, $i );
        # Cap expansión: no ensanchar más allá de max_width_atr
        my $atr = $self->{_atr}[$i] // $self->{_atr}[ $i - 1 ];
        my $max_w =
          ( defined $atr && $atr > 0 )
          ? $atr * ( $self->{max_width_atr_mult} // 6 )
          : undef;
        if ( $high > $par + $tol * 0.25 ) {
            my $new_par = $high - $ch->{slope} * $i;
            my $new_w   = _channel_width( $ch->{base_int}, $new_par );
            next if defined $max_w && $new_w > $max_w;
            $ch->{par_int} = $new_par;
            $ch->{mid_int} = ( $ch->{base_int} + $ch->{par_int} ) / 2;
            $ch->{width}   = $new_w;
        }
    }
}

sub _mitigate {
    my ( $self, $i ) = @_;
    my $close = $self->{_c}[$i];
    my $high  = $self->{_h}[$i];
    my $low   = $self->{_l}[$i];
    return unless defined $close && defined $high && defined $low;
    my $tol = $self->_tol($i);
    my $N   = $self->{reclaim_bars};

    for my $tl ( @{ $self->{_trendlines} } ) {
        next unless $tl->{active};
        my $lp = _line_price( $tl->{slope}, $tl->{intercept}, $i );
        my $broke = 0;
        if ( ( $tl->{side} // '' ) eq 'support' ) {
            $broke = ( $close < $lp - $tol ) ? 1 : 0;
            if ( $low < $lp - $tol && $close >= $lp - $tol * 0.5 ) {
                $broke = 0;
                $tl->{break_streak} = 0;
            }
        }
        else {
            $broke = ( $close > $lp + $tol ) ? 1 : 0;
            if ( $high > $lp + $tol && $close <= $lp + $tol * 0.5 ) {
                $broke = 0;
                $tl->{break_streak} = 0;
            }
        }
        $tl->{break_streak} = $broke ? ( ( $tl->{break_streak} // 0 ) + 1 ) : 0;
        if ( ( $tl->{break_streak} // 0 ) >= $N ) {
            $tl->{active} = 0;
            $tl->{reason} = 'break';
        }
    }

    for my $ch ( @{ $self->{_channels} } ) {
        next unless $ch->{active};
        my $base = _line_price( $ch->{slope}, $ch->{base_int}, $i );
        my $par  = _line_price( $ch->{slope}, $ch->{par_int},  $i );
        my $ctol = $ch->{break_tol} // $tol;
        $ctol = $tol if $tol < $ctol;
        my $half_w = abs( $base - $par ) * 0.25;
        $ctol = $half_w if $half_w > 0 && $ctol > $half_w;

        # Muerte por:
        #  (A) ruptura de BASE (soporte) sin retorno
        #  (B) ESCAPE FUERTE por el riel SUPERIOR (cierres claros fuera).
        #     Oral: superior "variable" ante roce/mecha; pero "escapa con fuerza
        #     → se desarma". Sin (B) un canal temprano bloquea todo el dataset
        #     (max_active_ch=1) porque el precio queda arriba de la base para siempre.
        my $broke = 0;
        my $reason_hint = 'liquidity_or_break';

        if ( $close < $base - $ctol ) {
            $broke       = 1;
            $reason_hint = 'base_break';
        }
        if ( $low < $base - $ctol && $close >= $base - $ctol * 0.5 ) {
            $broke = 0;    # perforación menor de base
            $ch->{break_streak} = 0;
        }
        if ( $low < $base - 2 * $ctol && $close < $base - $ctol ) {
            $broke       = 1;
            $reason_hint = 'base_sweep';
        }

        # Escape superior: N cierres claramente por encima del riel
        if ( $close > $par + $ctol ) {
            $broke       = 1;
            $reason_hint = 'upper_escape';
        }
        # Mecha sobre la tapa con close que vuelve dentro → no cuenta (variable)
        if ( $high > $par + $ctol && $close <= $par + $ctol * 0.5 && $close >= $base - $ctol ) {
            $broke = 0 if ( $reason_hint eq 'upper_escape' );
            $ch->{break_streak} = 0 if ( $reason_hint eq 'upper_escape' );
        }

        # Dentro del canal (entre base y par) → reset
        if ( $close >= $base - $ctol * 0.25 && $close <= $par + $ctol * 0.25 ) {
            $broke = 0;
            $ch->{break_streak} = 0;
        }

        $ch->{break_streak} = $broke ? ( ( $ch->{break_streak} // 0 ) + 1 ) : 0;
        if ( ( $ch->{break_streak} // 0 ) >= $N ) {
            $ch->{active}   = 0;
            $ch->{reason}   = $reason_hint;
            $ch->{to_index} = $i;
            my $prev = $self->{_channel_dead_after}{support} // -1;
            $self->{_channel_dead_after}{support} = $i if $i > $prev;
            my $sig = $ch->{touch_sig} // _touch_sig( $ch->{touches} || [] );
            $self->{_dead_touch_sigs}{$sig} = 1 if defined $sig && length $sig;
        }
    }
}

1;
