use strict;
use warnings;
use Data::Dump qw(dump);
use sml qw(show_plot);
use AI::MXNet qw(mx nd);

# =========================================================================
# MÉTODOS DEL ALGORITMO EM (GMM)
# =========================================================================

sub initialize_parameters {
  my ($self, $X, $K, $method) = @_;
  my ($N, $D) = @{$X->shape};
  
  $method //= 'random_from_data';

  if ($method eq 'random_from_data') {
    # --- MÉTODO 1: RANDOM FROM DATA (Estilo Correcto Sklearn) ---
    # 1. Seleccionar K centros reales del dataset de forma aleatoria
    my $indices = nd->random_choice($N, $K, replace=>0); 
    my $means = nd->take($X, $indices, axis => 0);
    
    # 2. Escalar la matriz identidad para reflejar la varianza real del espacio [0, 1]
    # Multiplicar por 0.01 o 0.005 hace que las campanas iniciales capten vecindarios locales.
    my @covs = map { nd->eye($D) * 0.01 } 1 .. $K;
    
    # 3. Pesos iniciales equitativos
    my $weights = nd->ones([$K]) / $K;
    
    # 4. Forzar un E-step inicial para propagar responsabilidades realistas
    my ($resp, $lower) = sml->e_step($X, $means, \@covs, $weights);
    return $resp;
    
  } elsif ($method eq 'random') {
    # --- MÉTODO 2: RANDOM CORREGIDO (Muestreo uniforme en el espacio [0,1]) ---
    # En lugar de rellenar la matriz de responsabilidades con ruido uniforme 
    # (lo que promedia todo al centro), generamos K centros aleatorios flotantes 
    # dentro del rango real de nuestros datos normalizados [0, 1].
    my $means = nd->random->uniform(low => 0.0, high => 1.0, shape => [$K, $D]);
    
    # Inicializamos con covarianzas pequeñas y locales para que capten vecindarios
    my @covs = map { nd->eye($D) * 0.01 } 1 .. $K;
    
    # Pesos iniciales equitativos
    my $weights = nd->ones([$K]) / $K;
    
    # Propagamos mediante el E-step para generar responsabilidades nítidas y reales
    my ($resp, $lower) = sml->e_step($X, $means, \@covs, $weights);
    return $resp;
  } else {
    die "Método de inicialización desconocido: $method";
  }
}
sml->add_to_class('initialize_parameters', \&initialize_parameters);

sub estimate_log_gaussian_prob {
  my ($self, $X, $mean, $cov) = @_;
  
  my ($N, $D) = @{$X->shape};

  # 1. Añadir regularización a la diagonal idéntica a reg_covar de sklearn
  my $cov_stable = $cov + (nd->eye($D) * 1e-6);

  # 2. Descomposición de Cholesky estable: cov = L * L^T
  # MXNet devuelve una matriz triangular inferior L
  my $L = nd->linalg->potrf($cov_stable); 

  # 3. Calcular Log-Determinante de forma segura usando la diagonal de L
  # log(det(Sigma)) = 2 * sum(log(diag(L)))
  # Extraemos la diagonal usando slicing dinámico indexado
  my @diag_elements;
  for my $i (0 .. $D - 1) {
    push @diag_elements, nd->log($L->slice($i, $i));
  }
  my $log_det = nd->add_n(@diag_elements) * 2.0;

  # 4. Resolver el término cuadrático de Mahalanobis usando linalg->trsm (Sustitución triangular)
  # Buscamos resolver de manera estable: L * Y = (X - mean)^T
  my $X_centered = nd->broadcast_sub($X, $mean)->T;
  
  # trsm resuelve sistemas triangulares de manera ultra-eficiente
  my $Y = nd->linalg->trsm($L, $X_centered, alpha => 1.0, rightside => 0, lower => 1, transpose => 0);
  
  # El término cuadrático equivale a la suma de los cuadrados de Y por columnas
  my $quad = nd->sum(nd->square($Y), axis => 0);

  # 5. Combinar todos los factores en la constante Gaussiana multivariada
  my $pi = 3.141592653589793;
  my $log_prob = -0.5 * ( $D * log(2 * $pi) + $log_det + $quad );

  return $log_prob;
}
sml->add_to_class('estimate_log_gaussian_prob', \&estimate_log_gaussian_prob);

sub e_step {
  my ($self, $X, $means, $covs, $weights) = @_;
  my $K = $weights->shape->[0];
  my @cols;

  for my $k (0 .. $K - 1) {
    my $slice = $means->slice($k);
    my $log_prob = sml->estimate_log_gaussian_prob(
      $X,
      $slice,
      $covs->[$k]
    );
    push @cols, $log_prob + log($weights->at($k)->asscalar);
  }

  my $log_resp = nd->stack(@cols, axis => 1);
  
  # Truco Log-Sum-Exp para estabilidad numérica
  my $max_log = $log_resp->max(axis => 1, keepdims => 1);
  my $log_sum_exp = $max_log + nd->log(
    nd->exp(nd->broadcast_sub($log_resp, $max_log))->sum(axis => 1, keepdims => 1)
  );

  my $responsibilities = nd->exp(nd->broadcast_sub($log_resp, $log_sum_exp));
  my $lower_bound    = $log_sum_exp->sum->asscalar;

  return ($responsibilities, $lower_bound);
}
sml->add_to_class('e_step', \&e_step);

sub m_step {
  my ($self, $X, $resp) = @_;
  my ($N, $D) = @{$X->shape};
  my $K = $resp->shape->[1];

  my $Nk = $resp->sum(axis => 0);
  # Ajuste de pesos idéntico a sklearn
  my $weights = $Nk / $N;
  my (@means, @covs);

  for my $k (0 .. $K - 1) {
    my $nk = $Nk->at($k)->asscalar;
    if ($nk < 1e-10) { $nk = 1e-10; } 

    my $r = $resp->slice(':', $k)->reshape([-1, 1]);

    # Actualización de Medias robusta con broadcasting explícito
    my $mean = nd->sum(nd->broadcast_mul($X, $r), axis => 0) / $nk;
    push @means, $mean;

    # Actualización de Covarianzas ponderada
    my $diff = nd->broadcast_sub($X, $mean);
    my $weighted_diff = nd->broadcast_mul($diff, $r);
    
    # Producto matricial clásico para la forma de la covarianza [D, D]
    my $cov = nd->dot($weighted_diff->T, $diff) / $nk;
    
    push @covs, $cov;
  }

  my $means_stacked = nd->stack(@means);
  return ($means_stacked, \@covs, $weights);
}
sml->add_to_class('m_step', \&m_step);

sub fit {
  my ($self, $X, $K, %args) = @_;
  my $max_iter   = $args{max_iter}   // 100;
  my $tol        = $args{tol}    // 1e-3;
  my $init_param = $args{init_params} // 'random_from_data'; # Recibe el parámetro

  # Inicializamos obteniendo la matriz de responsabilidades
  my $resp = sml->initialize_parameters($X, $K, $init_param);

  my $lower_old = -1e100;
  my (@history, @plots);
  my ($means, $covs, $weights);
  my $N = $X->len;
  my $has_converged = 0;

  for my $iter (1 .. $max_iter) {
    
    # 1. Paso M: Estimar parámetros a partir de las responsabilidades vigentes
    ($means, $covs, $weights) = sml->m_step($X, $resp);

    # 2. Paso E: Evaluar las nuevas responsabilidades y el Lower Bound
    my $lower;
    ($resp, $lower) = sml->e_step($X, $means, $covs, $weights);

    # -------------------------------------------
    # printf "Iter %d LL=%.4f\n", $iter, $lower;
    push @history, $lower;
    
    my $assignments = nd->argmax($resp, axis => 1);
    
    push @plots, sml->plot_current_state(
      $X, $means, $covs, $assignments, $iter, $args{header}, $K
    ) if $args{plot_steps};
    
    my $diff = abs($lower - $lower_old) / $N; # <--- Dividir para N
    
    if ($diff < $tol) {
      $has_converged = 1;
      print "Convergence achieved in the iteration $iter.\n";
      last;
    }

    $lower_old = $lower;
  }
  
  if (not $has_converged) {
    warn "\nConvergence warning: Initialization $max_iter did not converge. "
       . "Try different init parameters, or increase max_iter, tol "
       . "or check for degenerate data.\n\n";
  }

  return ($resp, $means, $covs, \@history, \@plots);
}
sml->add_to_class('fit', \&fit);


sub plot_current_state {
  my ($self, $X, $means, $covs, $assignments, $iteration, $header, $n_components) = @_;
  
  # 1. Escala de colores para los puntos
  my $color_scale = [
      [0,   'green'],
      [0.5, 'purple'], 
      [1,   'orange']
  ];
  my @contour_colors = ('green', 'purple', 'orange');
  
  # DINAMIZACIÓN: Extraer límites reales del dataset X para ajustar la ventana visual
  my $x_min = $X->slice(':', 0)->min->asscalar;
  my $x_max = $X->slice(':', 0)->max->asscalar;
  my $y_min = $X->slice(':', 1)->min->asscalar;
  my $y_max = $X->slice(':', 1)->max->asscalar;
  
  # Añadir un margen del 15% para que los puntos periféricos y contornos no se recorten
  my $x_margin = ($x_max - $x_min) * 0.15 || 0.5;
  my $y_margin = ($y_max - $y_min) * 0.15 || 0.5;
  
  my $plot_x_min = $x_min - $x_margin;
  my $plot_x_max = $x_max + $x_margin;
  my $plot_y_min = $y_min - $y_margin;
  my $plot_y_max = $y_max + $y_margin;
  
  # 2. Generación Dinámica de la Malla (Grid) basada en los límites del gráfico
  my $grid_steps = 50;
  my @grid_x;
  my @grid_y;
  for my $i (0 .. $grid_steps - 1) {
    my $factor = $i / ($grid_steps - 1);
    push @grid_x, $plot_x_min + $factor * ($plot_x_max - $plot_x_min);
    push @grid_y, $plot_y_min + $factor * ($plot_y_max - $plot_y_min);
  }
  
  # Construir el tensor de la malla [grid_steps * grid_steps, 2]
  my @grid_points;
  for my $y_val (@grid_y) {
    for my $x_val (@grid_x) {
      push @grid_points, [$x_val, $y_val];
    }
  }
  my $X_grid = nd->array(\@grid_points);
  
  # 3. Construcción de los trazos de los anillos
  my @contour_traces;
  for my $k (0 .. $n_components - 1) {
    my $mean_k = $means->slice($k);
    my $cov_k  = $covs->[$k];
    
    # Evaluar la densidad de probabilidad multivariada pura en toda la malla
    my $z_flat = multivariate_normal->pdf($X_grid, $mean_k, $cov_k);
    
    # Extraer el pico de densidad máxima del cluster
    my $z_max_val = $z_flat->max->asscalar;

    # Definimos 2 contornos: el anillo exterior (más bajo/grande) y el interno (más alto/pequeño)
    my $contour_start = $z_max_val * 0.30; # Primer anillo (30% de la altura)
    my $contour_end   = $z_max_val * 0.60; # Segundo anillo (60% de la altura)
    
    # El tamaño del paso (size) es exactamente la distancia entre ambos niveles
    my $contour_size  = $contour_end - $contour_start;
    
    my $z_matrix = $z_flat->reshape([$grid_steps, $grid_steps])->asarray;
    
    # 4. Crear la capa de contornos usando el paso lineal forzado
    my $contour_trace = new Chart::Plotly::Trace::Contour(
        x         => \@grid_x,
        y         => \@grid_y,
        z         => $z_matrix,
        showscale => 0,
        contours  => { 
            coloring => 'none',
            start    => $contour_start,  # Comienza en el 30%
            end      => $contour_end,    # Termina exactamente en el 60%
            size     => $contour_size    # El paso exacto para que solo dibuje esos dos
        },
        line      => { color => $contour_colors[$k], width => 2.5 },
        name      => "Contour Cluster $k"
    );
    
    push @contour_traces, $contour_trace;
  }
  
  # 4. Capa de puntos reales del dataset
  my $points_trace = new Chart::Plotly::Trace::Scatter(
      x    => $X->slice(':', 0)->asarray,
      y    => $X->slice(':', 1)->asarray,
      mode => 'markers',
      marker => {
          color      => ($assignments / ($n_components - 1))->asarray,
          colorscale => $color_scale,
          size       => 10,
          opacity    => 0.7,
          cmin       => 0.0, 
          cmax       => 1.0
      },
      name => 'Puntos'
  );

  # 5. Capa de Medias (Cruces Rojas)
  my $means_trace = new Chart::Plotly::Trace::Scatter(
      x    => $means->slice(':', 0)->asarray,
      y    => $means->slice(':', 1)->asarray,
      mode => 'markers',
      marker => { symbol => 'cross', color => 'red', size => 22 },
      name => 'Averages (Centers)'
  );

  # Ajuste adaptativo del Layout
  my $layout = {
      title  => { text => "GMM Clustering - Iteration: $iteration (Density Convergence)" },
      xaxis  => { title => $header->[0] // 'Feature 0', range => [$plot_x_min, $plot_x_max] },
      yaxis  => { title => $header->[1] // 'Feature 1', range => [$plot_y_min, $plot_y_max] },
      width  => 950, height => 500
  };

  return new Chart::Plotly::Plot(
      traces => [@contour_traces, $points_trace, $means_trace], 
      layout => $layout
  );
}
sml->add_to_class('plot_current_state', \&plot_current_state);

# =========================================================================
# CARGA Y PREPARACIÓN DE DATOS
# =========================================================================
my ($dataset, $header) = sml->load_csv('/home/jehosha/Downloads/data/iris.csv');
my ($lookup, $rlookup) = sml->str_column_to_int($dataset, -1);
$dataset = nd->array($dataset);

# Extraer columnas 0 y 2 para trabajar en un entorno 2D real
my $X = nd->take($dataset, nd->array([0, 2]), axis => 1);
my $y = $dataset->slice(':', -1);

# Crear un header temporal adaptado a las dos columnas seleccionadas
my $header_2d = [ $header->[0] // 'Sepal Length', $header->[2] // 'Petal Length' ];

# Normalización Min-Max
my $X_normalized = $X;
my $minmax = sml->dataset_minmax($X_normalized);
sml->normalize_dataset($X_normalized, $minmax);

# =========================================================================
# EJECUCIÓN DEL ALGORITMO (Configuración para Convergencia Real)
# =========================================================================
# Fijar semilla aleatoria global para asegurar reproducibilidad
mx->random->seed(0); 
my $K = 3;

# Ajuste iterativo del Modelo de Mezclas Gaussianas
my ($responsibilities, $gmm_means, $gmm_covs, $log_likelihoods, $plots) =  
  sml->fit($X_normalized, $K, 
           max_iter    => 50,         # <--- PERMITIR ITERACIONES
           tol         => 1e-4,       # <--- TOLERANCIA ESTÁNDAR
           header      => $header_2d, 
           plot_steps  => 0, 
           init_params => 'random'); # 'random_from_data'
show_plot($_) for @$plots;

# =========================================================================
# FINAL RESULTS
# =========================================================================
print "\n" . "=" x 50 . "\n";
print "         FINAL PARAMETERS\n";
print "=" x 50 . "\n";

# Imprimir Medias Finales
print "Final Means (Centers):\n";
print $gmm_means->asstr, "\n";

# Imprimir Covarianzas Finales
print "Final Covariances:\n";
if (defined $gmm_covs) {
  for my $k (0 .. $K - 1) {
    printf "Component %d Covariance Matrix:\n", $k;
    print $gmm_covs->[$k]->asstr, "\n";
  }
}

# Imprimir Métricas de Convergencia
my $num_iters = scalar(@$log_likelihoods);
printf "Number of iterations to converge: %d\n", $num_iters;
printf "Final Log-Likelihood (Lower Bound Perl): %.6f\n", $log_likelihoods->[-1] if @$log_likelihoods;
# Final assignments
my $assignments = nd->argmax($responsibilities, axis => 1);
printf "GMM Assignments:\n%s\n", $assignments->asstr;
print "=" x 50 . "\n";

# FINAL CONVERGENCE
my $plot = sml->plot_current_state(
    $X_normalized, 
    $gmm_means, 
    $gmm_covs, 
    $assignments, 
    $num_iters, 
    $header_2d, 
    $K
);
show_plot($plot);

# Graficar la evolución de la Log-Verosimilitud
my $trace = new Chart::Plotly::Trace::Scatter(
  x    => [ 1 .. scalar(@$log_likelihoods) ],
  y    => $log_likelihoods,
  mode => 'lines+markers',
  name => 'Log-Likelihood'
);

my $layout = {
  title  => { text => 'Evolution of Log-Likelihood in EM (GMM)' },
  xaxis  => { title => 'Iteration' },
  yaxis  => { title => 'Log-Likelihood' },
  width  => 850, height => 400
};

$plot = new Chart::Plotly::Plot(traces => [$trace], layout => $layout);
# IPerl->display($plot);
# sml->embed_plot($plot, width=>850, height=>450);
show_plot($plot);

sub gen_data {
  my ($self, %args) = @_;
  my $K                  = $args{k}                  // 3;
  my $dim                = $args{dim}                // 2;
  my $points_per_cluster = $args{points_per_cluster} // 200;
  my $lim                = $args{lim}                // [-10, 10];

  my @all_points;

  # 1. Generar K medias aleatorias dentro del rango [lim[0], lim[1]]
  # Formula: rand * (max - min) + min
  my $range = $lim->[1] - $lim->[0];
  my $means = nd->random->uniform(low => 0.0, high => 1.0, shape => [$K, $dim]) * $range + $lim->[0];

 for my $i (0 .. $K - 1) {
    my $mean_i = $means->slice($i);

    # Generar una covarianza aleatoria pero compacta para que no se encimen los clústeres
    my $cov_rand = nd->random->uniform(low => 0.1, high => 0.5, shape => [$dim, $dim]);

    # Controla el radio/dispersión de la nube. 
    # Si aumentas de 0.5 a 1.2, la nube se vuelve gigante y más dispersa.
    my $dispersion = 0.5; 
    my $cov_i = nd->eye($dim) * $dispersion;

    my $samples = multivariate_normal->rvs($mean_i, $cov_i, $points_per_cluster);
    push @all_points, $samples;
  }

  # 4. Concatenar verticalmente todos los componentes en un único tensor de datos X
  return nd->concat(@all_points, dim => 0);
}
sml->add_to_class('gen_data', \&gen_data);

sub plot_generated_data {
  my ($self, $X, %args) = @_;
  my $dim = $X->shape->[1];

  # El código original en Python solo grafica si la dimensión es estrictamente 2D
  if ($dim != 2) {
    print "Automated plotting is only supported for two-dimensional environments (dim = 2).\n";
    return;
  }

  # Extraer columnas cartesianas X e Y
  my $x_coords = $X->slice(':', 0)->asarray;
  my $y_coords = $X->slice(':', 1)->asarray;

  my $scatter_trace = new Chart::Plotly::Trace::Scatter(
      x      => $x_coords,
      y      => $y_coords,
      mode   => 'markers',
      marker => {
          size    => 4,
          opacity => 0.5,
          color   => 'blue'
      },
      name => 'GMM Synthetic Data'
  );

  my $layout = {
      title  => { text => 'Synthetic Dataset (Gaussian Mixtures)' },
      xaxis  => { title => 'Feature 0', przesz => 1 },
      yaxis  => { title => 'Feature 1', przesz => 1 },
      width  => 850, 
      height => 500
  };

  return new Chart::Plotly::Plot(traces => [$scatter_trace], layout => $layout);
}
sml->add_to_class('plot_generated_data', \&plot_generated_data);

# Generar la estructura de datos puramente matemática
mx->random->seed(42); 
my $X_synthetic = sml->gen_data(
    k                  => 3,
    dim                => 2,
    points_per_cluster => 150,
    lim                => [-10, 10]
);

printf "Successfully generated synthetic matrix. Dimensions: %s\n", dump($X_synthetic->shape);

# Renderizar de forma aislada e independiente
$plot = sml->plot_generated_data($X_synthetic);
# IPerl->display($plot);
# sml->embed_plot($plot, width=>850, height=>500);
show_plot($plot);

mx->random->seed(0);
$K = 3;

# Ajuste iterativo del Modelo de Mezclas Gaussianas
($responsibilities, $gmm_means, $gmm_covs, $log_likelihoods, $plots) =  
  sml->fit($X_synthetic, $K, 
           max_iter    => 50,         # <--- PERMITIR ITERACIONES
           tol         => 1e-4,       # <--- TOLERANCIA ESTÁNDAR
           header      => $header_2d, 
           plot_steps  => 0, 
           init_params => 'random_from_data'); # 'random_from_data'
show_plot($_) for @$plots;

# =========================================================================
# FINAL RESULTS
# =========================================================================
print "\n" . "=" x 50 . "\n";
print "         FINAL PARAMETERS\n";
print "=" x 50 . "\n";

# Imprimir Medias Finales
print "Final Means (Centers):\n";
print $gmm_means->asstr, "\n";

# Imprimir Covarianzas Finales
print "Final Covariances:\n";
if (defined $gmm_covs) {
  for my $k (0 .. $K - 1) {
    printf "Component %d Covariance Matrix:\n", $k;
    print $gmm_covs->[$k]->asstr, "\n";
  }
}

# Imprimir Métricas de Convergencia
$num_iters = scalar(@$log_likelihoods);
printf "Number of iterations to converge: %d\n", $num_iters;
printf "Final Log-Likelihood (Lower Bound Perl): %.6f\n", $log_likelihoods->[-1] if @$log_likelihoods;
# Final assignments
$assignments = nd->argmax($responsibilities, axis => 1);
printf "GMM Assignments:\n%s\n", $assignments->asstr;
print "=" x 50 . "\n";

# FINAL CONVERGENCE
$plot = sml->plot_current_state(
    $X_synthetic, 
    $gmm_means, 
    $gmm_covs, 
    $assignments, 
    $num_iters, 
    $header_2d, 
    $K
);
show_plot($plot);
# IPerl->display($plot);
# sml->embed_plot($plot, width=>850, height=>450);