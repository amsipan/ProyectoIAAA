use strict;
use warnings;
use Data::Dump qw(dump);
use List::Util qw(zip min max sum uniq);
use sml; # Statistical Machine Learning Library
use AI::MXNet qw(mx);

mx->nd->random->seed(1);

# Function To Make Zero Rule Classification Predictions.
# zero rule algorithm for classification
sub zero_rule_algorithm_classification{
  my ($self, $train, $test) = @_;
  my $output_values = $train->slice_axis(axis=>1, begin=>-1, end=>$train->shape->[-1]);
  my $num_classes   = $output_values->max->asscalar + 1;
  my $count         = mx->nd->one_hot($output_values, $num_classes)->sum(axis=>0);
  my $prediction    = mx->nd->argmax($count);
  return mx->nd->full([$test->len], $prediction->asscalar);
}

sml->add_to_class('zero_rule_algorithm_classification', \&{'zero_rule_algorithm_classification'});

my ($dataset, $header) = sml->load_csv('data/golf.csv');
my @lookup = map{sml->str_column_to_int($dataset, $_)} (0 .. $#{$dataset->[0]});
$dataset = mx->nd->array($dataset);

my ($train, $test) = sml->train_test_split($dataset);

my $predictions = sml->zero_rule_algorithm_classification($train, $test);

printf "predictions: %s\n", $predictions->aspdl;
printf "lookup: %s\n", dump $lookup[-1];


