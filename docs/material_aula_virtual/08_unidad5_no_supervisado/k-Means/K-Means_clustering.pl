use strict;
use warnings;
use Data::Dump qw(dump);
use sml qw(show_plot);
use AI::MXNet qw(mx nd);
# IPerl->load_plugin('Chart::Plotly');

my ($dataset, $header) = sml->load_csv('/home/jehosha/Downloads/data/iris.csv');
my ($lookup, $rlookup) = sml->str_column_to_int($dataset, -1);
$dataset   = nd->array($dataset);

printf "%d-%s ", $_, $header->[$_] for (0 .. $#$header);
printf "%s\n", dump $lookup, $rlookup;

my $X = $dataset->slice(':', [0, -1]);
my $y = $dataset->slice(':', -1);
printf "%d-%s ", $_, $header->[$_] for (0 .. $#$header -1);
print $X->slice([undef, 5])->asstr;

my $X_normalized = $X;
my $minmax = sml->dataset_minmax($X_normalized);
nd->print("Matriz Min-Max por columna:", $minmax);

# normalize
sml->normalize_dataset($X_normalized, $minmax);
nd->print("Normalized:", $X_normalized->slice([0, 5]));

sub random_centroids{
  my ($self, $all_vals, $K) = @_;
  # Place K centroids at random locations
  my $indices   = nd->arange($all_vals->len)->shuffle();
  my $shuffled  = nd->take($all_vals, $indices, axis=>0);
  return $shuffled->slice([0, $K]);
}

sml->add_to_class('random_centroids', \&{'random_centroids'});

sub assign_cluster {
  my ($self, $all_vals, $centroids) = @_;
  
  # 1. ||x||^2 -> Suma de cuadrados a lo largo de los atributos (N, 1)
  my $data_norms = $all_vals->square()->sum(axis=>1, keepdims=>1);
  
  # 2. ||c||^2 -> Suma de cuadrados de los centroides (1, K)
  my $centroid_norms = $centroids->square()->sum(axis=>1)->reshape([1, -1]);
  
  # 3. -2 * <x, c> -> Producto punto matricial (N, D) x (D, K) = (N, K)
  my $dot_product = nd->dot($all_vals, $centroids->T);
  
  # 4. Combinar términos usando broadcasting: (N, 1) - 2*(N, K) + (1, K) = (N, K)
  my $dists = $data_norms - (2 * $dot_product) + $centroid_norms;
  
  # Retornar el índice del centroide más cercano
  return nd->argmin($dists, axis=>1);
}
sml->add_to_class('assign_cluster', \&{'assign_cluster'});

sub new_centroids{
  my ($self, $all_vals, $centroids, $assignments, $K) = @_;
  my $one_hot = nd->one_hot($assignments, $K);                # (N, K)
  my $counts  = nd->sum($one_hot, axis=>0)->reshape([$K, 1]); # Forzamos (K, 1) para broadcasting directo
  my $sums    = nd->dot($one_hot->T, $all_vals);              # (K, D)
  return $sums / $counts; # means: (K, D) / (K, 1) -> Operación directa limpia
}

sml->add_to_class('new_centroids', \&{'new_centroids'});

sub sse{
  my ($self, $all_vals, $assignments, $centroids)= @_;
  my $centroid = nd->take($centroids, $assignments, axis=>0);
  my $errors   = nd->norm($all_vals - $centroid, axis=>1);
  return $errors->power(2)->sum();
}

sml->add_to_class('sse', \&{'sse'});

sub kmeans_clustering {
  my ($self, $all_vals, $K, $max_iter) = @_;
  $max_iter //= 20;
    
  my $centroids = sml->random_centroids($all_vals, $K);
  my $assignments;
  my @all_sse; # Aquí guardaremos el histórico de tensores SSE

  for (1 .. $max_iter) {
    $assignments = sml->assign_cluster($all_vals, $centroids);
    $centroids   = sml->new_centroids($all_vals, $centroids, $assignments, $K);
    
    # 1. Calculamos el SSE en cada iteración como un tensor (¡Sin usar ->asscalar!)
    my $sse = sml->sse($all_vals, $assignments, $centroids);
    push @all_sse, $sse;
  }

  # 2. Concatenamos todos los SSEs acumulados en un único tensor de MXNet al salir del bucle
  # Esto mantiene la ejecución asíncrona y eficiente.
  my $historical_sse = nd->concat(@all_sse, dim=>0);

  return $assignments, $centroids, $historical_sse;
}

sml->add_to_class('kmeans_clustering', \&{'kmeans_clustering'});

mx->random->seed(576);
my $K = 3;
my ($assignments, $centroids, $all_sse) = 
    sml->kmeans_clustering($X_normalized, $K, 10);
nd->print($all_sse);

my $trace = new Chart::Plotly::Trace::Scatter(x => nd->arange($all_sse->len)->asarray,
                                              y => $all_sse->asarray, 
                                              name => 'Train', 
                                              mode => 'lines');
              
my $layout = {title => {text => 'Plot of the Training'},
              xaxis => {title => 'Epoch'}, yaxis => {title => 'Loss'},
              width  => 900, height => 400,
              margin => { l => 50, r => 0, t => 50, b => 50 }};

my $plot = new Chart::Plotly::Plot(traces => [$trace],
                                   layout => $layout);

# IPerl->display($plot);
# sml->embedplot($plot, width=>900, height=>450);
show_plot($plot);

print $assignments->aspdl;

print $y->aspdl;

print $centroids->asstr;
# [[0.7073 0.4509 0.7970 0.8248]
#  [0.4413 0.3074 0.5757 0.5492]
#  [0.1961 0.5908 0.0786 0.0600]]

my $sort_idx = nd->array([2, 1, 0]);
my $sorted_centroids = nd->take($centroids, $sort_idx);
nd->print($sorted_centroids);

sub evaluate_centroids {
  my ($self, $test_vals, $centroids) = @_;
    
  # 1. Asignar los puntos de prueba al centroide más cercano (usando tu función optimizada)
  my $test_assignments = $self->assign_cluster($test_vals, $centroids);
    
  # 2. Calcular el SSE en el conjunto de prueba utilizando los centroides fijos
  my $test_sse = $self->sse($test_vals, $test_assignments, $centroids);
    
  # Retornamos las etiquetas asignadas a los datos de prueba y el error escalar
  return $test_assignments, $test_sse;
}

sml->add_to_class('evaluate_centroids', \&{'evaluate_centroids'});

my ($test_assignments, $test_sse) = 
    sml->evaluate_centroids($X_normalized, $sorted_centroids);

nd->print($test_assignments);

my $matrix = sml->confusion_matrix($y, $test_assignments);
print $matrix->asstr;

sub multiclass_perf_metrics {
    my ($self, $actual, $predicted) = @_;
    
    # 1. Obtener la matriz de confusión global usando tu método existente
    # Si viene en formato NDArray, $matrix será un NDArray, de lo contrario un array de arrays
    my $matrix = $self->confusion_matrix($actual, $predicted);
    
    my $is_tensor = (ref($matrix) =~ /^AI::MXNet::NDArray(?:::Slice)?$/);
    my $num_classes = $is_tensor ? $matrix->shape->[0] : scalar(@$matrix);
    
    my %report = ();
    my ($global_tp, $total_elements) = (0, 0);

    # 2. Iterar sobre cada clase bajo la estrategia One-vs-Rest
    for my $i (0 .. $num_classes - 1) {
        my ($tp, $fp, $fn, $tn) = (0, 0, 0, 0);
        
        if ($is_tensor) {
            # Extraer métricas binarias usando indexación nativa de MXNet
            $tp = $matrix->at($i, $i)->asscalar;
            
            # FP: Suma de la columna 'i' menos el verdadero positivo
            $fp = nd->sum($matrix->slice(':', $i))->asscalar - $tp;
            
            # FN: Suma de la fila 'i' menos el verdadero positivo
            $fn = nd->sum($matrix->slice($i, ':'))->asscalar - $tp;
            
            # TN: Suma total de toda la matriz menos los otros tres componentes
            $tn = nd->sum($matrix)->asscalar - ($tp + $fp + $fn);
        } else {
            # Extraer métricas usando desreferenciación estándar de Perl
            $tp = $matrix->[$i][$i];
            
            for my $row (0 .. $num_classes - 1) {
                for my $col (0 .. $num_classes - 1) {
                    if ($row == $i && $col == $i) { next; }
                    elsif ($row == $i) { $fn += $matrix->[$row][$col]; }
                    elsif ($col == $i) { $fp += $matrix->[$row][$col]; }
                    else               { $tn += $matrix->[$row][$col]; }
                }
            }
        }
        
        # 3. Calcular métricas clásicas de clasificación para la clase actual
        my $precision = ($tp + $fp) > 0 ? ($tp / ($tp + $fp)) : 0;
        my $recall    = ($tp + $fn) > 0 ? ($tp / ($tp + $fn)) : 0;
        my $f1_score  = ($precision + $recall) > 0 ? 
                        (2 * ($precision * $recall) / ($precision + $recall)) : 0;
        
        # Guardar resultados de la clase
        $report{"clase_$i"} = {
            precision => sprintf('%0.4f', $precision),
            recall    => sprintf('%0.4f', $recall),
            f1_score  => sprintf('%0.4f', $f1_score),
            support   => $tp + $fn
        };
        
        $global_tp      += $tp;
        $total_elements += ($tp + $fn);
    }
    
    # 4. Calcular métrica Micro-Average Global (Equivalente al Accuracy General)
    $report{global_accuracy} = sprintf('%0.4f', $total_elements > 0 ? 
                              ($global_tp / $total_elements) * 100 : 0);
    
    return \%report;
}

sml->add_to_class('multiclass_perf_metrics', \&{'multiclass_perf_metrics'});

sub print_classification_report {
    my ($self, $report) = @_;

    print "\n" . "=" x 58 . "\n";
    print "                 CLASSIFICATION REPORT\n";
    print "=" x 58 . "\n";
    # Encabezados de las columnas con anchos fijos
    printf "%-12s %10s %10s %10s %10s\n", "Clase", "Precision", "Recall", "F1-Score", "Support";
    print "-" x 58 . "\n";

    # Iterar sobre las clases ordenadas (clase_0, clase_1, clase_2)
    for my $key (sort grep { /^clase_/ } keys %$report) {
        my $metrics = $report->{$key};
        # Formatear el nombre de la clase para mostrar solo el ID o el string limpio
        my $class_name = ucfirst($key); $class_name =~ s/_/ /;

        printf "%-12s %10.4f %10.4f %10.4f %10d\n",
            $class_name,
            $metrics->{precision},
            $metrics->{recall},
            $metrics->{f1_score},
            $metrics->{support};
    }
    print "-" x 58 . "\n";
    
    # Métrica Global
    printf "%-47s %10.2f%%\n", "Accuracy Global:", $report->{global_accuracy};
    print "=" x 58 . "\n\n";
}

# Inyectar o ejecutar directamente:
sml->add_to_class('print_classification_report', \&{'print_classification_report'});

my $reporte_metricas = sml->multiclass_perf_metrics($y, $test_assignments);

sml->print_classification_report($reporte_metricas);

sub predict_proba {
    my ($self, $all_vals, $centroids) = @_;

    # 1. Calcular las distancias al cuadrado (N, K) usando tu álgebra del trinomio
    my $data_norms = $all_vals->square()->sum(axis=>1, keepdims=>1);
    my $centroid_norms = $centroids->square()->sum(axis=>1)->reshape([1, -1]);
    my $dot_product = nd->dot($all_vals, $centroids->T);
    my $dists = $data_norms - (2 * $dot_product) + $centroid_norms;

    # 2. Convertir distancias a probabilidades usando Softmax sobre el inverso (-dists)
    # axis=>1 asegura que las probabilidades de cada fila sumen 1.0
    my $probabilities = nd->softmax(-$dists, axis=>1);

    return $probabilities; # Retorna un NDArray de dimensiones (N, K)
}

sml->add_to_class('predict_proba', \&{'predict_proba'});

sub compute_roc_vectors {
    my ($self, $actual, $probabilities, $positive_class, %args) = @_;
    
    # Parámetro opcional para controlar la resolución del barrido de umbrales
    my $steps = $args{steps} // 100; # por defecto 100 pasos
    my @thresholds = map { $_ / $steps } (0 .. $steps);
    
    my (@fpr_points, @tpr_points);
    my $actual_binary;
    my $prob_target;
    
    # 1. Detectar si las entradas son tensores de MXNet o estructuras nativas de Perl
    if (ref($actual) =~ /^AI::MXNet::NDArray(?:::Slice)?$/) {
        
        # Crear vector binario: 1.0 para la clase positiva, 0.0 para el resto (One-vs-Rest)
        $actual_binary = ($actual == $positive_class)->astype('float32');
        
        # Extraer únicamente la columna de la probabilidad continua de la clase positiva (N, 1)
        $prob_target = $probabilities->slice(':', $positive_class);
        
    } else {
        # Si son arreglos de Perl estándar (conversión defensiva en caso de flujos mixtos)
        $actual_binary = [ map { $_ == $positive_class ? 1 : 0 } @$actual ];
        $prob_target   = [ map { $_->[$positive_class] } @$probabilities ];
    }
    
    # 2. Barrido iterativo sobre el espacio de umbrales utilizando tu función binaria perf_metrics
    for my $th (@thresholds) {
        my ($fpr, $tpr, $matrix) = $self->perf_metrics(
            $actual_binary, 
            $prob_target, 
            $th, 
            positive_class => 1
        );
        
        push @fpr_points, $fpr;
        push @tpr_points, $tpr;
    }
    
    # 3. Invertir los vectores para asegurar el orden ascendente 
    # estándar en el eje X de la curva ROC
    @fpr_points = reverse @fpr_points;
    @tpr_points = reverse @tpr_points;
    
    # Retornar las coordenadas listas para graficar y el cálculo de área bajo la curva (AUC)
    my $fpr_points = nd->stack(@fpr_points);
    my $tpr_points = nd->stack(@tpr_points);
    my $auc = $self->trapz($fpr_points, $tpr_points);
    
    return \@fpr_points, \@tpr_points, $auc;
}

sml->add_to_class('compute_roc_vectors', \&{'compute_roc_vectors'});

# Supongamos que ya tienes los centroides entrenados y tus datos cargados
my $probs = sml->predict_proba($X_normalized, $sorted_centroids);

# Elegimos una clase a evaluar
my $target_class = 1; 

# Llamada a la nueva función compute_roc_vectors()
my ($fpr, $tpr, $auc) = sml->compute_roc_vectors($y, $probs, $target_class, steps => 100);

print "--- ROC metrics for the class $rlookup->{$target_class} ---\n";
print "Area below the curve (AUC): $auc\n";

my $roc_trace = new Chart::Plotly::Trace::Scatter(
    x    => $fpr,
    y    => $tpr,
    mode => 'lines+markers',
    name => "ROC Clase $rlookup->{$target_class} (AUC: $auc)"
);

my $diagonal = new Chart::Plotly::Trace::Scatter(
    x    => [0, 1], y => [0, 1], mode => 'lines',
    line => { dash => 'dash', color => 'gray' }, name => 'Random line (0.5)'
);

$plot = new Chart::Plotly::Plot(
    traces => [$roc_trace, $diagonal],
    layout => {
        title  => "ROC curve (OvR Estrategy) for target class:" .
                  "$rlookup->{$target_class}",
        xaxis => { title => 'Specificity: False Positive Rate (FPR)' },
        yaxis => { title => 'Sensitivity: True Positive Rate (TPR)' }
    }
);

# IPerl->display($plot);
# sml->embedplot($plot, width=>900, height=>450);
show_plot($plot);

$K = 3;
my $max_iter = 10;
my $total_seeds_to_test = 100; 

my $max_delta = -1;
my $best_seed = undef;
my ($best_sse_start, $best_sse_end);

print "Iniciando búsqueda de la peor inicialización (Máxima Delta SSE)...\n";
print "-------------------------------------------------------------------\n";
my $start = 0; # Puedes aumentar el inicio para explorar nuevas semillas

for my $current_seed (1 + $start .. $total_seeds_to_test + $start) {
    # 1. Fijar la semilla actual de forma determinista para MXNet
    mx->random->seed($current_seed);
    
    # 2. Ejecutar tu algoritmo optimizado con el retorno histórico de SSEs
    my ($assignments, $centroids, $all_sse) = sml->kmeans_clustering($X, $K, $max_iter);
    
    # 3. Extraer el primer y el último SSE usando operaciones nativas y asscalar
    my $sse_inicio = $all_sse->slice([0])->asscalar;
    my $sse_final  = $all_sse->slice([-1])->asscalar;
    
    # 4. Calcular cuánta pérdida se redujo
    my $delta_sse = $sse_inicio - $sse_final;
    
    # Control de logs opcional por cada semilla para monitorear el progreso
    # printf "Semilla %02d -> Inicio: %.4f | Final: %.4f | Delta: %.4f\n", 
    # $current_seed, $sse_inicio, $sse_final, $delta_sse;
    
    # 5. Evaluar si es la máxima diferencia encontrada hasta el momento
    if ($delta_sse > $max_delta) {
        $max_delta      = $delta_sse;
        $best_seed      = $current_seed;
        $best_sse_start = $sse_inicio;
        $best_sse_end   = $sse_final;
    }
}

print "-------------------------------------------------------------------\n";
print "¡Búsqueda completada con éxito!\n";
print "=> La semilla con la máxima reducción de error es: Semilla $best_seed\n";
print "   SSE Inicial (Peor caso): $best_sse_start\n";
print "   SSE Final (Convergencia): $best_sse_end\n";
print "   Variación del Error (Delta): $max_delta\n";

my ($X0, $X1, $X2, $X3) = @{$X_normalized->T};

my $color_scale = [
    [0,   'green'],   
    [0.5, 'purple'], 
    [1,   'orange']   
];

# Now, we take any two columns from the dataset to visually 
# compare with their counterpart labels.

my $traces = new Chart::Plotly::Trace::Scatter(
    x      => $X0->aspdl,
    y      => $X2->aspdl,
    mode   => 'markers',
    marker => {color      => $test_assignments->aspdl,
               colorscale => $color_scale,
               size=>10},
);

my $centroids_trace = new Chart::Plotly::Trace::Scatter(
    x      => $centroids->slice(':', 0)->aspdl,
    y      => $centroids->slice(':', 2)->aspdl,
    mode   => 'markers',
    marker => {symbol => 'cross', color=>'red',  size=>25},
);

$layout = {title => {text => sprintf('K-means %s vs %s', @$header[0, 2])},
              xaxis => {title => $header->[0]}, yaxis => {title => $header->[2]},
              width  => 900, height => 400,
              margin => { l => 50, r => 0, t => 50, b => 50 }};
            
$plot = new Chart::Plotly::Plot(traces=>[$traces, $centroids_trace], 
                                   layout=>$layout);
                                    
# IPerl->display($plot);
# sml->embedplot($plot, width=>900, height=>450);
show_plot($plot);

$traces = new Chart::Plotly::Trace::Scatter(
    x      => $X0->aspdl,
    y      => $X2->aspdl,
    mode   => 'markers',
    marker => {color      => $y->aspdl,
               colorscale => $color_scale,
               size=>10},
);

$centroids_trace = new Chart::Plotly::Trace::Scatter(
    x      => $centroids->slice(':', 0)->aspdl,
    y      => $centroids->slice(':', 2)->aspdl,
    mode   => 'markers',
    marker => {symbol => 'cross', color=>'red',  size=>25},
);

$layout = {title => {text => sprintf('K-means centroids vs Actuals: %s vs %s',
                        @$header[0, 2])},
              xaxis => {title => $header->[0]}, yaxis => {title => $header->[2]},
              width  => 900, height => 400,
              margin => { l => 50, r => 0, t => 50, b => 50 }};
            
$plot = new Chart::Plotly::Plot(traces=>[$traces, $centroids_trace], 
                                   layout=>$layout);
                                    
# IPerl->display($plot);
# sml->embedplot($plot, width=>900, height=>450);
show_plot($plot);