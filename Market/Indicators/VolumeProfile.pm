package Market::Indicators::VolumeProfile;
use strict;
use warnings;

# =============================================================================
# Market::Indicators::VolumeProfile — Anchored Volume Profile (AVP)
#
# Estilo TradingView drawing tool "Anchored Volume Profile" (AVP):
#   - Ancla manual (índice de vela) -> perfil desde ancla hasta fin efectivo.
#     Si no hay ancla manual especificada, ancla por defecto a 0.
#   - Rows Layout = Number of Rows. Row Size configurable (default 100, max 1000).
#   - Value Area Volume % = 70.
#   - Volume mode: 'up_down' (desglose comprador/vendedor por bin) o 'total'.
#   - POC = bin de mayor volumen; VAH/VAL = área de valor al 70% expandiendo desde POC.
#
# Optimización de rendimiento: evaluación diferida (lazy evaluation con _dirty).
# Las llamadas a update_last() durante la carga/feed masivo son O(1).
# El recálculo del perfil (_recalculate_profile) ocurre SOLO 1 vez al consultar get_values().
# =============================================================================

sub new {
    my ($class, %opts) = @_;
    my $self = {
        rows_layout    => $opts{rows_layout} // 'number_of_rows',
        row_size       => $opts{row_size} // 300,
        value_area_pct => $opts{value_area_pct} // 70,
        volume_mode    => $opts{volume_mode} // 'up_down',  # 'up_down' | 'total'
        tick_size      => $opts{tick_size} // 0.25,

        anchor_idx     => $opts{anchor_idx}, # default undef (ancla por defecto a 0 al renderizar)
        _highs         => [],
        _lows          => [],
        _opens         => [],
        _closes        => [],
        _volumes       => [],
        _last_data_idx => -1,
        _profile       => undef,
        _dirty         => 1,
    };
    bless $self, $class;
    return $self;
}

sub reset {
    my ($self) = @_;
    my $keep = $self->{anchor_idx};
    $self->{_highs}        = [];
    $self->{_lows}         = [];
    $self->{_opens}        = [];
    $self->{_closes}       = [];
    $self->{_volumes}      = [];
    $self->{_last_data_idx} = -1;
    $self->{_profile}      = undef;
    $self->{_dirty}        = 1;
    $self->{anchor_idx}    = $keep;
    return $self;
}

sub anchor_index {
    my ($self) = @_;
    return $self->{anchor_idx};
}

sub has_anchor {
    my ($self) = @_;
    return defined $self->{anchor_idx} ? 1 : 0;
}

sub set_anchor {
    my ($self, $idx) = @_;
    return $self unless defined $idx;
    $idx = int($idx);
    $idx = 0 if $idx < 0;
    my $last = $self->{_last_data_idx};
    $idx = $last if $last >= 0 && $idx > $last;
    $self->{anchor_idx} = $idx;
    $self->{_dirty}     = 1;
    return $self;
}

sub clear_anchor {
    my ($self) = @_;
    $self->{anchor_idx} = undef;
    $self->{_profile}   = undef;
    $self->{_dirty}     = 0;
    return $self;
}

sub set_row_size {
    my ($self, $n) = @_;
    $n = int($n // 100);
    $n = 10 if $n < 10;
    $n = 1000 if $n > 1000;
    $self->{row_size} = $n;
    $self->{_dirty}   = 1;
    return $self;
}

sub set_value_area_pct {
    my ($self, $pct) = @_;
    $pct = 0 + ($pct // 70);
    $pct = 1 if $pct < 1;
    $pct = 100 if $pct > 100;
    $self->{value_area_pct} = $pct;
    $self->{_dirty}         = 1;
    return $self;
}

sub set_volume_mode {
    my ($self, $mode) = @_;
    $mode = 'up_down' unless defined $mode && ($mode eq 'total' || $mode eq 'up_down');
    $self->{volume_mode} = $mode;
    $self->{_dirty}         = 1;
    return $self;
}

sub row_size       { $_[0]->{row_size} }
sub value_area_pct { $_[0]->{value_area_pct} }
sub volume_mode    { $_[0]->{volume_mode} }

sub update_last {
    my ($self, $market_data, $index) = @_;
    my $candle = defined $index ? $market_data->get_candle($index) : $market_data->last_candle();
    return unless $candle;
    return unless defined $index;

    $self->{_opens}->[$index]   = $candle->[1];
    $self->{_highs}->[$index]   = $candle->[2];
    $self->{_lows}->[$index]    = $candle->[3];
    $self->{_closes}->[$index]  = $candle->[4];
    $self->{_volumes}->[$index] = defined $candle->[5] ? $candle->[5] : 0;

    $self->{_last_data_idx} = $index if $index > ($self->{_last_data_idx} // -1);
    $self->{_dirty}         = 1;
    return;
}

sub compute {
    my ($self, $market_data, %opts) = @_;
    my $size = $market_data->size();
    $self->reset();
    for (my $i = 0; $i < $size; $i++) {
        $self->update_last($market_data, $i);
    }
    return $self->get_values();
}

sub get_values {
    my ($self) = @_;
    if ($self->{_dirty} && $self->has_anchor()) {
        $self->_recalculate_profile();
        $self->{_dirty} = 0;
    }
    return $self->{_profile};
}

# ---------------------------------------------------------------------------
sub _recalculate_profile {
    my ($self) = @_;
    my $anchor = $self->{anchor_idx};
    my $end    = $self->{_last_data_idx};
    $self->{_profile} = undef;
    return unless defined $anchor && $end >= 0;
    return if $anchor > $end;

    my $min_p = 1e300;
    my $max_p = -1e300;
    my $total_vol = 0;

    for my $i ($anchor .. $end) {
        my $h = $self->{_highs}->[$i];
        my $l = $self->{_lows}->[$i];
        my $v = $self->{_volumes}->[$i] // 0;
        next unless defined $h && defined $l;
        $max_p = $h if $h > $max_p;
        $min_p = $l if $l < $min_p;
        $total_vol += $v if $v > 0;
    }

    return if $max_p <= $min_p;
    if ($total_vol <= 0) {
        $total_vol = ($end - $anchor + 1);
    }

    my $n_rows = int($self->{row_size} // 1000);
    $n_rows = 10 if $n_rows < 10;
    $n_rows = 2000 if $n_rows > 2000;
    my $step = ($max_p - $min_p) / $n_rows;
    $step = ($self->{tick_size} // 0.25) if $step <= 0;

    my @bins;
    for my $b (0 .. $n_rows - 1) {
        my $lo = $min_p + $b * $step;
        my $hi = $min_p + ($b + 1) * $step;
        push @bins, {
            lo       => $lo,
            hi       => $hi,
            mid      => ($lo + $hi) / 2,
            vol      => 0,
            vol_up   => 0,
            vol_down => 0,
        };
    }

    for my $i ($anchor .. $end) {
        my $h = $self->{_highs}->[$i];
        my $l = $self->{_lows}->[$i];
        my $o = $self->{_opens}->[$i] // $l;
        my $c = $self->{_closes}->[$i] // $h;
        my $v = $self->{_volumes}->[$i];
        next unless defined $h && defined $l;
        $v = 1 if !defined $v || $v <= 0;

        my $is_up = ($c >= $o) ? 1 : 0;

        my $i0 = int(($l - $min_p) / $step);
        my $i1 = int(($h - $min_p) / $step);
        $i0 = 0 if $i0 < 0;
        $i1 = 0 if $i1 < 0;
        $i0 = $n_rows - 1 if $i0 >= $n_rows;
        $i1 = $n_rows - 1 if $i1 >= $n_rows;
        ($i0, $i1) = ($i1, $i0) if $i0 > $i1;
        my $n_touch = $i1 - $i0 + 1;
        next if $n_touch < 1;
        my $share = $v / $n_touch;
        for my $b ($i0 .. $i1) {
            $bins[$b]->{vol} += $share;
            if ($is_up) {
                $bins[$b]->{vol_up} += $share;
            } else {
                $bins[$b]->{vol_down} += $share;
            }
        }
    }


    # POC = bin central del nodo/pico de mayor volumen
    my $max_b_vol = 0;
    for my $b (0 .. $#bins) {
        $max_b_vol = $bins[$b]->{vol} if $bins[$b]->{vol} > $max_b_vol;
    }

    my @peak_bins;
    if ($max_b_vol > 0) {
        my $threshold = $max_b_vol * 0.999;
        for my $b (0 .. $#bins) {
            push @peak_bins, $b if $bins[$b]->{vol} >= $threshold;
        }
    }

    my $poc_idx = 0;
    if (@peak_bins) {
        $poc_idx = $peak_bins[ int(@peak_bins / 2) ];
    }

    # Value Area: expandir desde POC comparando bin superior vs inferior (fórmula canónica legacy)
    my $va_frac = ($self->{value_area_pct} // 70) / 100;
    $va_frac = 0.7 if $va_frac <= 0 || $va_frac > 1;

    my $bins_total = 0;
    $bins_total += $_->{vol} for @bins;
    my $target = $va_frac * $bins_total;

    my $accum  = $bins[$poc_idx]->{vol};
    my $low_b  = $poc_idx;
    my $high_b = $poc_idx;

    while ($accum < $target && ($low_b > 0 || $high_b < $n_rows - 1)) {
        # Evaluar hasta 2 bins arriba
        my $v_up = 0;
        my $up_count = 0;
        if ($high_b < $n_rows - 1) {
            $v_up += $bins[$high_b + 1]->{vol};
            $up_count++;
        }
        if ($high_b < $n_rows - 2) {
            $v_up += $bins[$high_b + 2]->{vol};
            $up_count++;
        }

        # Evaluar hasta 2 bins abajo
        my $v_down = 0;
        my $dn_count = 0;
        if ($low_b > 0) {
            $v_down += $bins[$low_b - 1]->{vol};
            $dn_count++;
        }
        if ($low_b > 1) {
            $v_down += $bins[$low_b - 2]->{vol};
            $dn_count++;
        }

        if ($up_count == 0 && $dn_count == 0) {
            last;
        }

        if ($v_up >= $v_down && $up_count > 0) {
            $high_b++;
            $accum += $bins[$high_b]->{vol};
            last if $accum >= $target;
            if ($up_count > 1) {
                $high_b++;
                $accum += $bins[$high_b]->{vol};
            }
        }
        elsif ($dn_count > 0) {
            $low_b--;
            $accum += $bins[$low_b]->{vol};
            last if $accum >= $target;
            if ($dn_count > 1) {
                $low_b--;
                $accum += $bins[$low_b]->{vol};
            }
        }
        elsif ($up_count > 0) {
            $high_b++;
            $accum += $bins[$high_b]->{vol};
            last if $accum >= $target;
            if ($up_count > 1) {
                $high_b++;
                $accum += $bins[$high_b]->{vol};
            }
        }
        else {
            last;
        }
    }

    my $ts = $self->{tick_size} // 0.25;
    my $round_tick = sub {
        my ($val) = @_;
        return unless defined $val;
        return int($val / $ts + ($val >= 0 ? 0.5 : -0.5)) * $ts;
    };

    my $poc_price = $round_tick->($bins[$poc_idx]->{mid});
    my $vah_price = $round_tick->($bins[$high_b]->{hi});
    my $val_price = $round_tick->($bins[$low_b]->{lo});

    $self->{_profile} = {
        poc            => $poc_price,
        vah            => $vah_price,
        val            => $val_price,
        bins           => \@bins,
        min_p          => $min_p,
        max_p          => $max_p,
        anchor_idx     => $anchor,
        end_idx        => $end,
        total_vol      => $bins_total,
        poc_idx        => $poc_idx,
        va_low_idx     => $low_b,
        va_high_idx    => $high_b,
        row_size       => $n_rows,
        value_area_pct => $self->{value_area_pct},
    };
    return $self;
}

1;

