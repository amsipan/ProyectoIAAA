#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use File::Path qw(make_path);
use File::Copy qw(copy);
use Time::HiRes qw(time);
use JSON::PP ();

use AI::MXNet qw(mx nd);
use Market::ML::FantasmaLSTMData;

# LSTM v2b: misma receta v2 (val causal, early stop, dropout) con Dense intermedia relu.
# Artefactos con sufijo _v2b en out_dir propio; v1 y v2 quedan intactos.

STDOUT->autoflush(1);
STDERR->autoflush(1);

my %opt = (
    train        => 'Data/ml_out/fantasma_train_norm.csv',
    test         => 'Data/ml_out/fantasma_test_norm.csv',
    stats        => 'Data/ml_out/fantasma_norm_stats.json',
    out_dir      => 'Data/ml_out/lstm_fantasma_v2b',
    seq_len      => 5,
    batch_size   => 32,
    hidden       => 48,
    dense_hidden => 24,
    num_layers   => 1,
    dropout      => 0.2,
    lr           => 0.005,
    epochs       => 25,        # tope; early stopping suele cortar antes
    patience     => 4,
    min_delta    => 0.0005,
    val_frac     => 0.15,
    seed         => 42,
    eval_only    => 0,
    model        => undef,     # default: out_dir/fantasma_lstm_v2b.params
    binary_thr   => 1,
    grid         => undef,     # "name:hidden:dense:dropout:lr:batch,..."
    run_name     => 'single',
);

my %cli_given;
while (@ARGV) {
    my $a = shift @ARGV;
    if ( $a eq '--train' )          { $opt{train} = shift @ARGV }
    elsif ( $a eq '--test' )        { $opt{test} = shift @ARGV }
    elsif ( $a eq '--stats' )       { $opt{stats} = shift @ARGV }
    elsif ( $a eq '--out-dir' )     { $opt{out_dir} = shift @ARGV }
    elsif ( $a eq '--seq-len' )     { $opt{seq_len} = 0 + shift @ARGV;    $cli_given{seq_len} = 1 }
    elsif ( $a eq '--batch-size' )  { $opt{batch_size} = int( shift @ARGV ); $cli_given{batch_size} = 1 }
    elsif ( $a eq '--hidden' )      { $opt{hidden} = int( shift @ARGV );  $cli_given{hidden} = 1 }
    elsif ( $a eq '--dense-hidden' ){ $opt{dense_hidden} = int( shift @ARGV ); $cli_given{dense_hidden} = 1 }
    elsif ( $a eq '--num-layers' )  { $opt{num_layers} = int( shift @ARGV ); $cli_given{num_layers} = 1 }
    elsif ( $a eq '--dropout' )     { $opt{dropout} = 0 + shift @ARGV;    $cli_given{dropout} = 1 }
    elsif ( $a eq '--lr' )          { $opt{lr} = 0 + shift @ARGV;         $cli_given{lr} = 1 }
    elsif ( $a eq '--epochs' )      { $opt{epochs} = int( shift @ARGV ) }
    elsif ( $a eq '--patience' )    { $opt{patience} = int( shift @ARGV ) }
    elsif ( $a eq '--min-delta' )   { $opt{min_delta} = 0 + shift @ARGV }
    elsif ( $a eq '--val-frac' )    { $opt{val_frac} = 0 + shift @ARGV }
    elsif ( $a eq '--seed' )        { $opt{seed} = int( shift @ARGV ) }
    elsif ( $a eq '--model' )       { $opt{model} = shift @ARGV }
    elsif ( $a eq '--eval-only' )   { $opt{eval_only} = 1 }
    elsif ( $a eq '--binary-thr' )  { $opt{binary_thr} = 0 + shift @ARGV }
    elsif ( $a eq '--grid' )        { $opt{grid} = shift @ARGV }
    elsif ( $a eq '--run-name' )    { $opt{run_name} = shift @ARGV }
    elsif ( $a eq '--help' || $a eq '-h' ) { print_usage(); exit 0 }
    else { die "Opcion desconocida: $a (usa --help)\n" }
}

$opt{model} //= "$opt{out_dir}/fantasma_lstm_v2b.params";

die "Train no encontrado: $opt{train}\n" unless -f $opt{train};
die "Test no encontrado: $opt{test}\n"   unless -f $opt{test};
die "Stats no encontrado: $opt{stats}\n" unless -f $opt{stats};
make_path( $opt{out_dir} ) unless -d $opt{out_dir};

# En eval-only, heredar hiperparams del run elegido salvo flags explicitos
if ( $opt{eval_only} ) {
    my $cfgfile = "$opt{out_dir}/train_config_v2b.json";
    if ( -f $cfgfile ) {
        my $j = _slurp_json($cfgfile);
        if ( my $ch = $j->{chosen} ) {
            for my $k (qw( hidden dense_hidden num_layers dropout lr batch_size seq_len )) {
                next if $cli_given{$k};
                $opt{$k} = $ch->{$k} if defined $ch->{$k};
            }
            print "[*] eval-only hereda config elegida ($j->{chosen_run}): "
              . "hidden=$opt{hidden} dense=$opt{dense_hidden} dropout=$opt{dropout} seq_len=$opt{seq_len}\n";
        }
    }
}

print "[*] MXNet OK — Fantasma LSTM v2b (Dense intermedia relu)\n";
print "[*] train=$opt{train}\n";
print "[*] test=$opt{test}\n";
print "[*] stats=$opt{stats}\n";
print "[*] out_dir=$opt{out_dir}\n";
printf "[*] seq_len=%d max_epochs=%d patience=%d min_delta=%g val_frac=%.2f seed=%d\n",
  $opt{seq_len}, $opt{epochs}, $opt{patience}, $opt{min_delta}, $opt{val_frac}, $opt{seed};

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

# Split causal por filas: la cola del train es validacion (nunca se entrena con ella)
my $targets = $train_pack->{targets};
my $n_rows  = $train_pack->{n_rows};
my $n_val   = int( $n_rows * $opt{val_frac} );
my $n_sub   = $n_rows - $n_val;
die sprintf( "val_frac=%.2f deja sub-train=%d < seq_len=%d\n", $opt{val_frac}, $n_sub, $opt{seq_len} )
  if $n_sub < $opt{seq_len};

my ( @X_sub, @y_sub, @X_val, @y_val );
if ( $n_val >= $opt{seq_len} ) {
    @X_sub = @{ $train_pack->{X} }[ 0 .. $n_sub - 1 ];
    @y_sub = @{ $train_pack->{y} }[ 0 .. $n_sub - 1 ];
    @X_val = @{ $train_pack->{X} }[ $n_sub .. $n_rows - 1 ];
    @y_val = @{ $train_pack->{y} }[ $n_sub .. $n_rows - 1 ];
}
else {
    print "[!] val_frac demasiado pequeno: early stop desactivado, se usa todo el train\n";
    @X_sub = @{ $train_pack->{X} };
    @y_sub = @{ $train_pack->{y} };
    $n_val = 0;
}

my ( $Xtr_seq, $ytr_seq ) = Market::ML::FantasmaLSTMData->make_sequences(
    \@X_sub, \@y_sub, $opt{seq_len}
);
my ( $Xte_seq, $yte_seq, $idx_te ) = Market::ML::FantasmaLSTMData->make_sequences(
    $test_pack->{X}, $test_pack->{y}, $opt{seq_len}
);
my ( $Xva_seq, $yva_seq );
if ( $n_val ) {
    ( $Xva_seq, $yva_seq ) = Market::ML::FantasmaLSTMData->make_sequences(
        \@X_val, \@y_val, $opt{seq_len}
    );
}
printf "[*] secuencias subtrain=%d val=%d test=%d (seq_len=%d)\n",
  scalar(@$Xtr_seq), ( $n_val ? scalar(@$Xva_seq) : 0 ), scalar(@$Xte_seq), $opt{seq_len};

print "[*] Convirtiendo a NDArray...\n";
my $X_train = nd->array($Xtr_seq);
my $y_train = nd->array($ytr_seq);
my $X_test  = nd->array($Xte_seq);
my $y_test  = nd->array($yte_seq);
my ( $X_val_nd, $y_val_nd, $y_val_aoa );
if ( $n_val ) {
    $X_val_nd  = nd->array($Xva_seq);
    $y_val_nd  = nd->array($yva_seq);
    $y_val_aoa = ndarray_to_aoa($y_val_nd);
}
my $y_test_aoa = ndarray_to_aoa($y_test);
printf "[*] X_subtrain_seq shape=%s  X_test_seq shape=%s\n",
  _shape_str($X_train), _shape_str($X_test);

my $n_features = $X_train->shape->[-1];
my $n_targets  = $y_train->shape->[-1];

package FantasmaLSTMV2B {
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
        # Con 1 capa el dropout interno del LSTM no aplica: capa explicita
        $self->{drop} = mx->gluon->nn->Dropout( rate => $args{dropout} // 0 );
        # Dense intermedia: hidden -> dense_hidden con relu
        $self->{dense_mid} = mx->gluon->nn->Dense(
            units      => $args{dense_hidden},
            in_units   => $args{in_units},
            activation => 'relu',
            flatten    => 0,
        );
        $self->{dense} = mx->gluon->nn->Dense(
            units    => $args{units},
            in_units => $args{dense_hidden},
            flatten  => 0,
        );
        map { $self->register_child( $self->{$_} ) } ( 'lstm', 'drop', 'dense_mid', 'dense' );
        return bless( $self, $class );
    }

    sub forward {
        my ( $self, $X ) = @_;
        my $H = $self->{lstm}->forward($X);
        # Ultimo paso temporal: [batch, hidden]
        $H = $H->slice( ':', -1, ':' )->sever;
        $H = $self->{drop}->forward($H);
        $H = $self->{dense_mid}->forward($H);
        return $self->{dense}->forward($H);
    }
}

sub build_net {
    my ($cfg) = @_;
    return FantasmaLSTMV2B->new(
        hidden_units  => $cfg->{hidden},
        num_layer     => $opt{num_layers},
        layout        => 'NTC',
        dropout       => $cfg->{dropout},
        bidirectional => 0,
        input_size    => $n_features,
        dense_hidden  => $cfg->{dense_hidden},
        units         => $n_targets,
        in_units      => $cfg->{hidden},
    );
}

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

sub eval_mae_avg {
    my ( $net, $X, $y_aoa, $batch ) = @_;
    my $pred = predict_iter(
        $net,
        load_array( [ $X, nd->array($y_aoa) ], $batch, is_train => 0, last_batch => 'keep' )
    );
    my $reg = Market::ML::FantasmaLSTMData->mae_rmse_per_target( $y_aoa, $pred, $targets );
    my $avg = 0;
    $avg += $reg->{$_}{mae} for @$targets;
    return $avg / scalar(@$targets);
}

# Confusion completa: pos = >=1 rastro real; pred>=0.5 -> pos (misma convencion v2)
sub binary_full_per_target {
    my ( $y_true, $y_pred, $targets, $true_thr, $pred_thr ) = @_;
    my $n = scalar @$y_true;
    my %out;
    for my $t ( 0 .. $#$targets ) {
        my ( $tp, $fp, $tn, $fn ) = ( 0, 0, 0, 0 );
        for my $i ( 0 .. $n - 1 ) {
            my $yt = ( $y_true->[$i][$t] // 0 ) >= $true_thr ? 1 : 0;
            my $yp = ( $y_pred->[$i][$t] // 0 ) >= $pred_thr ? 1 : 0;
            if    ( $yt && $yp )  { $tp++ }
            elsif ( !$yt && $yp ) { $fp++ }
            elsif ( !$yt && !$yp ){ $tn++ }
            else                  { $fn++ }
        }
        my $prec  = ( $tp + $fp ) ? $tp / ( $tp + $fp ) : 0;
        my $rec   = ( $tp + $fn ) ? $tp / ( $tp + $fn ) : 0;
        my $spec  = ( $tn + $fp ) ? $tn / ( $tn + $fp ) : 0;
        my $f1    = ( $prec + $rec ) ? 2 * $prec * $rec / ( $prec + $rec ) : 0;
        $out{ $targets->[$t] } = {
            n           => $n,
            confusion   => { tp => $tp, fp => $fp, tn => $tn, fn => $fn },
            accuracy    => $n ? ( $tp + $tn ) / $n : 0,
            precision   => $prec,
            recall      => $rec,
            specificity => $spec,
            f1          => $f1,
        };
    }
    return \%out;
}

sub _slurp_json {
    my ($path) = @_;
    open my $fh, '<:encoding(UTF-8)', $path or die "No se puede leer $path: $!\n";
    local $/;
    my $raw = <$fh>;
    close $fh;
    return JSON::PP->new->decode($raw);
}

sub _shape_str {
    my ($a) = @_;
    return join( 'x', @{ $a->shape } );
}

sub train_run {
    my ($cfg) = @_;
    printf "[*] === run %s: hidden=%d dense=%d dropout=%.2f lr=%g batch=%d ===\n",
      $cfg->{name}, $cfg->{hidden}, $cfg->{dense_hidden}, $cfg->{dropout}, $cfg->{lr}, $cfg->{batch_size};

    # misma semilla por run para aislar el efecto de hiperparametros
    mx->random->seed( $opt{seed} );
    my $net = build_net($cfg);
    $net->collect_params->initialize( init => mx->init->Xavier(), force_reinit => 1 );

    my $loss    = mx->gluon->loss->L2Loss();
    my $trainer = mx->gluon->Trainer(
        $net->collect_params(),
        optimizer        => 'adam',
        optimizer_params => { learning_rate => $cfg->{lr} },
    );

    my $ckpt = "$opt{out_dir}/.ckpt_$cfg->{name}.params";
    my ( $best_val, $best_epoch, $wait ) = ( 9e9, 0, 0 );
    my @history;
    my $t0 = time();
    my $epochs_ran = 0;

    for ( my $epoch = 1 ; $epoch <= $opt{epochs} ; $epoch++ ) {
        $epochs_ran = $epoch;
        my $train_iter = load_array(
            [ $X_train, $y_train ],
            $cfg->{batch_size},
            is_train   => 1,
            last_batch => 'rollover',
        );
        my $l2 = train_epoch( $net, $train_iter, $loss, $trainer );

        my $val_mae  = $n_val
          ? eval_mae_avg( $net, $X_val_nd, $y_val_aoa, $cfg->{batch_size} )
          : 0;
        my $test_mae = eval_mae_avg( $net, $X_test, $y_test_aoa, $cfg->{batch_size} );

        push @history, {
            epoch        => $epoch,
            train_l2     => $l2,
            val_mae_avg  => $val_mae,
            test_mae_avg => $test_mae,
        };
        printf "[%s] epoch %02d/%02d train_L2=%.6f val_MAE=%.4f test_MAE=%.4f (%.1fs)%s\n",
          $cfg->{name}, $epoch, $opt{epochs}, $l2, $val_mae, $test_mae, time() - $t0,
          ( $epoch == $best_epoch ? '*' : '' );

        if ( !$n_val ) { $best_epoch = $epoch; next }
        if ( $val_mae < $best_val - $opt{min_delta} ) {
            $best_val   = $val_mae;
            $best_epoch = $epoch;
            $wait       = 0;
            $net->save_parameters($ckpt);
        }
        else {
            $wait++;
            if ( $wait >= $opt{patience} ) {
                printf "[%s] early stop: %d epochs sin mejora >= %g (best epoch %d val_MAE=%.4f)\n",
                  $cfg->{name}, $wait, $opt{min_delta}, $best_epoch, $best_val;
                last;
            }
        }
    }

    if ( $n_val && -f $ckpt ) {
        # restaurar mejor checkpoint del run
        $net->load_parameters($ckpt);
    }
    else {
        # sin validacion: guardar estado final como checkpoint del run
        $net->save_parameters($ckpt);
        $best_val = $history[-1]{test_mae_avg};
        $best_epoch = $epochs_ran;
    }

    my $test_at_best = $history[ $best_epoch - 1 ]{test_mae_avg};
    printf "[%s] run OK best_epoch=%d best_val_MAE=%.4f test_MAE\@best=%.4f (%.1fs)\n",
      $cfg->{name}, $best_epoch, $best_val, $test_at_best, time() - $t0;

    return {
        cfg              => $cfg,
        net              => $net,
        ckpt             => $ckpt,
        best_val_mae_avg => $best_val,
        best_epoch       => $best_epoch,
        epochs_ran       => $epochs_ran,
        test_mae_at_best => $test_at_best,
        history          => \@history,
    };
}

sub final_eval_and_write {
    my ( $net, $batch_size, $extra, $flags ) = @_;
    $flags //= {};

    print "[*] Evaluando test julio (modelo final v2b)...\n";
    my $test_iter = load_array(
        [ $X_test, $y_test ],
        $batch_size,
        is_train   => 0,
        last_batch => 'keep',
    );
    my $y_pred = predict_iter( $net, $test_iter );
    my $y_true = ndarray_to_aoa($y_test);

    my $n_eval = scalar @$y_pred;
    if ( $n_eval != scalar @$y_true ) {
        warn sprintf( "[!] pred_rows=%d true_rows=%d — truncando al minimo\n",
          $n_eval, scalar(@$y_true) );
        $n_eval = $n_eval < @$y_true ? $n_eval : scalar(@$y_true);
        @$y_pred = @$y_pred[ 0 .. $n_eval - 1 ];
        @$y_true = @$y_true[ 0 .. $n_eval - 1 ];
        @$idx_te = @$idx_te[ 0 .. $n_eval - 1 ];
    }

    my $reg = Market::ML::FantasmaLSTMData->mae_rmse_per_target( $y_true, $y_pred, $targets );
    my $bin = Market::ML::FantasmaLSTMData->binary_accuracy_per_target(
        $y_true, $y_pred, $targets, $opt{binary_thr}
    );
    my $bin_full = binary_full_per_target( $y_true, $y_pred, $targets, 1, 0.5 );

    my ( $mae_avg, $rmse_avg, $f1_avg ) = ( 0, 0, 0 );
    $mae_avg  += $reg->{$_}{mae}      for @$targets;
    $rmse_avg += $reg->{$_}{rmse}     for @$targets;
    $f1_avg   += $bin_full->{$_}{f1}  for @$targets;
    $mae_avg  /= scalar(@$targets);
    $rmse_avg /= scalar(@$targets);
    $f1_avg   /= scalar(@$targets);

    print "[*] === Metricas TEST v2b (julio) ===\n";
    for my $t (@$targets) {
        printf "[*] %s  MAE=%.4f  RMSE=%.4f  bin_acc(>=%.0f)=%.4f  F1=%.4f  (TP/FP/TN/FN=%d/%d/%d/%d)\n",
          $t, $reg->{$t}{mae}, $reg->{$t}{rmse}, $opt{binary_thr},
          $bin->{$t}{accuracy}, $bin_full->{$t}{f1},
          $bin_full->{$t}{confusion}{tp}, $bin_full->{$t}{confusion}{fp},
          $bin_full->{$t}{confusion}{tn}, $bin_full->{$t}{confusion}{fn};
    }
    printf "[*] PROMEDIO  MAE=%.4f  RMSE=%.4f  F1=%.4f\n", $mae_avg, $rmse_avg, $f1_avg;

    my $metrics_path = "$opt{out_dir}/metrics_test_v2b.json";
    my $preds_path   = "$opt{out_dir}/preds_test_v2b.csv";
    my $cfg_path     = "$opt{out_dir}/train_config_v2b.json";

    Market::ML::FantasmaLSTMData->write_preds_csv(
        $preds_path, $test_pack->{meta}, $idx_te, $y_true, $y_pred, $targets
    );

    my $metrics = {
        version           => 'v2b',
        split             => 'test_julio',
        n_sequences       => $n_eval,
        seq_len           => $opt{seq_len},
        targets           => $targets,
        regression        => $reg,
        binary_accuracy   => $bin,
        binary_threshold  => $opt{binary_thr},
        binary_full       => $bin_full,
        binary_full_definition => 'pos = >=1 rastro en la ventana; pred>=0.5 -> pos',
        mae_avg           => $mae_avg,
        rmse_avg          => $rmse_avg,
        f1_avg            => $f1_avg,
        model             => $opt{model},
        train_csv         => $opt{train},
        test_csv          => $opt{test},
        stats_json        => $opt{stats},
        n_features        => $n_features,
        selection         => $extra,
        hyperparams       => {
            batch_size    => $extra->{chosen}{batch_size},
            hidden        => $extra->{chosen}{hidden},
            dense_hidden  => $extra->{chosen}{dense_hidden},
            num_layers    => $opt{num_layers},
            dropout       => $extra->{chosen}{dropout},
            lr            => $extra->{chosen}{lr},
            epochs        => $extra->{epochs_ran},
            max_epochs    => $opt{epochs},
            patience      => $opt{patience},
            min_delta     => $opt{min_delta},
            val_frac      => $opt{val_frac},
            seed          => $opt{seed},
            loss          => 'L2Loss',
            optimizer     => 'adam',
            arch          => 'lstm+dense_relu+dense',
            cnn           => 0,
            dense_dropout => 1,
        },
    };
    Market::ML::FantasmaLSTMData->write_metrics_json( $metrics, $metrics_path );

    if ( $flags->{skip_config} ) {
        # eval-only no reescribe la config: contiene la procedencia del grid
        print "[*] config=$cfg_path (conservada)\n";
    }
    else {
        my $cfg = {
            version             => 'v2b',
            selection_criterion =>
              'primario: menor MAE promedio y3..y15 (early stop y seleccion de run por MAE val); '
              . 'secundario: mayor F1 promedio (test)',
            chosen_run          => $extra->{chosen_run},
            chosen              => $extra->{chosen},
            runs                => $extra->{runs},
            %opt,
            n_features        => $n_features,
            n_targets         => $n_targets,
            train_rows        => $train_pack->{n_rows},
            test_rows         => $test_pack->{n_rows},
            subtrain_rows     => $n_sub,
            val_rows          => $n_val,
            subtrain_sequences => scalar(@$Xtr_seq),
            val_sequences     => $n_val ? scalar(@$Xva_seq) : 0,
            test_sequences    => scalar(@$Xte_seq),
            feature_columns   => $train_pack->{feature_columns},
            targets           => $targets,
        };
        Market::ML::FantasmaLSTMData->write_metrics_json( $cfg, $cfg_path );
        print "[*] config=$cfg_path\n";
    }

    print "[*] metrics=$metrics_path\n";
    print "[*] preds=$preds_path\n";
    return $metrics;
}

if ( $opt{eval_only} ) {
    die "Modelo no encontrado: $opt{model}\n" unless -f $opt{model};
    print "[*] Cargando modelo $opt{model}\n";
    my $cfg = {
        name         => 'eval_only',
        hidden       => $opt{hidden},
        dense_hidden => $opt{dense_hidden},
        dropout      => $opt{dropout},
        lr           => $opt{lr},
        batch_size   => $opt{batch_size},
    };
    my $net = build_net($cfg);
    $net->collect_params->initialize( init => mx->init->Xavier(), force_reinit => 1 );
    $net->load_parameters( $opt{model} );

    # metricas conservan la procedencia del grid si la config ya existe
    my $sel = {
        chosen_run => 'eval_only',
        chosen     => $cfg,
        epochs_ran => 0,
        runs       => [],
    };
    my $cfgfile = "$opt{out_dir}/train_config_v2b.json";
    if ( -f $cfgfile ) {
        my $orig = _slurp_json($cfgfile);
        my ($chosen_run) = grep { $_->{chosen} } @{ $orig->{runs} // [] };
        $sel = {
            chosen_run => $orig->{chosen_run} // 'eval_only',
            chosen     => $orig->{chosen}     // $cfg,
            epochs_ran => $chosen_run ? $chosen_run->{epochs_ran} : 0,
            runs       => $orig->{runs} // [],
            eval_only_recheck => JSON::PP::true,
        };
    }
    final_eval_and_write( $net, $opt{batch_size}, $sel, { skip_config => 1 } );
    print "[*] OK (eval-only)\n";
    exit 0;
}

my @cfgs;
if ( defined $opt{grid} ) {
    for my $part ( split /,/, $opt{grid} ) {
        my @f = split /:/, $part;
        die "grid: formato name:hidden:dense:dropout:lr:batch (recibi '$part')\n" unless @f == 6;
        push @cfgs, {
            name         => $f[0],
            hidden       => int( $f[1] ),
            dense_hidden => int( $f[2] ),
            dropout      => 0 + $f[3],
            lr           => 0 + $f[4],
            batch_size   => int( $f[5] ),
        };
    }
}
else {
    @cfgs = ( {
        name         => $opt{run_name},
        hidden       => $opt{hidden},
        dense_hidden => $opt{dense_hidden},
        dropout      => $opt{dropout},
        lr           => $opt{lr},
        batch_size   => $opt{batch_size},
    } );
}
printf "[*] grid: %d run(s), seleccion por menor val MAE promedio\n", scalar(@cfgs);

my $t_grid = time();
my @runs;
for my $cfg (@cfgs) {
    push @runs, train_run($cfg);
}

@runs = sort { $a->{best_val_mae_avg} <=> $b->{best_val_mae_avg} } @runs;
my $best = $runs[0];

print "[*] === Resumen grid (ordenado por val MAE avg) ===\n";
for my $r (@runs) {
    my $c = $r->{cfg};
    printf "[*] %-8s h=%-3d dh=%-3d d=%.1f lr=%-5g b=%-3d epochs=%02d best_ep=%02d val_MAE=%.4f test_MAE\@best=%.4f%s\n",
      $c->{name}, $c->{hidden}, $c->{dense_hidden}, $c->{dropout}, $c->{lr}, $c->{batch_size},
      $r->{epochs_ran}, $r->{best_epoch}, $r->{best_val_mae_avg}, $r->{test_mae_at_best},
      ( $r == $best ? '  <-- ELEGIDO' : '' );
}
printf "[*] grid total %.1fs\n", time() - $t_grid;

copy( $best->{ckpt}, $opt{model} )
  or die "No se pudo copiar $best->{ckpt} -> $opt{model}: $!\n";
print "[*] Mejor checkpoint: $best->{cfg}{name} -> $opt{model}\n";

my $runs_summary = [
    map {
        my $c = $_->{cfg};
        +{
            name              => $c->{name},
            hidden            => $c->{hidden},
            dense_hidden      => $c->{dense_hidden},
            dropout           => $c->{dropout},
            lr                => $c->{lr},
            batch_size        => $c->{batch_size},
            epochs_ran        => $_->{epochs_ran},
            best_epoch        => $_->{best_epoch},
            best_val_mae_avg  => $_->{best_val_mae_avg},
            test_mae_at_best  => $_->{test_mae_at_best},
            history           => $_->{history},
            chosen            => ( $_ == $best ? JSON::PP::true : JSON::PP::false ),
        }
    } @runs
];

my $metrics = final_eval_and_write( $best->{net}, $best->{cfg}{batch_size}, {
    chosen_run => $best->{cfg}{name},
    chosen     => {
        hidden       => $best->{cfg}{hidden},
        dense_hidden => $best->{cfg}{dense_hidden},
        dropout      => $best->{cfg}{dropout},
        lr           => $best->{cfg}{lr},
        batch_size   => $best->{cfg}{batch_size},
        num_layers   => $opt{num_layers},
        seq_len      => $opt{seq_len},
    },
    epochs_ran => $best->{epochs_ran},
    runs       => $runs_summary,
} );

# Comparacion corta contra v2 simple si sus metricas estan disponibles (solo lectura)
my $v2_metrics_path = 'Data/ml_out/lstm_fantasma_v2/metrics_test_v2.json';
if ( -f $v2_metrics_path ) {
    my $v2 = _slurp_json($v2_metrics_path);
    my ( $v2_mae, $v2_f1 ) = ( 0, 0 );
    $v2_mae += $v2->{regression}{$_}{mae}  for @{ $v2->{targets} };
    $v2_f1  += $v2->{binary_full}{$_}{f1}  for @{ $v2->{targets} };
    $v2_mae /= scalar @{ $v2->{targets} };
    $v2_f1  /= scalar @{ $v2->{targets} };
    print "[*] === Comparacion vs v2 simple (test julio) ===\n";
    printf "[*] MAE avg:  v2=%.4f  v2b=%.4f  (delta %+.4f)\n",
      $v2_mae, $metrics->{mae_avg}, $metrics->{mae_avg} - $v2_mae;
    printf "[*] F1 avg:   v2=%.4f  v2b=%.4f  (delta %+.4f)\n",
      $v2_f1, $metrics->{f1_avg}, $metrics->{f1_avg} - $v2_f1;
    for my $t ( @{ $v2->{targets} } ) {
        printf "[*] %s  MAE v2=%.4f v2b=%.4f | F1 v2=%.4f v2b=%.4f\n",
          $t, $v2->{regression}{$t}{mae}, $metrics->{regression}{$t}{mae},
          $v2->{binary_full}{$t}{f1}, $metrics->{binary_full}{$t}{f1};
    }
}

for my $f ( glob "$opt{out_dir}/.ckpt_*.params" ) {
    unlink $f or warn "[!] no se pudo borrar $f: $!\n";
}

print "[*] OK\n";
exit 0;

sub print_usage {
    print <<'USAGE';
train_fantasma_lstm_v2b.pl — LSTM v2b: Dense intermedia relu antes de la salida

  --train PATH         (default Data/ml_out/fantasma_train_norm.csv)
  --test PATH          (default Data/ml_out/fantasma_test_norm.csv)
  --stats PATH         (default Data/ml_out/fantasma_norm_stats.json)
  --out-dir PATH       (default Data/ml_out/lstm_fantasma_v2b)
  --seq-len N          (default 5)
  --batch-size N       (default 32; run individual)
  --hidden N           (default 48; run individual)
  --dense-hidden N     unidades de la Dense intermedia relu (default 24)
  --num-layers N       (default 1)
  --dropout F          (default 0.2; run individual)
  --lr F               (default 0.005; run individual)
  --epochs N           tope de epochs (default 25; early stop corta antes)
  --patience N         epochs sin mejora en val MAE antes de cortar (default 4)
  --min-delta F        mejora minima en val MAE (default 0.0005)
  --val-frac F         fraccion de la cola del train como validacion (default 0.15)
  --seed N             (default 42; misma semilla en cada run del grid)
  --model PATH         (default OUT/fantasma_lstm_v2b.params)
  --grid SPEC          varias configs: "d24:48:24:0.2:0.005:32,d32:48:32:0.2:0.005:32"
                       (name:hidden:dense:dropout:lr:batch)
  --run-name NAME      nombre del run individual (default single)
  --eval-only          cargar modelo y evaluar test (hereda config elegida)
  --binary-thr F       umbral accuracy binaria estilo v1 (default 1)

Misma receta que v2 (val causal 15%, early stop por MAE val, dropout explicito)
con una unica diferencia arquitectonica: LSTM -> ultimo paso -> Dropout ->
Dense(dense_hidden, relu) -> Dense(4). Seleccion por menor MAE val; test julio
solo se reporta. Salida con sufijo _v2b; v1 y v2 no se tocan.
USAGE
}
