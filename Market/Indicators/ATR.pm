package Market::Indicators::ATR;
use strict;
use warnings;

# Market::Indicators::ATR — Average True Range (Capa de Indicadores)
# CONTRATO DE DESACOPLE (Req. 13.1)
# Este módulo pertenece a la CAPA DE INDICADORES de la arquitectura de 4 capas.
# Calcula la volatilidad (ATR) ÚNICAMENTE a partir de los datos OHLC que expone
# Market::MarketData (vía get_candle/last_candle). Está TOTALMENTE DESACOPLADO
# del renderizado
# NO referencia `Tk` ni ningún widget/canvas de la GUI.
# NO conoce paneles (PricePanel/ATRPanel) ni coordenadas de pantalla.
# NO realiza conversión datos<->píxeles (eso vive solo en Scales.pm).
# NO usa variables globales: todo el estado vive en la instancia ($self).
# Esto permite validar el ATR contra TradingView de forma aislada y preservar
# la regla "no mezclar cálculo con render".
# CONTRATO O(1) POR VELA — método Wilder (Req. 13.2)
# `update_last` realiza trabajo en TIEMPO CONSTANTE por cada vela nueva. No
# recorre el historial: mantiene estado incremental (_last_close, _last_atr,
# _tr_sum, _count) y aplica el suavizado de Wilder
# True Range (TR) de la vela actual
# primera vela: TR = high - low
# resto: TR = max(high-low,
# high - prev_close|,
# low - prev_close|)
# ATR (Wilder)
# velas 1..period-1: acumula TR en _tr_sum, ATR = undef (warm-up)
# vela == period (semilla): ATR = _tr_sum / period (SMA inicial)
# velas > period: ATR = (_last_atr*(period-1) + TR) / period
# Cada llamada hace un nº fijo de operaciones aritméticas y un push => O(1).
# La serie completa de N velas se construye en O(N) llamadas incrementales,
# produciendo el MISMO resultado que un recálculo desde la serie completa
# (equivalencia incremental == batch, Req. 13.3).
# RECÁLCULO AL CAMBIAR TIMEFRAME (Req. 13.4)
# No hay lógica de timeframe aquí. Al cambiar de temporalidad, el orquestador
# (ChartEngine::set_timeframe) invoca IndicatorManager::reset_all (que llama a
# `reset` de cada indicador) y luego recalcula vela por vela con `update_last`.
# Ver Market/IndicatorManager.pm para el contrato del recálculo.
# Métodos
# new($period) — inicializa el indicador con el período (entero > 0).
# update_last($md,$i) — incorpora UNA vela (la última, o la de índice $i) en O(1).
# get_values() — serie completa de ATR (con `undef` durante el warm-up).
# reset() — reinicia el estado interno (usado al cambiar timeframe).

sub new {
    my ($class, $period) = @_;
    die "ATR period must be a positive integer"
        unless defined $period && $period =~ /^\d+$/ && $period > 0;

    my $self = {
        period      => $period,
        values      => [],
        _tr_sum     => 0,
        _last_close => undef,
        _last_atr   => undef,
        _count      => 0,
    };
    bless $self, $class;
    return $self;
}

sub update_last {
    my ($self, $market_data, $index) = @_;
    # O(1) por vela: solo lee una vela y actualiza estado incremental (Wilder).
    my $candle = defined $index ? $market_data->get_candle($index) : $market_data->last_candle();
    return unless $candle;
    return $self->update_ohlc( $candle->[2], $candle->[3], $candle->[4] );
}

# update_ohlc($high, $low, $close) — mismo Wilder O(1) sin depender de MarketData.
# Permite construir ATR de un TF en background sin mutar active_tf.
sub update_ohlc {
    my ( $self, $high, $low, $close ) = @_;
    return unless defined $high && defined $low && defined $close;

    my $tr;
    if ( defined $self->{_last_close} ) {
        my $prev_close = $self->{_last_close};
        my $hl         = $high - $low;
        my $hpc        = abs( $high - $prev_close );
        my $lpc        = abs( $low - $prev_close );
        $tr = $hl;
        $tr = $hpc if $hpc > $tr;
        $tr = $lpc if $lpc > $tr;
    }
    else {
        $tr = $high - $low;
    }

    $self->{_count}++;
    my $period = $self->{period};

    if ( $self->{_count} < $period ) {
        $self->{_tr_sum} += $tr;
        push @{ $self->{values} }, undef;
    }
    elsif ( $self->{_count} == $period ) {
        $self->{_tr_sum} += $tr;
        my $atr = $self->{_tr_sum} / $period;
        $self->{_last_atr} = $atr;
        push @{ $self->{values} }, $atr;
    }
    else {
        my $atr = ( $self->{_last_atr} * ( $period - 1 ) + $tr ) / $period;
        $self->{_last_atr} = $atr;
        push @{ $self->{values} }, $atr;
    }

    $self->{_last_close} = $close;
    return $self;
}

sub get_values {
    my ($self) = @_;
    return $self->{values};
}

# export_state / import_state — cache por temporalidad (switch TF O(1) si hay hit).
sub export_state {
    my ($self) = @_;
    return {
        period      => $self->{period},
        values      => [ @{ $self->{values} || [] } ],
        _tr_sum     => $self->{_tr_sum},
        _last_close => $self->{_last_close},
        _last_atr   => $self->{_last_atr},
        _count      => $self->{_count},
    };
}

sub import_state {
    my ( $self, $st ) = @_;
    return $self unless $st && ref($st) eq 'HASH';
    if ( defined $st->{period} && $st->{period} != $self->{period} ) {
        return $self;
    }
    $self->{values}      = [ @{ $st->{values} || [] } ];
    $self->{_tr_sum}     = $st->{_tr_sum} // 0;
    $self->{_last_close} = $st->{_last_close};
    $self->{_last_atr}   = $st->{_last_atr};
    $self->{_count}      = $st->{_count} // 0;
    return $self;
}

sub reset {
    my ($self) = @_;
    # Reinicia el estado incremental.
    $self->{values}      = [];
    $self->{_tr_sum}     = 0;
    $self->{_last_close} = undef;
    $self->{_last_atr}   = undef;
    $self->{_count}      = 0;
    return;
}

1;
