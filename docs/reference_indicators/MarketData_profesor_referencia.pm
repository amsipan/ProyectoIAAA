# Referencia del profesor (optimizacion TF / base_index). No es el runtime de la app.
# Runtime: Market/MarketData.pm
package Market::MarketDataProfesorReferencia;

use strict;
use warnings;
use Time::Moment;
use Exporter 'import';
use constant {
    TF_1M  => 60,
    TF_5M  => 300,
    TF_15M => 900,
};
our @EXPORT_OK = qw(TF_1M TF_5M TF_15M);

sub new {
    my ($class) = @_;

    my $self = {
        candles_0060 => [],
        candles_0300 => [],
        candles_0900 => [],

        closing_prices => [],
        volume_points  => [],
        delta_points   => [],
        poc_prices     => [],

        session_cvd => 0,
        volume_profile => {},

        pk_to_index => {},
        
        last_base_candle => undef,
        last_timestamp   => undef,

        # multiple timeframes
        tf_map => {
            TF_1M()  => 'candles_0060',
            TF_5M()  => 'candles_0300',
            TF_15M() => 'candles_0900',
        },
        
        active_tf => TF_1M(),
        
        # Escala horizontal de tiempo
        time_axis => {
            anchors        => [],   # fijos (data-driven)
            intraday       => [],   # dinámicos (zoom-driven)
            last_zoom      => undef,
            last_tf        => TF_1M(),
        },
    };
    
    return bless ($self, $class);
}


sub get_data {
    my ($self, $market_file_path, $indicators) = @_;

    die "Missing market_file_path\n" unless defined $market_file_path;
    die "market_file_path is not found.\n" unless -e $market_file_path;
    
    open my $fh, "<", $market_file_path or die $!;
    
    my $idx;
    while (<$fh>) {
        chomp;
        next if $. == 1; # skip header
    
        my @f = split /,/;
    
        # AJUSTA ESTO a tu formato real
        my $candle = [
            $f[0],  # time
            $f[1],  # open
            $f[2],  # high
            $f[3],  # low
            $f[4],  # close
            $f[5],  # vol
            $f[6],  # BV
            $f[7],  # SV
            $f[8],  # Delta
            $f[9],  # min_D
            $f[10], # max_D
            $f[11], # session_cvd
            $f[12], # POC
        ];
    
        $idx = $self->add_candle($candle);
        $indicators->update_last($self, $idx);  # ✔ en cada iteración
        
        # printf "%s\n", $idx if $idx % 20000 == 0;
        
        my $tm    = Time::Moment->from_string($f[0]);
        #last if $tm->year == 2026 && $tm->month == 5 && $tm->day_of_month == 1 && $tm->hour == 1 && $tm->minute == 40;
        #last if $tm->year == 2026 && $tm->month == 4 && $tm->day_of_month == 22 && $tm->hour == 00 && $tm->minute == 00;
    }
    close $fh;
    
    # 🔥 CLAVE: construir anchors UNA SOLA VEZ
    $self->{time_axis}{anchors} = $self->compute_time_anchors();
}

sub add_candle {
    my ($self, $candle) = @_;

    die "Invalid candle" unless ref $candle eq 'ARRAY' && scalar(@$candle) >= 13;

    my ($time, $open, $high, $low, $close, $vol,
        $BV, $SV, $Delta, $min_D, $max_D, $session_cvd, $POC) = @$candle;

    # -----------------------------
    # 1. INDEXING (CRÍTICO)
    # -----------------------------
    my $idx = @{$self->{candles_0060}};
    $self->{pk_to_index}{$time} = $idx;

    # -----------------------------
    # 2. STORE BASE CANDLE
    # -----------------------------
    push @{$self->{candles_0060}}, $candle;

    # -----------------------------
    # 3. DERIVED SERIES
    # -----------------------------
    push @{$self->{closing_prices}}, $close;
    push @{$self->{volume_points}},  $vol;
    push @{$self->{delta_points}},   $Delta;
    push @{$self->{poc_prices}},     $POC;

    # -----------------------------
    # 4. SESSION STATE
    # -----------------------------
    $self->{session_cvd} = $session_cvd if defined $session_cvd;

    if (defined $POC && defined $vol) {
        $self->{volume_profile}{$POC} += $vol;
    }

    # -----------------------------
    # 5. BUILD HIGHER TF (CRÍTICO)
    # -----------------------------
    $self->build_timeframes($candle, $idx);
    
    # al final de add_candle
    $self->{last_base_candle} = $candle;
    $self->{last_timestamp}   = $time;

    return $idx;
}

sub build_tf_candles {
    my ($self, $candles, $tick, $tf_seconds, $base_index) = @_;

  my ($time, $open, $high, $low, $close, $vol, $BV, $SV, $Delta, $min_D, $max_D, $session_cvd, $POC) = @$tick;
  
  my $epoch = Time::Moment->from_string($time)->epoch;
  my $slot  = int($epoch / $tf_seconds);
  my $next_slot = int(($epoch + 60) / $tf_seconds); # 60 is the current tick in seconds
  my $is_last_tick_of_slot = $next_slot != $slot;

  # first candle
  if (!@$candles) {
    push @$candles, [$time, $open, $high, $low, $close, $vol, $BV, $SV, $Delta, $min_D, $max_D, $session_cvd, $POC, $slot, ($POC // 0) * $vol];
    return;
  }

  my $c = $candles->[-1];

  # same timeframe bucket
  if ($c->[13] == $slot) {

      $c->[2]  = $high if $high > $c->[2];
      $c->[3]  = $low  if $low  < $c->[3];
      $c->[4]  = $close;

      $c->[5] += $vol;
      $c->[6] += $BV;
      $c->[7] += $SV;
      $c->[8] += $Delta;

      $c->[9]  = $min_D if $min_D < $c->[9];
      $c->[10] = $max_D if $max_D > $c->[10];

      $c->[11] = $session_cvd;

      $c->[14] += ($POC // 0) * $vol;
      # $c->[12]  = $c->[5] > 0 ? sprintf "%.2f", $c->[14] / $c->[5] : undef;
      $c->[16]  = $c->[5] > 0 ? sprintf "%.2f", $c->[14] / $c->[5] : undef;

      # finalize immediately if this is last tick of slot
      if ($is_last_tick_of_slot) {
        # $c->[14] = $base_index;
        $c->[15] = $base_index; # mapea entre múltiples timeframe → índice base. permite sincronizar crosshair, alinear indicadores, debugging avanzado
        return $c;
      }

    # índices consistentes:
    # 12 = POC
    # 13 = slot
    # 14 = poc_volume_accumulator
    # 15 = base_index (nuevo)
    # 16 = vwap_poc (nuevo)

      return;
  }
  
  # store new candle
  push @$candles, [$time, $open, $high, $low, $close, $vol, $BV, $SV, $Delta, $min_D, $max_D, $session_cvd, $POC, $slot, ($POC // 0) * $vol];
}

sub build_timeframes {
    my ($self, $candle, $index) = @_;

    $self->build_tf_candles($self->{candles_0300}, $candle, 300, $index);
    $self->build_tf_candles($self->{candles_0900}, $candle, 900, $index);
}

sub set_timeframe {
    my ($self, $tf) = @_;

    die "Invalid timeframe" unless exists $self->{tf_map}{$tf};

    $self->{active_tf} = $tf;
    
    # Ancoras para preparar la escala horizontal de tiempo
    $self->{time_axis}{anchors} = $self->compute_time_anchors();
}

sub _active_array {
    my ($self) = @_;

    my $key = $self->{tf_map}{ $self->{active_tf} };

    return $self->{$key};
}

sub get_slice {
    my ($self, $start, $end) = @_;

    my $arr = $self->_active_array();

    my $max = $#$arr;

    $start = 0 if $start < 0;
    $end   = $max if $end > $max;

    return [] if $start > $end;

    return [ @$arr[$start .. $end] ];
}

sub get_candle {
    my ($self, $idx) = @_;

    my $arr = $self->_active_array();
    
    return if $idx >= scalar(@$arr);

    return $arr->[$idx];
}

sub size {
    my ($self) = @_;

    my $arr = $self->_active_array();

    return scalar @$arr;
}

sub last_candle {
    my ($self) = @_;
    my $arr = $self->_active_array();
    return $arr->[-1];
}

sub last_index {
    my ($self) = @_;
    my $arr = $self->_active_array();
    return $#$arr;
}

sub get_timestamp {
    my ($self, $idx) = @_;
    
    my $arr = $self->_active_array();

    return if $idx >= scalar(@$arr);
    
    return $arr->[$idx][0];
}

sub merge_delta_row { # Absorbs part of the original update_charts() function
    my ($self, $delta_row) = @_;

    die "Invalid delta_row" unless ref $delta_row eq 'ARRAY';

    my ($time, $d_vol, $d_BV, $d_SV, $d_Delta, $d_min_D, $d_max_D, $d_POC) = @$delta_row;

    # ----------------------------------------
    # 1. USAR SOLO EL ÚLTIMO CANDLE
    # ----------------------------------------
    my $base = $self->{last_base_candle};

    return undef unless $base;

    my ($t, $open, $high, $low, $close, $vol,
        $BV, $SV, $Delta_old, $min_D, $max_D,
        $session_cvd, $POC) = @$base;

    # ----------------------------------------
    # 2. CONSTRUIR NUEVO CANDLE
    # ----------------------------------------
    my $new_candle = [
        $time,
        $open,
        $high,
        $low,
        $close,

        $d_vol   // $vol,
        $d_BV    // $BV,
        $d_SV    // $SV,
        $d_Delta // $Delta_old,
        $d_min_D // $min_D,
        $d_max_D // $max_D,
        $session_cvd,
        $d_POC   // $POC,
    ];

    # ----------------------------------------
    # 3. INSERTAR
    # ----------------------------------------
    my $idx = $self->add_candle($new_candle);

    return $idx;
}

# ----------------------------------------
# Usado para la escala horizontal de tiempo
# ----------------------------------------
sub compute_time_anchors {
    my ($self) = @_;

    my @anchors;
    my @tss = map {$_->[0]} @{$self->_active_array()};
    my ($prev_day, $prev_month, $prev_year, $day, $month, $yearv, $tm, $type);

    while (my ($i, $ts) = each @tss) {
      
        next unless defined $ts;

        $tm    = Time::Moment->from_string($ts);
        $day   = $tm->day_of_month;
        $month = $tm->month;
        $yearv = $tm->year;

        # ----------------------------------------
        # PRIORIDAD: year > month > day
        # ----------------------------------------
        if (!defined $prev_year || $yearv != $prev_year) {
            $type = 'year';
        } elsif (!defined $prev_month || $month != $prev_month) {
            $type = 'month';
        } elsif (!defined $prev_day || $day != $prev_day) {
            $type = 'day';
        }else{
            $type = undef;
        }

        if ($type) {
            push @anchors, {
                index => $i,   # 🔥 índice DEL TF ACTIVO
                ts    => $ts,
                type  => $type,
            };
        }

        $prev_day   = $day;
        $prev_month = $month;
        $prev_year  = $yearv;
    }
    
    # ----------------------------------------
    # 🔥 última vela del timeframe siempre disponible como áncora
    # ----------------------------------------
    push @anchors, {
        index => $self->size() - 1,
        ts    => $tss[-1],
        type  => 'last',
    };

    return \@anchors;
}

1;