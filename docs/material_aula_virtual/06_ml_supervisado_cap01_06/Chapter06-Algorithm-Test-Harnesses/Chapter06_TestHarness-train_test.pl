use strict;
use warnings;
use Data::Dump qw(dump);
use List::Util qw(zip min max sum uniq);
use sml; # Statistical Machine Learning Library
use AI::MXNet qw(mx);

# Test the train/test harness
mx->nd->random->seed(1);
# load and prepare data
my $filename = './data/pima-indians-diabetes.csv';
my ($dataset, $header) = sml->load_csv($filename);
$dataset = mx->nd->array($dataset);

my $split = 0.6;

my ($train, $test) = sml->train_test_split($dataset, split=>$split);

my $algorithm = \&{'sml::zero_rule_algorithm_classification'};

my $predicted = $algorithm->('sml', $train, $test, split => $split,
                                                   metric => 'accuracy');

my $actual = $test->slice_axis(axis=>1, begin=>-1, end=>$test->shape->[-1])->squeeze();

print $actual;

my $score = mx->nd->sum($actual->trunc - $actual)->asscalar != 0 ?
sml->rmse_metric($actual, $predicted) :
sml->accuracy_metric($actual, $predicted);

print $score;

my ($unique, $matrix) = sml->confusion_matrix($actual, $predicted);
sml->print_confusion_matrix($unique, $matrix);
