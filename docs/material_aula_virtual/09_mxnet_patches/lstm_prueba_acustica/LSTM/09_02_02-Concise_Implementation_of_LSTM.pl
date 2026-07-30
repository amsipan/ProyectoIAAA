use strict;
use warnings;
use Data::Dump qw(dump);
use List::Util qw(zip);
use AI::MXNet qw(mx nd);
use sml qw(show_plot);

my $batch_size = 128;
#https://mxnet.apache.org/versions/1.7/api/python/docs/api/gluon/rnn/index.html
#https://mxnet.apache.org/versions/1.2.1/api/python/gluon/rnn.html

my $train_file_name = "data/VAD_data/201703211831/VAD_train1.csv";
my ($train_data, $train_header, $train_header_idx) = sml->load_csv($train_file_name);
my $row = $train_data->[0];
printf "%s\n", join " ", map { "$_-$train_header->[$_]" } 0 .. $#$train_header;
printf "%s\n", join " ", map { "$_-$row->[$_]" } 0 .. $#$row;

# Converts last label into an integer
my $lookup = { pause => 0, speech => 1 };
($lookup, my $rlookup) = sml->str_column_to_int($train_data, -1, lookup => $lookup);
printf "lookup: %s\n", dump $lookup;

# Separates the metadata columns
my $metadata_train = [ map { [ @{$_}[0 .. 1] ] } @$train_data ];
my $train = [ map { [ @{$_}[2 .. 22] ] } @$train_data ];

printf "metadata_train: %s\n", dump $metadata_train->[0];
$train = nd->array($train);
nd->printf("Train: %.1f", $train->slice(0));

# Doing the same for the test data:
my $test_file_name = "data/VAD_data/202003021300/VAD_test1.csv";
my ($test_data, $test_header, $test_header_idx) = sml->load_csv($test_file_name);
sml->str_column_to_int($test_data, -1, lookup => $lookup);
# Separates the metadata columns
my $metadata_test = [ map { [ @{$_}[0 .. 1] ] } @$test_data ];
my $test = [ map { [ @{$_}[2 .. 22] ] } @$test_data ];
printf "metadata_test: %s\n", dump $metadata_test->[0];
$test = nd->array($test);

my $X_train = $train->slice(':', [0, -1]);
my $X_test  = $test->slice(':', [0, -1]);
printf "train: %s\n", $X_train;
printf "test: %s\n", $X_test;

nd->printf("Train:\n%.2f", $X_train->slice(0));
nd->printf("Test:\n%.2f", $X_test->slice(0));

# Standardize $X_train
my $all_data = nd->concat($X_train, $X_test, dim=>0);
my $X_means  = nd->mean($all_data, axis=>0);
my $X_stdevs = nd->std($all_data, axis=>0, ddof=>1);
sml->standardize_dataset($X_train, $X_means, $X_stdevs);
nd->printf("Train:\n%.2f", $X_train->slice(0));

# Standardize $X_test
sml->standardize_dataset($X_test, $X_means, $X_stdevs);
nd->printf("Test:\n%.2f", $X_test->slice(0));

my $y_train = $train->slice(':', -1)->astype('int8');
my $y_test  = $test->slice(':', -1)->astype('int8');
printf "train: %s\n", $y_train;
printf "test: %s\n", $y_test;

# sub make_sequences {
#  my ($X, $y, $seq_len) = @_;
#
#  my $N = $X->shape->[0];
#  my $base = nd->arange($N-$seq_len+1)->reshape([-1, 1]);
#  my $offset = nd->arange($seq_len)->reshape([1, -1]);
#  my $idx = $base + $offset;
#  my $X_seq = nd->take($X, $idx);
#  my $y_seq = nd->take($y, $idx);
#
#  return ($X_seq, $y_seq);
# }

sub make_sequences {
  my ($X, $y, $seq_len) = @_;

  my $N      = $X->len;
  my $base   = nd->arange($N-$seq_len+1)->reshape([-1, 1]);
  my $offset = nd->arange($seq_len)->reshape([1, -1]);
  my $idx    = $base + $offset;
  my $X_seq  = nd->take($X,$idx);
  my $y_seq  = $y->slice([$seq_len-1, $N])->sever;

  return ($X_seq, $y_seq);
}

my $seq_len = 5;
my ($X_train_seq, $y_train_seq) = make_sequences($X_train, $y_train, $seq_len);
my ($X_test_seq, $y_test_seq)   = make_sequences($X_test, $y_test, $seq_len);

nd->printf("X_train_seq->shape: %s", $X_train_seq->shape);
nd->printf("y_train_seq->shape: %s", $y_train_seq->shape);

nd->printf("X_train->slice([0, 2]:\n%.2f", $X_train_seq->slice([0, 2]));
nd->printf("y_train->slice([0, 2]:\n%.2f", $y_train_seq->slice([0, 2]));

sub load_array{ #@save
  # Construct a Gluon data iterator.
  my ($data_arrays, $batch_size, %args) = (splice (@_, 0, 2),
                                                   is_train => 1,
                                                   last_batch => 'keep', @_);
  my ($X, $y) = @$data_arrays;
  my $dataset = mx->gluon->data->ArrayDataset(data  => $X, 
                                              label => $y);
  
  return mx->gluon->data->DataLoader($dataset, 
                                     batch_size => $batch_size, 
                                     shuffle    => $args{is_train},
                                     # 'keep', 'discard', 'rollover'
                                     last_batch => $args{last_batch} // 'discard');
}

package LSTM {
  use strict;
  use warnings;
  use Data::Dump qw(dump);
  use AI::MXNet qw(mx);
  use base ("AI::MXNet::Gluon::Block");
  
  sub new{
    my ($class, %args) = @_;

    my $self = $class->SUPER::new(%args);                                  
    #$self->{model} = mx->gluon->nn->Sequential();
    #$self->{model}->add(mx->gluon->rnn->LSTM(hidden_size   => $args{hidden_units}, 
    #                                         num_layers    => $args{num_layer}     // 1,
    #                                         layout        => $args{layout}        // 'NTC',
    #                                         dropout       => $args{dropout}       // 0,
    #                                         bidirectional => $args{bidirectional} // 0,
    #                                         input_size    => $args{input_size} #C from NT'C'
    #                                         ));
    #
    #$self->{model}->add(mx->gluon->nn->Dense(units         => $args{units},
    #                                         in_units      => $args{in_units},
    #                                         flatten       => 0,
    #                                         #activation   => 'tanh'
    #                                         ));
    #$self->register_child($self->{model});
    
    $self->{lstm} = mx->gluon->rnn->LSTM(hidden_size   => $args{hidden_units}, 
                                             num_layers    => $args{num_layer}     // 1,
                                             layout        => $args{layout}        // 'NTC',
                                             dropout       => $args{dropout}       // 0,
                                             bidirectional => $args{bidirectional} // 0,
                                             input_size    => $args{input_size} #C from NT'C'
                                             );
    
    $self->{dense} = mx->gluon->nn->Dense(units         => $args{units},
                                             in_units      => $args{in_units},
                                             flatten       => 0,
                                             #activation   => 'tanh'
                                             );
    
    map{$self->register_child($self->{$_})} ('lstm', 'dense');
    
    return bless($self, $class);
  }
  
  #sub forward {
  #  my ($self, $X) = @_;
  #  return $self->{model}->forward($X);
  #}
  
  sub forward {
    my ($self, $X) = @_;

    my $H = $self->{lstm}->forward($X);

    # H : [batch_size, seq_len, num_hidden]

    $H = $H->slice(':', -1, ':')->sever; # materialized slice. -1 preserves just the last prediction of the sequence

    # H : [batch_size, num_hidden]

    return $self->{dense}->forward($H);
  }

  1;
}

my $net = new LSTM(hidden_units  => 8,
                   num_layer     => 1,
                   layout        => 'NTC',
                   dropout       => 0.2,
                   bidirectional => 0,
                   input_size    => $X_train_seq->shape->[-1], # Feature dimensions C from NTC'.
                   units         => 2,  # number of classes.
                   in_units      => 8); # matches with hidden_units. Double it if bidirectional => 1.

# print $net->{model};
print join "\n", map{$net->{$_}} ('lstm', 'dense');

my $train_iter = load_array([$X_train_seq, $y_train_seq], $batch_size, is_train => 1, last_batch => 'rollover');
my $test_iter  = load_array([$X_test_seq, $y_test_seq], $batch_size, is_train => 0, last_batch => 'keep');

$net->collect_params->initialize(init => mx->init->Xavier(), force_reinit => 1);
#$net->collect_params->initialize(init => mx->init->Xavier(magnitude=>2), force_reinit => 1);
#$net->collect_params->initialize(init => mx->init->Normal(sigma => 0.01), force_reinit => 1);


sub train_epoch_ch3{
  # Train a model within one epoch (defined in Chapter 3).
  # Sum of training loss, sum of training accuracy, no. of examples
  my ($net, $train_iter, $loss, $updater) = @_;
  
  my ($y_hat, $l, $X, $y);

  while ( my $batch = <$train_iter> ) {
    ($X, $y) = @$batch;
    # Computes gradients and updates parameters

    mx->autograd->record(sub {
      $y_hat = $net->($X);
      $l     = $loss->($y_hat, $y->astype('float32'));
    });
    $l->backward();
    
    $updater->step($X->len);
  }
}

sub train_ch3{
  # Train a model (defined in Chapter 3).
  my ($net, $train_iter, $test_iter, $loss, $num_epochs, $updater) = @_;

  my (@train_metrics, $test_acc);
  for (my $epoch = 0; $epoch < $num_epochs; $epoch++){
    train_epoch_ch3($net, $train_iter, $loss, $updater);
  }
}

my $lr   = 0.01;
my $loss = mx->gluon->loss->SoftmaxCrossEntropyLoss();

my $trainer = mx->gluon->Trainer($net->collect_params(), 
                                 optimizer => 'adam', # sgd
                                 optimizer_params=>{ learning_rate => $lr });#, clip_gradient => 0.0

my ($train_model, $num_epochs, $animator, $model_file_name) = (1, 1, undef, '09_02_02-Concise_Implementation_of_LSTM.mdl');

if ($train_model){
  train_ch3($net, $train_iter, $test_iter, $loss,  $num_epochs, $trainer);
  $net->save_parameters($model_file_name);
}else{
  $net->load_parameters($model_file_name);
}

sub get_probs {
  my ($net, $data_iter, $batch_size, $seq_len) = @_;

  my $hidden_state = $net->begin_state($batch_size);
  my (@logits, $y_hat, $X, $y);
  while(my $batch = <$data_iter>){
    ($X, $y) = @$batch;
    ($y_hat, $hidden_state) = $net->forward($X, $hidden_state);
    push @logits, $y_hat;
  }
  
  # Assumes the first predictions are repeated because seq_len just predicts the last element of a sequence given the previous as context
  my $first_logits = nd->tile($logits[0]->slice(0), reps => $seq_len -1)->reshape([$seq_len -1, -1]);
  my $logits = nd->concat($first_logits, @logits, dim=>0);
  return nd->softmax($logits, axis => 1);
}

my $probs = get_probs($net, $test_iter, $batch_size, $seq_len);
my $mask = ($probs + 0.1) > 0.6;
my $preds = $mask->argmax(axis => 1)->astype('int8');
my @preds = map {$rlookup->{$_}} $preds->tolist;
print dump @preds[150 .. 200];

my $both = nd->concat($y_test->expand_dims(axis=>1), $preds->expand_dims(axis=>1), dim=>1);
print $both;
nd->printf("Actual\tPredictions:\n%s", $both->slice([30, 80]));
my $accuracy = sml->accuracy_metric($y_test, $preds);
printf 'Accuracy: %0.2f%%', $accuracy;

my ($clases, $matrix) = sml->confusion_matrix($y_test, $preds);
printf "clases: %s\n", $clases->asstr;
nd->printf("confusion matrix:\n%s\n", $matrix);

# Test MAE
my $mae = sml->mae_metric($y_test, $preds);
printf "mae:%s\n", $mae;


# Test RMSE
my $rmse   = sml->rmse_metric($y_test, $preds);
printf "rmse:%s\n", $rmse;

  
my $pause_probs  = $probs->slice(':', 0);
my $speech_probs = $probs->slice(':', 1);

my $positive_class = 0;
my $positive_probs = $probs->slice(':', $positive_class);

# Calculate TPR and FPR for a specific threshold
(my $fpr, my $tpr, $matrix) = sml->perf_metrics($y_test, $positive_probs, 0.5, positive_class=>$positive_class);

# Print sensitivity and specificity
printf "tpr: %s, 1 - fpr: %s\n", $tpr->asstr, (1 - $fpr)->asstr;
printf "confusion matrix:\n%s\n", $matrix->asstr;
# tpr: 0.77, 1 - fpr: 0.69 where positive_class => 1
# tpr: 0.69, 1 - fpr: 0.77 where positive_class => 0

# Calculate TPR and FPR for various decision thresholds
my $thresholds = nd->arange(101) / 100;
nd->printf("thresholds: %.2f\n", $thresholds->slice([0, 5]));

# 1. Execute loop over thresholds - returning arrays of tensors
my ($fprs_array, $tprs_array) = (zip map { 
    my ($f, $t) = sml->perf_metrics($y_test, $positive_probs, $_, positive_class=>$positive_class);
    [$f, $t];
} @$thresholds);

# 2. Stack the tensor pieces into continuous vectors 
# (No string-to-number casting overhead!)
my $fprs = nd->concat(@$fprs_array, dim=>0);
my $tprs = nd->concat(@$tprs_array, dim=>0);

# 3. Print the results with your perfect numpy-style visual alignment
printf "fprs vector:\n%s\n", $fprs->slice([0, 10])->asstr;
printf "tprs vector:\n%s\n", $tprs->slice([0, 10])->asstr;

# 1. Obtain the indices that sorts the FPR tensor in ascending order
my $sorted_indices = nd->argsort($fprs, axis=>0);

# 2. Sort both vectors using nd->take over the $sorted_indices
my $sorted_fprs = nd->take($fprs, $sorted_indices);
my $sorted_tprs = nd->take($tprs, $sorted_indices);

# 3. Visual verification of the sort of FPR aligned with TPR
printf "sorted fprs:\n%s\n", $sorted_fprs->slice([20, 30])->asstr;
printf "sorted tprs:\n%s\n", $sorted_tprs->slice([20, 30])->asstr;

# Calculate the area under the ROC curve (AUC) using the trapezoid rule
my $auc = sml->trapz($sorted_fprs, $sorted_tprs);
printf "Area under the ROC curve (AUC) for %s prediction: %0.2f\n", $rlookup->{$positive_class}, $auc;

# Plot the ROC curve using Chart::Plotly
my $trace1 = new Chart::Plotly::Trace::Scatter(
  x => $sorted_fprs->aspdl,
  y => $sorted_tprs->aspdl,
  mode => 'lines',
  name => 'ROC Curve'
);

my $trace2 = new Chart::Plotly::Trace::Scatter(
  x => [0, 1],
  y => [0, 1],
  mode => 'lines',
  name => 'Reference Curve'
);

my $plot = new Chart::Plotly::Plot(
  traces => [$trace1, $trace2],
  layout => {
    title => sprintf('ROC curve for %s prediction', $rlookup->{$positive_class}),
    xaxis => { title => 'Specificity: False Positive Rate (FPR)' },
    yaxis => { title => 'Sensitivity: True Positive Rate (TPR)' }
  }
);

# Show the graph directly in IPerl
show_plot($plot);