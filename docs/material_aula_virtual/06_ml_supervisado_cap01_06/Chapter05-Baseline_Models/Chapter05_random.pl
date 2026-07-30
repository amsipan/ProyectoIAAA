use strict;
use warnings;
use Data::Dump qw(dump);
use sml; # Statistical Machine Learning Library
use AI::MXNet qw(mx);

# Example of Making Random Predictions
# Generate random predictions
sub random_algorithm{
  my ($self, $train, $test) = @_;
  my $output_values = $train->slice_axis(axis=>1, begin=>-1, end=>$train->shape->[-1]);
  my $max_value = $output_values->max->asscalar + 1;
  return mx->nd->random->randint(0, $max_value, shape=> [$test->len]);
}

sml->add_to_class('random_algorithm', \&{'random_algorithm'});

mx->nd->random->seed(1);
my ($dataset, $header) = sml->load_csv('data/iris.csv');
sml->str_column_to_int($dataset, -1);
$dataset = mx->nd->array($dataset);

my ($train, $test) = sml->train_test_split($dataset);
printf "Train: %s\n", $train->slice_axis(axis=>0, begin=>0, end=>5)->aspdl;
printf "Test: %s\n", $test->slice_axis(axis=>0, begin=>0, end=>5)->aspdl;
printf "Test->shape: %s\n", dump $test->shape;

my $predictions = sml->random_algorithm($train, $test);
printf "Random Predictions: %s\n", $predictions->aspdl;

printf "Random Predictions->shape: %s\n", dump $predictions->shape;

print mx->nd->one_hot($predictions, 3)->sum(axis=>0)->aspdl;