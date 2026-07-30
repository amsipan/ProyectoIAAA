# Todo programa que usted desarrolle debe cargar las siguientes librerías:
use strict;
use warnings;
use Data::Dump qw(dump);
use AI::MXNet qw(mx);
use sml;

my $filename = '../../data/pima-indians-diabetes.csv';
my $dataset = sml->load_csv($filename);
$dataset = mx->nd->array($dataset);

my $dataset_cols = $dataset->slice_axis(axis=>1, begin=>0, end=>-1);
print $dataset_cols->slice_axis(axis=>0, begin=>0, end=>4)->aspdl;

# ->min(), ->max()
printf "min %s\n", $dataset_cols->min(axis=>0)->aspdl;
printf "max %s\n", $dataset_cols->max(axis=>0)->aspdl;

# ->stack()

# Function To Calculate the Min and Max Values For a Dataset.
# Find the min and max values for each column
sub dataset_minmax{
 my ($self, $dataset) = @_;
 mx->nd->stack($dataset->min(axis=>0), $dataset->max(axis=>0))->transpose;
}
sml->add_to_class('dataset_minmax', \&{'dataset_minmax'});

my $minmax = sml->dataset_minmax($dataset_cols);
print $minmax->transpose->aspdl;


# Function To Normalize a Dataset.
# Rescale dataset columns to the range 0-1
sub normalize_dataset{
 my ($self, $dataset, $minmax) = @_;
 my ($min, $max) = @{$minmax->transpose};
 ($dataset - $min) / ($max - $min);
}
sml->add_to_class('normalize_dataset', \&{'normalize_dataset'});

my $normalized = sml->normalize_dataset($dataset_cols, $minmax);
printf "Normalized: %s\n", $normalized->slice(begin=>[0,0], end=>[4, 8])->aspdl;

# Function To Calculate Means For Each Column in a Dataset.
# Calculate column means
sub column_means{
 my ($self, $dataset) = @_;
 $dataset_cols->mean(axis=>0);
}

my $means = sml->column_means($dataset_cols);
printf "mean: %s\n", $means->aspdl;
# Standardize Data

# Function To Calculate Standard Deviations For Each Column in a Dataset.
# Calculate column standard deviations
sub column_stdevs{
  my ($self, $dataset, $means) = @_;
  mx->nd->sqrt(($dataset - $means)->power(2)->sum(axis=>0) / ($dataset_cols->len -1));
}
sml->add_to_class('column_stdevs', \&{'column_stdevs'});

my $stdevs = sml->column_stdevs($dataset_cols, $means);
printf "stdev: %s\n", $stdevs->aspdl;

# Function To Standardize a Dataset.
# Standardize dataset
sub standardize_dataset{
 my ($self, $dataset, $means, $stdevs) = @_;
 ($dataset - $means) / $stdevs;
}
sml->add_to_class('standardize_dataset', \&{'standardize_dataset'});

my $standardized = sml->standardize_dataset($dataset_cols, $means, $stdevs);

printf "Standardized:%s\n", $standardized->slice(begin=>[0,0], end=>[4, 8])->aspdl;
