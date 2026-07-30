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

my $X = $dataset->slice(':', [undef, -1]);
my $y = $dataset->slice(':', -1);

printf "%d-%s ", $_, $header->[$_] for (0 .. $#$header -1);
nd->print("\nX: ", $X->slice([undef, 5]));
nd->print("y:\n", $y);

nd->print('Mean: ', $X->mean(axis=>0));
nd->print('Deviation: ', $X->std(axis=>0));

my $X_normalized = $X;
my $minmax = sml->dataset_minmax($X_normalized);
nd->print("Matriz Min-Max por columna:", $minmax);

# normalize
sml->normalize_dataset($X_normalized, $minmax);
my $normalized = nd->concat($X_normalized, $y->expand_dims(axis=>1));
nd->print("Normalized:", $normalized->slice([0, 5]));

my $mean_data = $X_normalized - nd->mean($X_normalized, axis=>0);
print $mean_data->slice([0, 5])->asstr;

# Compute covariance matrix
my $cov_matrix = nd->cov($mean_data->T, dtype => 'float32');
# $cov_matrix  = nd->_npi_around($cov_matrix, 3);
nd->print("Covariance matrix:", $cov_matrix);

# Perform eigen decomposition of covariance matrix
# my ($eig_vals, $eig_vec) = nd->linalg->eig($cov_matrix);
my ($eig_vals, $eig_vec) = @{nd->_npi_eig($cov_matrix)};
nd->printf("Eigen values:\n%.6f\n", $eig_vals);
nd->printf("Eigen vectors:\n%.6f\n", $eig_vec);

# Eigen values  [0.23231168 0.03239279 0.00963728 0.00175337] 

# Eigen vectors 
# [[ 0.4252893  -0.42100611 -0.71434339  0.36276216]
#  [-0.14612219 -0.90470509  0.33510219 -0.21877734]
#  [ 0.61610511  0.06432645 -0.06825927 -0.78205964]
#  [ 0.64667752  0.01116485  0.61054133  0.45708076]]

# Sort eigen values and vectors in descending order
my $sort_idx      = nd->argsort($eig_vals)->reverse(axis=>0);
my $sort_eig_vals = nd->take($eig_vals, $sort_idx);
my $sort_eig_vec  = nd->take($eig_vec->T, $sort_idx);

nd->printf("Sorted Eigen values:\n%.6f\n", $sort_eig_vals);
nd->printf("Sorted Eigen vectors:\n%.6f\n", $sort_eig_vec);

# Sorted Eigen values  [0.23231168 0.03239279 0.00963728 0.00175337] 

# Sorted Eigen vectors
# [[ 0.4252893  -0.14612219  0.61610511  0.64667752]
#  [-0.42100611 -0.90470509  0.06432645  0.01116485]
#  [-0.71434339  0.33510219 -0.06825927  0.61054133]
#  [ 0.36276216 -0.21877734 -0.78205964  0.45708076]]

# Get explained variance
my $explained_variance = $sort_eig_vals / $sort_eig_vals->sum();
nd->print("Explained variance:", $explained_variance); 
my $cumulative_variance = nd->cumsum($explained_variance);
nd->print("cumulative_variance:", $cumulative_variance);

# explained_variance: [0.84141901 0.11732474 0.03490564 0.00635061]
# cumulative_variance: [0.84141901 0.95874375 0.99364939 1.        ]

my $pca_data = nd->dot($mean_data, $sort_eig_vec);
nd->printf("Transformed data:\n%.6f\n", $pca_data->slice([0, 5]));

# Transformed data:
# [[-0.03142478 -0.1808823   0.23745169 -0.56572707]
#  [ 0.03265764  0.01571582  0.18982228 -0.60397961]
#  [-0.01394587 -0.05723807  0.1621117  -0.64932389]
#  [-0.03243257 -0.00412367  0.14000352 -0.64705604]
#  [-0.06078029 -0.2145194   0.22301793 -0.58322513]]

package PCA{
  use strict;
  use warnings;
  use AI::MXNet qw(nd);
  
  sub new{
    my ($class, %args) = (shift, n_components => undef, @_);
    
    my $self = {
      n_components   => $args{n_components},
      components     => undef,
      mean           => undef,
      variance_share => undef,
      chosen_columns => undef,
    };
        
    return bless($self, $class);
  }

  sub fit{
    my ($self, $X) = @_;
    
    # 1. Copia no destructiva y centrado de datos (Evita mutar el X original)
    $self->{mean}  = nd->mean($X, axis => 0);
    my $X_centered = $X - $self->{mean};

    # Si n_components es undef, asignamos dinámicamente el máximo posible
    $self->{n_components} //= $X_centered->shape->[1];
    
    # 2. Matriz de Covarianza balanceada por (N - 1)
    my $cov_matrix = nd->cov($X_centered->T, dtype => 'float32');

    # Eigenvalues, eigenvectors
    # my ($eig_vals, $eig_vec) = nd->linalg->eig($cov_matrix);
    my ($eig_vals, $eig_vec) = @{nd->_npi_eig($cov_matrix)};
    $eig_vals = $eig_vals->astype("float32");
    $eig_vec  = $eig_vec->astype("float32");

    # Sort eigen values and vectors in descending order
    my $sort_idx      = nd->argsort($eig_vals)->reverse(axis=>0);
    my $sort_eig_vals = nd->take($eig_vals, $sort_idx);
    my $sort_eig_vec  = nd->take($eig_vec->T, $sort_idx);

    # store principal components & variance
    $self->{chosen_columns} = $sort_idx->slice([0, $self->{n_components}]);
    $self->{components}     = $sort_eig_vec->slice([0, $self->{n_components}]);
    $self->{variance_share} = nd->sum($sort_eig_vals->slice([0, $self->{n_components}])) 
                              / nd->sum($sort_eig_vals);
  }

  sub transform {
    my ($self, $X) = @_;
    die "The PCA model has not yet been trained. First run 'fit()'." 
        unless defined $self->{components};
    
    # Operación no destructiva de centrado para la proyección
    my $X_centered = $X - $self->{mean};
    
    return nd->dot($X_centered, $self->{components}->T);
  }
  
  # =========================================================================
  # Model parameters persistency
  # =========================================================================

  sub save_model {
    my ($self, $filename) = @_;
    die "No hay parámetros entrenados para guardar." if !defined $self->{components};
    $filename //= 'pca_model.ndarray';

    # Creamos un hash intermedio de tensores compatibles con nd->save
    my $save_data = {
        'n_components'   => nd->array([$self->{n_components}]),
        'components'     => $self->{components}->sever, # materializes slice
        'mean'           => $self->{mean},
        'variance_share' => $self->{variance_share},
        'chosen_columns' => $self->{chosen_columns}->sever, # materializes slice
    };
    
    # Guarda el diccionario estructurado en un archivo binario
    nd->save($filename, $save_data);
    
    return 1;
  }

  sub load_model {
    my ($self, $filename) = @_;
    $filename //= 'pca_model.ndarray';
    die "El archivo de modelo '$filename' no existe." unless -e $filename;

    # Retorna una referencia a un hash con los mismos nombres de llaves
    my $loaded_data = nd->load($filename);

    # Alimenta las propiedades del objeto con los NDArrays recuperados
    $self->{n_components}   = int($loaded_data->{'n_components'}->asscalar);
    $self->{components}     = $loaded_data->{'components'};
    $self->{mean}           = $loaded_data->{'mean'};
    $self->{variance_share} = $loaded_data->{'variance_share'};
    $self->{chosen_columns} = $loaded_data->{'chosen_columns'};
    
    return 1;
  }
  
  1;
};

nd->printf("Normalized data:\n%.6f\n", $X_normalized->slice(end=>5));

# Project the dataset onto the 2 primary principal components
my $pca = new PCA(n_components=>2);
$pca->fit($X_normalized);
my $X_PCA = $pca->transform($X_normalized);

printf "Shape of X: %s\n", dump $X_normalized->shape;
printf "Shape of transformed X: %s\n", dump $X_PCA->shape;
printf "Variance share: %s\n", $pca->{variance_share}->asstr('%.2f');
printf "Chosen columns: %s\n", $pca->{chosen_columns}->asstr;

# Shape of X: (150, 4)
# Shape of transformed X: (150, 2)
# Variance share:  0.9587437487644828
# Chosen columns:  [0 1]

nd->printf("PCA data:\n%.6f\n", $X_PCA->slice(end=>5));
# [[-0.63036125 -0.11155626]
#  [-0.62354631  0.1003132 ]
#  [-0.6697928   0.04722006]
#  [-0.65463305  0.09879127]
#  [-0.64826327 -0.13755769]]

my $X1_PCA = $X_PCA->slice(':', 0);
my $X2_PCA = $X_PCA->slice(':', 1);
nd->print("Pearson Correlation X1_PCA x X2_PCA:", nd->corrcoef($X1_PCA, $X2_PCA));
# Pearson Correlation X1_PCA x X2_PCA:
# [[     1 0.0000]
#  [0.0000      1]]
# <AI::MXNet::NDArray 2x2 @cpu(0)> float64

# Plotting the result of the PCA data transformation

my $color_scale = [
    [0,   'green'],   
    [0.5, 'purple'], 
    [1,   'orange']   
];

my $trace = new Chart::Plotly::Trace::Scatter(
    x      => $X1_PCA->aspdl,
    y      => $X2_PCA->aspdl,
    mode   => 'markers',
    marker => { 
        color      => $y->aspdl,
        colorscale => $color_scale,  
        cmin       => $y->min,  
        cmax       => $y->max,
        size       => 10
    }
);

my $layout = {title => { text => 'PCA' },
           xaxis => { title => 'Principal Component X1_PCA' }, 
           yaxis => { title => 'Principal Component X2_PCA' },
           width  => 600, height => 500,
           margin => { l => 50, r => 0, t => 50, b => 50 }};
              
my $plot = new Chart::Plotly::Plot(traces => [$trace],
                                   layout => $layout);


# IPerl->display($plot);
# sml->embed_plot($plot, width=>900, height=>450);
show_plot($plot);

# Let's first investigate the changes in the columns chosen by the PCA algorithm.

my @chosen_columns = $pca->{chosen_columns}->tolist;
printf "Chosen columns: %s", dump @chosen_columns;

my ($X0_normalized, $X1_normalized) = @{$X_normalized->T}[@chosen_columns];

# Plotting the normalized data before PCA projection

$trace = new Chart::Plotly::Trace::Scatter(
    x      => $X0_normalized->aspdl,
    y      => $X1_normalized->aspdl,
    mode   => 'markers',
    marker => { 
        color      => $y->aspdl,
        colorscale => $color_scale,  
        cmin       => $y->min,  
        cmax       => $y->max,
        size       => 10
    }
);

$layout = {title => { text => 'Before PCA' },
           xaxis => { title => $header->[$chosen_columns[0]] }, 
           yaxis => { title => $header->[$chosen_columns[1]] },
           width  => 600, height => 500,
           margin => { l => 50, r => 0, t => 50, b => 50 }};
              
$plot = new Chart::Plotly::Plot(traces => [$trace],
                                   layout => $layout);


# IPerl->display($plot);
# sml->embed_plot($plot, width=>900, height=>450);
show_plot($plot);

my $PCA = nd->concat($X_PCA, $y->expand_dims(axis=>1));
nd->print("Normalized:", $PCA->slice([0, 5]));

# Coefficientes before PCA

my $corrcoef_before = nd->corrcoef($normalized->T);
printf "Pearson Correlation coefficients of the Iris dataset:\n%s\n", 
        $corrcoef_before->asstr;

# Show a heatmap out of the Pearson Correlation coefficients of X
$trace = new Chart::Plotly::Trace::Heatmap(
    x => $header,
    y => $header,
    z => $corrcoef_before->aspdl,
    colorscale => 'Jet', # Electric Greens Greys Hot Jet Picnic Portland Reds YlOrRd YlGnBu
                           # https://plotly.com/javascript/colorscales/#hot-colorscale
);

$layout = {title => { text => 'Pearson Correlation coefficients of Iris dataset before PCA' },
           yaxis => { autorange => "reversed" }, # Flip so lower frequencies are at the bottom
           width  => 700, height => 400,
           margin => { l => 50, r => 0, t => 50, b => 50 }};
              
$plot = new Chart::Plotly::Plot(traces => [$trace],
                                layout => $layout);

# IPerl->display($plot);
# sml->embed_plot($plot, width=>900, height=>450);
show_plot($plot);

my $corrcoef_after = nd->corrcoef($PCA->T);
printf "Pearson Correlation coefficients of the Iris dataset:\n%s\n", 
        $corrcoef_after->asstr;

my $squeezed_header = [@$header[@chosen_columns, -1]];

# Show a heatmap out of the Pearson Correlation coefficients of X
$trace = new Chart::Plotly::Trace::Heatmap(
    x => $squeezed_header,
    y => $squeezed_header,
    z => $corrcoef_after->aspdl,
    colorscale => 'Jet', # Electric Greens Greys Hot Jet Picnic Portland Reds YlOrRd YlGnBu
                         # https://plotly.com/javascript/colorscales/#hot-colorscale
);

$layout = {title => { text => 'Pearson Correlation coefficients of Iris dataset after PCA' },
           yaxis => { autorange => "reversed" }, # Flip so lower frequencies are at the bottom
           width  => 700, height => 400,
           margin => { l => 50, r => 0, t => 50, b => 50 }};
              
$plot = new Chart::Plotly::Plot(traces => [$trace],
                                layout => $layout);

# IPerl->display($plot);
# sml->embed_plot($plot, width=>700, height=>450);
show_plot($plot);

# Save the object's state to disk
$pca->save_model('modelo_pca_iris.ndarray');

# --- In a clean session or new code block ---
# Instantiate an empty object without hyperparameters
my $pca_restored = new PCA();
$pca_restored->load_model('modelo_pca_iris.ndarray');

# Project over a the data
$X_PCA = $pca_restored->transform($X_normalized);
nd->print("Projected data:\n", $X_PCA->slice([0, 5]));


