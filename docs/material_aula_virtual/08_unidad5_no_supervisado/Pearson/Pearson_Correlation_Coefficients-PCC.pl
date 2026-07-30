use strict;
use warnings;
use Data::Dump qw(dump);
use AI::MXNet qw(nd);
use sml qw(show_plot);
# IPerl->load_plugin('Chart::Plotly');

my ($dataset, $header) = sml->load_csv('data/iris.csv');
my ($lookup, $rlookup) = sml->str_column_to_int($dataset, -1);
$dataset = nd->array($dataset);

printf "%d-%s ", $_, $header->[$_] for (0 .. $#$header);
printf "%s\n", dump $lookup, $rlookup;

print $dataset->slice([0, 5])->asstr;

my $X = $dataset->slice(':', [undef, -1]);
printf "%d-%s ", $_, $header->[$_] for (0 .. $#$header -1);
print $X->slice([undef, 5])->asstr;

my $y = $dataset->slice(':', -1);
printf "y: %s", $y->asstr;

printf "Mean: %s\n", nd->mean($X, axis=>0)->asstr;
printf "Deviaton: %s\n", nd->std($X, axis=>0)->asstr;
# Mean: [5.84333   3.054 3.75867 1.19867]
# Deviaton: [0.825301 0.432147 1.75853 0.760613]

# Now, we take any two columns from the dataset, calculate their correlation we plot their points in two dimensions.
my ($X0, $X1, $X2, $X3) = @{$X->T};

printf "Pearson Correlation %s x %s: %s\n", @$header[0, 1], 
       nd->corrcoef($X0, y=>$X1)->asstr;
# Pearson Correlation X0 x X1
#  [[ 1.         -0.10936925]
#  [-0.10936925  1.        ]]

my $color_scale = [
    [0,   'green'],   
    [0.5, 'purple'], 
    [1,   'orange']   
];

my $trace = new Chart::Plotly::Trace::Scatter(
    x      => $X0->aspdl,
    y      => $X1->aspdl,
    mode   => 'markers',
    marker => { 
        color      => $y->aspdl,
        colorscale => $color_scale,  
        cmin       => $y->min,  
        cmax       => $y->max,
        size       => 10
    }
);

my $layout = {title => { text => sprintf('Scatter Plot %s vs %s', @$header[0, 1]) },
              xaxis => { title => $header->[0] }, yaxis => { title => $header->[1] },
              width  => 900, height => 400,
              margin => { l => 50, r => 0, t => 50, b => 50 }};
              
my $plot = new Chart::Plotly::Plot(traces => [$trace],
                                   layout => $layout);

# IPerl->display($plot);
# sml->embed_plot($plot, width=>900, height=>450);#show_plot($plot);
show_plot($plot);

printf "Pearson Correlation %s x %s: %s\n", @$header[0, 2], 
       nd->corrcoef($X0, y=>$X2)->asstr;
# Pearson Correlation X0 x X2
#  [[1.         0.87175416]
#  [0.87175416 1.        ]]

$trace = new Chart::Plotly::Trace::Scatter(
    x      => $X0->aspdl,
    y      => $X2->aspdl,
    mode   => 'markers',
    marker => { 
        color      => $y->aspdl,
        colorscale => $color_scale,  
        cmin       => $y->min,  
        cmax       => $y->max,
        size       => 10
    }
);

$layout = {title => { text => sprintf('Scatter Plot %s vs %s', @$header[0, 2]) },
           xaxis => { title => $header->[0] }, yaxis => { title => $header->[2] },
           width  => 900, height => 400,
           margin => { l => 50, r => 0, t => 50, b => 50 }};
              
$plot = new Chart::Plotly::Plot(traces => [$trace],
                                layout => $layout);
                                
# IPerl->display($plot);
# sml->embed_plot($plot, width=>900, height=>450);
show_plot($plot);

printf "Pearson Correlation %s x %s: %s\n", @$header[0, 3], 
       nd->corrcoef($X0, y=>$X3)->asstr;
# Pearson Correlation X0 x X3
#  [[1.         0.81795363]
#  [0.81795363 1.        ]]

$trace = new Chart::Plotly::Trace::Scatter(
    x      => $X0->aspdl,
    y      => $X3->aspdl,
    mode   => 'markers',
    marker => { 
        color      => $y->aspdl,
        colorscale => $color_scale,  
        cmin       => $y->min,  
        cmax       => $y->max,
        size       => 10
    }
);

$layout = {title => { text => sprintf('Scatter Plot %s vs %s', @$header[0, 3]) },
           xaxis => { title => $header->[0] }, yaxis => { title => $header->[3] },
           width  => 900, height => 400,
           margin => { l => 50, r => 0, t => 50, b => 50 }};
              
$plot = new Chart::Plotly::Plot(traces => [$trace],
                                layout => $layout);

# IPerl->display($plot);
# sml->embed_plot($plot, width=>900, height=>450);
show_plot($plot);

printf "Pearson Correlation %s x %s: %s\n", @$header[1, 2], 
       nd->corrcoef($X1, y=>$X2)->asstr;
# Pearson Correlation X1 x X2
#  [[ 1.        -0.4205161]
#  [-0.4205161  1.       ]]

$trace = new Chart::Plotly::Trace::Scatter(
    x      => $X1->aspdl,
    y      => $X2->aspdl,
    mode   => 'markers',
    marker => { 
        color      => $y->aspdl,
        colorscale => $color_scale,  
        cmin       => $y->min,  
        cmax       => $y->max,
        size       => 10
    }
);

$layout = {title => { text => sprintf('Scatter Plot %s vs %s', @$header[1, 2]) },
           xaxis => { title => $header->[1] }, yaxis => { title => $header->[2] },
           width  => 900, height => 400,
           margin => { l => 50, r => 0, t => 50, b => 50 }};
              
$plot = new Chart::Plotly::Plot(traces => [$trace],
                                layout => $layout);

# IPerl->display($plot);
# sml->embed_plot($plot, width=>900, height=>450);
show_plot($plot);

printf "Pearson Correlation %s x %s: %s\n", @$header[1, 3], 
       nd->corrcoef($X1, y=>$X3)->asstr;
# Pearson Correlation X1 x X3
#  [[ 1.         -0.35654409]
#  [-0.35654409  1.        ]]

$trace = new Chart::Plotly::Trace::Scatter(
    x      => $X1->aspdl,
    y      => $X3->aspdl,
    mode   => 'markers',
    marker => { 
        color      => $y->aspdl,
        colorscale => $color_scale,  
        cmin       => $y->min,  
        cmax       => $y->max,
        size       => 10
    }
);

$layout = {title => { text => sprintf('Scatter Plot %s vs %s', @$header[1, 3]) },
           xaxis => { title => $header->[1] }, yaxis => { title => $header->[3] },
           width  => 900, height => 400,
           margin => { l => 50, r => 0, t => 50, b => 50 }};
              
$plot = new Chart::Plotly::Plot(traces => [$trace],
                                layout => $layout);

# IPerl->display($plot);
# sml->embed_plot($plot, width=>900, height=>450);
show_plot($plot);

printf "Pearson Correlation %s x %s: %s\n", @$header[2, 3],
       nd->corrcoef($X2, y=>$X3)->asstr;
# Pearson Correlation X2 x X3
#  [[1.        0.9627571]
#  [0.9627571 1.       ]]

$trace = new Chart::Plotly::Trace::Scatter(
    x      => $X2->aspdl,
    y      => $X3->aspdl,
    mode   => 'markers',
    marker => { 
        color      => $y->aspdl,
        colorscale => $color_scale,  
        cmin       => $y->min,  
        cmax       => $y->max,
        size       => 10
    }
);

$layout = {title => { text => sprintf('Scatter Plot %s vs %s', @$header[2, 3]) },
           xaxis => { title => $header->[2] }, yaxis => { title => $header->[3] },
           width  => 900, height => 400,
           margin => { l => 50, r => 0, t => 50, b => 50 }};
              
$plot = new Chart::Plotly::Plot(traces => [$trace],
                                layout => $layout);

# IPerl->display($plot);
# sml->embed_plot($plot, width=>900, height=>450);
show_plot($plot);

my $X_normalized = $dataset->slice(':', [0, -1]);
$y = $dataset->slice(':', -1);
# normalize
my $minmax = sml->dataset_minmax($X_normalized);
sml->normalize_dataset($X_normalized, $minmax);
my $normalized = nd->concat($X_normalized, $y->expand_dims(axis=>1));
nd->print("Normalized:", $normalized->slice([0, 5]));

my $corrcoef_normalized = nd->corrcoef($normalized->T);
printf "Pearson Correlation coefficients of the Iris dataset: %s\n", 
        $corrcoef_normalized->asstr;

printf "Pearson Correlation coefficients of X: %s\n", nd->corrcoef($dataset->T)->asstr;
# Pearson Correlation coefficients of X
#  [[ 1.         -0.10936925  0.87175416  0.81795363]
#  [-0.10936925  1.         -0.4205161  -0.35654409]
#  [ 0.87175416 -0.4205161   1.          0.9627571 ]
#  [ 0.81795363 -0.35654409  0.9627571   1.        ]]

# Show a heatmap out of the Pearson Correlation coefficients of X
$trace = new Chart::Plotly::Trace::Heatmap(
    x => $header,
    y => $header,
    z => $corrcoef_normalized->aspdl,
    colorscale => 'Jet', # Electric Greens Greys Hot Jet Picnic Portland Reds YlOrRd YlGnBu
                         # https://plotly.com/javascript/colorscales/#hot-colorscale
);

$layout = {title => { text => 'Heatmap for Pearson Correlation coefficients of Iris dataset' },
           yaxis => { autorange => "reversed" }, # Flip so lower frequencies are at the bottom
           width  => 700, height => 400,
           margin => { l => 50, r => 0, t => 50, b => 50 }};
              
$plot = new Chart::Plotly::Plot(traces => [$trace],
                                layout => $layout);

# IPerl->display($plot);
# sml->embed_plot($plot, width=>900, height=>450);
show_plot($plot);

# load and prepare data
my $filename = '../data/pima-indians-diabetes.csv';
($dataset, $header) = sml->load_csv($filename, asndarray=>1);

$X_normalized = $dataset->slice(':', [0, -1]);
$y = $dataset->slice(':', -1);
# normalize
$minmax = sml->dataset_minmax($X_normalized);
sml->normalize_dataset($X_normalized, $minmax);
$normalized = nd->concat($X_normalized, $y->expand_dims(axis=>1));
printf "Normalized:%s", $normalized->asstr;

$corrcoef_normalized = nd->corrcoef($normalized->T);
printf "Pearson Correlation coefficients of the Diabetes dataset: %s\n", 
        $corrcoef_normalized->asstr;

# standardize
my $X_standardized = $dataset->slice(':', [0, -1]);
# Estimate mean and standard deviation
my $means = sml->column_means($X_standardized);
my $stdevs   = sml->column_stdevs($X_standardized, $means);

# standardize dataset
sml->standardize_dataset($X_standardized, $means, $stdevs);
my $standardized = nd->concat($X_standardized, $y->expand_dims(axis=>1));
print $standardized->asstr;

my $corrcoef_standardized = nd->corrcoef($standardized->T);
printf "Pearson Correlation coefficients of the Diabetes dataset: %s\n", 
        $corrcoef_standardized->asstr;

printf "%d-%s ", $_, $header->[$_] for (0 .. $#$header);

# Show a heatmap out of the Pearson Correlation coefficients of X
$trace = new Chart::Plotly::Trace::Heatmap(
    x => $header,
    y => $header,
    z => nd->corrcoef($normalized->T)->aspdl,
    colorscale => 'YlOrRd', # Electric Greens Greys Hot Jet Picnic Portland Reds YlOrRd YlGnBu
                            # https://plotly.com/javascript/colorscales/#hot-colorscale
);

$layout = {title => { text => 'Heatmap for Pearson Correlation coefficients of the Diabetes dataset' },
           yaxis => { autorange => "reversed" }, # Flip so lower frequencies are at the bottom
           width  => 700, height => 400,
           margin => { l => 50, r => 0, t => 50, b => 50 }};
              
$plot = new Chart::Plotly::Plot(traces => [$trace],
                                layout => $layout);

# IPerl->display($plot);
# sml->embed_plot($plot, width=>900, height=>450);
show_plot($plot);

