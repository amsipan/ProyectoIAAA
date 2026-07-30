use strict;
use warnings;
use List::Util qw(zip);
use sml;
use AI::MXNet qw(mx);
use Chart::Plotly qw(show_plot);
use Chart::Plotly::Plot;
use Chart::Plotly::Trace::Scatter;

# Function to calculate the ROC metrics by using one-hot encoding and dot product
sub perf_metrics{
  my ($self, $actual, $predicted_prob, $threshold) = @_;

  my ($tp, $fp, $tn, $fn, $tpr, $fpr) = (0, 0, 0, 0);
  
  # Step 1: Threshold to create binary predictions
  my $predicted = $predicted_prob >= $threshold;

  # Step 2: Convert actual and predicted to one-hot encoded matrices
  my $num_classes       = $actual->max->asscalar + 1;
  my $actual_one_hot    = mx->nd->one_hot($actual, $num_classes);    # Shape [n, $num_classes]
  my $predicted_one_hot = mx->nd->one_hot($predicted, $num_classes); # Shape [n, $num_classes]

  # Step 3: Compute confusion matrix using dot product
  my $confusion_matrix  = mx->nd->dot($actual_one_hot->T, $predicted_one_hot);

  # Extract counts from the confusion matrix
  $tp = $confusion_matrix->at(0, 0)->asscalar; # True Positives
  $fn = $confusion_matrix->at(0, 1)->asscalar; # False Negatives
  $fp = $confusion_matrix->at(1, 0)->asscalar; # False Positives
  $tn = $confusion_matrix->at(1, 1)->asscalar; # True Negatives

  # Step 4: Compute TPR and FPR
  $tpr = $tp / ($tp + $fn); # True Positive Rate
  $fpr = $fp / ($fp + $tn); # False Positive Rate

  return sprintf('%0.2f', $fpr), sprintf('%0.2f', $tpr);
}

sml->add_to_class('perf_metrics', \&{'perf_metrics'});

my ($dataset, $header) = sml->load_csv('data/model.csv');
$dataset = mx->nd->array($dataset);

my (undef, $actual, $predicted_prob) = @{$dataset->T};

printf "class: %s\n",        $actual->slice(begin=>0, end=>5)->aspdl;
printf "predicted_prob: %s\n", $predicted_prob->slice(begin=>0, end=>5)->aspdl;

# Calculate TPR and FPR for a specific threshold
my ($fpr, $tpr) = sml->perf_metrics($actual, $predicted_prob, 0.5);

# Print sensitivity and specificity
printf "tpr: %s, 1 - fpr: %s\n", $tpr, 1 - $fpr;

# Calculate TPR and FPR for various decision thresholds
my $thresholds = mx->nd->arange(stop=>101) / 100;
printf "thresholds: %s\n", $thresholds->slice(begin=>0, end=>5)->aspdl;

my ($fprs, $tprs) = (zip map {[sml->perf_metrics($actual, $predicted_prob, $_)]} @$thresholds);

printf "fprs:%s\n", "@$fprs";
printf "tprs:%s\n", "@$tprs";

# Plot the ROC curve using Chart::Plotly
my $trace1 = new Chart::Plotly::Trace::Scatter(
  x => $fprs,
  y => $tprs,
  mode => 'lines',
  name => 'ROC Curve'
);

my $trace2 = new Chart::Plotly::Trace::Scatter(
  x => [0, 1],
  y => [0, 1],
  mode => 'lines',
  name => 'Reference Curve'
);

my $chart = new Chart::Plotly::Plot(
  traces => [$trace1, $trace2],
  layout => {
    title => 'ROC curve',
    xaxis => { title => 'False Positive Rate (FPR)' },
    yaxis => { title => 'True Positive Rate (TPR)' }
  }
);

# Show the graph directly in IPerl
show_plot($chart);

