#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use Time::HiRes qw(time);

use JSON::PP ();
use AI::MXNet qw(mx nd);
use Market::ML::FantasmaLSTMData;

# Demo oral: carga modelo LSTM fantasmita y muestra N predicciones vs labels.
# Solo lee test + stats (no reentrena). Salida ASCII apta para proyector.

STDOUT->autoflush(1);
STDERR->autoflush(1);

my %opt = (
    test      => 'Data/ml_out/fantasma_test_norm.csv',
    stats     => 'Data/ml_out/fantasma_norm_stats.json',
    model     => 'Data/ml_out/lstm_fantasma_final/fantasma_lstm.params',
    metrics   => 'Data/ml_out/lstm_fantasma_final/metrics_test.json',
    seq_len   => 5,
    hidden    => 48,
    num_layers => 1,
    dropout   => 0.2,
    dense_dropout => undef,  # undef=auto (2.weight→v2; 1.weight→v1)
    n         => 8,
    seed      => 42,
    indices   => undef,    # CSV de indices de secuencia, p.ej. 0,100,500
    spaced    => 1,        # muestrear espaciado en el test (default oral)
);

while (@ARGV) {
    my $a = shift @ARGV;
    if ( $a eq '--test' )          { $opt{test} = shift @ARGV }
    elsif ( $a eq '--stats' )      { $opt{stats} = shift @ARGV }
    elsif ( $a eq '--model' )      { $opt{model} = shift @ARGV }
    elsif ( $a eq '--metrics' )    { $opt{metrics} = shift @ARGV }
    elsif ( $a eq '--seq-len' )    { $opt{seq_len} = 0 + shift @ARGV }
    elsif ( $a eq '--hidden' )     { $opt{hidden} = int( shift @ARGV ) }
    elsif ( $a eq '--num-layers' ) { $opt{num_layers} = int( shift @ARGV ) }
    elsif ( $a eq '--dropout' )    { $opt{dropout} = 0 + shift @ARGV }
    elsif ( $a eq '--dense-dropout' ) { $opt{dense_dropout} = 1 }
    elsif ( $a eq '--no-dense-dropout' ) { $opt{dense_dropout} = 0 }
    elsif ( $a eq '--n' )          { $opt{n} = int( shift @ARGV ) }
    elsif ( $a eq '--seed' )       { $opt{seed} = int( shift @ARGV ) }
    elsif ( $a eq '--indices' )    { $opt{indices} = shift @ARGV }
    elsif ( $a eq '--first' )      { $opt{spaced} = 0 }
    elsif ( $a eq '--help' || $a eq '-h' ) { print_usage(); exit 0 }
    else { die "Opcion desconocida: $a (usa --help)\n" }
}

die "Test no encontrado: $opt{test}\n"     unless -f $opt{test};
die "Stats no encontrado: $opt{stats}\n"   unless -f $opt{stats};
die "Modelo no encontrado: $opt{model}\n"  unless -f $opt{model};

# v2/final guarda Dense como 2.* (Dropout hijo 1 sin params); v1 usa 1.*
my $arch = _detect_arch( $opt{model}, $opt{dense_dropout} );
mx->random->seed( $opt{seed} );

_banner('DEMO FANTASMA LSTM — prediccion en vivo');
print "Modelo : $opt{model}\n";
print "Test   : $opt{test}\n";
print "Stats  : $opt{stats}\n";
printf "seq_len=%d  hidden=%d  dense_dropout=%s  CNN=no\n",
  $opt{seq_len}, $opt{hidden}, $arch->{dense_dropout} ? 'si' : 'no';
print "\n";

my $t0 = time();
print "[1/4] Cargando test normalizado + stats...\n";
my $pack = Market::ML::FantasmaLSTMData->load_xy(
    csv   => $opt{test},
    stats => $opt{stats},
);
my ( $X_seq, $y_seq, $end_idx ) = Market::ML::FantasmaLSTMData->make_sequences(
    $pack->{X}, $pack->{y}, $opt{seq_len}
);
my $n_seq = scalar @$X_seq;
printf "      filas=%d  secuencias=%d  feats=%d  targets=%s  (%.1fs)\n",
  $pack->{n_rows}, $n_seq, $pack->{n_features},
  join( ',', @{ $pack->{targets} } ), time() - $t0;

printf "[2/4] Construyendo red LSTM (Gluon NTC%s + Dense)...\n",
  $arch->{dense_dropout} ? ' + Dropout' : '';
my $n_features = $pack->{n_features};
my $n_targets  = $pack->{n_targets};

package FantasmaLSTM {
    use strict;
    use warnings;
    use AI::MXNet qw(mx);
    use base ('AI::MXNet::Gluon::Block');

    sub new {
        my ( $class, %args ) = @_;
        my $self = $class->SUPER::new(%args);
        $self->{lstm} = mx->gluon->rnn->LSTM(
            hidden_size   => $args{hidden_units},
            num_layers    => $args{num_layer} // 1,
            layout        => $args{layout} // 'NTC',
            dropout       => $args{dropout} // 0,
            bidirectional => $args{bidirectional} // 0,
            input_size    => $args{input_size},
        );
        my @children = ('lstm');
        if ( $args{dense_dropout} ) {
            # Misma indexacion que train v2: Dropout ocupa el hijo 1 (sin params)
            $self->{drop} = mx->gluon->nn->Dropout( rate => $args{dropout} // 0 );
            push @children, 'drop';
        }
        $self->{dense} = mx->gluon->nn->Dense(
            units    => $args{units},
            in_units => $args{in_units},
            flatten  => 0,
        );
        push @children, 'dense';
        map { $self->register_child( $self->{$_} ) } @children;
        return bless( $self, $class );
    }

    sub forward {
        my ( $self, $X ) = @_;
        my $H = $self->{lstm}->forward($X);
        $H = $H->slice( ':', -1, ':' )->sever;
        $H = $self->{drop}->forward($H) if $self->{drop};
        return $self->{dense}->forward($H);
    }
}

my $net = FantasmaLSTM->new(
    hidden_units  => $opt{hidden},
    num_layer     => $opt{num_layers},
    layout        => 'NTC',
    dropout       => $opt{dropout},
    dense_dropout => $arch->{dense_dropout},
    bidirectional => 0,
    input_size    => $n_features,
    units         => $n_targets,
    in_units      => $opt{hidden},
);
$net->collect_params->initialize( init => mx->init->Xavier(), force_reinit => 1 );

print "[3/4] Cargando pesos: $opt{model}\n";
print "      arch detectada: Dense=@{[$arch->{dense_dropout} ? '2.* (v2/final)' : '1.* (v1)']}\n";
$net->load_parameters( $opt{model} );
print "      OK — modelo cargado (sin reentrenar)\n";

my @pick = _pick_indices( \%opt, $n_seq );
printf "[4/4] Prediciendo %d muestras...\n\n", scalar @pick;

my @targets = @{ $pack->{targets} };
my @rows_out;

for my $si (@pick) {
    my $X1 = nd->array( [ $X_seq->[$si] ] );    # [1, seq_len, feats]
    my $yhat = $net->($X1);
    my @pred = $yhat->tolist;
    # tolist en batch 1 → una fila [y3,y5,y10,y15]
    my $pred_row = ref( $pred[0] ) eq 'ARRAY' ? $pred[0] : \@pred;
    my $true_row = $y_seq->[$si];
    my $ri       = $end_idx->[$si];
    my $m        = $pack->{meta}[$ri] // {};

    push @rows_out, {
        seq_i => $si,
        row   => $ri,
        time  => $m->{time} // '',
        true  => $true_row,
        pred  => $pred_row,
    };
}

_print_table( \@rows_out, \@targets );
_print_metrics_snapshot( $opt{metrics} ) if defined $opt{metrics} && -f $opt{metrics};

print "\n";
_banner('FIN DEMO — comparar true_* vs pred_* (conteo de rastros)');
printf "Total wall: %.1fs\n", time() - $t0;
exit 0;

# ---------------------------------------------------------------------------

# Detecta indexacion Dense: v2/final = 2.weight (Dropout hijo intermedio); v1 = 1.weight
sub _detect_arch {
    my ( $params_path, $force ) = @_;
    if ( defined $force ) {
        return { dense_dropout => $force ? 1 : 0, source => 'flag' };
    }
    open my $fh, '<:raw', $params_path
      or die "No se pudo leer params para detectar arch: $params_path: $!\n";
    local $/;
    my $blob = <$fh>;
    close $fh;
    my $has2 = index( $blob, '2.weight' ) >= 0;
    my $has1 = index( $blob, '1.weight' ) >= 0;
    if ( $has2 && !$has1 ) {
        return { dense_dropout => 1, source => 'params:2.weight' };
    }
    if ( $has1 && !$has2 ) {
        return { dense_dropout => 0, source => 'params:1.weight' };
    }
    # Ambiguo o sin claves claras: asumir v2/final (default del paquete)
    return { dense_dropout => 1, source => 'default:v2' };
}

sub _pick_indices {
    my ( $opt, $n_seq ) = @_;
    if ( defined $opt->{indices} && length $opt->{indices} ) {
        my @idx = map { int($_) } split /,/, $opt->{indices};
        for my $i (@idx) {
            die "indice fuera de rango: $i (0..@{[ $n_seq - 1 ]})\n"
              if $i < 0 || $i >= $n_seq;
        }
        return @idx;
    }

    my $n = $opt->{n};
    $n = $n_seq if $n > $n_seq;
    $n = 1      if $n < 1;

    if ( !$opt->{spaced} ) {
        return ( 0 .. $n - 1 );
    }

    # Espaciado uniforme a lo largo de julio (buen muestreo para oral)
    return (0) if $n == 1;
    my @out;
    for my $k ( 0 .. $n - 1 ) {
        my $i = int( $k * ( $n_seq - 1 ) / ( $n - 1 ) );
        push @out, $i;
    }
    # Unicos preservando orden
    my %seen;
    return grep { !$seen{$_}++ } @out;
}

sub _print_table {
    my ( $rows, $targets ) = @_;

    print '=' x 100, "\n";
    printf "  %-4s %-28s %6s | %8s %8s %8s %8s\n",
      '#', 'meta_time (UTC-5)', 'seq', @$targets;
    print '=' x 100, "\n";

    my $k = 0;
    for my $r (@$rows) {
        $k++;
        my $t = $r->{time};
        $t = substr( $t, 0, 28 ) if length($t) > 28;

        printf "  %-4d %-28s %6d\n", $k, $t, $r->{seq_i};
        printf "  %-4s %-28s %6s | %8s %8s %8s %8s\n",
          '', 'TRUE (label auto)', '',
          map { sprintf( '%8.0f', $r->{true}[$_] // 0 ) } ( 0 .. $#$targets );
        printf "  %-4s %-28s %6s | %8s %8s %8s %8s\n",
          '', 'PRED (modelo)', '',
          map { sprintf( '%8.2f', $r->{pred}[$_] // 0 ) } ( 0 .. $#$targets );
        printf "  %-4s %-28s %6s | %8s %8s %8s %8s\n",
          '', 'err (pred-true)', '',
          map {
            sprintf( '%8.2f',
                ( $r->{pred}[$_] // 0 ) - ( $r->{true}[$_] // 0 ) )
          } ( 0 .. $#$targets );
        print '-' x 100, "\n";
    }
}

sub _print_metrics_snapshot {
    my ($path) = @_;
    open my $fh, '<:encoding(UTF-8)', $path or return;
    local $/;
    my $raw = <$fh>;
    close $fh;
    my $j = eval { JSON::PP->new->decode($raw) };
    return unless $j && ref( $j->{regression} ) eq 'HASH';

    print "\n";
    _banner('METRICAS TEST JULIO (referencia, ya calculadas)');
    printf "%-6s %8s %8s %12s\n", 'tgt', 'MAE', 'RMSE', 'bin_acc>=1';
    print '-' x 40, "\n";
    for my $t (qw( y3 y5 y10 y15 )) {
        my $r = $j->{regression}{$t} // {};
        my $b = $j->{binary_accuracy}{$t} // {};
        printf "%-6s %8.2f %8.2f %12.2f\n",
          $t, $r->{mae} // 0, $r->{rmse} // 0, $b->{accuracy} // 0;
    }
    printf "n_sequences=%s  cnn=%s\n",
      $j->{n_sequences} // '?',
      ( $j->{hyperparams}{cnn} // '?' );
}

sub _banner {
    my ($msg) = @_;
    print '=' x 96, "\n";
    print "  $msg\n";
    print '=' x 96, "\n";
}

sub print_usage {
    print <<'USAGE';
demo_fantasma_predict.pl — demo oral: cargar LSTM y mostrar true vs pred

  --test PATH       (default Data/ml_out/fantasma_test_norm.csv)
  --stats PATH      (default Data/ml_out/fantasma_norm_stats.json)
  --model PATH      (default Data/ml_out/lstm_fantasma_final/fantasma_lstm.params)
  --metrics PATH    (default Data/ml_out/lstm_fantasma_final/metrics_test.json)
  --seq-len N       (default 5)
  --hidden N        (default 48)
  --dropout R       (default 0.2; tasa del Dropout pre-Dense en v2)
  --dense-dropout   forzar arch v2 (LSTM+Dropout+Dense → Dense=2.*)
  --no-dense-dropout forzar arch v1 (LSTM+Dense → Dense=1.*)
  --n N             cuantas muestras mostrar (default 8)
  --indices I,J,..  indices de secuencia concretos (anula --n/--first)
  --first           primeras N secuencias (en vez de espaciadas)
  --seed N

Por defecto auto-detecta la arch leyendo claves del .params
(2.weight → v2/final; 1.weight → v1).

Ejemplo oral (Fedora35):

  cd /mnt/c/Users/bryan/ia/proyecto_iaaa/Proyecto/ProyectoIAAA
  perl -I. scripts/demo_fantasma_predict.pl --n 8

USAGE
}
