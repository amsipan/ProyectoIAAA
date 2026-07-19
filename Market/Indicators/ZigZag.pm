package Market::Indicators::ZigZag;
use strict;
use warnings;

# =============================================================================
# Market::Indicators::ZigZag — dirección interna (MTF) + externa (swing)
# Task 0033: dos ZigZag conviven con SMC/Mxwll; cálculo puro sin Tk.
#
# Interno (ZZMTF / LonesomeTheBlue): resolución HTF (default 30m profe), period=2.
#   Captura profe: Show Zig Zag ON; Fibonacci OFF; colores verde/rojo.
#   Source: docs/reference_indicators/zigzag_mtf_fibonacci_lonesometheblue.txt
#   Pivotes ph/pl con ventana len desde newbar; dir +1/-1; último tramo ajustable.
#
# Externo (ChartPrime): swingLength=150, solo línea zigzag azul.
#   Captura profe: Swing Channel OFF, VolumeProfile OFF, PoC OFF.
#   Source: docs/reference_indicators/zigzag_volumeprofile_chartprime.txt
#   max_external_segments=15 (paridad visual TV).
#
# compute_internal / compute_external: on-demand (producto 3.2).
# external_only=1 ⇒ no calcular interno (compat fase 3.1 / atajos).
#
# Contrato: new / update_last($md,$i) / get_values / reset
# =============================================================================

use Time::Moment;

my $MAX_VERTICES = 50;
# ChartPrime: Amount of ZigZag Volume Profiles = 15 (captura profe)
my $DEFAULT_MAX_EXT_SEGS = 15;


sub new {
    my ($class, %args) = @_;
    # Compat: external_only=1 → no interno. Si se pasa compute_*, gana compute_*.
    my $external_only = exists $args{external_only} ? ( $args{external_only} ? 1 : 0 ) : 0;
    my $compute_internal =
        exists $args{compute_internal}
      ? ( $args{compute_internal} ? 1 : 0 )
      : ( $external_only ? 0 : 1 );
    my $compute_external =
        exists $args{compute_external} ? ( $args{compute_external} ? 1 : 0 ) : 1;

    my $self = {
        # ZZMTF captura profe: Resolution 30, Period 2, Show ZZ only (sin fib)
        internal_resolution => $args{internal_resolution} // 30,
        internal_period     => $args{internal_period}     // 2,
        # ChartPrime captura profe: Length 150
        swing_length        => $args{swing_length}        // 150,
        atr_period          => $args{atr_period}          // 200,
        channel_width       => $args{channel_width}       // 1,
        channel_max_span    => $args{channel_max_span}    // 220,
        external_only       => $external_only,
        compute_internal    => $compute_internal,
        compute_external    => $compute_external,
        max_external_segments => $args{max_external_segments} // $DEFAULT_MAX_EXT_SEGS,
    };
    # No %args al final: evita que keys sueltas pisen flags ya resueltos.
    for my $k ( keys %args ) {
        next if $k =~ /^(?:external_only|compute_internal|compute_external|
            internal_resolution|internal_period|swing_length|atr_period|
            channel_width|channel_max_span|max_external_segments)$/x;
        $self->{$k} = $args{$k};
    }
    bless $self, $class;
    $self->reset();
    return $self;
}

sub reset {
    my ($self) = @_;
    $self->{_int_dir}              = 0;
    $self->{_int_prev_dir}         = 0;
    $self->{_int_vertices}         = [];
    $self->{_int_segments}         = [];
    $self->{_int_newbar_indices}   = [];
    $self->{_last_mtf_bucket}      = undef;
    $self->{internal_direction}    = [];

    $self->{_ext_trend}            = undef;
    $self->{_ext_bullish}          = undef;
    $self->{_ext_vertices}         = [];
    $self->{_ext_segments}         = [];
    $self->{_ext_pivot_high_idx}   = undef;
    $self->{_ext_pivot_high_price} = undef;
    $self->{_ext_pivot_low_idx}    = undef;
    $self->{_ext_pivot_low_price}  = undef;
    $self->{_high_buf}             = [];
    $self->{_low_buf}              = [];
    $self->{_close_buf}            = [];
    $self->{_tr_buf}               = [];
    $self->{_atr}                  = undef;
    $self->{external_direction}    = [];
    return $self;
}

sub set_internal_resolution {
    my ($self, $minutes) = @_;
    return $self unless defined $minutes && $minutes =~ /^\d+$/ && $minutes > 0;
    return $self if ($self->{internal_resolution} // 0) == $minutes;
    $self->{internal_resolution} = $minutes;
    $self->reset();
    return $self;
}

sub set_external_only {
    my ( $self, $bool ) = @_;
    $self->{external_only}    = $bool ? 1 : 0;
    $self->{compute_internal} = $bool ? 0 : 1;
    return $self;
}

sub set_compute_internal {
    my ( $self, $bool ) = @_;
    $self->{compute_internal} = $bool ? 1 : 0;
    $self->{external_only}    = $self->{compute_internal} ? 0 : 1;
    return $self;
}

sub set_compute_external {
    my ( $self, $bool ) = @_;
    $self->{compute_external} = $bool ? 1 : 0;
    return $self;
}

sub wants_internal { $_[0]->{compute_internal} ? 1 : 0 }
sub wants_external { $_[0]->{compute_external} ? 1 : 0 }

sub update_last {
    my ($self, $market_data, $index) = @_;
    return unless $market_data && defined $index;

    my $candle = $market_data->get_candle($index);
    return unless $candle;
    my ($ts, $open, $high, $low, $close) = @$candle[0 .. 4];

    # On-demand: ZZMTF interno y/o ChartPrime externo (producto 3.2).
    if ( $self->{compute_internal} ) {
        $self->_update_internal( $market_data, $index, $ts, $high, $low );
    }
    if ( $self->{compute_external} ) {
        $self->_update_external( $index, $high, $low, $close );
    }

    $self->{internal_direction}[$index] =
        $self->{compute_internal}
      ? ( $self->{_int_dir}
          ? $self->{_int_dir}
          : ( $index > 0 ? ( $self->{internal_direction}[ $index - 1 ] // 0 ) : 0 ) )
      : 0;
    $self->{external_direction}[$index] =
        $self->{compute_external}
      ? ( defined $self->{_ext_bullish}
          ? ( $self->{_ext_bullish} ? 1 : -1 )
          : ( $index > 0 ? ( $self->{external_direction}[ $index - 1 ] // 0 ) : 0 ) )
      : 0;
    return $self;
}

sub get_values {
    my ($self) = @_;
    return {
        internal_vertices   => [ @{ $self->{_int_vertices} } ],
        external_vertices   => [ @{ $self->{_ext_vertices} } ],
        internal_segments   => [ @{ $self->{_int_segments} } ],
        external_segments   => [ @{ $self->{_ext_segments} } ],
        external_channel    => [ @{ $self->_external_channel_list() } ],
        trend_channels      => [ @{ $self->_trend_channels_list() } ],
        internal_direction  => [ @{ $self->{internal_direction} } ],
        external_direction  => [ @{ $self->{external_direction} } ],
    };
}

# external_channel — deprecado (task 0061); vacío; tests antiguos solo exigen la clave.
sub _external_channel_list {
    return [];
}

# trend_channels — canal de tendencia clásico (task 0061).
# Trendline: 2 pivotes del mismo lado (2 lows si tendencia up, 2 highs si down).
# Paralela: misma pendiente, anclada al pivote opuesto más extremo ENTRE esos dos.
# Nota: _ext_vertices trae vértices DUPLICADOS (cada segmento empuja inicio+fin, así
# que pivotes contiguos se repiten); hay que deduplicar por índice antes de clasificar
# por alternancia, si no la paridad se desalinea.
sub _dedup_ext_vertices {
    my ($self) = @_;
    my @out;
    for my $v (@{ $self->{_ext_vertices} }) {
        next unless defined $v->{index} && defined $v->{price};
        next if @out && $out[-1]{index} == $v->{index};
        push @out, { index => $v->{index}, price => $v->{price} };
    }
    return \@out;
}

sub _trend_channels_list {
    my ($self) = @_;
    my @segs  = @{ $self->{_ext_segments} // [] };
    return [] unless @segs >= 1;
    my @verts = @{ $self->_dedup_ext_vertices() };
    return [] unless @verts >= 3;

    my $dir       = $segs[-1]{dir};
    my $same_side = $dir eq 'up' ? 'low' : 'high';

    # Los vértices deduplicados alternan high/low; el tipo del primero se decide
    # comparando con el segundo (real, no por posición).
    my $first_is_low = $verts[0]{price} < $verts[1]{price};
    my @sides = map {
        ($_ % 2 == 0) ? ($first_is_low ? 'low' : 'high')
                      : ($first_is_low ? 'high' : 'low')
    } 0 .. $#verts;

    my @same_idx = grep { $sides[$_] eq $same_side } 0 .. $#verts;
    return [] if @same_idx < 2;

    my @channels;
    for my $k (1 .. $#same_idx) {
        my $ch = $self->_trend_channel_between(
            \@verts, \@sides, $dir, $same_idx[$k - 1], $same_idx[$k],
        );
        push @channels, $ch if $ch;
    }
    return \@channels;
}

# Canal entre dos pivotes del mismo lado (posiciones $ai < $bi en la lista deduplicada).
sub _trend_channel_between {
    my ($self, $verts, $sides, $dir, $ai, $bi) = @_;
    my $a = $verts->[$ai];
    my $b = $verts->[$bi];
    my $di = $b->{index} - $a->{index};
    return undef if !$di;
    my $max_span = $self->{channel_max_span} // 220;
    return undef if $max_span > 0 && $di > $max_span;

    my $opp = $dir eq 'up' ? 'high' : 'low';
    my $anchor;
    for my $vi ($ai + 1 .. $bi - 1) {
        next unless $sides->[$vi] eq $opp;
        my $v = $verts->[$vi];
        if ($dir eq 'up') {
            $anchor = $v if !defined $anchor || $v->{price} > $anchor->{price};
        } else {
            $anchor = $v if !defined $anchor || $v->{price} < $anchor->{price};
        }
    }
    return undef unless defined $anchor;

    my $m  = ($b->{price} - $a->{price}) / $di;
    my $pf = $anchor->{price} + $m * ($a->{index} - $anchor->{index});
    my $pt = $anchor->{price} + $m * ($b->{index} - $anchor->{index});

    return {
        from_index           => $a->{index},
        from_price           => $a->{price},
        to_index             => $b->{index},
        to_price             => $b->{price},
        parallel_from_index  => $a->{index},
        parallel_from_price  => $pf,
        parallel_to_index    => $b->{index},
        parallel_to_price    => $pt,
        dir                  => $dir,
    };
}

# Items para IndicatorSnapshot / tests (vértices + segmentos consolidados).
sub get_snapshot_items {
    my ($self) = @_;
    my @items;
    for my $seg (@{ $self->{_int_segments} }) {
        push @items, {
            index => $seg->{to_index},
            type  => $seg->{dir} eq 'up' ? 'ZZ_INT_UP' : 'ZZ_INT_DOWN',
            dir   => $seg->{dir},
            price => $seg->{to_price},
            meta  => {
                from_index => $seg->{from_index},
                from_price => $seg->{from_price},
                consolidated => $seg->{consolidated} ? 1 : 0,
                kind => 'internal',
            },
        };
    }
    for my $seg (@{ $self->{_ext_segments} }) {
        push @items, {
            index => $seg->{to_index},
            type  => $seg->{dir} eq 'up' ? 'ZZ_EXT_UP' : 'ZZ_EXT_DOWN',
            dir   => $seg->{dir},
            price => $seg->{to_price},
            meta  => {
                from_index => $seg->{from_index},
                from_price => $seg->{from_price},
                consolidated => $seg->{consolidated} ? 1 : 0,
                kind => 'external',
            },
        };
    }
    return \@items;
}

# --- MTF bucket (fronteras de reloj, estilo MarketData) -----------------------

sub _mtf_bucket_id {
    my ($self, $ts) = @_;
    my $res = $self->{internal_resolution} // 30;
    my $tm  = Time::Moment->from_string($ts);
    my $min = $tm->hour * 60 + $tm->minute;
    my $bucket_min = int($min / $res) * $res;
    return join ':', $tm->year, $tm->month, $tm->day_of_month, $bucket_min;
}

sub _range_extreme {
    my ($md, $from, $to, $kind) = @_;
    my ($best_val, $best_is) = (undef, 0);
    for my $i ($from .. $to) {
        my $c = $md->get_candle($i);
        next unless $c;
        my $v = $kind eq 'high' ? $c->[2] : $c->[3];
        if (!defined $best_val || ($kind eq 'high' ? $v > $best_val : $v < $best_val)) {
            $best_val = $v;
            $best_is  = $i;
        }
    }
    return ($best_val, $best_is);
}

sub _update_internal {
    my ($self, $md, $index, $ts, $high, $low) = @_;

    my $bucket = $self->_mtf_bucket_id($ts);
    my $newbar = !defined $self->{_last_mtf_bucket} || $bucket ne $self->{_last_mtf_bucket};
    $self->{_last_mtf_bucket} = $bucket;
    if ($newbar) {
        push @{ $self->{_int_newbar_indices} }, $index;
        shift @{ $self->{_int_newbar_indices} }
            while @{ $self->{_int_newbar_indices} } > 20;
    }

    my $prd = $self->{internal_period} // 2;
    my $bi  = 0;
    if (@{ $self->{_int_newbar_indices} } >= $prd) {
        $bi = $self->{_int_newbar_indices}[-$prd];
    }
    my $len = $index - $bi + 1;
    $len = 1 if $len < 1;

    my ($max_h, $max_i) = _range_extreme($md, $index - $len + 1, $index, 'high');
    my ($min_l, $min_i) = _range_extreme($md, $index - $len + 1, $index, 'low');

    my $ph = (defined $max_h && $max_i == $index && $high == $max_h) ? $high : undef;
    my $pl = (defined $min_l && $min_i == $index && $low == $min_l)  ? $low  : undef;

    my $dir = $self->{_int_dir};
    if (defined $ph && !defined $pl) {
        $dir = 1;
    } elsif (defined $pl && !defined $ph) {
        $dir = -1;
    }

    return unless defined $ph || defined $pl;

    my $dir_changed = $dir != ($self->{_int_prev_dir} // 0);
    if ($dir_changed) {
        $self->_int_add_vertex($dir > 0 ? $ph : $pl, $index);
    } else {
        $self->_int_update_vertex($dir > 0 ? $ph : $pl, $index, $dir);
    }
    $self->{_int_prev_dir} = $dir;
    $self->{_int_dir}      = $dir;
    $self->_rebuild_internal_segments();
}

sub _int_add_vertex {
    my ($self, $price, $index) = @_;
    return unless defined $price;
    unshift @{ $self->{_int_vertices} }, { index => $index, price => $price };
    pop @{ $self->{_int_vertices} } while @{ $self->{_int_vertices} } > $MAX_VERTICES;
}

sub _int_update_vertex {
    my ($self, $price, $index, $dir) = @_;
    return unless defined $price;
    if (!@{ $self->{_int_vertices} }) {
        $self->_int_add_vertex($price, $index);
        return;
    }
    my $v = $self->{_int_vertices}[0];
    if (($dir > 0 && $price > $v->{price}) || ($dir < 0 && $price < $v->{price})) {
        $v->{price} = $price;
        $v->{index} = $index;
    }
}

sub _rebuild_internal_segments {
    my ($self) = @_;
    my @verts = reverse @{ $self->{_int_vertices} };
    my @segs;
    for my $i (1 .. $#verts) {
        my $a = $verts[$i - 1];
        my $b = $verts[$i];
        my $dir = $b->{price} >= $a->{price} ? 'up' : 'down';
        push @segs, {
            from_index   => $a->{index},
            from_price   => $a->{price},
            to_index     => $b->{index},
            to_price     => $b->{price},
            dir          => $dir,
            consolidated => ($i < $#verts) ? 1 : 0,
        };
    }
    $self->{_int_segments} = \@segs;
}

# --- Externo: swingLength + lógica ChartPrime (solo línea) --------------------

sub _push_buf {
    my ($buf, $val, $max) = @_;
    push @$buf, $val;
    shift @$buf while @$buf > $max;
}

sub _buf_max { my ($b) = @_; return undef unless $b && @$b; my $m = $b->[0]; $m = $_ > $m ? $_ : $m for @$b; return $m; }
sub _buf_min { my ($b) = @_; return undef unless $b && @$b; my $m = $b->[0]; $m = $_ < $m ? $_ : $m for @$b; return $m; }

sub _update_atr {
    my ($self, $high, $low, $close) = @_;
    my $prev = $self->{_close_buf}[-1];
    my $tr;
    if (defined $prev) {
        my $hl  = $high - $low;
        my $hpc = abs($high - $prev);
        my $lpc = abs($low - $prev);
        $tr = $hl;
        $tr = $hpc if $hpc > $tr;
        $tr = $lpc if $lpc > $tr;
    } else {
        $tr = $high - $low;
    }
    _push_buf($self->{_tr_buf}, $tr, $self->{atr_period});
    my $n = @{ $self->{_tr_buf} };
    return if $n < $self->{atr_period};
    if (!defined $self->{_atr}) {
        my $sum = 0; $sum += $_ for @{ $self->{_tr_buf} };
        $self->{_atr} = $sum / $self->{atr_period};
    } else {
        my $p = $self->{atr_period};
        $self->{_atr} = ($self->{_atr} * ($p - 1) + $tr) / $p;
    }
}

sub _update_external {
    my ($self, $index, $high, $low, $close) = @_;
    my $slen = $self->{swing_length} // 150;

    _push_buf($self->{_high_buf},  $high,  $slen);
    _push_buf($self->{_low_buf},   $low,   $slen);
    $self->_update_atr($high, $low, $close);
    _push_buf($self->{_close_buf}, $close, $slen + 1);

    return if @{ $self->{_high_buf} } < $slen;

    my $swing_high = _buf_max($self->{_high_buf});
    my $swing_low  = _buf_min($self->{_low_buf});
    my $at_high = defined $swing_high && $high >= $swing_high - 1e-9;
    my $at_low  = defined $swing_low  && $low  <= $swing_low  + 1e-9;

    # ChartPrime (zigzag_volumeprofile_chartprime.txt):
    #   priceHigh := low[1]  en el swing high  → vértice en la PARTE INFERIOR de la vela del máximo
    #   priceLow  := low[1]  en el swing low   → vértice en el low de la vela del mínimo
    # No usar high del extremo superior (eso es lo que veía el usuario en la app).
    if ($at_high) {
        $self->{_ext_pivot_high_idx}   = $index;
        $self->{_ext_pivot_high_price} = $low;
    }
    if ($at_low) {
        $self->{_ext_pivot_low_idx}    = $index;
        $self->{_ext_pivot_low_price}  = $low;
    }

    my $trend     = $self->{_ext_trend};
    my $new_trend = $trend;
    if ($at_high && (!$at_low || ($trend // -1) <= 0)) {
        $new_trend = 1;
    } elsif ($at_low && (!$at_high || ($trend // 1) >= 0)) {
        $new_trend = -1;
    }

    if (defined $new_trend && (!defined $trend || $new_trend != $trend)) {
        if ($new_trend > 0
            && defined $self->{_ext_pivot_low_idx}
            && defined $self->{_ext_pivot_high_idx}) {
            $self->_ext_start_segment(
                $self->{_ext_pivot_low_idx},  $self->{_ext_pivot_low_price},
                $self->{_ext_pivot_high_idx}, $self->{_ext_pivot_high_price},
                'up',
            );
        } elsif ($new_trend < 0
            && defined $self->{_ext_pivot_high_idx}
            && defined $self->{_ext_pivot_low_idx}) {
            $self->_ext_start_segment(
                $self->{_ext_pivot_high_idx}, $self->{_ext_pivot_high_price},
                $self->{_ext_pivot_low_idx},  $self->{_ext_pivot_low_price},
                'down',
            );
        }
        $self->{_ext_trend} = $new_trend;
    } elsif (defined $new_trend) {
        # Actualizar extremo del tramo activo: siempre con low (paridad ChartPrime)
        if ($new_trend > 0 && $at_high) {
            $self->_ext_update_last( $index, $low );
        } elsif ($new_trend < 0 && $at_low) {
            $self->_ext_update_last( $index, $low );
        }
    }

    $self->{_ext_bullish} = defined $new_trend ? ($new_trend > 0 ? 1 : 0) : undef;
}

sub _ext_start_segment {
    my ($self, $i0, $p0, $i1, $p1, $dir) = @_;
    return unless defined $i0 && defined $p0 && defined $i1 && defined $p1;
    push @{ $self->{_ext_vertices} }, { index => $i0, price => $p0 };
    push @{ $self->{_ext_vertices} }, { index => $i1, price => $p1 };
    $self->_trim_external_history();
    $self->_rebuild_external_segments();
}

sub _ext_update_last {
    my ($self, $index, $price) = @_;
    return unless @{ $self->{_ext_vertices} };
    $self->{_ext_vertices}[-1] = { index => $index, price => $price };
    $self->_rebuild_external_segments();
}

# ChartPrime: if SProfile.size() > volumeProfilesQty (15) → shift y zg.delete().
# Cada segmento externo = 2 vértices (par). Conservar los N pares más recientes.
sub _trim_external_history {
    my ($self) = @_;
    my $max_segs = $self->{max_external_segments} // $DEFAULT_MAX_EXT_SEGS;
    $max_segs = $DEFAULT_MAX_EXT_SEGS if $max_segs < 1;
    my $max_verts = $max_segs * 2;
    # Techo duro también por MAX_VERTICES (interno/histórico)
    my $hard = $MAX_VERTICES * 2;
    $max_verts = $hard if $max_verts > $hard;
    my $v = $self->{_ext_vertices} ||= [];
    while ( @$v > $max_verts ) {
        shift @$v;
        shift @$v if @$v;    # quitar el par completo (inicio+fin del tramo más viejo)
    }
    return $self;
}

sub _rebuild_external_segments {
    my ($self) = @_;
    my @verts = @{ $self->{_ext_vertices} };
    my @segs;
    for (my $i = 1; $i < @verts; $i += 2) {
        my $a = $verts[$i - 1];
        my $b = $verts[$i];
        next unless $a && $b;
        my $dir = $b->{price} >= $a->{price} ? 'up' : 'down';
        push @segs, {
            from_index   => $a->{index},
            from_price   => $a->{price},
            to_index     => $b->{index},
            to_price     => $b->{price},
            dir          => $dir,
            consolidated => ($i < @verts - 2) ? 1 : 0,
        };
    }
    # Defensa: no más de max_external_segments (por si el buffer quedó impar)
    my $max_segs = $self->{max_external_segments} // $DEFAULT_MAX_EXT_SEGS;
    while ( @segs > $max_segs ) {
        shift @segs;
    }
    $self->{_ext_segments} = \@segs;
}

1;