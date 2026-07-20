package Market::Indicators::VolumeProfile2;
use strict;
use warnings;
use Time::Local qw(timegm);

# =============================================================================
# Market::Indicators::VolumeProfile2 — AVP v2 (paridad TradingView calibrada)
#
# Versión corregida de Market::Indicators::VolumeProfile (misma API pública:
# new/reset/set_anchor/clear_anchor/set_row_size/set_value_area_pct/
# set_volume_mode/update_last/compute/get_values) — intercambiable en
# ChartEngine cambiando la clase instanciada.
#
# Diferencias matemáticas vs v1 (calibradas contra 5 anclas GT de TradingView
# en NQ1! 15m; ver scratch/calibrate3.py):
#
#   1. REJILLA ALINEADA AL TICK: step = ceil( ((max-min)/row_size) / tick ) * tick
#      (v1 usaba (max-min)/row_size flotante). Origen en min de la ventana.
#      n_rows = ceil((max-min)/step)  (típicamente < row_size; p.ej. 974).
#
#   2. VOLUMEN LTF (lower timeframe): TradingView calcula el AVP con barras
#      1m, no con las velas del chart 15m. v2 carga CSVs 1m (ltf_dir/ltf_files):
#        - con columna Volume  -> volumen real;
#        - sin columna Volume  -> volumen estimado (modelo 'slotrange':
#          promedio por minuto-del-día medido en la data real × rango relativo).
#      Cada barra LTF reparte su volumen a partes iguales entre las filas que
#      su [low,high] toca (share = vol/n_tocadas). Up/Down: close>=open => up.
#      Barras del chart sin cobertura LTF aportan su volumen si > 0; si no hay
#      ningún volumen -> fallback v=1 por barra (renderiza como v1).
#
#   3. POC = fila de mayor volumen (empate => primera/más baja). Precio POC =
#      punto MEDIO de la fila redondeado al tick (v1 reportaba mid sin ajustar
#      rejilla).
#
#   4. VALUE AREA 70% (algoritmo documentado por TV): desde el POC, comparar
#      SUMA de las 2 filas superiores vs SUMA de las 2 inferiores; se agrega
#      el PAR ganador completo (en borde, la fila disponible). Empate => sube.
#      VAH = hi de la fila superior del VA; VAL = lo de la fila inferior.
#      (v1 agregaba de a 1 y cortaba a mitad de par => desplazaba VAH/VAL.)
#
# Optimización igual que v1: lazy (_dirty), update_last O(1), LTF cacheado.
# =============================================================================

sub new {
    my ($class, %opts) = @_;
    my $self = {
        rows_layout    => $opts{rows_layout} // 'number_of_rows',
        row_size       => $opts{row_size} // 1000,   # AVP TradingView = 1000
        value_area_pct => $opts{value_area_pct} // 70,
        volume_mode    => $opts{volume_mode} // 'up_down',  # 'up_down' | 'total'
        tick_size      => $opts{tick_size} // 0.25,
        ltf_dir        => $opts{ltf_dir},            # p.ej. 'Data'
        ltf_files      => $opts{ltf_files},          # lista explícita de CSVs 1m
        est_model      => $opts{est_model} // 'slotrange',

        anchor_idx     => $opts{anchor_idx},
        _highs         => [],
        _lows          => [],
        _opens         => [],
        _closes        => [],
        _volumes       => [],
        _times         => [],
        _last_data_idx => -1,
        _profile       => undef,
        _dirty         => 1,

        _ltf_scanned   => 0,
        _ltf           => [],   # barras 1m reales/estimadas: [t,o,h,l,c,v,est]
        _slot_sum      => {},
        _slot_n        => {},
        _glob_sum      => 0,
        _glob_n        => 0,
        _ratios        => [],
    };
    bless $self, $class;
    return $self;
}

sub reset {
    my ($self) = @_;
    my $keep = $self->{anchor_idx};
    $self->{_highs}         = [];
    $self->{_lows}          = [];
    $self->{_opens}         = [];
    $self->{_closes}        = [];
    $self->{_volumes}       = [];
    $self->{_times}         = [];
    $self->{_last_data_idx} = -1;
    $self->{_profile}       = undef;
    $self->{_dirty}         = 1;
    $self->{anchor_idx}     = $keep;
    return $self;
}

sub anchor_index { return $_[0]->{anchor_idx}; }
sub has_anchor   { return defined $_[0]->{anchor_idx} ? 1 : 0; }

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
    $n = int($n // 1000);
    $n = 10   if $n < 10;
    $n = 1000 if $n > 1000;
    $self->{row_size} = $n;
    $self->{_dirty}   = 1;
    return $self;
}

sub set_value_area_pct {
    my ($self, $pct) = @_;
    $pct = 0 + ($pct // 70);
    $pct = 1   if $pct < 1;
    $pct = 100 if $pct > 100;
    $self->{value_area_pct} = $pct;
    $self->{_dirty}         = 1;
    return $self;
}

sub set_volume_mode {
    my ($self, $mode) = @_;
    $mode = 'up_down' unless defined $mode && ($mode eq 'total' || $mode eq 'up_down');
    $self->{volume_mode} = $mode;
    $self->{_dirty}      = 1;
    return $self;
}

sub set_ltf_dir {
    my ($self, $d) = @_;
    $self->{ltf_dir} = $d;
    $self->{_ltf_scanned} = 0;
    $self->{_dirty} = 1;
    return $self;
}

sub set_ltf_files {
    my ($self, $files) = @_;
    $self->{ltf_files} = $files;
    $self->{_ltf_scanned} = 0;
    $self->{_dirty} = 1;
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
    $self->{_times}->[$index]   = _iso_epoch($candle->[0]);

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
# Utilidades de tiempo y rejilla
# ---------------------------------------------------------------------------
sub _iso_epoch {
    my ($s) = @_;
    return undef unless defined $s;
    return unless $s =~ /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?/;
    my ($Y, $M, $D, $h, $m, $sec) = ($1, $2, $3, $4, $5, $6 // 0);
    # Offset constante -05:00 en todo el dataset: comparaciones consistentes
    # tratando la parte naive como UTC.
    return timegm($sec, $m, $h, $D, $M - 1, $Y);
}

sub _ceil_pos {
    my ($x) = @_;
    my $i = int($x);
    return ($x > $i) ? $i + 1 : $i;
}

# Carga perezosa de CSVs 1m (con o sin columna Volume), deduplicando por
# timestamp (gana el que trae volumen real). También acumula estadísticos
# para el modelo de volumen estimado (slot por minuto-del-día, ratio vol/rango).
sub _ensure_ltf_loaded {
    my ($self) = @_;
    return if $self->{_ltf_scanned};
    $self->{_ltf_scanned} = 1;

    my @files;
    if (ref $self->{ltf_files} eq 'ARRAY' && @{ $self->{ltf_files} }) {
        @files = @{ $self->{ltf_files} };
    }
    elsif (defined $self->{ltf_dir} && length $self->{ltf_dir}) {
        @files = sort glob("$self->{ltf_dir}/*.csv");
    }
    return unless @files;

    my %seen;   # timestamp => 1 si ya hay barra con volumen real
    my @bars;   # [t,o,h,l,c,v,est]
    for my $f (@files) {
        next unless -f $f;
        open my $fh, '<', $f or next;
        my $header = <$fh>;
        next unless defined $header;
        my $has_vol = ($header =~ /volume/i) ? 1 : 0;
        # Solo aceptar CSVs de 1 minuto: verificar delta de 60s entre las
        # dos primeras filas de datos (descarta exports 15m/5m/etc.).
        my ($l1, $l2) = (scalar(<$fh>), scalar(<$fh>));
        next unless defined $l1 && defined $l2;
        my $e1 = _iso_epoch((split /,/, $l1)[0]);
        my $e2 = _iso_epoch((split /,/, $l2)[0]);
        next unless defined $e1 && defined $e2 && ($e2 - $e1) == 60;
        my $process = sub {
            my ($line) = @_;
            chomp $line; $line =~ s/\r//g;
            my @c = split /,/, $line;
            return if @c < 5;
            return unless $c[1] =~ /^-?\d/;    # descarta encabezados
            my $t = _iso_epoch($c[0]) or return;
            my ($o, $h, $l, $cl) = (0 + $c[1], 0 + $c[2], 0 + $c[3], 0 + $c[4]);
            my $v = ($has_vol && @c >= 6 && defined $c[5] && $c[5] =~ /^-?\d+(?:\.\d+)?$/)
                  ? 0 + $c[5] : undef;
            if (defined $v) {
                return if $seen{$c[0]}++;
                push @bars, [ $t, $o, $h, $l, $cl, $v, 0 ];
                # estadísticos para el modelo estimado
                my ($hh, $mm) = $c[0] =~ /^.{11}(\d{2}):(\d{2})/;
                my $moday = $hh * 60 + $mm;
                $self->{_slot_sum}{$moday} += $v;
                $self->{_slot_n}{$moday}++;
                $self->{_glob_sum} += $v;
                $self->{_glob_n}++;
                push @{ $self->{_ratios} }, $v / ($h - $l) if $h > $l;
            }
            else {
                return if $seen{$c[0]};        # ya existe con volumen real
                push @bars, [ $t, $o, $h, $l, $cl, undef, 1 ];
            }
        };
        $process->($l1);
        $process->($l2);
        while (my $line = <$fh>) {
            $process->($line);
        }
        close $fh;
    }
    @bars = sort { $a->[0] <=> $b->[0] } @bars;
    $self->{_ltf} = \@bars;
    return;
}


# ---------------------------------------------------------------------------
sub _recalculate_profile {
    my ($self) = @_;
    my $anchor = $self->{anchor_idx};
    my $end    = $self->{_last_data_idx};
    $self->{_profile} = undef;
    return unless defined $anchor && $end >= 0;
    return if $anchor > $end;

    # 1) Rango de la ventana [ancla .. fin] sobre barras del chart
    my $min_p = 1e300;
    my $max_p = -1e300;
    for my $i ($anchor .. $end) {
        my $h = $self->{_highs}->[$i];
        my $l = $self->{_lows}->[$i];
        next unless defined $h && defined $l;
        $max_p = $h if $h > $max_p;
        $min_p = $l if $l < $min_p;
    }
    return if $max_p <= $min_p;

    # 2) Rejilla TradingView: step = ceil(((max-min)/rows)/tick)*tick, origen min
    my $rows_req = int($self->{row_size} // 1000);
    $rows_req = 10   if $rows_req < 10;
    $rows_req = 1000 if $rows_req > 1000;
    my $ts = $self->{tick_size} // 0.25;
    $ts = 0.25 if $ts <= 0;
    my $raw_step = ($max_p - $min_p) / $rows_req;
    my $step = ($raw_step > $ts) ? _ceil_pos(($raw_step / $ts) - 1e-12) * $ts : $ts;
    my $n_rows = _ceil_pos(($max_p - $min_p) / $step - 1e-9);
    $n_rows = 1 if $n_rows < 1;

    my @bins;
    for my $b (0 .. $n_rows - 1) {
        my $lo = $min_p + $b * $step;
        push @bins, {
            lo       => $lo,
            hi       => $lo + $step,
            mid      => $lo + $step / 2,
            vol      => 0,
            vol_up   => 0,
            vol_down => 0,
        };
    }

    # 3) Fuente de volumen: barras LTF (1m) reales/estimadas en la ventana
    $self->_ensure_ltf_loaded();
    my $t0 = $self->{_times}->[$anchor] // 0;
    my $t1 = ($self->{_times}->[$end] // 0) + 900;   # vela 15m: +15 min exclusivo

    my @src;   # (h, l, v, is_up)
    my $ltf = $self->{_ltf};
    my ($n_real, $n_est, $n_chart) = (0, 0, 0);

    # Parámetros del modelo de volumen estimado (medidos en la data 1m real)
    my $glob_avg = $self->{_glob_n} ? $self->{_glob_sum} / $self->{_glob_n} : 0;
    my $k_rng = 0;
    if (@{ $self->{_ratios} }) {
        my @r = sort { $a <=> $b } @{ $self->{_ratios} };
        $k_rng = $r[ int(@r / 2) ];
    }
    my $est_vol = sub {    # ($t, $h, $l, $mult_por_barra) -> volumen estimado
        my ($t, $h, $l, $mult) = @_;
        return 1 if $glob_avg <= 0;
        my $moday = int(($t % 86400) / 60);
        my $sn  = $self->{_slot_n}{$moday} // 0;
        my $sav = $sn ? ($self->{_slot_sum}{$moday} / $sn) : $glob_avg;
        if (($self->{est_model} // '') eq 'slotrange' && $k_rng > 0) {
            return $sav * ($h > $l ? ($h - $l) : 0.25) * $k_rng / $glob_avg * $mult;
        }
        return $sav * $mult;
    };

    if (@$ltf) {
        # 3a) Barras del chart NO cubiertas por ninguna barra LTF (huecos):
        #     aportan su volumen propio si > 0, si no, volumen estimado.
        my $jj = 0;
        $jj++ while $jj < @$ltf && $ltf->[$jj][0] < $t0;
        for my $i ($anchor .. $end) {
            my $bt = $self->{_times}->[$i] // next;
            $jj++ while $jj < @$ltf && $ltf->[$jj][0] < $bt;
            my $covered = ($jj < @$ltf && $ltf->[$jj][0] < $bt + 900) ? 1 : 0;
            next if $covered;
            my ($h, $l) = ($self->{_highs}->[$i], $self->{_lows}->[$i]);
            next unless defined $h && defined $l;
            my $v = $self->{_volumes}->[$i] // 0;
            $v = $est_vol->($bt, $h, $l, 15) if $v <= 0;
            my $up = (($self->{_closes}->[$i] // $h) >= ($self->{_opens}->[$i] // $l)) ? 1 : 0;
            push @src, [ $h, $l, $v, $up ];
            $n_chart++;
        }
        # 3b) Barras LTF dentro de la ventana [t0, t1)
        for my $b (@$ltf) {
            my ($t, $o, $h, $l, $c, $v, $est) = @$b;
            next if $t < $t0 || $t >= $t1;
            if (!defined $v) {
                $v = $est_vol->($t, $h, $l, 1);
                $n_est++;
            }
            else {
                $n_real++;
            }
            push @src, [ $h, $l, $v, ($c >= $o ? 1 : 0) ];
        }
    }
    else {
        # Sin data LTF: todas las barras del chart (volumen propio, estimado o 1)
        for my $i ($anchor .. $end) {
            my ($h, $l) = ($self->{_highs}->[$i], $self->{_lows}->[$i]);
            next unless defined $h && defined $l;
            my $v = $self->{_volumes}->[$i] // 0;
            $v = $est_vol->($self->{_times}->[$i] // $t0, $h, $l, 15) if $v <= 0;
            my $up = (($self->{_closes}->[$i] // $h) >= ($self->{_opens}->[$i] // $l)) ? 1 : 0;
            push @src, [ $h, $l, $v, $up ];
            $n_chart++;
        }
    }
    my $source = $n_real ? 'ltf' : ($n_est ? 'ltf_est' : ($n_chart ? 'chart' : 'unit'));

    # 4) Distribución equal-split sobre las filas tocadas por cada barra
    for my $s (@src) {
        my ($h, $l, $v, $up) = @$s;
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
            if ($up) { $bins[$b]->{vol_up}   += $share; }
            else     { $bins[$b]->{vol_down} += $share; }
        }
    }


    # 5) POC = primera fila con volumen máximo (empate => la más baja)
    my $poc_idx = 0;
    my $max_b_vol = -1;
    for my $b (0 .. $#bins) {
        if ($bins[$b]->{vol} > $max_b_vol) {
            $max_b_vol = $bins[$b]->{vol};
            $poc_idx   = $b;
        }
    }

    # 6) Value Area 70%: pares de 2 filas arriba vs 2 abajo (algoritmo TV)
    my $va_frac = ($self->{value_area_pct} // 70) / 100;
    $va_frac = 0.7 if $va_frac <= 0 || $va_frac > 1;

    my $bins_total = 0;
    $bins_total += $_->{vol} for @bins;
    my $target = $va_frac * $bins_total;

    my $accum  = $bins[$poc_idx]->{vol};
    my $low_b  = $poc_idx;
    my $high_b = $poc_idx;

    while ($accum < $target && ($low_b > 0 || $high_b < $n_rows - 1)) {
        my $v_up = 0;
        $v_up += $bins[$high_b + 1]->{vol} if $high_b < $n_rows - 1;
        $v_up += $bins[$high_b + 2]->{vol} if $high_b < $n_rows - 2;

        my $v_down = 0;
        $v_down += $bins[$low_b - 1]->{vol} if $low_b > 0;
        $v_down += $bins[$low_b - 2]->{vol} if $low_b > 1;

        if ($v_up >= $v_down && $high_b < $n_rows - 1) {
            for (1 .. 2) {
                last if $high_b >= $n_rows - 1;
                $high_b++;
                $accum += $bins[$high_b]->{vol};
            }
        }
        elsif ($low_b > 0) {
            for (1 .. 2) {
                last if $low_b <= 0;
                $low_b--;
                $accum += $bins[$low_b]->{vol};
            }
        }
        else {
            for (1 .. 2) {
                last if $high_b >= $n_rows - 1;
                $high_b++;
                $accum += $bins[$high_b]->{vol};
            }
        }
    }

    # 7) Precios reportados (convenciones TradingView + redondeo al tick)
    my $round_tick = sub {
        my ($val) = @_;
        return unless defined $val;
        return int($val / $ts + ($val >= 0 ? 0.5 : -0.5)) * $ts;
    };

    my $poc_price = $round_tick->($min_p + ($poc_idx + 0.5) * $step);   # mid de la fila POC
    my $vah_price = $round_tick->($min_p + ($high_b + 1) * $step);     # hi fila superior VA
    my $val_price = $round_tick->($min_p + $low_b * $step);            # lo fila inferior VA

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
        step           => $step,
        source         => $source,
        ltf_real       => $n_real,
        ltf_est        => $n_est,
        chart_bars     => $n_chart,
        value_area_pct => $self->{value_area_pct},
    };
    return $self;
}

1;

