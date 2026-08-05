package Market::ReplayController;
use strict;
use warnings;

# Market::ReplayController control del índice tope de Replay.

# Tabla de velocidades TradingView: etiqueta → ms por tick de autoplay.
my @SPEED_OPTIONS = (
    { label => '10x',  ms => 100 },
    { label => '7x',   ms => 143 },
    { label => '5x',   ms => 200 },
    { label => '3x',   ms => 333 },
    { label => '1x',   ms => 1000 },
    { label => '0.5x', ms => 2000 },
    { label => '0.3x', ms => 3000 },
    { label => '0.2x', ms => 5000 },
    { label => '0.1x', ms => 10000 },
);

my %SPEED_MS = map { $_->{label} => $_->{ms} } @SPEED_OPTIONS;

sub new {
    my ($class, %args) = @_;
    my $self = {
        market_data     => $args{market_data},
        active          => 0,
        replay_idx      => undef,
        # Instante causal exacto en coordenadas de la serie base (fuente de
        replay_base_idx => undef,
        head_partial    => 0,
        playing         => 0,
        speed           => $args{speed} || 1,
        speed_label     => '1x',
        replay_interval => 1,
        auto_replay_interval => 1,
        interval_label  => '1 hour',
        _timer_id       => undef,
        _timer_cb       => undef,
    };
    bless $self, $class;
    return $self;
}

# _bi_capable el MarketData soporta el índice compartido base_index.
sub _bi_capable {
    my ($self) = @_;
    my $md = $self->{market_data};
    return ($md && $md->can('base_index_at') && $md->can('index_of_bucket_containing')) ? 1 : 0;
}

# _bi_mode operando con instante exacto en coordenadas base.
sub _bi_mode {
    my ($self) = @_;
    return ($self->_bi_capable() && defined $self->{replay_base_idx}) ? 1 : 0;
}

# _sync_from_base deriva replay_idx (bucket contenedor del instante) y
sub _sync_from_base {
    my ($self) = @_;
    my $md = $self->{market_data};
    my $bi = $self->{replay_base_idx};
    my $last = $self->_last_index();
    if (!defined $last || $last < 0) {
        $self->{replay_idx} = 0;
        $self->{head_partial} = 0;
        return $self->{replay_idx};
    }
    my $idx = $md->index_of_bucket_containing($md->{active_tf}, $bi);
    $idx = 0 if $idx < 0;
    $idx = $last if $idx > $last;
    $self->{replay_idx} = $idx;
    my $close = $md->base_index_at($md->{active_tf}, $idx);
    $self->{head_partial} = (defined $close && defined $bi && $close == $bi) ? 0 : 1;
    return $idx;
}

# start($idx) activa Replay con tope en $idx (clamp a [0, last_index]).
sub start {
    my ($self, $idx) = @_;
    my $last = $self->_last_index();
    $idx = 0 if !defined $idx || $idx < 0;
    $idx = $last if defined $last && $idx > $last;
    $self->{active} = 1;
    $self->{playing} = 0;
    $self->{head_partial} = 0;
    if ($self->_bi_capable()) {
        my $md = $self->{market_data};
        $self->{replay_base_idx} = $md->base_index_at($md->{active_tf}, $idx);
        $self->_sync_from_base();
    }
    else {
        $self->{replay_base_idx} = undef;
        $self->{replay_idx} = $idx;
    }
    return $self;
}

# play inicia reproducción automática via after($ms, $cb).
sub play {
    my ($self, $cb) = @_;
    return unless $self->{active};
    $self->{playing} = 1;
    $self->{_timer_cb} = $cb if defined $cb;
    $self->_schedule_timer();
    return $self;
}

# pause detiene la reproducción automática.
sub pause {
    my ($self) = @_;
    $self->{playing} = 0;
    $self->_cancel_timer();
    return $self;
}

# step_forward avanza al siguiente cierre de bucket (en modo base_index: si
sub step_forward {
    my ($self) = @_;
    return unless $self->{active};
    if ($self->_bi_mode()) {
        my $md = $self->{market_data};
        my $tf = $md->{active_tf};
        my $close_cur = $md->base_index_at($tf, $self->{replay_idx});
        my $next_close;
        if (defined $close_cur && $close_cur > $self->{replay_base_idx}) {
            $next_close = $close_cur;   # completar el bucket en formación
        }
        else {
            my $ni = $self->{replay_idx} + 1;
            my $last = $self->_last_index();
            $ni = $last if defined $last && $ni > $last;
            $next_close = $md->base_index_at($tf, $ni);
        }
        $self->{replay_base_idx} = $next_close if defined $next_close;
        $self->_sync_from_base();
        my $max_bi = $md->can('base_last_index') ? $md->base_last_index() : undef;
        $self->pause() if defined $max_bi && defined $self->{replay_base_idx}
            && $self->{replay_base_idx} >= $max_bi;
        return $self->{replay_idx};
    }
    my $last = $self->_last_index();
    $self->{replay_idx}++ if defined $self->{replay_idx};
    $self->{replay_idx} = $last if defined $last && $self->{replay_idx} > $last;
    # Si Play llega al último índice, detener el loop automático. Sin esto,
    $self->pause() if defined $self->{replay_idx} && defined $last && $self->{replay_idx} >= $last;
    return $self->{replay_idx};
}

# step_backward retrocede al cierre de bucket anterior al instante actual
sub step_backward {
    my ($self) = @_;
    return unless $self->{active};
    if ($self->_bi_mode()) {
        my $md = $self->{market_data};
        my $tf = $md->{active_tf};
        my $prev_close;
        for (my $i = $self->{replay_idx}; $i >= 0; $i--) {
            my $c = $md->base_index_at($tf, $i);
            next unless defined $c;
            if ($c < $self->{replay_base_idx}) { $prev_close = $c; last; }
        }
        $prev_close = 0 if !defined $prev_close;
        $self->{replay_base_idx} = $prev_close;
        $self->_sync_from_base();
        return $self->{replay_idx};
    }
    $self->{replay_idx}-- if defined $self->{replay_idx};
    $self->{replay_idx} = 0 if !defined $self->{replay_idx} || $self->{replay_idx} < 0;
    return $self->{replay_idx};
}

# fast_forward avanza N velas (default: 10 speed), clamp al último.
sub fast_forward {
    my ($self, $n) = @_;
    return unless $self->{active};
    $n //= 10 * ($self->{speed} || 1);
    if ($self->_bi_mode()) {
        my $md = $self->{market_data};
        my $last = $self->_last_index();
        my $target = ($self->{replay_idx} // 0) + $n;
        $target = $last if defined $last && $target > $last;
        $self->{replay_base_idx} = $md->base_index_at($md->{active_tf}, $target);
        $self->_sync_from_base();
        my $max_bi = $md->can('base_last_index') ? $md->base_last_index() : undef;
        $self->pause() if defined $max_bi && defined $self->{replay_base_idx}
            && $self->{replay_base_idx} >= $max_bi;
        return $self->{replay_idx};
    }
    my $last = $self->_last_index();
    $self->{replay_idx} += $n;
    $self->{replay_idx} = $last if defined $last && $self->{replay_idx} > $last;
    $self->pause() if defined $self->{replay_idx} && defined $last && $self->{replay_idx} >= $last;
    return $self->{replay_idx};
}

# jump_to_end revela hasta la ultima vela (tope último instante base) y pausa autoplay.
sub jump_to_end {
    my ($self) = @_;
    return unless $self->{active};
    $self->pause();
    if ($self->_bi_mode()) {
        my $md = $self->{market_data};
        $self->{replay_base_idx} = $md->base_last_index();
        $self->_sync_from_base();
        return $self->{replay_idx};
    }
    my $last = $self->_last_index();
    $self->{replay_idx} = $last if defined $last;
    return $self->{replay_idx};
}

# exit desactiva Replay y restaura tope last_index.
sub exit {
    my ($self) = @_;
    $self->pause();
    $self->{active} = 0;
    $self->{replay_idx} = undef;
    $self->{replay_base_idx} = undef;
    $self->{head_partial} = 0;
    return $self;
}

# current_index retorna replay_idx o undef si no activo.
sub current_index {
    my ($self) = @_;
    return $self->{active} ? $self->{replay_idx} : undef;
}

# current_base_index instante causal exacto en coordenadas de la serie base
sub current_base_index {
    my ($self) = @_;
    return undef unless $self->{active};
    return $self->{replay_base_idx} if defined $self->{replay_base_idx};
    my $md = $self->{market_data};
    return undef unless $md && $md->can('base_index_at') && defined $self->{replay_idx};
    return $md->base_index_at($md->{active_tf}, $self->{replay_idx});
}

# seek_base_index($bi) fija el instante causal exacto y lo remapea al TF
sub seek_base_index {
    my ($self, $bi) = @_;
    return undef unless $self->{active} && defined $bi;
    return undef unless $self->_bi_capable();
    my $md  = $self->{market_data};
    my $max = $md->can('base_last_index') ? $md->base_last_index() : undef;
    $bi = $max if defined $max && $bi > $max;
    $bi = 0 if $bi < 0;
    $self->{replay_base_idx} = $bi;
    return $self->_sync_from_base();
}

# head_is_partial 1 si el head cae dentro de un bucket aún abierto (vela en
sub head_is_partial {
    my ($self) = @_;
    return ($self->{active} && $self->{head_partial}) ? 1 : 0;
}

# closed_index índice de la última vela CERRADA permitida para feeds de
sub closed_index {
    my ($self) = @_;
    return undef unless $self->{active} && defined $self->{replay_idx};
    return $self->{head_partial} ? $self->{replay_idx} - 1 : $self->{replay_idx};
}

# is_active bool.
sub is_active {
    my ($self) = @_;
    return $self->{active} ? 1 : 0;
}

# effective_end($last_index) retorna el índice efectivo superior para
sub effective_end {
    my ($self, $last_index) = @_;
    return $last_index unless $self->{active} && defined $self->{replay_idx};
    my $end = $self->{replay_idx};
    $end = $last_index if defined $last_index && $end > $last_index;
    return $end;
}

# set_speed($n) cambia la velocidad de fast_forward (retrocompat; no afecta tick_ms).
sub set_speed {
    my ($self, $n) = @_;
    $self->{speed} = $n if defined $n && $n > 0;
    return $self;
}

# speed_options lista ordenada {label, ms} para los 9 multiplicadores TV.
sub speed_options {
    return map { +{ label => $_->{label}, ms => $_->{ms} } } @SPEED_OPTIONS;
}

# set_speed_label($label) selecciona velocidad de autoplay por etiqueta (p.ej. '5x').
sub set_speed_label {
    my ($self, $label) = @_;
    if (defined $label && exists $SPEED_MS{$label}) {
        $self->{speed_label} = $label;
    }
    return $self;
}

# tick_ms periodo del tick de autoplay según la velocidad seleccionada.
sub tick_ms {
    my ($self) = @_;
    my $label = $self->{speed_label} // '1x';
    return $SPEED_MS{$label} // 1000;
}

# replay_interval nº de velas avanzadas por tick de autoplay.
sub replay_interval {
    my ($self) = @_;
    return $self->{replay_interval} // 1;
}

# set_replay_interval($n) cuántas velas añade cada tick (default 1).
sub set_replay_interval {
    my ($self, $n) = @_;
    $self->{replay_interval} = $n if defined $n && $n > 0;
    return $self;
}

# auto_replay_interval 1 intervalo sigue al TF; 0 manual.
sub auto_replay_interval {
    my ($self) = @_;
    return $self->{auto_replay_interval} // 1;
}

sub set_auto_replay_interval {
    my ($self, $on) = @_;
    $self->{auto_replay_interval} = $on ? 1 : 0;
    return $self;
}

sub interval_label {
    my ($self) = @_;
    return $self->{interval_label};
}

sub set_interval_label {
    my ($self, $label) = @_;
    $self->{interval_label} = $label if defined $label;
    return $self;
}

# advance_one_tick avanza replay_interval pasos de step_forward (clamp + pause al final).
sub advance_one_tick {
    my ($self) = @_;
    return unless $self->{active};
    my $interval = $self->replay_interval();
    my $last = $self->_last_index();
    my $idx;
    for (my $i = 0; $i < $interval; $i++) {
        $idx = $self->step_forward();
        last if defined $last && defined $idx && $idx >= $last;
    }
    return $idx;
}

# internals

sub _last_index {
    my ($self) = @_;
    return undef unless $self->{market_data};
    my $size = $self->{market_data}->size();
    return $size > 0 ? $size - 1 : 0;
}

sub _schedule_timer {
    my ($self) = @_;
    return unless $self->{playing} && $self->{_timer_cb};
    my $canvas = $self->{market_data};  # placeholder; el timer real se cablea en 0004
    # El temporizador Tk se cablea en con after().
}

sub _cancel_timer {
    my ($self) = @_;
    $self->{_timer_id} = undef;
}

1;
