package Market::Indicators::VolumeProfile;
use strict;
use warnings;

# =============================================================================
# Market::Indicators::VolumeProfile  — Anchored Volume Profile (AVP)
#
# Estilo TradingView drawing tool "Anchored Volume Profile":
#   - Ancla manual (índice de vela) → perfil desde ancla hasta fin efectivo
#     (feed/Replay). Sin ancla: sin perfil.
#   - Rows Layout = Number of Rows (por defecto): Row Size = nº de filas del
#     histograma (TV Inputs; profe: "número de barras/filas").
#   - Value Area Volume % (default 70).
#   - Volume mode: 'total' (profe: todo azul, sin up/down por fila).
#   - POC = fila de mayor volumen; VAH/VAL = área de valor expandiendo desde POC.
#
# Distribución de volumen: cada vela reparte su volumen equitativamente entre
# las filas de precio que intersecta [low, high] (estándar VP, no solo close).
# =============================================================================

sub new {
    my ($class, %opts) = @_;
    my $self = {
        # TV: Rows Layout = Number of Rows → Row Size = total rows
        rows_layout    => $opts{rows_layout} // 'number_of_rows',
        # TV default "Number of Rows" en Volume Profile es 24 (no 1000).
        row_size       => $opts{row_size} // 24,
        value_area_pct => $opts{value_area_pct} // 70,
        volume_mode    => $opts{volume_mode} // 'total',  # total | up_down
        tick_size      => $opts{tick_size} // 0.25,

        anchor_idx => undef,
        _highs     => [],
        _lows      => [],
        _opens     => [],
        _closes    => [],
        _volumes   => [],
        _last_data_idx => -1,
        # { poc, vah, val, bins => [{lo,hi,mid,vol}], min_p, max_p, anchor_idx, end_idx, total_vol }
        _profile   => undef,
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
    $self->{anchor_idx}    = $keep;
    return;
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
    $self->_recalculate_profile();
    return $self;
}

sub clear_anchor {
    my ($self) = @_;
    $self->{anchor_idx} = undef;
    $self->{_profile}   = undef;
    return $self;
}

sub set_row_size {
    my ($self, $n) = @_;
    $n = int($n // 0);
    $n = 1 if $n < 1;
    $n = 5000 if $n > 5000;  # techo defensivo
    $self->{row_size} = $n;
    $self->_recalculate_profile() if $self->has_anchor();
    return $self;
}

sub set_value_area_pct {
    my ($self, $pct) = @_;
    $pct = 0 + ($pct // 70);
    $pct = 1 if $pct < 1;
    $pct = 100 if $pct > 100;
    $self->{value_area_pct} = $pct;
    $self->_recalculate_profile() if $self->has_anchor();
    return $self;
}

sub set_volume_mode {
    my ($self, $mode) = @_;
    $mode = 'total' unless defined $mode && ($mode eq 'total' || $mode eq 'up_down');
    $self->{volume_mode} = $mode;
    # Profe: dibujo siempre total azul; el modo se guarda por API.
    $self->_recalculate_profile() if $self->has_anchor();
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

    return unless $self->has_anchor();
    # Recalcular solo cuando el feed llega a/por encima de la ancla.
    return if $index < $self->{anchor_idx};
    $self->_recalculate_profile();
    return;
}

sub get_values {
    my ($self) = @_;
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
    # Si no hay volumen, usar 1 por vela para no dejar perfil vacío.
    if ($total_vol <= 0) {
        $total_vol = ($end - $anchor + 1);
    }

    my $n_rows = int($self->{row_size} // 24);
    $n_rows = 1 if $n_rows < 1;
    my $step = ($max_p - $min_p) / $n_rows;
    $step = ($self->{tick_size} // 0.25) if $step <= 0;

    my @bins;
    for my $b (0 .. $n_rows - 1) {
        my $lo = $min_p + $b * $step;
        my $hi = $min_p + ($b + 1) * $step;
        push @bins, {
            lo  => $lo,
            hi  => $hi,
            mid => ($lo + $hi) / 2,
            vol => 0,
        };
    }

    for my $i ($anchor .. $end) {
        my $h = $self->{_highs}->[$i];
        my $l = $self->{_lows}->[$i];
        my $v = $self->{_volumes}->[$i];
        next unless defined $h && defined $l;
        $v = 1 if !defined $v || $v <= 0;

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
        }
    }

    # POC = fila de mayor volumen (en empate, la del medio del rango)
    my $max_b_vol = -1;
    my $poc_idx   = 0;
    for my $b (0 .. $#bins) {
        if ($bins[$b]->{vol} > $max_b_vol) {
            $max_b_vol = $bins[$b]->{vol};
            $poc_idx   = $b;
        }
    }

    # Value Area: expandir desde POC (método TV: comparar fila arriba/abajo)
    my $va_frac = ($self->{value_area_pct} // 70) / 100;
    $va_frac = 0.7 if $va_frac <= 0 || $va_frac > 1;
    my $target = $va_frac * $total_vol;
    # Usar suma de volúmenes de bins (puede diferir levemente por reparto)
    my $bins_total = 0;
    $bins_total += $_->{vol} for @bins;
    $target = $va_frac * $bins_total if $bins_total > 0;

    my $accum = $bins[$poc_idx]->{vol};
    my $low_b  = $poc_idx;
    my $high_b = $poc_idx;

    while ($accum < $target && ($low_b > 0 || $high_b < $n_rows - 1)) {
        my $v_down = ($low_b > 0) ? $bins[$low_b - 1]->{vol} : -1;
        my $v_up   = ($high_b < $n_rows - 1) ? $bins[$high_b + 1]->{vol} : -1;

        if ($v_up < 0 && $v_down < 0) {
            last;
        }
        if ($v_up >= $v_down && $high_b < $n_rows - 1) {
            $high_b++;
            $accum += $bins[$high_b]->{vol};
        }
        elsif ($low_b > 0) {
            $low_b--;
            $accum += $bins[$low_b]->{vol};
        }
        elsif ($high_b < $n_rows - 1) {
            $high_b++;
            $accum += $bins[$high_b]->{vol};
        }
        else {
            last;
        }
    }

    $self->{_profile} = {
        poc        => $bins[$poc_idx]->{mid},
        vah        => $bins[$high_b]->{hi},
        val        => $bins[$low_b]->{lo},
        bins       => \@bins,
        min_p      => $min_p,
        max_p      => $max_p,
        anchor_idx => $anchor,
        end_idx    => $end,
        total_vol  => $bins_total,
        poc_idx    => $poc_idx,
        va_low_idx => $low_b,
        va_high_idx=> $high_b,
        row_size   => $n_rows,
        value_area_pct => $self->{value_area_pct},
    };
    return $self;
}

1;
