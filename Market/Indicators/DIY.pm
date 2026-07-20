package Market::Indicators::DIY;
use strict;
use warnings;
use List::Util qw(max min);

# DIY Custom Strategy Builder [ZP] - v1 (Supply/Demand Zone sub-indicator)
# 
# Algoritmo de cálculo de zonas de oferta (Supply) y demanda (Demand):
#   - Detección de pivotes Swing High/Low con longitud configurable k (default 10).
#   - Cálculo incremental de ATR(50) de forma causal.
#   - Cajas de oferta: top = Swing High, bottom = top - atr_buffer (width 2.5 * ATR / 10).
#   - Cajas de demanda: bottom = Swing Low, top = bottom + atr_buffer.
#   - Regla de no superposición: POI a más de 2 * ATR de cualquier zona activa existente.
#   - Mitigación por cierre: close >= top (Supply) o close <= bottom (Demand) rompe la zona.
#   - Zonas mitigadas (BOS) se conservan para dibujo lineal histórico (límite de 5).
#   - Implementación como cola de tamaño fijo (sliding window) para active_supply y active_demand.
#
# Métodos del contrato:
#   new(%args)
#   reset()
#   update_last($market_data, $index)
#   get_values()
#   compute($market_data, %opts)

sub new {
    my ($class, %args) = @_;
    my $self = {
        swing_length       => $args{swing_length} // 10,
        history_to_keep    => $args{history_to_keep} // 20,
        bos_history_limit  => $args{bos_history_limit} // 20,
        box_width          => $args{box_width} // 2.5,
        atr_length         => $args{atr_length} // 50,
        # Historial de series
        _tr_history        => [],
        _atr_history       => [],
        _high_history      => [],
        _low_history       => [],
        _close_history     => [],
        # Colas de tamaño fijo (sliding windows)
        _supply_queue      => [],
        _demand_queue      => [],
        _broken_supply     => [],
        _broken_demand     => [],
    };
    bless $self, $class;
    return $self;
}

sub reset {
    my ($self) = @_;
    $self->{_tr_history}    = [];
    $self->{_atr_history}   = [];
    $self->{_high_history}  = [];
    $self->{_low_history}   = [];
    $self->{_close_history} = [];
    $self->{_supply_queue}  = [];
    $self->{_demand_queue}  = [];
    $self->{_broken_supply} = [];
    $self->{_broken_demand} = [];
    return $self;
}

sub get_values {
    my ($self) = @_;
    my @active_supply = grep { defined $_ && !$_->{broken} } @{ $self->{_supply_queue} };
    my @active_demand = grep { defined $_ && !$_->{broken} } @{ $self->{_demand_queue} };
    return {
        active_supply => [ map { { %$_ } } @active_supply ],
        active_demand => [ map { { %$_ } } @active_demand ],
        broken_supply => [ map { { %$_ } } @{ $self->{_broken_supply} } ],
        broken_demand => [ map { { %$_ } } @{ $self->{_broken_demand} } ],
    };
}

sub update_last {
    my ($self, $market_data, $index) = @_;
    return unless $market_data && defined $index;

    my $candle = $market_data->get_candle($index);
    return unless $candle;
    my ($ts, $open, $high, $low, $close) = @$candle[0 .. 4];

    # 1. Guardar historial
    $self->{_high_history}->[$index]  = $high;
    $self->{_low_history}->[$index]   = $low;
    $self->{_close_history}->[$index] = $close;

    # 2. Calcular ATR(50) incrementalmente usando RMA (Wilders)
    my $tr = $high - $low;
    if ($index > 0) {
        my $prev_close = $self->{_close_history}->[$index - 1];
        my $d1 = abs($high - $prev_close);
        my $d2 = abs($low - $prev_close);
        $tr = $d1 if $d1 > $tr;
        $tr = $d2 if $d2 > $tr;
    }
    $self->{_tr_history}->[$index] = $tr;

    my $atr_len = $self->{atr_length};
    my $atr = $tr;
    if ($index == $atr_len - 1) {
        my $sum = 0;
        $sum += $_ for @{ $self->{_tr_history} }[0 .. $atr_len - 1];
        $atr = $sum / $atr_len;
    }
    elsif ($index >= $atr_len) {
        my $prev_atr = $self->{_atr_history}->[$index - 1];
        $atr = ($tr + ($atr_len - 1) * $prev_atr) / $atr_len;
    }
    else {
        my $sum = 0;
        $sum += $_ for @{ $self->{_tr_history} }[0 .. $index];
        $atr = $sum / ($index + 1);
    }
    $self->{_atr_history}->[$index] = $atr;

    # 3. Mitigación/Ruptura de zonas activas (BOS)
    $self->_check_mitigations($close, $index);

    # 4. Detección de Pivotes a la distancia swing_length
    my $k = $self->{swing_length};
    my $p = $index - $k; # Candidato a pivote
    if ($p >= $k) {
        $self->_detect_and_create_zones($market_data, $index, $p, $k, $atr);
    }

    # 5. Extender zonas activas al índice actual
    for my $box (@{ $self->{_supply_queue} }, @{ $self->{_demand_queue} }) {
        next unless $box && !$box->{broken};
        $box->{right} = $index;
    }

    return $self;
}

# _check_mitigations: evalúa si el precio de cierre rompe zonas activas
sub _check_mitigations {
    my ($self, $close, $index) = @_;

    # Evaluar Supply
    for my $box (@{ $self->{_supply_queue} }) {
        next unless $box && !$box->{broken};
        if ($close >= $box->{top}) {
            # Se rompe (BOS)
            $box->{broken}    = 1;
            $box->{break_idx} = $index;
            $box->{right}     = $index;
            
            my $copied = { %$box };
            unshift @{ $self->{_broken_supply} }, $copied;
            # Mantener límite de historial de rotas
            if (@{ $self->{_broken_supply} } > $self->{bos_history_limit}) {
                pop @{ $self->{_broken_supply} };
            }
        }
    }

    # Evaluar Demand
    for my $box (@{ $self->{_demand_queue} }) {
        next unless $box && !$box->{broken};
        if ($close <= $box->{bottom}) {
            # Se rompe (BOS)
            $box->{broken}    = 1;
            $box->{break_idx} = $index;
            $box->{right}     = $index;
            
            my $copied = { %$box };
            unshift @{ $self->{_broken_demand} }, $copied;
            if (@{ $self->{_broken_demand} } > $self->{bos_history_limit}) {
                pop @{ $self->{_broken_demand} };
            }
        }
    }
}

# _detect_and_create_zones: valida pivotes y crea cajas correspondientes
sub _detect_and_create_zones {
    my ($self, $market_data, $index, $p, $k, $atr) = @_;

    my $highs = $self->{_high_history};
    my $lows  = $self->{_low_history};

    # Detección de Swing High
    my $is_sh   = 1;
    my $high_p  = $highs->[$p];
    for my $j ($index - 2 * $k .. $index) {
        next if $j == $p;
        if ($j < $p) {
            if ($highs->[$j] > $high_p) { $is_sh = 0; last; }
        }
        else {
            if ($highs->[$j] >= $high_p) { $is_sh = 0; last; }
        }
    }

    if ($is_sh) {
        my $atr_buffer = $atr * ($self->{box_width} / 10);
        my $box_top    = $high_p;
        my $box_bottom = $box_top - $atr_buffer;
        my $poi        = ($box_top + $box_bottom) / 2;

        if ($self->_check_overlapping($poi, $self->{_supply_queue}, $atr)) {
            my $new_box = {
                left      => $p,
                right     => $index,
                top       => $box_top,
                bottom    => $box_bottom,
                poi       => $poi,
                broken    => 0,
                break_idx => undef,
                type      => 'supply',
            };
            unshift @{ $self->{_supply_queue} }, $new_box;
            if (@{ $self->{_supply_queue} } > $self->{history_to_keep}) {
                pop @{ $self->{_supply_queue} };
            }
        }
    }

    # Detección de Swing Low
    my $is_sl  = 1;
    my $low_p  = $lows->[$p];
    for my $j ($index - 2 * $k .. $index) {
        next if $j == $p;
        if ($j < $p) {
            if ($lows->[$j] < $low_p) { $is_sl = 0; last; }
        }
        else {
            if ($lows->[$j] <= $low_p) { $is_sl = 0; last; }
        }
    }

    if ($is_sl) {
        my $atr_buffer = $atr * ($self->{box_width} / 10);
        my $box_bottom = $low_p;
        my $box_top    = $box_bottom + $atr_buffer;
        my $poi        = ($box_top + $box_bottom) / 2;

        if ($self->_check_overlapping($poi, $self->{_demand_queue}, $atr)) {
            my $new_box = {
                left      => $p,
                right     => $index,
                top       => $box_top,
                bottom    => $box_bottom,
                poi       => $poi,
                broken    => 0,
                break_idx => undef,
                type      => 'demand',
            };
            unshift @{ $self->{_demand_queue} }, $new_box;
            if (@{ $self->{_demand_queue} } > $self->{history_to_keep}) {
                pop @{ $self->{_demand_queue} };
            }
        }
    }
}

# _check_overlapping: retorna true si es seguro dibujar (no se superpone en 2 * ATR)
sub _check_overlapping {
    my ($self, $new_poi, $queue, $atr) = @_;
    my $threshold = $atr * 2;
    for my $box (@$queue) {
        next unless $box && !$box->{broken};
        if (abs($new_poi - $box->{poi}) <= $threshold) {
            return 0; # Superposición detectada
        }
    }
    return 1;
}

sub compute {
    my ($self, $market_data, %opts) = @_;
    return $self->get_values();
}

1;
