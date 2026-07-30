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

my $n_folds=10;

my @folds = @{sml->cross_validation_split($dataset, n_folds=>$n_folds)};
my @train_set = @folds;

#print @folds;

my $i = 0;
my $test_set = $folds[$i];
splice @train_set, $i, 1;
my $train_set = mx->nd->concat(@train_set, dim=>0);
print $train_set;

my $algorithm = \&{'sml::zero_rule_algorithm_classification'};

  my ($predicted, $train_loss, $test_loss) = $algorithm->('sml', 
                                            $train_set, $test_set, @_);
  
my $actual = $test_set->slice_axis(axis=>1, begin=>-1, end=>$test_set->shape->[-1])->squeeze();

print $predicted->aspdl;


