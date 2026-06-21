package Market::MarketData;
use strict;
use warnings;
use Time::Moment;

sub new {
    my ($class) = @_;
    my $self = {
        data      => { '1m' => [], '5m' => [], '15m' => [], '1h' => [], '2h' => [], '4h' => [], 'D' => [], 'W' => [] },
        active_tf => '1m',
    };
    bless $self, $class;
    return $self;
}

sub get_data {
    my ($self) = @_;
    return $self->_active_array();
}

sub add_candle {
    my ($self, $candle) = @_;
    push @{ $self->{data}->{'1m'} }, $candle;
}

sub build_tf_candles {
    my ($self, $tf) = @_;
    my $base_data = $self->{data}->{'1m'};
    return unless @$base_data;

    my @aggregated;
    my ($current_key, $current);

    for my $c (@$base_data) {
        my $bucket_ts = $self->_bucket_timestamp($c->[0], $tf);
        next unless defined $bucket_ts;

        if (!defined $current_key || $bucket_ts ne $current_key) {
            push @aggregated, $current if defined $current;
            $current_key = $bucket_ts;
            $current = [$bucket_ts, $c->[1], $c->[2], $c->[3], $c->[4], $c->[5]];
            next;
        }

        $current->[2] = $c->[2] if $c->[2] > $current->[2];
        $current->[3] = $c->[3] if $c->[3] < $current->[3];
        $current->[4] = $c->[4];
        $current->[5] += $c->[5];
    }

    push @aggregated, $current if defined $current;
    $self->{data}->{$tf} = \@aggregated;
}

# _bucket_timestamp($ts, $tf) — frontera de reloj para el TF dado.
# $tf puede ser un nombre ('5m','15m','1h','2h','4h','D','W') o un entero de minutos.
# - minutos (5,15,60,120,240): truncar al múltiplo de minutos desde medianoche.
# - 'D': truncar a inicio de día (00:00) calendario.
# - 'W': truncar a inicio de semana (lunes). Time::Moment->day_of_week es ISO 8601
#   (1=Lun .. 7=Dom). Se resta (dow-1) días para llegar al lunes de esa semana.
sub _bucket_timestamp {
    my ($self, $ts, $tf) = @_;
    return undef unless defined $ts;

    # --- Casos especiales: D y W no usan minutos ---
    if (!defined $tf) {
        return $ts;
    }
    elsif ($tf eq 'D') {
        if ($ts =~ /^(\d{4}-\d{2}-\d{2})T\d{2}:\d{2}:\d{2}(.*)$/) {
            return $1 . 'T00:00:00' . $2;
        }
        return $ts;
    }
    elsif ($tf eq 'W') {
        my $tm = eval { Time::Moment->from_string($ts) };
        return $ts unless $tm;
        my $dow = $tm->day_of_week;  # 1=Lun .. 7=Dom
        my $monday = $tm->minus_days($dow - 1);
        if ($ts =~ /^(\d{4}-\d{2}-\d{2})T\d{2}:\d{2}:\d{2}(.*)$/) {
            my $suffix = $2;
            return sprintf('%04d-%02d-%02dT00:00:00%s',
                $monday->year, $monday->month, $monday->day_of_month, $suffix);
        }
        return $ts;
    }

    # --- Minutos: resolver $minutes desde $tf o entero ---
    my $minutes;
    if ($tf =~ /^(\d+)$/) {
        $minutes = int($1);
    } elsif ($tf eq '1m') {
        return $ts;  # sin agregación
    } elsif ($tf eq '5m') {
        $minutes = 5;
    } elsif ($tf eq '15m') {
        $minutes = 15;
    } elsif ($tf eq '1h') {
        $minutes = 60;
    } elsif ($tf eq '2h') {
        $minutes = 120;
    } elsif ($tf eq '4h') {
        $minutes = 240;
    } else {
        return $ts;
    }

    return $ts if !$minutes || $minutes <= 1;

    # Para >= 60 min, truncar hora+minuto juntos.
    if ($minutes >= 60) {
        if ($ts =~ /^(\d{4}-\d{2}-\d{2}T)(\d{2}):(\d{2}):(\d{2})(.*)$/) {
            my ($date_prefix, $hour, $min, $sec, $sfx) = ($1, $2, $3, $4, $5);
            my $total_minutes = int($hour) * 60 + int($min);
            my $bucket_total = int($total_minutes / $minutes) * $minutes;
            my $bucket_hour = int($bucket_total / 60);
            my $bucket_min = $bucket_total % 60;
            return sprintf('%s%02d:%02d:00%s', $date_prefix, $bucket_hour, $bucket_min, $sfx);
        }
        return $ts;
    }

    # Para < 60 min (5m, 15m), truncar solo minutos.
    if ($ts =~ /^(\d{4}-\d{2}-\d{2}T\d{2}):(\d{2}):(\d{2})(.*)$/) {
        my ($prefix, $minute, $second, $suffix) = ($1, $2, $3, $4);
        my $bucket_minute = int($minute / $minutes) * $minutes;
        return sprintf('%s:%02d:00%s', $prefix, $bucket_minute, $suffix);
    }

    return $ts;
}

sub build_timeframes {
    my ($self) = @_;
    for my $tf ('5m', '15m', '1h', '2h', '4h', 'D', 'W') {
        $self->build_tf_candles($tf);
    }
}

sub set_timeframe {
    my ($self, $tf) = @_;
    $self->{active_tf} = $tf if exists $self->{data}->{$tf};
}

sub _active_array {
    my ($self) = @_;
    return $self->{data}->{ $self->{active_tf} };
}

sub get_slice {
    my ($self, $start, $end) = @_;
    my $arr = $self->_active_array();
    return [] unless @$arr;
    return [] if !defined $start || !defined $end || $start > $end;

    my @slice;
    for my $i ($start .. $end) {
        push @slice, ($i >= 0 && $i <= $#$arr) ? $arr->[$i] : undef;
    }
    return \@slice;
}

sub get_candle {
    my ($self, $index) = @_;
    return $self->_active_array()->[$index];
}

sub size {
    my ($self) = @_;
    return scalar @{ $self->_active_array() };
}

sub last_candle {
    my ($self) = @_;
    return $self->_active_array()->[-1];
}

sub last_index {
    my ($self) = @_;
    return $self->size() - 1;
}

sub get_timestamp {
    my ($self, $index) = @_;
    my $candle = $self->get_candle($index);
    return $candle ? $candle->[0] : undef;
}

sub merge_delta_row {
    my ($self, $row) = @_;
    my $arr = $self->{data}->{'1m'};
    
    if (@$arr && $arr->[-1]->[0] eq $row->[0]) {
        my $last = $arr->[-1];
        $last->[2] = $row->[2] if $row->[2] > $last->[2];
        $last->[3] = $row->[3] if $row->[3] < $last->[3];
        $last->[4] = $row->[4];
        $last->[5] += $row->[5];
    } else {
        $self->add_candle($row);
    }
}

# compute_time_anchors — puntos clave de tiempo para el eje/etiquetas (capa de datos).
#
# Detecta dos tipos de ancla temporal recorriendo el array de velas activo:
#   * Cambio de HORA dentro del mismo día (etiqueta de tiempo regular).
#   * Cambio de DÍA calendario (marcador de fecha) usando Time::Moment
#     (->year, ->month, ->day_of_month). Un cambio de día es ancla aunque la
#     hora coincida con la de la vela anterior (p.ej. gaps de datos entre jornadas).
#
# CAMBIO DE CONTRATO (tradingview-parity, tarea 4.1):
#   Antes devolvía un arrayref de ENTEROS (índices donde cambiaba la hora).
#   Ahora devuelve un arrayref de HASHES enriquecidos:
#       [ { index => N, is_date => 0|1 }, ... ]
#   donde is_date == 1 marca un cambio de DÍA (cambio de fecha) e is_date == 0
#   marca un cambio de HORA dentro del mismo día. La primera vela del array no
#   se considera cambio de fecha (no tiene vela anterior con la cual comparar),
#   por lo que se marca como ancla de hora (is_date => 0).
#   No hay consumidores previos que dependan del formato antiguo; ChartEngine
#   usará la marca is_date para resaltar los cambios de fecha en el eje de tiempo.
#
# Responsabilidad: SOLO capa de datos. No conoce render ni coordenadas; usa
# exclusivamente Time::Moment (ya importado). Las velas con timestamp no
# parseable se omiten sin abortar.
sub compute_time_anchors {
    my ($self) = @_;
    my $arr = $self->_active_array();
    my @anchors;

    my ($last_year, $last_month, $last_day, $last_hour) = (-1, -1, -1, -1);
    my $have_prev = 0;

    for my $i (0 .. $#$arr) {
        my $tm = eval { Time::Moment->from_string($arr->[$i]->[0]) };
        next unless $tm;

        my $year  = $tm->year;
        my $month = $tm->month;
        my $day   = $tm->day_of_month;
        my $hour  = $tm->hour;

        my $day_changed  = ($year != $last_year)
                        || ($month != $last_month)
                        || ($day != $last_day);
        my $hour_changed = ($hour != $last_hour);

        if ($day_changed || $hour_changed) {
            # is_date solo cuando hay una vela anterior real con la que comparar.
            my $is_date = ($day_changed && $have_prev) ? 1 : 0;
            push @anchors, { index => $i, is_date => $is_date };
        }

        ($last_year, $last_month, $last_day, $last_hour) =
            ($year, $month, $day, $hour);
        $have_prev = 1;
    }

    return \@anchors;
}

1;