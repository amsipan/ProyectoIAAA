package Market::MarketData;
use strict;
use warnings;
use Time::Moment;

# Resolución relativa de TFs (más bajo más fino).
my %TF_RANK = (
    '1m'  => 1,
    '5m'  => 5,
    '10m' => 10,
    '15m' => 15,
    '1h'  => 60,
    '2h'  => 120,
    '4h'  => 240,
    'D'   => 1440,
    'W'   => 10080,
);

sub new {
    my ($class) = @_;
    my $self = {
        data      => {
            '1m'  => [], '5m' => [], '10m' => [], '15m' => [],
            '1h'  => [], '2h' => [], '4h'  => [], 'D'   => [], 'W' => [],
        },
        active_tf => '1m',
        # Serie nativa cargada desde CSV (1m por defecto; 15m si export TV 15m).
        base_tf   => '1m',
        # TFs ya agregados. Con add_candle incremental, los HTF se llenan al cargar.
        _tf_built => { '1m' => 1 },
        # Cache Time::Moment por string de timestamp (evita re parse en agregación).
        _tm_cache => {},
    };
    bless $self, $class;
    return $self;
}

sub base_timeframe {
    my ($self) = @_;
    return $self->{base_tf} // '1m';
}

# set_base_timeframe($tf) define la serie nativa (p.ej. '1m' o '15m').
sub set_base_timeframe {
    my ($self, $tf) = @_;
    return unless defined $tf && exists $self->{data}{$tf};
    $self->{base_tf}   = $tf;
    $self->{active_tf} = $tf;
    for my $k (keys %{ $self->{data} }) {
        $self->{data}{$k} = [];
    }
    $self->{_tf_built} = { $tf => 1 };
    $self->{_tm_cache} = {};
    return $self;
}

sub _tf_rank {
    my ($self, $tf) = @_;
    return $TF_RANK{$tf} if defined $tf && exists $TF_RANK{$tf};
    return int($tf) if defined $tf && $tf =~ /^\d+$/;
    return 0;
}

sub get_data {
    my ($self) = @_;
    return $self->_active_array();
}

# TFs agregables desde la base (orden fijo; O(1) por vela).
sub _aggregate_tf_names {
    return qw(5m 10m 15m 1h 2h 4h D W);
}

# add_candle: push base O(1) + actualizar HTF abiertos O(1) por TF fijo.
sub add_candle {
    my ( $self, $candle ) = @_;
    return undef unless $candle && ref($candle) eq 'ARRAY';

    my $base = $self->base_timeframe();
    my $arr  = $self->{data}{$base} ||= [];
    push @$arr, $candle;
    my $base_index = $#$arr;
    $arr->[$base_index][6] = $base_index;

    $self->_update_higher_tfs( $arr->[$base_index], $base_index );

    if ( $self->{_tm_cache} && keys %{ $self->{_tm_cache} } > 200_000 ) {
        $self->{_tm_cache} = {};
    }
    return $base_index;
}

# Actualiza todos los TF de rango mayor que la base (patrón del profesor).
sub _update_higher_tfs {
    my ( $self, $candle, $base_index ) = @_;
    my $base      = $self->base_timeframe();
    my $rank_base = $self->_tf_rank($base);

    for my $tf ( $self->_aggregate_tf_names() ) {
        next unless exists $self->{data}{$tf};
        my $rank_tf = $self->_tf_rank($tf);
        next if $rank_tf > 0 && $rank_base > 0 && $rank_tf < $rank_base;
        $self->_update_tf_incremental( $tf, $candle, $base_index );
        $self->{_tf_built}{$tf} = 1;
    }
    return $self;
}

# Un tick de la base → bucket HTF: nuevo push o merge in place + base_index.
sub _update_tf_incremental {
    my ( $self, $tf, $candle, $base_index ) = @_;
    my $arr = $self->{data}{$tf} ||= [];
    my $bucket = $self->_bucket_timestamp( $candle->[0], $tf );
    return unless defined $bucket;

    if ( !@$arr || ( $arr->[-1][0] // '' ) ne $bucket ) {
        push @$arr, [
            $bucket,
            $candle->[1],
            $candle->[2],
            $candle->[3],
            $candle->[4],
            $candle->[5] // 0,
            $base_index,
        ];
        return;
    }

    my $c = $arr->[-1];
    $c->[2] = $candle->[2] if $candle->[2] > $c->[2];
    $c->[3] = $candle->[3] if $candle->[3] < $c->[3];
    $c->[4] = $candle->[4];
    $c->[5] = ( $c->[5] // 0 ) + ( $candle->[5] // 0 );
    $c->[6] = $base_index;
    return;
}

# Parche HTF cuando la última vela base se actualiza in place (merge_delta_row).
sub _patch_open_htf_from_base {
    my ( $self, $base_candle, $base_index, $vol_delta ) = @_;
    my $base      = $self->base_timeframe();
    my $rank_base = $self->_tf_rank($base);
    $vol_delta = 0 unless defined $vol_delta;

    for my $tf ( $self->_aggregate_tf_names() ) {
        next unless exists $self->{data}{$tf};
        my $rank_tf = $self->_tf_rank($tf);
        next if $rank_tf > 0 && $rank_base > 0 && $rank_tf < $rank_base;

        my $arr = $self->{data}{$tf} ||= [];
        my $bucket = $self->_bucket_timestamp( $base_candle->[0], $tf );
        next unless defined $bucket;

        if ( !@$arr || ( $arr->[-1][0] // '' ) ne $bucket ) {
            push @$arr, [
                $bucket,
                $base_candle->[1],
                $base_candle->[2],
                $base_candle->[3],
                $base_candle->[4],
                $vol_delta,
                $base_index,
            ];
        }
        else {
            my $c = $arr->[-1];
            $c->[2] = $base_candle->[2] if $base_candle->[2] > $c->[2];
            $c->[3] = $base_candle->[3] if $base_candle->[3] < $c->[3];
            $c->[4] = $base_candle->[4];
            $c->[5] = ( $c->[5] // 0 ) + $vol_delta;
            $c->[6] = $base_index;
        }
        $self->{_tf_built}{$tf} = 1;
    }
    return $self;
}

sub build_tf_candles {
    my ($self, $tf) = @_;
    return unless defined $tf;
    my $base = $self->base_timeframe();
    return if $tf eq $base;

    # No se puede construir un TF más fino que la base (p.ej. 1m/5m con base 15m).
    my $rank_tf   = $self->_tf_rank($tf);
    my $rank_base = $self->_tf_rank($base);
    if ($rank_tf > 0 && $rank_base > 0 && $rank_tf < $rank_base) {
        $self->{data}{$tf} = [] if exists $self->{data}{$tf};
        $self->{_tf_built}{$tf} = 1;
        return;
    }

    # Idempotente: no reconstruir si ya está (lazy multi llamada OK).
    if ($self->{_tf_built}{$tf} && @{ $self->{data}{$tf} || [] }) {
        return;
    }
    my $base_data = $self->{data}->{$base};
    return unless $base_data && @$base_data;

    my @aggregated;
    my ($current_key, $current);

    for my $i ( 0 .. $#$base_data ) {
        my $c = $base_data->[$i];
        my $bucket_ts = $self->_bucket_timestamp($c->[0], $tf);
        next unless defined $bucket_ts;

        if (!defined $current_key || $bucket_ts ne $current_key) {
            push @aggregated, $current if defined $current;
            $current_key = $bucket_ts;
            $current = [$bucket_ts, $c->[1], $c->[2], $c->[3], $c->[4], $c->[5] // 0, $i];
            next;
        }

        $current->[2] = $c->[2] if $c->[2] > $current->[2];
        $current->[3] = $c->[3] if $c->[3] < $current->[3];
        $current->[4] = $c->[4];
        $current->[5] = ($current->[5] // 0) + ($c->[5] // 0);
        $current->[6] = $i;
    }

    push @aggregated, $current if defined $current;
    $self->{data}->{$tf} = \@aggregated;
    $self->{_tf_built}{$tf} = 1;
}

# _bucket_timestamp($ts, $tf) frontera de reloj/sesión para el TF dado.
sub _parse_tm_cached {
    my ($self, $ts) = @_;
    return undef unless defined $ts;
    my $cache = $self->{_tm_cache} ||= {};
    return $cache->{$ts} if exists $cache->{$ts};
    my $tm = eval { Time::Moment->from_string($ts) };
    $cache->{$ts} = $tm;  # puede ser undef si falla
    return $tm;
}

sub _bucket_timestamp {
    my ($self, $ts, $tf) = @_;
    return undef unless defined $ts;

    if (!defined $tf || $tf eq '1m') {
        return $ts;
    }

    my $suffix = $self->_timestamp_suffix($ts);

    # 5m/15m: solo regex, sin Time::Moment (antes se parseaba y se descartaba).
    my $minutes;
    if ($tf eq '5m') {
        $minutes = 5;
    } elsif ($tf eq '10m') {
        $minutes = 10;
    } elsif ($tf eq '15m') {
        $minutes = 15;
    } elsif ($tf eq '1h') {
        $minutes = 60;
    } elsif ($tf eq '2h') {
        $minutes = 120;
    } elsif ($tf eq '4h') {
        $minutes = 240;
    } elsif ($tf =~ /^(\d+)$/) {
        $minutes = int($1);
    } elsif ($tf eq 'D' || $tf eq 'W') {
        $minutes = undef;
    } else {
        return $ts;
    }

    if (defined $minutes && $minutes > 1 && $minutes < 60) {
        if ($ts =~ /^(\d{4}-\d{2}-\d{2}T\d{2}):(\d{2}):(\d{2})(.*)$/) {
            my ($prefix, $minute, $second, $sfx) = ($1, $2, $3, $4);
            my $bucket_minute = int($minute / $minutes) * $minutes;
            return sprintf('%s:%02d:00%s', $prefix, $bucket_minute, $sfx);
        }
        return $ts;
    }

    # D/W y > 1h necesitan Time::Moment (cacheado).
    my $tm = $self->_parse_tm_cached($ts);

    if ($tf eq 'D') {
        return $ts unless $tm && defined $suffix;
        my $trading_day = $self->_trading_day_tm($tm);
        return $self->_format_bucket_timestamp($trading_day, 0, 0, $suffix);
    }
    if ($tf eq 'W') {
        return $ts unless $tm && defined $suffix;
        my $trading_day = $self->_trading_day_tm($tm);
        my $dow = $trading_day->day_of_week;  # 1 Lun.. 7 Dom
        my $monday = $trading_day->minus_days($dow - 1);
        return $self->_format_bucket_timestamp($monday, 0, 0, $suffix);
    }

    return $ts if !defined $minutes || $minutes <= 1;

    # Para > 60 min, anclar al inicio de sesión CME (17:00 local).
    if ($minutes >= 60) {
        return $self->_session_bucket_timestamp($tm, $minutes, $suffix) if $tm && defined $suffix;

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

    return $ts;
}

sub _timestamp_suffix {
    my ($self, $ts) = @_;
    return $1 if defined $ts && $ts =~ /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(.*)$/;
    return undef;
}

sub _format_bucket_timestamp {
    my ($self, $date_tm, $hour, $minute, $suffix) = @_;
    $hour   //= 0;
    $minute //= 0;
    $suffix //= '';
    return sprintf('%04d-%02d-%02dT%02d:%02d:00%s',
        $date_tm->year, $date_tm->month, $date_tm->day_of_month,
        $hour, $minute, $suffix);
}

sub _trading_day_tm {
    my ($self, $tm) = @_;
    my $minute_of_day = $tm->hour * 60 + $tm->minute;
    return $minute_of_day >= 17 * 60 ? $tm->plus_days(1) : $tm;
}

sub _session_bucket_timestamp {
    my ($self, $tm, $minutes, $suffix) = @_;

    my $session_start_minute = 17 * 60;
    my $minute_of_day = $tm->hour * 60 + $tm->minute;

    # Fecha calendario donde empezó la sesión activa.
    my $session_date = $minute_of_day >= $session_start_minute ? $tm : $tm->minus_days(1);

    # Minutos transcurridos desde 17:00 local. Rango lógico [0, 1439].
    my $elapsed = $minute_of_day >= $session_start_minute
        ? $minute_of_day - $session_start_minute
        : $minute_of_day + (24 * 60 - $session_start_minute);

    my $bucket_elapsed = int($elapsed / $minutes) * $minutes;

    my ($bucket_date, $bucket_minute_of_day);
    if ($bucket_elapsed < (24 * 60 - $session_start_minute)) {
        $bucket_date = $session_date;
        $bucket_minute_of_day = $session_start_minute + $bucket_elapsed;
    } else {
        $bucket_date = $session_date->plus_days(1);
        $bucket_minute_of_day = $bucket_elapsed - (24 * 60 - $session_start_minute);
    }

    my $bucket_hour = int($bucket_minute_of_day / 60);
    my $bucket_min  = $bucket_minute_of_day % 60;
    return $self->_format_bucket_timestamp($bucket_date, $bucket_hour, $bucket_min, $suffix);
}

# build_timeframes incremental ya llena HTF en add_candle.
sub build_timeframes {
    my ($self, %opts) = @_;
    if ($opts{eager}) {
        my $base = $self->base_timeframe();
        for my $tf ( '1m', $self->_aggregate_tf_names() ) {
            next if $tf eq $base;
            next unless exists $self->{data}{$tf};
            if ( $self->{_tf_built}{$tf} && @{ $self->{data}{$tf} || [] } ) {
                next;
            }
            $self->build_tf_candles($tf);
        }
    }
    return $self;
}

# ensure_timeframe($tf) garantiza que el TF está agregado antes de usarlo.
sub ensure_timeframe {
    my ($self, $tf) = @_;
    return unless defined $tf;
    my $base = $self->base_timeframe();
    return if $tf eq $base;
    $self->build_tf_candles($tf) if exists $self->{data}{$tf} || $tf =~ /^(?:5m|10m|15m|1h|2h|4h|D|W|\d+)$/;
    return $self;
}

# set_timeframe O(1) si el TF ya está precargado; fallback rebuild si falta.
sub set_timeframe {
    my ($self, $tf) = @_;
    return unless defined $tf;
    return unless exists $self->{data}->{$tf};

    my $base = $self->base_timeframe();
    if ( $tf ne $base
        && ( !$self->{_tf_built}{$tf} || !@{ $self->{data}{$tf} || [] } ) )
    {
        $self->ensure_timeframe($tf);
    }
    $self->{active_tf} = $tf;
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

# base_index_at($tf, $idx) base_index (campo [6]) de la vela $idx en la serie
sub base_index_at {
    my ($self, $tf, $idx) = @_;
    my $arr = (defined $tf) ? $self->{data}{$tf} : undef;
    return undef unless $arr && defined $idx && $idx >= 0 && $idx <= $#$arr;
    my $bi = $arr->[$idx][6];
    $bi = $idx if !defined $bi && $tf eq $self->base_timeframe();
    return $bi;
}

# index_for_base_index($tf, $bi) mayor índice de la serie $tf cuya vela está
sub index_for_base_index {
    my ($self, $tf, $bi) = @_;
    return -1 unless defined $tf && defined $bi;
    my $arr = $self->{data}{$tf} or return -1;
    my $base = $self->base_timeframe();
    my ($lo, $hi, $best) = (0, $#$arr, -1);
    while ($lo <= $hi) {
        my $mid = ($lo + $hi) >> 1;
        my $v = $arr->[$mid][6];
        $v = $mid if !defined $v && $tf eq $base;
        if (defined $v && $v <= $bi) { $best = $mid; $lo = $mid + 1; }
        else                         { $hi = $mid - 1; }
    }
    return $best;
}

# base_last_index último índice de la serie nativa (tope del tiempo base).
sub base_last_index {
    my ($self) = @_;
    my $arr = $self->{data}{ $self->base_timeframe() } || [];
    return $#$arr;
}

# index_of_bucket_containing($tf, $bi) primer índice de la serie $tf cuya
sub index_of_bucket_containing {
    my ($self, $tf, $bi) = @_;
    return -1 unless defined $tf && defined $bi;
    my $arr = $self->{data}{$tf} or return -1;
    my $base = $self->base_timeframe();
    my ($lo, $hi, $best) = (0, $#$arr, -1);
    while ($lo <= $hi) {
        my $mid = ($lo + $hi) >> 1;
        my $v = $arr->[$mid][6];
        $v = $mid if !defined $v && $tf eq $base;
        if (defined $v && $v >= $bi) { $best = $mid; $hi = $mid - 1; }
        else                         { $lo = $mid + 1; }
    }
    return $best;
}

# partial_candle($tf, $idx, $bi) vela del bucket $idx agregada SOLO hasta el
sub partial_candle {
    my ($self, $tf, $idx, $bi) = @_;
    return undef unless defined $tf && defined $idx && defined $bi;
    my $arr  = $self->{data}{$tf} or return undef;
    my $base = $self->base_timeframe();
    my $barr = $self->{data}{$base} or return undef;
    return undef if $idx < 0 || $idx > $#$arr;

    my $close = $self->base_index_at($tf, $idx);
    return $arr->[$idx] if defined $close && $close <= $bi;

    my $from = ($idx > 0) ? ($self->base_index_at($tf, $idx - 1) // -1) + 1 : 0;
    my $to   = $bi;
    $to = $#$barr if $to > $#$barr;
    return undef if $to < $from;

    my ($o, $h, $l, $c, $v);
    for my $i ($from .. $to) {
        my $bc = $barr->[$i] or next;
        $o = $bc->[1] if !defined $o;
        $h = $bc->[2] if !defined $h || $bc->[2] > $h;
        $l = $bc->[3] if !defined $l || $bc->[3] < $l;
        $c = $bc->[4];
        $v += $bc->[5] // 0;
    }
    return undef unless defined $o;
    return [ $arr->[$idx][0], $o, $h, $l, $c, $v // 0, $bi ];
}

sub merge_delta_row {
    my ($self, $row) = @_;
    my $base = $self->base_timeframe();
    my $arr  = $self->{data}->{$base};

    if (@$arr && $arr->[-1]->[0] eq $row->[0]) {
        my $last       = $arr->[-1];
        my $base_index = $#$arr;
        my $vol_delta  = $row->[5] // 0;
        $last->[2] = $row->[2] if $row->[2] > $last->[2];
        $last->[3] = $row->[3] if $row->[3] < $last->[3];
        $last->[4] = $row->[4];
        $last->[5] = ( $last->[5] // 0 ) + $vol_delta;
        $last->[6] = $base_index;
        $self->_patch_open_htf_from_base( $last, $base_index, $vol_delta );
    }
    else {
        $self->add_candle($row);
    }
}

# compute_time_anchors puntos clave de tiempo para el eje/etiquetas (capa de datos).
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