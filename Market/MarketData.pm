package Market::MarketData;
use strict;
use warnings;
use Time::Moment;

sub new {
    my ($class) = @_;
    my $self = {
        data      => { '1m' => [], '5m' => [], '15m' => [] },
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

    my $group_size = ($tf eq '5m') ? 5 : ($tf eq '15m') ? 15 : 1;
    my @aggregated;
    
    for (my $i = 0; $i < @$base_data; $i += $group_size) {
        my $end = $i + $group_size - 1;
        $end = $#$base_data if $end > $#$base_data;
        
        my @slice = @$base_data[$i .. $end];
        my $ts = $slice[0]->[0];
        my $open = $slice[0]->[1];
        my $close = $slice[-1]->[4];
        
        my ($high, $low, $vol) = ($slice[0]->[2], $slice[0]->[3], 0);
        for my $c (@slice) {
            $high = $c->[2] if $c->[2] > $high;
            $low  = $c->[3] if $c->[3] < $low;
            $vol += $c->[5];
        }
        push @aggregated, [$ts, $open, $high, $low, $close, $vol];
    }
    $self->{data}->{$tf} = \@aggregated;
}

sub build_timeframes {
    my ($self) = @_;
    $self->build_tf_candles('5m');
    $self->build_tf_candles('15m');
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
    $start = 0 if !defined $start || $start < 0;
    $end = $#$arr if !defined $end || $end > $#$arr;
    return [] if $start > $end;
    return [ @{$arr}[$start .. $end] ];
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