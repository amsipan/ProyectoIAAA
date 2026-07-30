# Todo programa que usted desarrolle debe cargar las siguientes librerías:
use strict;
use warnings;
use Data::Dump qw(dump);
use AI::MXNet qw(mx);
use sml;

mx->random->seed(1);
my $dataset = mx->nd->array([[1], [2], [3], [4], [5], [6], [7], [8], [9], [10]]);
my $split= 0.6;


# Defined in Section 3.2.1 Train and Test Split
# Function To Split a Dataset.
# Split a dataset into a train and test set
sub train_test_split{
 my ($self, $dataset, %args) = (splice (@_, 0, 2), split=>0.6, @_);

  my $train_size = int($args{split} * $dataset->len);
  my $idx = mx->nd->arange(stop=>$dataset->len)->shuffle;
  #printf "idx: %s\n", $idx->aspdl;
  
  my $train_idx = $idx->slice(begin=>0, end=>$train_size);
  #printf "train_idx: %s\n", $train_idx->aspdl;
  
  my $test_idx = $idx->slice(begin=>$train_size, end=>$dataset->len);
  #printf "test_idx: %s\n", $test_idx->aspdl;
  
  # ->take()
  my $train = mx->nd->take($dataset, $train_idx);
  #printf "train: %s\n", $train->aspdl;
  
  my $test = mx->nd->take($dataset, $test_idx);
  #printf "test: %s\n", $test->aspdl;

  return $train, $test;
}
sml->add_to_class('train_test_split', \&{'train_test_split'});

my ($train, $test) = sml->train_test_split($dataset);

printf "train: %s\n", $train->aspdl;
printf "test: %s\n", $test->aspdl;


# Defined in Section 3.2.2 k-fold Cross-Validation Split
# Function Create A Cross-Validation Split.
# Split a dataset into $ k $ folds
sub cross_validation_split{
 my ($self, $dataset, %args) = (splice (@_, 0, 2), n_folds=>10, @_);
 my @dataset_split;
 my $fold_size = int($dataset->len / $args{n_folds});
 my $idx = mx->nd->arange(stop=>$dataset->len)->shuffle;

  for my $i (0 .. $args{n_folds} -1){
    my $fold_idx = $idx->slice(begin=>$i * $fold_size, end=> ($i +1) * $fold_size);
    push @dataset_split, mx->nd->take($dataset, $fold_idx);
  }

 return mx->nd->stack(@dataset_split);
}
sml->add_to_class('cross_validation_split', \&{'cross_validation_split'});

my $folds = sml->cross_validation_split($dataset);
# print $folds->aspdl;

($dataset, my $header) = sml->load_csv('../../data/iris.csv');

my $lookup = sml->str_column_to_int($dataset, -1);
my $rev_lookup = {reverse %$lookup};

$dataset = mx->nd->array($dataset);
my $labels = $dataset->slice_axis(axis=>1, begin=>-1, end=>$dataset->at(0)->len)->squeeze(axis=>1);
print $labels->aspdl;
my $num_clases = $labels->max->asscalar + 1;

print mx->nd->one_hot($labels, $num_clases)->sum(axis=>0)->aspdl;







