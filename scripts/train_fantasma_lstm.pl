#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use File::Path qw(make_path);
use Time::HiRes qw(time);

use AI::MXNet qw(mx nd);
use Market::ML::FantasmaLSTMData;

# LSTM regresion multi-salida (y3/y5/y10/y15) sobre dataset fantasma normalizado.
# Sin CNN. Patron adaptado del lab 09_02_02 (seq_len≈5, Gluon LSTM NTC).

STDOUT->autoflush(1);
STDERR->autoflush(1);

my %opt = (
    train       => 'Data/ml_out/fantasma_train_norm.csv',
    test        => 'Data/ml_out/fantasma_test_norm.csv',
    stats       => 'Data/ml_out/fantasma_norm_stats.json',
    out_dir     => 'Data/ml_out/lstm_fantasma',
    seq_len     => 5,
    batch_size  => 64,
    hidden      => 32,
    num_layers  => 1,
    dropout     => 0.2,
    lr          => 0.01,
    epochs      => 20,
    seed        => 42,
    eval_only   => 0,
    model       => undef,    # default: out_dir/fantasma_lstm.params
    binary_thr  => 1,
);

while (@ARGV) {
    my $a = shift @ARGV;
    if ( $a eq '--train' )          { $opt{train} = shift @ARGV }
    elsif ( $a eq '--test' )        { $opt{test} = shift @ARGV }
    elsif ( $a eq '--stats' )       { $opt{stats} = shift @ARGV }
    elsif ( $a eq '--out-dir' )     { $opt{out_dir} = shift @ARGV }
    elsif ( $a eq '--seq-len' )     { $opt{seq_len} = 0 + shift @ARGV }
    elsif ( $a eq '--batch-size' )  { $opt{batch_size} = int( shift @ARGV ) }
    elsif ( $a eq '--hidden' )      { $opt{hidden} = int( shift @ARGV ) }
    elsif ( $a eq '--num-layers' )  { $opt{num_layers} = int( shift @ARGV ) }
    elsif ( $a eq '--dropout' )     { $opt{dropout} = 0 + shift @ARGV }
    elsif ( $a eq '--lr' )          { $opt{lr} = 0 + shift @ARGV }
    elsif ( $a eq '--epochs' )      { $opt{epochs} = int( shift @ARGV ) }
    elsif ( $a eq '--seed' )        { $opt{seed} = int( shift @ARGV ) }
    elsif ( $a eq '--model' )       { $opt{model} = shift @ARGV }
    elsif ( $a eq '--eval-only' )   { $opt{eval_only} = 1 }
    elsif ( $a eq '--binary-thr' )  { $opt{binary_thr} = 0 + shift @ARGV }
    elsif ( $a eq '--help' || $a eq '-h' ) { print_usage(); exit 0 }
    else { die "Opcion desconocida: $a (usa --help)\n" }
}

$opt{model} //= "$opt{out_dir}/fantasma_lstm.params";

die "Train no encontrado: $opt{train}\n" unless -f $opt{train};
die "Test no encontrado: $opt{test}\n"   unless -f $opt{test};
die "Stats no encontrado: $opt{stats}\n" unless -f $opt{stats};
make_path( $opt{out_dir} ) unless -d $opt{out_dir};

mx->random->seed( $opt{seed} );

print "[*] MXNet OK — Fantasma LSTM (regresion MSE multi-salida)\n";
print "[*] train=$opt{train}\n";
print "[*] test=$opt{test}\n";
print "[*] stats=$opt{stats}\n";
print "[*] out_dir=$opt{out_dir}\n";
printf "[*] seq_len=%d batch=%d hidden=%d layers=%d dropout=%.2f lr=%g epochs=%d\n",
  $opt{seq_len}, $opt{batch_size}, $opt{hidden}, $opt{num_layers},
  $opt{dropout}, $opt{lr}, $opt{epochs};

my $t_load = time();
print "[*] Cargando train...\n";
my $train_pack = Market::ML::FantasmaLSTMData->load_xy(
    csv   => $opt{train},
    stats => $opt{stats},
);
print "[*] Cargando test...\n";
my $test_pack = Market::ML::FantasmaLSTMData->load_xy(
    csv   => $opt{test},
    stats => $opt{stats},
);
printf "[*] load OK train_rows=%d test_rows=%d feats=%d targets=%s (%.1fs)\n",
  $train_pack->{n_rows}, $test_pack->{n_rows}, $train_pack->{n_features},
  join( ',', @{ $train_pack->{targets} } ), time() - $t_load;

my ( $Xtr_seq, $ytr_seq, $idx_tr ) = Market::ML::FantasmaLSTMData->make_sequences(
    $train_pack->{X}, $train_pack->{y}, $opt{seq_len}
);
my ( $Xte_seq, $yte_seq, $idx_te ) = Market::ML::FantasmaLSTMData->make_sequences(
    $test_pack->{X}, $test_pack->{y}, $opt{seq_len}
);
printf "[*] secuencias train=%d test=%d (seq_len=%d)\n",
  scalar(@$Xtr_seq), scalar(@$Xte_seq), $opt{seq_len};

print "[*] Convirtiendo a NDArray...\n";
my $X_train = nd->array($Xtr_seq);
my $y_train = nd->array($ytr_seq);
my $X_test  = nd->array($Xte_seq);
my $y_test  = nd->array($yte_seq);
printf "[*] X_train_seq shape=%s y_train_seq shape=%s\n",
  _shape_str($X_train), _shape_str($y_train);
printf "[*] X_test_seq shape=%s y_test_seq shape=%s\n",
  _shape_str($X_test), _shape_str($y_test);

my $n_features = $X_train->shape->[-1];
my $n_targets  = $y_train->shape->[-1];

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
        $self->{dense} = mx->gluon->nn->Dense(
            units    => $args{units},
            in_units => $args{in_units},
            flatten  => 0,
        );
        map { $self->register_child( $self->{$_} ) } ( 'lstm', 'dense' );
        return bless( $self, $class );
    }

    sub forward {
        my ( $self, $X ) = @_;
        my $H = $self->{lstm}->forward($X);
        # Ultimo paso temporal: [batch, hidden]
        $H = $H->slice( ':', -1, ':' )->sever;
        return $self->{dense}->forward($H);
    }
}

my $net = FantasmaLSTM->new(
    hidden_units  => $opt{hidden},
    num_layer     => $opt{num_layers},
    layout        => 'NTC',
    dropout       => $opt{dropout},
    bidirectional => 0,
    input_size    => $n_features,
    units         => $n_targets,
    in_units      => $opt{hidden},
);

$net->collect_params->initialize( init => mx->init->Xavier(), force_reinit => 1 );

my $loss    = mx->gluon->loss->L2Loss();
my $trainer = mx->gluon->Trainer(
    $net->collect_params(),
    optimizer        => 'adam',
    optimizer_params => { learning_rate => $opt{lr} },
);

sub load_array {
    my ( $data_arrays, $batch_size, %args ) = (
        splice( @_, 0, 2 ),
        is_train   => 1,
        last_batch => 'keep',
        @_
    );
    my ( $X, $y ) = @$data_arrays;
    my $dataset = mx->gluon->data->ArrayDataset( data => $X, label => $y );
    return mx->gluon->data->DataLoader(
        $dataset,
        batch_size => $batch_size,
        shuffle    => $args{is_train},
        last_batch => $args{last_batch} // 'discard',
    );
}

sub train_epoch {
    my ( $net, $train_iter, $loss, $updater ) = @_;
    my ( $sum_loss, $n ) = ( 0, 0 );
    while ( my $batch = <$train_iter> ) {
        my ( $X, $y ) = @$batch;
        my ( $y_hat, $l );
        mx->autograd->record(
            sub {
                $y_hat = $net->($X);
                $l     = $loss->( $y_hat, $y->astype('float32') );
            }
        );
        $l->backward();
        $updater->step( $X->len );
        $sum_loss += $l->sum->asscalar;
        $n        += $l->len;
    }
    return $n ? $sum_loss / $n : 0;
}

sub predict_iter {
    my ( $net, $data_iter ) = @_;
    my @rows;
    while ( my $batch = <$data_iter> ) {
        my ( $X, $y ) = @$batch;
        my $yhat = $net->($X);
        # tolist en contexto lista (escalar solo devuelve el conteo)
        my @batch_rows = $yhat->tolist;
        push @rows, @batch_rows;
    }
    return \@rows;
}

sub ndarray_to_aoa {
    my ($arr) = @_;
    my @rows = $arr->tolist;
    return \@rows;
}

if ( $opt{eval_only} ) {
    die "Modelo no encontrado: $opt{model}\n" unless -f $opt{model};
    print "[*] Cargando modelo $opt{model}\n";
    $net->load_parameters( $opt{model} );
}
else {
    print "[*] Entrenando...\n";
    my $t0 = time();
    for ( my $epoch = 1 ; $epoch <= $opt{epochs} ; $epoch++ ) {
        my $train_iter = load_array(
            [ $X_train, $y_train ],
            $opt{batch_size},
            is_train   => 1,
            last_batch => 'rollover',
        );
        my $avg = train_epoch( $net, $train_iter, $loss, $trainer );
        printf "[*] epoch %02d/%02d  train_L2=%.6f  (%.1fs)\n",
          $epoch, $opt{epochs}, $avg, time() - $t0;
    }
    $net->save_parameters( $opt{model} );
    printf "[*] Modelo guardado: %s (%.1fs total train)\n", $opt{model}, time() - $t0;
}

print "[*] Evaluando test julio...\n";
my $test_iter = load_array(
    [ $X_test, $y_test ],
    $opt{batch_size},
    is_train   => 0,
    last_batch => 'keep',
);
my $y_pred = predict_iter( $net, $test_iter );
my $y_true = ndarray_to_aoa($y_test);

# Alinear longitudes por si last_batch descarta (keep → debe coincidir)
my $n_eval = scalar @$y_pred;
if ( $n_eval != scalar @$y_true ) {
    warn sprintf(
        "[!] pred_rows=%d true_rows=%d — truncando al minimo\n",
        $n_eval, scalar(@$y_true)
    );
    $n_eval = $n_eval < @$y_true ? $n_eval : scalar(@$y_true);
    @$y_pred = @$y_pred[ 0 .. $n_eval - 1 ];
    @$y_true = @$y_true[ 0 .. $n_eval - 1 ];
    @$idx_te = @$idx_te[ 0 .. $n_eval - 1 ];
}

my $targets = $train_pack->{targets};
my $reg = Market::ML::FantasmaLSTMData->mae_rmse_per_target( $y_true, $y_pred, $targets );
my $bin = Market::ML::FantasmaLSTMData->binary_accuracy_per_target(
    $y_true, $y_pred, $targets, $opt{binary_thr}
);

print "[*] === Metricas TEST (julio) ===\n";
for my $t (@$targets) {
    printf "[*] %s  MAE=%.4f  RMSE=%.4f  bin_acc(>=%.0f)=%.4f  (n_pos=%d/%d)\n",
      $t, $reg->{$t}{mae}, $reg->{$t}{rmse}, $opt{binary_thr},
      $bin->{$t}{accuracy}, $bin->{$t}{n_pos}, $bin->{$t}{n};
}

my $metrics_path = "$opt{out_dir}/metrics_test.json";
my $preds_path   = "$opt{out_dir}/preds_test.csv";
my $cfg_path     = "$opt{out_dir}/train_config.json";

Market::ML::FantasmaLSTMData->write_preds_csv(
    $preds_path, $test_pack->{meta}, $idx_te, $y_true, $y_pred, $targets
);

my $metrics = {
    split            => 'test_julio',
    n_sequences      => $n_eval,
    seq_len          => $opt{seq_len},
    targets          => $targets,
    regression       => $reg,
    binary_accuracy  => $bin,
    binary_threshold => $opt{binary_thr},
    model            => $opt{model},
    train_csv        => $opt{train},
    test_csv         => $opt{test},
    stats_json       => $opt{stats},
    n_features       => $n_features,
    hyperparams      => {
        batch_size => $opt{batch_size},
        hidden     => $opt{hidden},
        num_layers => $opt{num_layers},
        dropout    => $opt{dropout},
        lr         => $opt{lr},
        epochs     => $opt{epochs},
        seed       => $opt{seed},
        loss       => 'L2Loss',
        optimizer  => 'adam',
        cnn        => 0,
    },
};
Market::ML::FantasmaLSTMData->write_metrics_json( $metrics, $metrics_path );

my $cfg = {
    %opt,
    n_features      => $n_features,
    n_targets       => $n_targets,
    train_rows      => $train_pack->{n_rows},
    test_rows       => $test_pack->{n_rows},
    train_sequences => scalar(@$Xtr_seq),
    test_sequences  => scalar(@$Xte_seq),
    feature_columns => $train_pack->{feature_columns},
    targets         => $targets,
};
Market::ML::FantasmaLSTMData->write_metrics_json( $cfg, $cfg_path );

print "[*] metrics=$metrics_path\n";
print "[*] preds=$preds_path\n";
print "[*] config=$cfg_path\n";
print "[*] OK\n";
exit 0;

sub _shape_str {
    my ($a) = @_;
    return join( 'x', @{ $a->shape } );
}

sub print_usage {
    print <<'USAGE';
train_fantasma_lstm.pl — LSTM regresion multi-salida (fantasma, sin CNN)

  --train PATH         (default Data/ml_out/fantasma_train_norm.csv)
  --test PATH          (default Data/ml_out/fantasma_test_norm.csv)
  --stats PATH         (default Data/ml_out/fantasma_norm_stats.json)
  --out-dir PATH       (default Data/ml_out/lstm_fantasma)
  --seq-len N          (default 5)
  --batch-size N       (default 64)
  --hidden N           (default 32)
  --num-layers N       (default 1)
  --dropout F          (default 0.2)
  --lr F               (default 0.01)
  --epochs N           (default 20)
  --seed N             (default 42)
  --model PATH         (default OUT/fantasma_lstm.params)
  --eval-only          solo cargar modelo y evaluar test
  --binary-thr F       umbral accuracy binaria (default 1)

Entrena solo con train; reporta MAE/RMSE y accuracy binaria (>=thr) por y3/y5/y10/y15.
USAGE
}
