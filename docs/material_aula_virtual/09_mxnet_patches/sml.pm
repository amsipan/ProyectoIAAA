package sml{
  use strict;
  use warnings;
  use Data::Dump qw(dump);
  use List::Util qw(zip min max sum uniq all any shuffle);
  use Tie::IxHash;
  use AI::MXNet qw(mx nd);
  use Chart::Plotly qw(show_plot);
  use Chart::Plotly::Plot;
  use Chart::Plotly::Trace::Scatter;
  use Chart::Plotly::Trace::Heatmap;
  use Chart::Plotly::Trace::Contour;
  use File::Temp qw(tempfile);
  use Encode;
  use utf8; # Tell perl source code is utf-8
  binmode(STDOUT, ":utf8"); #Correcly prints Wide characters.
  
  use Exporter qw(import);
  our @EXPORT_OK = qw(show_plot);

  # https://stackoverflow.com/questions/28373405/add-new-method-to-existing-object-in-perl
  sub add_to_class{ #@save
    # Register functions as methods in created class.
    my($class, $method_name, $code_ref) = @_; # $self, 
  
    {
      # We need to use symbolic references.
      no strict 'refs';
      no warnings;
      # Shove the code reference into the class' symbol table.
      *{$class.'::'.$method_name} = $code_ref;
    }
  }
  
  # embedplot(): useful for embedding a plot into a Jupyter notebook.
  # IPerl->display($plot); # useful for plotting into Jupyter notebook.
  # show_plot($plot); # Use show_plot($plot) from terminal or from IDE.
  # save_plot($plot); useful for locally saving the plot.
  sub embed_plot{
    my ($self, $plot, %args) = (splice (@_, 0, 2), width=>800, height=>650, @_);

    # 1. Force MXNet synchronization to release the execution thread
    AI::MXNet::NDArray->waitall();

    # 2. Validaciones básicas
    if (`whereis wkhtmltoimage` =~ m/wkhtmltoimage:\s*$/){
      print STDERR "wkhtmltoimage is not found in your system. Install wkhtmltoimage first before running this function.\n";
      return;
    }
    
    unless (ref ($plot) eq 'Chart::Plotly::Plot'){
      print STDERR "First parameter plot must be a Chart::Plotly::Plot.\n";
      return;
    }
    
    # Save to file
    my $html_path = 'plot.html';
    open my $fh, '>', $html_path or die "Cannot write plot.html: $!";
    print $fh $plot->html();
    close $fh;
  
    # Convert HTML to PNG using wkhtmltoimage
    my $png_path = "plot.png";
    #my $cmd   = `wkhtmltoimage --quiet --width $args{width} --height $args{height} $html_path $png_path`; # "--width", "800", "--height", "600",
    #print STDERR "Image generation failed: $cmd" if $cmd;
    
    
    # 4. Invocación estructurada y segura del sistema (Evita abortos del Kernel)
    # Al pasar los argumentos como una lista a system(), Perl no levanta un shell intermedio,
    # bloqueando el hilo actual de forma segura hasta que la imagen esté 100% escrita en disco.
    my $exit_code = system(
        'wkhtmltoimage',
        '--quiet',
        '--width',  $args{width},
        '--height', $args{height},
        $html_path,
        $png_path
    );
    
    if ($exit_code != 0) {
        print STDERR "Image generation failed with exit code: $exit_code\n";
        unlink $html_path;
        return;
    }
    # sleep 2;
    unlink $html_path;
  
    # Actually embed the graph into a Jupyter code cell
    IPerl->png( $png_path );
  }
  
  sub embedplot{
    printf STDERR "The function embedplot will be depricated soon. Use embed_plot() instead.\n";
    return embed_plot(@_);
  }
  
  sub save_plot{
    my ($self, $plot, %args) = (splice(@_, 0, 2), width => 800, height => 650, file_name => 'plot_XXXX', @_);
    
    # 1. Force MXNet synchronization to release the execution thread
    AI::MXNet::NDArray->waitall();

    if (`whereis wkhtmltoimage` =~ m/wkhtmltoimage:\s*$/) {
      print STDERR "wkhtmltoimage is not found in your system. Install wkhtmltoimage first before running this function.\n";
      return;
    }
    
    unless (ref($plot) eq 'Chart::Plotly::Plot') {
      print STDERR "First parameter plot must be a Chart::Plotly::Plot.\n";
      return;
    }
    
    # 2. Setup safe unique files
    my ($html_fh, $html_path) = tempfile($args{file_name}, SUFFIX => '.html', UNLINK => 0);
    my ($png_fh, $png_path)   = tempfile($args{file_name}, SUFFIX => '.png',  UNLINK => 0);
    close $png_fh; # Close handle so wkhtmltoimage can write to it cleanly

    print $html_fh $plot->html();
    close $html_fh;
  
    # 3. Synchronous system execution
    my $exit_code = system(
        'wkhtmltoimage',
        '--quiet',
        '--width',  $args{width},
        '--height', $args{height},
        $html_path,
        $png_path
    );
    
    if ($exit_code != 0) {
      print STDERR "Image generation failed with exit code: $exit_code\n";
      unlink $html_path;
      return;
    }
    
    printf "Plot generated at %s\n", $html_path;
  }
  
# Defined in Section 1.2.1 Load CSV File
# Function for loading a CSV
# Load a CSV file
sub load_csv{
  my ($self, $file_path, %args) = (splice(@_, 0, 2), 
                                   delimiter  => '[,;\t]',
                                   asndarray  => 0,
                                   has_header => 1, @_);
  
  open(my $fh, "<", $file_path) or die "Cannot open file $file_path: $!";
    
  my $header = <$fh> if $args{has_header};
  my $header_idx;
  if (defined $header){
    $header =~ s/[\r\n]+$//g;
    my $i = 0;
    $header_idx = {map {$_=>$i++} split /$args{delimiter}/, $header};
    # Preserve original order of the column names
    $header     = [sort { $header_idx->{$a} <=> $header_idx->{$b} } keys %$header_idx];
  }
  
  my $dataset = [];
  while (<$fh>) {
    $_ =~ s/[\r\n]+$//g;
    next if (!defined $_ || $_ =~ /^\s*$/ || $_ =~ /^$args{delimiter}*$/);
    push @$dataset, [ split /$args{delimiter}/, $_ ];
  }
  close $fh;
  
  $dataset = nd->array($dataset) if $args{asndarray};
  
  return wantarray ? ($dataset, $header, $header_idx) : $dataset;
}
  
  sub load_csv2{
    my ($self, $file_path, %args) = (splice(@_, 0, 2),
                                     delimiter => '[,;\t]',
                                     asndarray  => 0,
                                     has_header => 1,
                                     max_cols => 999, @_);
    
    open(my $fh, "<", $file_path) or die "Cannot open file $file_path: $!";
    
    my $header = <$fh> if $args{has_header};
    my $header_idx;
    if (defined $header){
      $header =~ s/[\r\n]+$//g;
      my $i = 0;
      $header_idx = {map {$_=>$i++} split /$args{delimiter}/, $header};
      # Preserve original order of the column names
      $header     = [sort { $header_idx->{$a} <=> $header_idx->{$b} } keys %$header_idx];
    }
    
    my ($dataset, $last_idx, $pos) = ([], 0);
    while (<$fh>){
      $_ =~ s/[\r\n]+$//g;
      next if (!defined $_ || $_ =~ /^\s*$/ || $_ =~ /^$args{delimiter}*$/);
      push @$dataset, [ split /$args{delimiter}/, $_ ];
      if (@{$dataset->[-1]} == $args{max_cols}){
        $last_idx = $#$dataset;
        $pos = tell($fh);  # 👈 byte position after this line
      }
    }
    close $fh;
    
    $dataset = nd->array($dataset) if $args{asndarray};
    
    return wantarray ? ($dataset, $header, $header_idx, $last_idx, $pos) : $dataset;
  }
  
  
  # Defined in Section 1.2.3 Convert String to Integers
  # Function To Integer Encode String Class Values.
  # Convert string column to integer
  sub str_column_to_int{
    my ($self, $dataset, $column, %args) = (splice(@_, 0, 3), lookup=>undef, @_);
    
    my $lookup = $args{lookup} // {};
    unless (%$lookup){
      my $class_values = [map {$_->[$column]} @$dataset];
      my @unique = uniq @$class_values;
      
      while (my ($i, $value) = each @unique) {
        $lookup->{$value} = $i;
      }
    }

    for my $row (@$dataset){
      $row->[$column] = $lookup->{$row->[$column]};
    }
    
    return $lookup, {reverse(%$lookup)};
  }
  
  # Function To Calculate the Min and Max Values For a Dataset.
  # Find the min and max values for each column
  sub dataset_minmax{
   my ($self, $dataset) = @_;
   return nd->stack($dataset->min(axis=>0), $dataset->max(axis=>0))->T;
  }
  
  # Function To Normalize a Dataset.
  # Rescale dataset columns to the range 0-1
  # Be careful not to include the y labels
  sub normalize_dataset{
    my ($self, $X, $minmax) = @_;
    my ($min, $max) = @{$minmax->transpose};
    $X->slice(':',':')->set(($X - $min) / ($max - $min));
  }
  
  # Function To Calculate Means For Each Column in a Dataset.
  # Calculate column means
  sub column_means{
    my ($self, $dataset) = @_;
    return $dataset->mean(axis=>0);
  }
  
  # Function To Calculate Standard Deviations For Each Column in a Dataset.
  # Calculate column standard deviations
  sub column_stdevs{
    my ($self, $dataset, $means) = @_;
    return nd->sqrt(($dataset - $means)->power(2)->sum(axis=>0) / ($dataset->len -1));
  }
  
  # Function To Standardize a Dataset.
  # Standardize dataset
  sub standardize_dataset{
    my ($self, $X, $means, $stdevs) = @_;
    $X->slice(':',':')->set(($X - $means) / $stdevs);
  }
  
  # Defined in Section 3.2.1 Train and Test Split
  # Function To Split a Dataset.
  # Split a dataset into a train and test set
  sub train_test_split{
    my ($self, $dataset, %args) = (splice (@_, 0, 2), split=>0.6, @_);
    
    my $train_size = int($args{split} * $dataset->len);
    my $idx        = nd->arange($dataset->len)->shuffle;
    my $train_idx  = $idx->slice([0, $train_size]);
    my $test_idx   = $idx->slice([$train_size, $dataset->len]);
    my $train      = nd->take($dataset, $train_idx);
    my $test       = nd->take($dataset, $test_idx);
    
    return $train, $test;
  }
  
  # Defined in Section 3.2.2 k-fold Cross-Validation Split
  # Function Create A Cross-Validation Split.
  # Split a dataset into $ k $ folds
  sub cross_validation_split{
    my ($self, $dataset, %args) = (splice (@_, 0, 2), n_folds=>10, @_);
    
    my @dataset_split;
    my $fold_size = int($dataset->len / $args{n_folds});
    my $idx       = nd->arange($dataset->len)->shuffle;
    for my $i (0 .. $args{n_folds} -1){
      my $fold_idx = $idx->slice([$i * $fold_size, ($i +1) * $fold_size]);
      push @dataset_split, nd->take($dataset, $fold_idx);
    }
    return nd->stack(@dataset_split, axis=>0);
  }
  
  sub count_labels{
    my ($self, $dataset) = @_;
    my $Y = $dataset->slice(':', -1);
    my $num_classes = $Y->max->asscalar + 1;
    return nd->one_hot($Y, $num_classes)->sum(axis=>0);
  }
  
  # Defined in Section 4.2.1 Classification Accuracy
  # Function To Calculate Classification Accuracy.
  # Calculate accuracy percentage between two lists
  sub accuracy_metric{
    my ($self, $actual, $predicted) = @_;
    my $cmp = $predicted->astype($actual->dtype) == $actual;
    sprintf '%0.3f', (100 * $cmp->astype('int64')->sum->asscalar / $actual->len);
  }
  
  # Defined in Section 4.2.2 Confusion Matrix
  # Function To Calculate a Confusion Matrix.
  # calculate a confusion matrix
  sub confusion_matrix{
    my ($self, $actual, $predicted) = @_;
    
    # Step 1: One-hot encode the actual and predicted arrays
    my $num_classes       = $actual->max->asscalar + 1;
    my $actual_one_hot    = nd->one_hot($actual, $num_classes); # Shape [n, $num_classes]
    my $predicted_one_hot = nd->one_hot($predicted, $num_classes); # Shape [n, $num_classes]
  
    # Step 2: Compute confusion matrix
    # Matrix multiplication: (actual_one_hot^T) * predicted_one_hot
    my $matrix = nd->dot($actual_one_hot->T, $predicted_one_hot);
    
    return wantarray ? (nd->arange($num_classes), $matrix) : $matrix;
  }
  
  # Defined in Section 4.2.2 Confusion Matrix
  # Function To Pretty Print a Confusion Matrix.
  # pretty print a confusion matrix
  sub print_confusion_matrix{
    my ($self, $unique, $matrix) = @_;
    printf "A/P%s", $unique->asstr;
    printf "%s\n", nd->concat($unique->expand_dims(axis=>1), $matrix, dim=>1)->asstr;
  }
  
  # Defined in Section 4.2.3 Mean Absolute Error
  # Function To Calculate Mean Absolute Error.
  # Calculate mean absolute error
  sub mae_metric{
    my ($self, $actual, $predicted) = @_;
    sprintf '%0.3f', (nd->abs($actual - $predicted)->astype('int64')->sum->asscalar / $actual->len);
  }
  
  # Defined in Section 4.2.4 Root Mean Squared Error
  # Function To Calculate Root Mean Squared Error.
  # Calculate root mean squared error
  sub rmse_metric{
    my ($self, $actual, $predicted) = @_;
    my $mean_error = ($actual - $predicted)->astype('int64')->square()->sum / $actual->len;
    sprintf '%0.3f', $mean_error->sqrt()->asscalar;
  }
  
  # Defined in Section 4.2.5 ROC curves
  # Function to calculate the ROC metrics by using one-hot encoding and dot product
  sub perf_metrics{
    my ($self, $actual, $predicted_prob, $threshold, %args) = (splice(@_, 0, 4), 
                                                               positive_class => 1, @_);
  
    # Define operator and truth matching dynamically
    my $op = $args{positive_class} == 1 ? sub { $_[0] >= $_[1] } : sub { $_[0] <= $_[1] };
    
    # Dynamic operator thresholding via functional lookup
    my $predicted = $op->($predicted_prob, $threshold);
    
    # Compute confusion matrix
    my $matrix = $self->confusion_matrix($actual, $predicted);
  
    # Map extraction coordinates dynamically based on the target positive class
    my ($p_idx, $n_idx) = $args{positive_class} == 1 ? (1, 0) : (0, 1);
  
    # Extract counts from the confusion matrix
    my $tp = $matrix->at($p_idx, $p_idx); # True Positives
    my $tn = $matrix->at($n_idx, $n_idx); # True Negatives
    my $fp = $matrix->at($n_idx, $p_idx); # False Positives
    my $fn = $matrix->at($p_idx, $n_idx); # False Negatives
  
    # Compute TPR and FPR
    my $tpr = ($tp + $fn)->asscalar > 0 ? ($tp / ($tp + $fn)) : nd->array([0]);
    my $fpr = ($fp + $tn)->asscalar > 0 ? ($fp / ($fp + $tn)) : nd->array([0]);
  
    return $fpr, $tpr, $matrix;
  }
  
  # Defined in Section 4.2.5 ROC curves
  # Function to calculate the integral using the trapezoid rule
  sub trapz{
    my ($self, $x, $y) = @_;
  
    # Compute differences (x[i+1] - x[i])
    my $dx = $x->slice([1, undef]) - $x->slice([0, -1]);
  
    # Compute averages of y values (y[i+1] + y[i]) / 2
    my $avg_y = ($y->slice([1, undef]) + $y->slice([0, -1])) / 2;
  
    # Compute trapezoid areas and sum them
    return sprintf '%0.2f', nd->sum($dx * $avg_y)->asscalar;
  }
  
  # Defined in Section 5.2.2 Zero Rule Algorithm: Classification
  # Example of Making Random Predictions
  # Generate random predictions
  sub random_algorithm{
    my ($self, $train, $test) = @_;
    my $output_values = $train->slice(':', -1);
    my $max_value = $output_values->max->asscalar + 1;
    return nd->random->randint(0, $max_value, shape=> [$test->len]);
  }
  
  # Defined in Section 5.2.2 Zero Rule Algorithm: Classification
  # Function To Make Zero Rule Classification Predictions.
  # zero rule algorithm for classification
  sub zero_rule_algorithm_classification{
    my ($self, $train, $test) = @_;
    my $output_values = $train->slice(':', -1);
    my $num_classes   = $output_values->max->asscalar + 1;
    my $count         = nd->one_hot($output_values, $num_classes)->sum(axis=>0);
    my $prediction    = nd->argmax($count);
    return nd->full([$test->len], $prediction->asscalar);
  }
  
  # Defined in Section 5.2.3 Zero Rule Algorithm: Regression
  # Function To Make Zero Rule Regression Predictions.
  # zero rule algorithm for regression
  sub zero_rule_algorithm_regression{
    my ($self, $train, $test) = @_;
    my $output_values = $train->slice(':', -1);
    my $prediction    = $output_values->sum() / $output_values->len;
    return nd->full([$test->len], $prediction->asscalar);
  }
  
  # Defined in Section 6.2.1 Train-Test Algorithm Test Harness
  # Function To Evaluate An Algorithm Using a Train/Test Split.
  # Evaluate an algorithm using a train/test split
  sub evaluate_algorithm_train_test_split{
    my ($self, $dataset, $algorithm, %args) = ((splice @_, 0, 3), 
                                                split=>0.6, metric=>undef, @_);
    
    my ($train, $test) = sml->train_test_split($dataset, split=>$args{split});
    my ($actual, $predicted, $score);
   
    $predicted = $algorithm->('sml', $train, $test, %args);
    $actual    = $test->slice(':', -1);
        
    # Regression : Classification
    if (defined $args{metric}){
      if ($args{metric} =~ /accuracy/i){
        $score = sml->accuracy_metric($actual, $predicted);
      }elsif($args{metric} =~ /rmse/i){
        $score = sml->rmse_metric($actual, $predicted);
      }
    }else{
      if (nd->sum($actual->trunc() - $actual)->asscalar != 0){
        $score = sml->rmse_metric($actual, $predicted);
      }else{
        $score = sml->accuracy_metric($actual, $predicted);
      }
    }
    
    return wantarray ? 
           ($score, $train, $test, $actual, $predicted) : 
           $score;
  }
  
  # Defined in Section 6.2.2 Cross-Validation Algorithm Test Harness
  # Function To Evaluate An Algorithm Using k-fold Cross-Validation.
  # Evaluate an algorithm using a cross-validation split
  sub evaluate_algorithm_cross_validation_split{
    my ($self, $dataset, $algorithm, %args) = ((splice @_, 0, 3), 
                                               n_folds=>10, metric=>undef, @_);
    
    my $folds = sml->cross_validation_split($dataset, n_folds=>$args{n_folds});
    my ($actual, $predicted, $score, $train_loss, $test_loss, 
        @scores, @train_losses, @test_losses, @predictions, @actuals);
    
    foreach my $i (0 .. $#$folds){
    
      # 1. Crear el train_folds con todos los folds excepto el actual ($i)
      my @train_folds = @$folds;
      my $test_fold   = splice @train_folds, $i, 1;
  
      # 2. Bajamos la 3ra dimensión y concatenando todas las filas
      my $train_set = nd->concat(@train_folds, dim=>0);
      
      ($predicted, $train_loss, $test_loss) = $algorithm->('sml', 
                                              $train_set, $test_fold, @_);
      $actual = $test_fold->slice(':', -1);
      
      # Regression : Classification
      if (defined $args{metric}){
        if ($args{metric} =~ /accuracy/i){
          push @scores, sml->accuracy_metric($actual, $predicted);
        }elsif($args{metric} =~ /rmse/i){
          push @scores, sml->rmse_metric($actual, $predicted);
        }
      }else{
        if (nd->sum($actual->trunc() - $actual)->asscalar != 0){
          push @scores, sml->rmse_metric($actual, $predicted);
        }else{
          push @scores, sml->accuracy_metric($actual, $predicted);
        }
      }
      
      push @train_losses, $train_loss;
      push @test_losses, $test_loss;
      push @actuals, $actual;
      push @predictions, $predicted;
    }
    
    return wantarray ? (\@scores, \@train_losses, \@test_losses, \@actuals, 
                        \@predictions) : \@scores;
  }

  # Defined in Section 7.2.4 Make Predictions
  # Evaluate regression algorithm on training dataset
  sub evaluate_algorithm_no_split{
    my ($self, $dataset, $algorithm, %args) = (splice(@_, 0, 3), metric=>undef, @_);
    
    my ($actual, $predicted, $score);
    if (ref($dataset) =~ /^AI::MXNet::NDArray(?:::Slice)?$/){
      my $test_set = $dataset->copy();
      $predicted   = $algorithm->('sml', $dataset, $test_set, @_);
      $actual      = $dataset->slice_axis(':', -1);
    }else{
      my @test_set = ();
      for my $row (@$dataset){
        my @row_copy  = @$row;
        # $row_copy[-1] = undef; # The test labels are needed for plotting the loss curve
        push @test_set, \@row_copy;
      }
      $predicted = $algorithm->('sml', $dataset, \@test_set, @_);
      $actual    = [map {$_->[-1]} @$dataset];
    }
    
    # Regression : Classification
    if (defined $args{metric}){
      if ($args{metric} =~ /accuracy/i) {
        $score = sml->accuracy_metric($actual, $predicted);
      }elsif($args{metric} =~ /rmse/i){
        $score = sml->rmse_metric($actual, $predicted);
      }
    }elsif (ref($dataset) =~ /^AI::MXNet::NDArray(?:::Slice)?$/){
      if (nd->sum($actual->trunc() - $actual)->asscalar != 0){
        $score = sml->rmse_metric($actual, $predicted);
      }else{
        $score = sml->accuracy_metric($actual, $predicted);
      }
    }else{
      $score = (grep { $_ =~ /\d+\.\d+/} @$actual) ?
                sml->rmse_metric($actual, $predicted) :
                sml->accuracy_metric($actual, $predicted);
    }
    
    return wantarray ? ($score, undef, $dataset, $actual, $predicted) : $score;
  }

  # Local definition only.
  # Choses evaluation method between either train/test or cross-validation split.
  # Depends on the input parameter name or value.
  sub evaluate_algorithm{
    my ($self, $dataset, $algorithm, %args) = (splice (@_, 0, 3), split=>undef, n_folds=>undef, metric=>undef, @_);

    if (!defined $args{split} && !defined $args{n_folds}){
      return sml->evaluate_algorithm_no_split($dataset, $algorithm, metric=>$args{metric}, @_);
    }else{
      if(defined $args{split}){
        return sml->evaluate_algorithm_train_test_split($dataset, $algorithm, split=>$args{split}, metric=>$args{metric}, @_);
      }elsif (defined $args{n_folds}){
        return sml->evaluate_algorithm_cross_validation_split($dataset, $algorithm, n_folds=>$args{n_folds}, metric=>$args{metric}, @_);
      }
    }
  }
  
  1;
}

package multivariate_normal{
  use strict;
  use warnings;
  use AI::MXNet qw(nd);

  #import numpy as np
  #from scipy.stats import multivariate_normal
  #
  ## Datos fijos de prueba
  #X = np.array([[0.5, 1.5], [1.0, 2.0], [-0.5, -0.5]], dtype=np.float32)
  #mean = np.array([0.0, 1.0], dtype=np.float32)
  #cov = np.array([[1.0, 0.5], [0.5, 1.0]], dtype=np.float32)
  #
  ## Obtener densidades verdaderas
  #pdf_esperada = multivariate_normal.pdf(X, mean=mean, cov=cov)
  #print("X:", X.tolist())
  #print("PDF Esperada:", pdf_esperada.tolist())

  #my $X    = nd->array([[0.5, 1.5], [1.0, 2.0], [-0.5, -0.5]]);
  #my $mean = nd->array([0.0, 1.0])->reshape([1, -1]); 
  #my $cov  = nd->array([[1.0, 0.5], [0.5, 1.0]]);
  #
  #my $pdf_calculada = sml->multivariate_normal_pdf($X, $mean, $cov);
  #
  #print "--- COMPROBACIÓN EXACTA DE MULTIVARIATE GAUSSIAN ---\n";
  #print "PDF en Perl MXNet:\n";
  #print $pdf_calculada->asstr('%.8f') . "\n";
  #print "Debe ser igual a:\n[0.15556328, 0.0943539, 0.05722853]\n";

  # Basada en scipy.stats.multivariate_normal.pdf como Función de Densidad de Probabilidad (PDF)
  sub pdf {
    my ($self, $X, $mean, $cov) = @_;
    my ($N, $D) = @{$X->shape};

    # 1. Asegurar regularización idéntica a la configurada en tu pipeline
    my $cov_stable = $cov + (nd->eye($D) * 1e-6);

    # 2. Inversa y determinante estables mediante operaciones nativas de MXNet
    my $inv = nd->linalg->inverse($cov_stable);
    my $det = nd->linalg->det($cov_stable);
    
    # Salvaguarda para el escalar del determinante
    my $det_val = $det->asscalar;
    $det_val = 1e-10 if $det_val <= 0;

    # 3. Centrar datos X frente a la Media usando Broadcasting dinámico
    # Si $mean viene como [1, D], nos aseguramos de que se alinee con [N, D]
    my $X_centered = nd->broadcast_sub($X, $mean->reshape([1, $D]));

    # 4. Forma Cuadrática de Mahalanobis exacta y vectorizada: (X - mu) * Sigma^-1 * (X - mu)^T
    # nd->dot([N, D], [D, D]) -> produce un tensor intermedio de tamaño [N, D]
    my $dot_product = nd->dot($X_centered, $inv);
    
    # Multiplicación elemento a elemento de las diferencias y suma por filas (axis => 1) -> [N]
    my $exponent = nd->sum($dot_product * $X_centered, axis => 1) * -0.5;

    # 5. Factor de normalización Gaussiana multivariada usando constantes flotantes puras
    my $pi = 3.141592653589793;
    my $norm_factor = 1.0 / ( sqrt((2 * $pi)**$D * $det_val) );

    # 6. Retornar el vector de densidades evaluadas [N] multiplicando por el escalar
    return nd->exp($exponent) * $norm_factor;
  }
  
  # Basada en scipy.stats.multivariate_normal.rvs para generar Muestreo (Sampling)
  sub rvs {
    my ($self, $mean, $cov, $size) = @_;
    my $D = $mean->shape->[0];
    
    # 1. Añadir una pequeña regularización para dar estabilidad matemática absoluta
    my $cov_stable = $cov + (nd->eye($D) * 1e-6);
    
    # 2. TRADUCCIÓN EXACTA DE SCIPY: Usar _npi_eigh para matrices simétricas
    # Retorna una lista con: [Autovalores (w), Autovectores (V)]
    my ($w, $V) = @{ nd->_npi_eigh($cov_stable, UPLO => 'L') };
    
    # 3. Forzar estabilidad en los autovalores y calcular su raíz cuadrada (Dispersión)
    my $clipped_w = nd->clip($w, 1e-8, 1e10);
    my $sqrt_w = nd->sqrt($clipped_w);
    
    # 4. Construir la matriz de transformación exacta: V * diag(sqrt_w)
    # Escalamos cada autovector de V usando broadcasting sobre la fila de la raíz
    my $transform = nd->broadcast_mul($V, $sqrt_w->reshape([1, $D]));
    
    # 5. Generar ruido blanco Gaussiano puramente independiente columna por columna
    my @noise_columns;
    for my $d (1 .. $D) {
      push @noise_columns, nd->random->normal(loc => 0.0, scale => 1.0, shape => [$size, 1]);
    }
    my $Z = nd->concat(@noise_columns, dim => 1);
    
    # 6. Proyeccion afín exacta en el espacio bidimensional:
    # Muestras = Z * Transform^T
    my $samples = nd->dot($Z, nd->transpose($transform));
    
    # 7. Desplazar horizontalmente aplicando broadcasting de la media real
    my $X_samples = nd->broadcast_add($samples, $mean->reshape([1, $D]));
    
    return $X_samples;
  }

  1;
}