# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

package AI::MXNet::NDArray;

=head1 NAME

    AI::MXNet::NDArray - Multidimensional tensor object of MXNet.
=cut

=head1 DESCRIPTION

    AI::MXNet::NDArray - Imperative tensor operations on CPU/GPU
    In AI::MXNet, NDArray is the core data structure for all mathematical computations.
    An NDArray represents a multidimensional, fixed-size homogenous array.
    If you're familiar with the PDL, you might notice some similarities.
    However, NDArray is row-major, unlike the PDL that is column-major.
    Like the PDL, MXNet's NDArray enables imperative computation.

    Some NDArray advandages compared to PDL:
    MXNet's NDArray supports fast execution on a wide range of hardware configurations, including CPU, GPU, and multi-GPU machines.
    MXNet also scales to distributed systems in the cloud.
    MXNet's NDArray executes code lazily, allowing it to automatically parallelize multiple operations across the available hardware.

    An NDArray is a multidimensional array of numbers with the same type.
    We could represent the coordinates of a point in 3D space, e.g. [2, 1, 6] as a 1D array with shape (3).
    Similarly, we could represent a 2D array.
    Below, we present an array with length 2 along the first axis and length 3 along the second axis.

    [[0, 1, 2]
     [3, 4, 5]]
    Note that here the use of 'dimension' is overloaded. When we say a 2D array, we mean an array with 2 axes, not an array with two components.

    Each NDArray supports some important attributes that you'll often want to query:

    $ndarray->shape: The dimensions of the array.
    It is an array ref of integers indicating the length of the array along each axis.
    For a matrix with $n rows and $m columns, its shape will be [$n, $m].
    $ndarray->dtype: A string describing the type of its elements.
    Dtype (defined in AI::MXNet::Types) is one of (float32 float64 float16 uint8 int8 int32 int64)
    $ndarray->size: The total number of components in the array - equal to the product of the components of its shape.
    $ndarray->context: The device on which this array is stored, represented by an object of AI::MXNet::Context class, e.g. cpu() or gpu(1).

=cut

use strict;
use warnings;
use Data::Dump qw(dump);
use AI::MXNet::NS;
use AI::MXNet::Base;
use AI::MXNet::NDArray::Slice;
use AI::MXNet::Context;
use AI::MXNet::RunTime;
use Mouse;
use AI::MXNet::Function::Parameters;
use Tie::IxHash;
use overload (
    '""' => \&stringify,
    '+'  => \&add,
    '+=' => \&iadd,
    '-'  => \&subtract,
    '-=' => \&isubtract,
    '*'  => \&multiply,
    '*=' => \&imultiply,
    '/'  => \&divide,
    '/=' => \&idivide,
    '%'  => \&modulo,
    '%=' => \&imodulo,
    '**' => \&power,
    '==' => \&equal,
    '!=' => \&not_equal,
    '>'  => \&greater,
    '>=' => \&greater_equal,
    '<'  => \&lesser,
    '<=' => \&lesser_equal,
    '.=' => \&set,
    '@{}'=> \&split_array,
    '='  => sub { $_[0] },

    'sqrt' => sub { $_[0]->sqrt() },
    'abs' => sub { $_[0]->abs() },
    'sin' => sub { $_[0]->sin() },
    'cos' => sub { $_[0]->cos() },
    'atan2' => \&atan2,
    'log' => sub { $_[0]->log() },
    'exp' => sub { $_[0]->exp() },
);

extends 'AI::MXNet::NDArray::Base';
has 'writable' => (is => 'rw', isa => 'Int', default => 1, lazy => 1);
has 'handle'   => (is => 'rw', isa => 'NDArrayHandle', required => 1);

our %PRINT_OPTIONS = (
    precision => 4,
    threshold => 1000,
    edge      => 3,
    suppress  => 0,
);

# La forma my ($arg1, $arg2) = @_; presupone siempre respetar una cantidad fija de parámetros. Si la cantidad es fija, use ese método.
# Por otro lado, para una cantidad variable de parámetros use siempre la función get_arguments().
# Ella se alimenta de los nombres de cada parámetro acompañados de sus respectivos valores por defecto, ya que está conformada por una arreglo asociativo: key/value.
# Al registrar los parámetros mediante la función get_arguments(), debe siempre respetar el orden establecido de los parámetros,
# para que ella admita saltarse aquellos parámetros que se consideren innecesarios, ya que se alimentará con los valores definidos por defecto.
# Al registrar los parámetros, considere: si en Python es None use el equivalente undef, si es True use 1, si es False use 0, etc.
# Cuando no hay la definición del valor por defecto en el código Python, si el parámetro es de tipo string use la cadena vacía '',
# si es numérico use 0, si es una referencia a un arreglo use [], si es un objeto como un tensor MXNet use undef.
sub get_arguments{
  my ($self, $args, %named_args) = (shift, pop @_, ());
  tie my %args, 'Tie::IxHash';
  %args = @_; # Receives default keys/values
  
  # Tranfering key/value from @$args into %args
  for (my ($i, $key) = 0; $i < @$args; $i++){
    $key = $args->[$i];
    if (defined $key && ref(\$key) eq 'SCALAR' && exists $args{$key} && $key eq 'out'){ # Handling out as an exception, to preserve it in the input @_;
      $i++; # skips its value.
      next;
    }
    if (defined $key && ref(\$key) eq 'SCALAR' && exists $args{$key}){ # key validation.
      $args{$key} = $args->[$i + 1] if defined $args->[$i + 1]; # replaces default value by a newly defined value. Undef is not enough to replace default argument value.
      $named_args{$key} = undef; # stores the key of an updated value
      splice @$args, $i, 2; # removes key and value from @$args
      $i--; # repositioning after removal
    }
  }
  
  # Updating default values of %args out of the first unnamed arguments present in @$args by their respective positions
  while (my ($key, $default_value, $new_value) = each %args){
    # print "$key\n";
    last if !@$args; # Exits if empty @$args
    next if exists $named_args{$key}; # Skips previously updated key/value
    # Elements left must be paired and even positions of @$args must be scalars to be considered as possible keys. In addition, $args->[2*$_] =~ /^[a-zA-Z]\w+$/ must be a variable type.
    last if @$args % 2 == 0 && all{ (defined $args->[2*$_]) && (ref(\$args->[2*$_]) eq 'SCALAR') && ($args->[2*$_] =~ /^[a-zA-Z]\w+$/)} (0 .. (@$args / 2) -1);
    $new_value  = shift @$args;
    $args{$key} = $new_value if defined $new_value; # updates default value
  }
  
  # Handling additional arguments left in @$args at this point
  for (my ($i, $key) = 0; $i < @$args; $i++){
    $key = $args->[$i];
    if (defined $key && ref(\$key) eq 'SCALAR' && !exists $args{$key} && $key =~ /^[a-zA-Z]\w+$/){ # key validation
      # This block might still insert incorrect keys ?
      # print "New attribute found: $key\n";
      $args{$key} = $args->[$i + 1];
      $named_args{$key} = undef; # stores the key
      splice @$args, $i, 2; # removes key and value from @$args
      $i--; # repositioning after removal
    }
  }
  
  return %args;
}

sub set_printoptions {
    my $self = shift;
    my %opts = $self->get_arguments(precision => 4,
                                    threshold => 1000,
                                    edge      => 3,
                                    suppress  => 0,
                                    \@_);

    @PRINT_OPTIONS{keys %opts} = values %opts;
}
# AI::MXNet::NDArray->set_printoptions(precision=>8, threshold=>1000, edge=>3, suppress=>0);

#method asstr($format=)
#{
#    my $precision = $PRINT_OPTIONS{precision};
#    # Si no está definido O es una cadena vacía, usa el formato por defecto
#    my $fmt = (defined($format) && $format ne "") ? $format : "%.${precision}f";
#
#    local $PRINT_OPTIONS{edge} =
#        $self->size <= $PRINT_OPTIONS{threshold}
#            ? 1_000_000
#            : $PRINT_OPTIONS{edge};
#
#    # PASADA PREVIA GLOBAL: ¿Hay algún número negativo en el tensor?
#    # (Usamos tu puente a PDL para hacerlo extremadamente rápido y eficiente)
#    my $pdl = $self->aspdl;
#    my $global_has_negative = ($pdl->lt(0)->any) ? 1 : 0;
#
#    # Pasamos un argumento extra inicializado en undef para la primera llamada
#    return _print_recursive($self, $fmt, 0, [], $global_has_negative, undef);
#}

method asstr($format=)
{
    my $precision = $PRINT_OPTIONS{precision};
    
    # Flag to detect if format is custom or default fallback
    my $is_default_format = (!defined($format) || $format eq "") ? 1 : 0;
    my $fmt = !$is_default_format ? $format : "%.${precision}f";

    local $PRINT_OPTIONS{edge} =
        $self->size <= $PRINT_OPTIONS{threshold}
            ? 1_000_000
            : $PRINT_OPTIONS{edge};

    my $pdl = $self->aspdl;
    my $global_has_negative = ($pdl->lt(0)->any) ? 1 : 0;

    # SURGERY: Pass $is_default_format as the last parameter
    return _print_recursive($self, $fmt, 0, [], $global_has_negative, undef, undef, $is_default_format);
}

#sub _print_recursive {
#    my ($tensor, $fmt, $current_dim, $indices, $global_has_negative, $global_max_len) = @_;
#    
#    my $shape = $tensor->shape;
#    my $ndim  = @$shape;
#    
#    if ($ndim == 0) {
#      return $fmt ? sprintf($fmt, $tensor->aspdl->at(0)) : $tensor->aspdl->at(0); 
#    }
#
#    my $dim_size = $shape->[$current_dim];
#    my $edge     = $PRINT_OPTIONS{edge};
#    
#    my @range;
#    if ($dim_size <= 2 * $edge) {
#      @range = (0 .. $dim_size - 1);
#    } else {
#      @range = (0 .. $edge - 1, '...', $dim_size - $edge .. $dim_size - 1);
#    }
#
#    # =========================================================================
#    # PASO NUEVO: CALCULAR EL ANCHO MÁXIMO GLOBAL ANTES DE PINTAR (Solo en la raíz)
#    # =========================================================================
#    if ($current_dim == 0 && !defined $global_max_len) {
#        my $pdl_all = $tensor->aspdl;
#        my $sample_max_len = 0;
#        
#        # Validar si el formato fue explícitamente enviado o es el genérico
#        my $is_explicit_float = ($fmt =~ /\.\d+f/);
#
#        # SOLUCIÓN DEFINITIVA: ->list extrae todos los elementos como una lista nativa de Perl
#        for my $val ($pdl_all->clump(-1)->list) {
#            my $str;
#            if (!$is_explicit_float && $val == int($val)) {
#                $str = sprintf("%d", $val);
#            } else {
#                $str = $fmt ? sprintf($fmt, $val) : $val;
#                $str =~ s/\.?0+$// if $PRINT_OPTIONS{suppress} and $str =~ /\./ and $str !~ /e/i;
#            }
#            if ($global_has_negative && $val >= 0) { $str = ' ' . $str; }
#            $sample_max_len = length($str) if length($str) > $sample_max_len;
#        }
#        $global_max_len = $sample_max_len;
#    }
#
#    # --- IF WE ARE AT THE LAST DIMENSION ---
#    if ($current_dim == $ndim - 1) {
#      my @raw_strings;
#
#      # Determinar si el formato es un float explícito para esta pasada
#      my $is_explicit_float = ($fmt =~ /\.\d+f/);
#
#      # First pass: Extraer valores y aplicar el formato matemático correcto
#      for my $i (@range) {
#        if ($i eq '...') {
#          push @raw_strings, '...';
#        } else {
#          my @full_indices = (@$indices, $i);
#          my $val = $tensor->slice(map { [$_ , $_ + 1] } @full_indices)->aspdl->at(0);
#          
#          my $str;
#          if (!$is_explicit_float && $val == int($val)) {
#              $str = sprintf("%d", $val);
#          } else {
#              $str = $fmt ? sprintf($fmt, $val) : $val;
#              $str =~ s/\.?0+$// if $PRINT_OPTIONS{suppress} and $str =~ /\./ and $str !~ /e/i;
#          }
#          
#          if ($global_has_negative and $val >= 0) {
#              $str = ' ' . $str;
#          }
#
#          push @raw_strings, $str;
#        }
#      }
#
#      # Second pass: Padding usando el $global_max_len unificado para todo el tensor
#      my @elements;
#      for my $str (@raw_strings) {
#        if ($str eq '...') {
#          push @elements, '...';
#        } else {
#          push @elements, sprintf("%${global_max_len}s", $str);
#        }
#      }
#
#      return '[' . join(' ', @elements) . ']';
#    }
#
#    # --- SI NO ES LA ÚLTIMA DIMENSIÓN (Recursión) ---
#    my @lines;
#    for my $i (@range) {
#        if ($i eq '...') {
#            push @lines, '...';
#        } else {
#            # Propagar $global_max_len aguas abajo en las llamadas recursivas
#            push @lines, _print_recursive($tensor, $fmt, $current_dim + 1, [@$indices, $i], $global_has_negative, $global_max_len);
#        }
#    }
#
#    my $indent = ' ' x ($current_dim + 1);
#    my $newline_join = "\n" . ("\n" x ($ndim - $current_dim - 2)) . $indent;
#    
#    return "[" . join($newline_join, @lines) . "]";
#}

sub _print_recursive {
    # SURGERY: Catch $is_default_format at the end of the signature
    my ($tensor, $fmt, $current_dim, $indices, $global_has_negative, $global_max_len, $col_is_float, $is_default_format) = @_;
    
    my $shape = $tensor->shape;
    my $ndim  = @$shape;
    
    if ($ndim == 0) {
      return $fmt ? sprintf($fmt, $tensor->aspdl->at(0)) : $tensor->aspdl->at(0); 
    }

    my $dim_size = $shape->[$current_dim];
    my $edge     = $PRINT_OPTIONS{edge};
    
    my @range;
    if ($dim_size <= 2 * $edge) {
      @range = (0 .. $dim_size - 1);
    } else {
      @range = (0 .. $edge - 1, '...', $dim_size - $edge .. $dim_size - 1);
    }

    # =========================================================================
    # PRE-ANALYSIS: Analyze Columns and Global Max Length at the Root Level
    # =========================================================================
    if ($current_dim == 0 && (!defined $global_max_len || !defined $col_is_float)) {
        my $pdl_all = $tensor->aspdl;
        $col_is_float = [];

        # SURGERY: If it's an explicit float format passed by user, it rules globally
        my $is_explicit_float = ($fmt =~ /\.\d+f/) && !$is_default_format;

        if ($ndim >= 2) {
            my $num_cols = $shape->[-1];
            for my $col_idx (0 .. $num_cols - 1) {
                my $column_data = $pdl_all->slice("($col_idx)");
                
                # Check if column has fractional values
                my $has_decimals = ($column_data->floor->ne($column_data)->any) ? 1 : 0;
                
                # SURGERY: If user passed explicit float, use it. 
                # Otherwise, it only stays float if the data actually has decimals.
                $col_is_float->[$col_idx] = $is_explicit_float ? 1 : $has_decimals;
            }
        }

        # Compute Global Max Length based on Column Types
        my $sample_max_len = 0;
        
        if ($ndim == 2) {
            for my $r (0 .. $shape->[0] - 1) {
                for my $c (0 .. $shape->[1] - 1) {
                    my $val = $pdl_all->at($c, $r);
                    my $str;
                    
                    # SURGERY: Evaluates column status dynamically
                    my $use_float = $col_is_float->[$c];

                    if (!$use_float && $val == int($val)) {
                        $str = sprintf("%d", $val);
                    } else {
                        $str = $fmt ? sprintf($fmt, $val) : $val;
                        $str =~ s/\.?0+$// if $PRINT_OPTIONS{suppress} and $str =~ /\./ and $str !~ /e/i;
                    }
                    if ($global_has_negative && $val >= 0) { $str = ' ' . $str; }
                    $sample_max_len = length($str) if length($str) > $sample_max_len;
                }
            }
        } else {
            # Fallback for 1D or >2D tensors
            for my $val ($pdl_all->clump(-1)->list) {
                my $str = ($is_explicit_float || $val != int($val)) ? ($fmt ? sprintf($fmt, $val) : $val) : sprintf("%d", $val);
                if ($global_has_negative && $val >= 0) { $str = ' ' . $str; }
                $sample_max_len = length($str) if length($str) > $sample_max_len;
            }
        }
        $global_max_len = $sample_max_len;
    }

    # --- IF WE ARE AT THE LAST DIMENSION ---
    if ($current_dim == $ndim - 1) {
      my @raw_strings;
      #my $is_explicit_float = ($fmt =~ /\.\d+f/);
      # SURGERY: If it's an explicit float format passed by user, it rules globally
      my $is_explicit_float = ($fmt =~ /\.\d+f/) && !$is_default_format;

      # First pass: Extract values and apply the proper column-based format
      for my $i (@range) {
        if ($i eq '...') {
          push @raw_strings, '...';
        } else {
          my @full_indices = (@$indices, $i);
          my $val = $tensor->slice(map { [$_ , $_ + 1] } @full_indices)->aspdl->at(0);
          
          # Detect column tracking index
          my $col_idx = $i; 
          my $use_float = $is_explicit_float || ($col_is_float->[$col_idx] // ($val != int($val)));

          my $str;
          if (!$use_float && $val == int($val)) {
              $str = sprintf("%d", $val);
          } else {
              $str = $fmt ? sprintf($fmt, $val) : $val;
              $str =~ s/\.?0+$// if $PRINT_OPTIONS{suppress} and $str =~ /\./ and $str !~ /e/i;
          }
          
          if ($global_has_negative and $val >= 0) {
              $str = ' ' . $str;
          }

          push @raw_strings, $str;
        }
      }

      # Second pass: Dynamic Padding with uniform max length
      my @elements;
      for my $str (@raw_strings) {
        if ($str eq '...') {
          push @elements, '...';
        } else {
          push @elements, sprintf("%${global_max_len}s", $str);
        }
      }

      return '[' . join(' ', @elements) . ']';
    }

    # --- IF NOT AT THE LAST DIMENSION (Recursion) ---
    my @lines;
    for my $i (@range) {
        if ($i eq '...') {
            push @lines, '...';
        } else {
            push @lines, _print_recursive($tensor, $fmt, $current_dim + 1, [@$indices, $i], $global_has_negative, $global_max_len, $col_is_float, $is_default_format);
        }
    }

    my $indent = ' ' x ($current_dim + 1);
    my $newline_join = "\n" . ("\n" x ($ndim - $current_dim - 2)) . $indent;
    
    return "[" . join($newline_join, @lines) . "]";
}

sub print{
  my $self = shift;
  my $fmt = "";
  
  # Unificar $self y @_ si se llamó como función estática o método de clase
  my @items = (blessed($self) || ref($self)) ? ($self, @_) : (@_);
  
  # 1. DETECCIÓN DE FORMATO GLOBAL / MIXTO
  if (defined($items[0]) && !ref($items[0]) && $items[0] =~ /(?<!%)%(?!%)/) {
      
    # Caso A: Es un printf clásico puro (solo escalares subsiguientes)
    if (!grep { ref($_) } @items[1 .. $#items]) {
      my $template = shift @items;
      printf $template, @items;
      print "\n";
      return;
    }
    
    # Caso B: Es un formato mixto destinado a un Tensor (e.g., "Dataset:\n%.5f")
    # Extraemos el texto descriptivo previo y aislamos el token de formato numérico
    my $raw_str = shift @items;
    if ($raw_str =~ /^(.*)(%\.\d+f|%[dfgs])(.*)$/s) {
      my ($before, $extracted_fmt, $after) = ($1, $2, $3);
      print STDERR "The function print() does not admit format. Use printf() instead to introduce formats.\n";
      # print $before if $before; # Imprime "Dataset:\n" limpiamente
      $fmt = $extracted_fmt;    # Guarda "%.5f" para el tensor
      # Si quedó texto remanente después del formato, lo reinyectamos
      unshift @items, $after if $after && $after =~ /\S/;
    } else {
      $fmt = $raw_str;
    }
  }
  
  my $line_break;
  if(blessed($self) and ref($self) =~ /^AI::MXNet::NDArray(?:::Slice)?$/){
    print $self->asstr($fmt), "\n", $self, " ", ref($self), " ", $self->dtype, "\n";
    $line_break = 1;
  } else {
    # Unificar $self y @_ si se llamó como función estática o método de clase
    my @items = (blessed($self) || ref($self)) ? ($self, @_) : (@_);
    
    for my $piece (@items){
      if (ref($piece) =~ /^AI::MXNet::NDArray(?:::Slice)?$/) {
        print $piece->asstr($fmt), "\n", $piece, " ", ref($piece), " ", $piece->dtype, "\n";
        $line_break = 1;
      } elsif (ref($piece) eq 'HASH') {
        # Recorrer de uno en uno el Hash imprimiendo las claves y formateando los tensores
        for my $key (sort keys %$piece) {
          my $val = $piece->{$key};
          if (ref($val) =~ /^AI::MXNet::NDArray(?:::Slice)?$/) {
            print $key, ":\n", $val->asstr($fmt), "\n", $val, " ", ref($val), " ", $val->dtype, "\n";
            $line_break = 1;
          } else {
            # Si el valor interno no es un tensor (escalar, sub-array, etc.), usar dump normal
            print $key, " => ", dump($val);
            $line_break = 0;
          }
        }
      }elsif (ref($piece) eq 'PDL') {
        print $piece;
        $line_break = 1 if $piece =~ m/\n$/;
      } elsif (ref($piece)) {
        # Cualquier otra referencia (ARRAY, SCALAR, etc.) usa el dump por defecto
        print dump $piece;
        $line_break = 0;
      } else {
        # Cadenas de texto o escalares planos
        print $piece;
        $line_break = 0;
      }
    }
  }
  print "\n" unless $line_break;
}

#sub printf{
#  my $self = shift;
#  my $fmt = "";
#  
#  # Unificar $self y @_ si se llamó como función estática o método de clase
#  my @items = (blessed($self) || ref($self)) ? ($self, @_) : (@_);
#  
#  # 1. DETECCIÓN DE FORMATO GLOBAL / MIXTO
#  if (defined($items[0]) && !ref($items[0]) && $items[0] =~ /(?<!%)%(?!%)/) {
#      
#    # Caso A: Es un printf clásico puro (solo escalares subsiguientes)
#    if (!grep { ref($_) } @items[1 .. $#items]) {
#      my $template = shift @items;
#      printf $template, @items;
#      print "\n";
#      return;
#    }
#    
#    # Caso B: Formato mixto con uno o múltiples formatos asociados a variables/tensores
#    # Extraemos el texto descriptivo previo y aislamos el token de formato numérico
#    my $raw_str = shift @items;
#    if ($raw_str =~ /^(.*?)(%\.\d+f|%[dfgs])(.*)$/s) {
#      my ($before, $extracted_fmt, $after) = ($1, $2, $3);
#      print $before if $before; # Imprime "P_mat:\n" limpiamente
#      $fmt = $extracted_fmt;    # Guarda "%.6f" para el tensor inmediato ($P_mat)
#      # SURGERY: Reinyectamos el resto de la cadena ("\nP_condensed:\n%.6f\n") 
#      # en la posición 1 de @items para que se procese secuencialmente tras el tensor actual
#      splice @items, 1, 0, $after if defined $after && $after ne '';
#    } else {
#      $fmt = $raw_str;
#    }
#  }
#  
#  # Si el objeto base es un Tensor Puro aislado sin más argumentos
#  if (blessed($self) and ref($self) =~ /^AI::MXNet::NDArray(?:::Slice)?$/ && scalar(@items) == 0) {
#    printf "%s\n%s %s %s\n", $self->asstr($fmt), $self, ref($self), $self->dtype;
#    return;
#  }
#  
#  my $line_break = 0;
#  
#  # 2. PROCESAMIENTO SEGMENTADO O MIXTO
#  for my $piece (@items) {
#    if (ref($piece) =~ /^AI::MXNet::NDArray(?:::Slice)?$/) {
#      printf "%s\n%s %s %s\n", $piece->asstr($fmt), $piece, ref($piece), $piece->dtype;
#      $line_break = 1;
#    } elsif (ref($piece) eq 'HASH') {
#      for my $key (sort keys %$piece) {
#        my $val = $piece->{$key};
#        if (ref($val) =~ /^AI::MXNet::NDArray(?:::Slice)?$/) {
#          printf "%s:\n%s\n%s %s %s\n", $key, $val->asstr($fmt), $val, ref($val), $val->dtype;
#          $line_break = 1;
#        } else {
#          printf "%s => %s", $key, dump($val);
#          $line_break = 0;
#        }
#      }
#    } elsif (ref($piece)) {
#      printf "%s", dump $piece;
#      $line_break = 0;
#    } elsif (defined($piece) && !ref($piece) && $piece =~ /^\s*%\.?\d*[dfgs]\s*$/) {
#      # Validar formatos dinámicos en línea más amplios (e.g., "%.5f", "%d", "%g")
#      $fmt = $piece; 
#      $fmt =~ s/\s//g; # Limpiar espacios en blanco
#      next;
#    } else {
#      # Cadenas de texto o escalares planos
#      printf $fmt ? ($fmt, $piece) : $piece;
#      $line_break = 0;
#    }
#    $fmt = "";
#  }
#  
#  print "\n" unless $line_break;
#}

sub printf {
  my $self = shift;
  my $fmt = "";
  
  # Unificar $self y @_ si se llamó como función estática o método de clase
  my @items = (blessed($self) || ref($self)) ? ($self, @_) : (@_);
  
  # 1. DETECCIÓN DE FORMATO GLOBAL / MIXTO
  if (defined($items[0]) && !ref($items[0]) && $items[0] =~ /(?<!%)%(?!%)/) {
      
    # Caso A: Es un printf clásico puro (solo escalares subsiguientes)
    if (!grep { ref($_) } @items[1 .. $#items]) {
      my $template = shift @items;
      printf $template, @items;
      print "\n";
      return;
    }
    
    # =========================================================================
    # SURGERY: Caso B: Descomposición iterativa multi-variable y multi-formato
    # =========================================================================
    my $raw_str = shift @items;
    my @reconstructed_items;
    
    # Extrae iterativamente el texto base (antes) y el token de formato
    while ($raw_str =~ /^(.*?)(%\.\d+f|%[dfgs])(.*)$/s) {
        my $before = $1;
        my $extracted_fmt = $2;
        $raw_str = $3; # El remanente pasa a ser el nuevo raw_str
        
        # 1. Si había texto descriptivo previo (ej: "P_mat:\n"), lo agregamos
        push @reconstructed_items, $before if defined $before && $before ne '';
        
        # 2. Agregamos el token de formato aislado (ej: "%.6f")
        push @reconstructed_items, $extracted_fmt;
        
        # 3. Extraemos el objeto/tensor correspondiente de la cola original y lo emparejamos
        if (@items) {
            push @reconstructed_items, shift @items;
        }
    }
    # Si sobró texto al final de la cadena (ej: un "\n" de cierre), se agrega al final
    push @reconstructed_items, $raw_str if defined $raw_str && $raw_str ne '';
    
    # Reemplazamos @items con la nueva lista completamente aplanada y ordenada secuencialmente
    @items = (@reconstructed_items, @items);
  }
  
  # Si el objeto base es un Tensor Puro aislado sin más argumentos
  if (blessed($self) and ref($self) =~ /^AI::MXNet::NDArray(?:::Slice)?$/ && scalar(@items) == 0) {
    printf "%s\n%s %s %s\n", $self->asstr($fmt), $self, ref($self), $self->dtype;
    return;
  }
  
  my $line_break = 0;
  
  # 2. PROCESAMIENTO SEGMENTADO O MIXTO (Trabaja de manera nativa con el nuevo @items ordenado)
  while (my ($i, $piece) = each @items) {
    if (ref($piece) =~ /^AI::MXNet::NDArray(?:::Slice)?$/) {
      my $in_fmt = $i < $#items && $items[$i +1] =~ m/^\s*\n/ ? "%s\n%s %s %s" : "%s\n%s %s %s\n";
      printf $in_fmt, $piece->asstr($fmt), $piece, ref($piece), $piece->dtype;
      $line_break = 1 if $in_fmt =~ m/\n$/;
    } elsif (ref($piece) eq 'HASH') {
      for my $key (sort keys %$piece) {
        my $val = $piece->{$key};
        if (ref($val) =~ /^AI::MXNet::NDArray(?:::Slice)?$/) {
          printf "%s:\n%s\n%s %s %s\n", $key, $val->asstr($fmt), $val, ref($val), $val->dtype;
          $line_break = 1;
        } else {
          printf "%s => %s", $key, dump($val);
          $line_break = 0;
        }
      }
      
    }elsif (ref($piece) eq 'PDL') {
      print $piece;
      $line_break = 1 if $piece =~ m/\n$/;
    } elsif (ref($piece)) {
      printf "%s", dump $piece;
      $line_break = 0;
    } elsif (defined($piece) && !ref($piece) && $piece =~ /^\s*%\.?\d*[dfgs]\s*$/) {
      # El formato se captura aquí en su turno y se aplica inmediatamente al siguiente objeto
      $fmt = $piece; 
      $fmt =~ s/\s//g; 
      next;
    } else {
      # Cadenas de texto o escalares planos se imprimen usando el formato actual
      printf $fmt ? ($fmt, $piece) : $piece;
      $line_break = 0;
    }
    $fmt = "";
  }
  
  print "\n" unless $line_break;
}

sub DEMOLISH
{
    check_call(AI::MXNetCAPI::NDArrayFree(shift->handle));
}

method STORABLE_freeze($cloning)
{
    my $buf = check_call(AI::MXNetCAPI::NDArraySaveRawBytes($self->handle));
    return ($buf,\ $self->writable);
}

method STORABLE_thaw($cloning, $buf, $writable)
{
    my $handle = check_call(
                    AI::MXNetCAPI::NDArrayLoadFromRawBytes(
                        $buf, length($buf)
                    )
    );
    $self->handle($handle);
    $self->writable($$writable);
}

method split_array(@args)
{
    my $shape = $self->shape;
    return [] if $shape->[0] == 0;
    my $list = $self->split(num_outputs=>$shape->[0],
        squeeze_axis=>int(@$shape > 1), axis=>0);
    $shape->[0] == 1 ? [ $list ] : $list;
}

method at(Index @indices)
{
    confess("No idxs supplied") unless @indices;
    my $shape = $self->shape;
    my $dsize = @$shape;
    my $isize = @indices;
    confess("Dimensions size $dsize < indexes size $isize")
        if $dsize < $isize;
    confess("Dimensions size $dsize = indexes size $isize,
                   ndarray only supports either ->at on dimension 0
                   or full crop")
        if $isize > 1 and $dsize != $isize;
    my $i = 0;
    for(zip(\@indices, $shape)) {
        my ($idx, $dim_size) = @$_;
        confess("Dimension $i mismatch Idx: $idx >= Dim Size: $dim_size")
            if $idx >= $dim_size or ($idx + $dim_size) < 0;
        ++$i;
    }
    $i = 0;
    for my $v (@indices)
    {
        $v += $shape->[$i] if $v < 0;
        ++$i;
    }
    # return $self->_at($indices[0]) if @indices == 1;
    return $self->slice(@indices);
}

method len() { $self->shape->[0] }

method slice(Slice|AdvancedSlice|InternalSlice|Undef @slices){
    confess("No slices supplied") unless @slices;
    #if(grep { not ref and /^(?:begin|end|slice)$/ } @slices)
    #{
    #    return $self->SUPER::slice(@slices);
    #}
    if(grep { defined($_) and not ref($_) and /^(?:begin|end|step)$/ } @slices){
        my %args = @slices;
        
        if(exists $args{begin} || exists $args{end} || exists $args{step}){
            my ($begin, $end, $step) = ($args{begin}, $args{end}, $args{step});
            my $shape = $self->shape;
            my $ndim = @$shape;
            
            #
            # 1-D syntax
            #
            if ($ndim == 1 || !(ref($begin) eq 'ARRAY' || ref($end) eq 'ARRAY' || ref($step) eq 'ARRAY')) {
                my $begin = defined($begin) ? $begin : 0;
                my $end   = defined($end) ? $end : $shape->[0];
                my $step  = defined($step) ? $step : 1;
                return $self->slice([$begin, $end, $step]);
            }
            
            #
            # Multi-dimensional syntax
            #
            if(ref($begin) eq 'ARRAY' || ref($end) eq 'ARRAY' || ref($step) eq 'ARRAY'){
                
                my @expanded;
                
        
                for my $i (0 .. $ndim-1){
                    
                    my $inicio = ref($begin) eq 'ARRAY'
                            ? ($i <= $#$begin ? defined($begin->[$i]) ? $begin->[$i] : 0 : 0)
                            : (defined($begin) ? $begin : 0);
                            
                    my $fin = ref($end) eq 'ARRAY'
                            ? ($i <= $#$end ? defined($end->[$i]) ? $end->[$i] : $shape->[$i] : $shape->[$i])
                            : (defined($end) ? $end : $shape->[$i]);
        
                    my $salto = ref($step) eq 'ARRAY'
                            ? ($i <= $#$step ? defined($step->[$i]) ? $step->[$i] : 1 : 1)
                            : (defined($step) ? $step : 1);
        
                    push @expanded, [$inicio, $fin, $salto];
                }
                
                return $self->slice(@expanded);
            }

        }
    
        return $self->SUPER::slice(@slices);
    }
    if(ref $slices[0] eq 'ARRAY' and ref $slices[0]->[0])
    {
        my @indices;
        my $key = $slices[0];
        my $dtype = 'int32';
        for my $idx_i (@{ $key })
        {
            if(not (blessed $idx_i and $idx_i->isa(__PACKAGE__))){
                $idx_i = __PACKAGE__->array($idx_i, ctx=>$self->context, dtype=>$dtype);
            }
            else{
                $dtype = $idx_i->dtype;
            }
            push @indices, $idx_i;
        }
        my $indices = __PACKAGE__->stack(@indices);
        return __PACKAGE__->gather_nd($self, $indices);
    }
    my $shape = $self->shape;
    
    # Expand ellipsis (...)
    my $ellipsis_count = scalar grep { !ref($_) && $_ eq '...' } @slices;

    if($ellipsis_count){
        confess("Only one ellipsis (...) is allowed")
            if $ellipsis_count > 1;
    
        my ($ellipsis_pos) = grep { !ref($slices[$_]) && $slices[$_] eq '...' } 0 .. $#slices;
        my $missing = @$shape - (@slices - 1);
        splice(@slices, $ellipsis_pos, 1, ((':') x $missing));
    }
        
    my $dsize = @$shape;
    my $isize = @slices;
    
    confess("Too many dimensions on a $dsize-D tensor: $isize")
        if $dsize < $isize;
    confess("Dimensions size $dsize != slices size $isize,
                   ndarray only supports either ->slice on dimension 0
                   or full crop")
        if $isize > 1 and $dsize != $isize;

    my $i = -1;
    @slices = map {
        ++$i;
        if(ref($_) eq 'ARRAY'){ # Arrays
            if(@$_ == 1){
                [$_->[0], $_->[0], 1, '__INDEX__'];
            }else{
                my ($begin, $end, $step) = @$_;
                $begin = 0            unless defined $begin;
                $end   = $shape->[$i] unless defined $end;
                $step  = 1            unless defined $step;
                [$begin, $end, $step, '__SLICE__'];
            }
        }else{ # Scalars
            ($_ =~ /^[X:]$/)
                ? [0, $shape->[$i], 1, '__SLICE__']
                : [$_, $_, 1, '__INDEX__'];
        }
    
    } @slices;

    for(zip(\@slices, $shape)) { # Validation
        my ($slice, $dim_size) = @$_;
        my ($begin, $end, $stride, $kind) = @$slice;
        $stride //= 1;
        
        confess("Slice stride must be > 0")
            if $stride <= 0;
        confess("Out of bounds: Invalid range at axis $i: begin : $begin > end : $dim_size. Tensor shape: [" . join(",", @{$self->shape}). "]")
            if $begin >= $dim_size or ($begin + $dim_size) < 0;
        confess("Out of bounds: at axis $i mismatch slice end : $end > Dim Size: $dim_size. Tensor shape: [" . join(",", @{$self->shape}). "]")
            if $end > $dim_size or ($end + $dim_size) < 0;
    }
    $i = 0;
    my ($begin, $end, $step) = ([], [], []);
    my @squeeze_axes;
    for my $s (@slices){
        $s->[0] += $shape->[$i] if $s->[0] < 0;
        $s->[1] += $shape->[$i] if $s->[1] < 0;
        confess("Dimension $i slice mismatch (begin $s->[0] > end $s->[1])")
            if($s->[0] > $s->[1]);
        my ($inicio, $fin, $stride, $kind) = @$s;
        push @$begin, $inicio;
        push @$end, $kind eq '__INDEX__' ? $fin + 1 : $fin;
        push @$step,  defined($stride) ? $stride : 1;
        push @squeeze_axes, $i if $kind eq '__INDEX__';
        $i++;
    }
    # return $self->_slice($begin->[0], $end->[0]) if @slices == 1;
    return new AI::MXNet::NDArray::Slice(parent => $self, begin => $begin, end => $end, step => $step, squeeze_axes => \@squeeze_axes);
}

method set(AcceptableInput $value, $reverse=)
{
    confess("set value must be defined") unless defined $value;
    confess("Array is not writable") if not $self->writable;
    ## plain number
    if(not ref $value){
        $self->_set_value($value, out => $self);
    }
    # ndarray
    elsif(blessed($value) and $value->isa(__PACKAGE__)){
        $value->copyto($self);
    }
    # slice of another ndarray
    elsif(blessed($value) and $value->isa('AI::MXNet::NDArray::Slice')){
        $value->sever->copyto($self);
    }
    # perl array, PDL, PDL::Matrix
    else{
        $self->_sync_copyfrom($value);
    }
    return $self;
}

=pod
method asscalar()
{
    confess("ndarray size must be 1") unless $self->size == 1;
    if (ref($self) =~ /^AI::MXNet::NDArray(?:::Slice)?$/) {
      return $self->aspdl->at(0);
    }
    ## code below works happily on CPU/segfaults on GPU
    #$self->wait_to_read;
    #my $perl_pack_type = DTYPE_MX_TO_PERL->{$self->dtype};
    #my $length = {qw/f 4 d 8 S 2 C 1 l 4/}->{$perl_pack_type};
    #return
    #(map {
    #        $perl_pack_type eq 'S' ? AI::MXNetCAPI::_half_to_float($_) : $_
    #     } unpack("$perl_pack_type", check_call(AI::MXNetCAPI::NDArrayGetData($self->handle, $length)))
    #)[0];
}
=cut

# --- Subrutina auxiliar ultrarrápida para CPU
method asscalar()
{
    confess("ndarray size must be 1") unless $self->size == 1;
    
    # 1. Detectar si estamos en CPU o GPU
    my $ctx = $self->context;
    my $device_type = $ctx->device_type; # 'cpu' o 'gpu'
    
    my $perl_pack_type = DTYPE_MX_TO_PERL->{$self->dtype};
    
    my $dtype = $self->dtype;
    confess("Unsupported dtype '$dtype'")
        unless defined $perl_pack_type;
    
    my %PACK_LENGTH = (f => 4, d => 8, S => 2, C => 1, c => 1, l => 4, q => 8,);
    
    my $length = $PACK_LENGTH{$perl_pack_type}
        // confess("Unknown Perl pack type '$perl_pack_type'");
    
    # Asegurar que las operaciones asíncronas previas en C++ hayan terminado
    $self->wait_to_read;
    
    if ($device_type eq 'cpu') {
        # --- RUTA ULTRA-RÁPIDA PARA CPU ---
        # Acceso directo a memoria RAM nativa (Cero conversión, cero PDL)
        my $value = (map {
            $perl_pack_type eq 'S'
                ? AI::MXNetCAPI::_half_to_float($_)
                : $_
        } unpack($perl_pack_type,
            check_call(
                AI::MXNetCAPI::NDArrayGetData($self->handle, $length)
            )
        ))[0];

        return $dtype eq 'bool' ? !!$value : $value; # !!$value garantiza que el resultado sea un booleano de Perl:
        
    } else {
        # --- RUTA SEGURA PARA GPU ---
        # Creamos una variable escalar de Perl para recibir los bytes binarios
        my $buffer = "\0" x $length;

        # Sincronizamos y extraemos de la GPU a la memoria de la CPU de Perl en un solo paso
        # Esta función de la CAPI acepta un puntero de destino en CPU ($buffer)
        check_call(
            AI::MXNetCAPI::NDArraySyncCopyToCPU(
                $self->handle,
                $buffer,
                1
            )
        );

        # Desempaquetamos de forma segura el buffer copiado de la GPU
        my $value = (map {
            $perl_pack_type eq 'S'
                ? AI::MXNetCAPI::_half_to_float($_)
                : $_
        } unpack($perl_pack_type, $buffer))[0];

        return $dtype eq 'bool' ? !!$value : $value;
    }
}

method _sync_copyfrom(ArrayRef|PDL|PDL::Matrix $source_array)
{
    my $dtype = $self->dtype;
    my $pdl_type = PDL::Type->new(DTYPE_MX_TO_PDL->{ $dtype });
    if(not blessed($source_array))
    {
        $source_array = eval {
            pdl($pdl_type, $source_array);
        };
        confess($@) if $@;
    }
    if($pdl_type->numval != $source_array->type->numval)
    {
        my $convert_func = $pdl_type->convertfunc;
        $source_array = $source_array->$convert_func;
    }
    $source_array = pdl($pdl_type, [@{ $source_array->unpdl } ? $source_array->unpdl->[0] : 0 ])
        unless @{ $source_array->shape->unpdl };
    my $pdl_shape = $source_array->shape->unpdl;
    my $pdl_shape_str = join(',', ref($source_array) eq 'PDL' ? reverse @{ $pdl_shape } : @{ $pdl_shape });
    my $ndary_shape_str = join(',', @{ $self->shape });
    if($pdl_shape_str ne $ndary_shape_str)
    {
        confess("Shape inconsistant: expected $ndary_shape_str vs got $pdl_shape_str")
    }
    my $perl_pack_type = DTYPE_MX_TO_PERL->{$dtype};
    my $ptr = $source_array->get_dataref;
    ## special handling for float16
    if($perl_pack_type eq 'S')
    {
        $ptr = \( pack("S*", map { AI::MXNetCAPI::_float_to_half($_) } unpack ("f*", $$ptr)) );
    }
    check_call(AI::MXNetCAPI::NDArraySyncCopyFromCPU($self->handle, $$ptr, $self->size));
    return $self;
}

=head2 aspdl

    Returns a copied PDL array of current array.

    Returns
    -------
    array : PDL
        A copy of the array content.
=cut

method aspdl($format=)
{
    my $dtype = $self->dtype;
    my $pdl_type = PDL::Type->new(DTYPE_MX_TO_PDL->{ $dtype });
    my $pdl = PDL->new_from_specification($pdl_type, reverse @{ $self->shape });
    my $perl_pack_type = DTYPE_MX_TO_PERL->{$dtype};
    my $ptr = $pdl->get_dataref;
    check_call(AI::MXNetCAPI::NDArraySyncCopyToCPU($self->handle, $$ptr, $self->size));
    ## special handling for float16
    if($perl_pack_type eq 'S')
    {
        $$ptr = pack("f*", map { AI::MXNetCAPI::_half_to_float($_) } unpack("S*", $$ptr));
    }
    $pdl->upd_data;
    return $pdl;
}

method asarray()
{
    my $dtype = $self->dtype;
    my $pdl_type = PDL::Type->new(DTYPE_MX_TO_PDL->{ $dtype });
    my $pdl = PDL->new_from_specification($pdl_type, reverse @{ $self->shape });
    my $perl_pack_type = DTYPE_MX_TO_PERL->{$dtype};
    my $ptr = $pdl->get_dataref;
    check_call(AI::MXNetCAPI::NDArraySyncCopyToCPU($self->handle, $$ptr, $self->size));
    ## special handling for float16
    if($perl_pack_type eq 'S')
    {
        $$ptr = pack("f*", map { AI::MXNetCAPI::_half_to_float($_) } unpack("S*", $$ptr));
    }
    $pdl->upd_data;
    my $result = $pdl->unpdl;
    $result = ref ($result) eq 'ARRAY' ? $result : [$result];
    return $result;
}

method tolist()
{
    return @{$self->asarray};
}

=head2 asmpdl

    Returns copied PDL::Matrix objectt of current array.

    Requires caller to "use PDL::Matrix" in user space.

    Returns
    -------
    array : PDL::Matrix
        A copy of array content.
=cut

method asmpdl()
{
    my $dtype = $self->dtype;
    my $pdl_type = PDL::Type->new(DTYPE_MX_TO_PDL->{ $dtype });
    my $pdl = PDL::Matrix->new_from_specification($pdl_type, @{ $self->shape });
    my $perl_pack_type = DTYPE_MX_TO_PERL->{$dtype};
    my $ptr = $pdl->get_dataref;
    check_call(AI::MXNetCAPI::NDArraySyncCopyToCPU($self->handle, $$ptr, $self->size));
    ## special handling for float16
    if($perl_pack_type eq 'S')
    {
        $$ptr = pack("f*", map { AI::MXNetCAPI::_half_to_float($_) } unpack("S*", $$ptr));
    }
    $pdl->upd_data;
    return $pdl;
}


=head2 _slice

    Returns sliced NDArray that shares memory with the current one.
    Does not allow step.

    Parameters
    ----------
    start : int
        Starting index of slice.
    stop : int
        Finishing index of slice.
=cut

method _slice (
    Index $start,
    Index $stop
)
{
    confess("start $start > stop $stop") if $start > $stop;
    my $sub = AI::MXNet::RunTime->Features()->is_enabled('INT64_TENSOR_SIZE')
              ? \&AI::MXNetCAPI::NDArraySlice64
              : \&AI::MXNetCAPI::NDArraySlice;
    my $handle = check_call(
        $sub->(
            $self->handle,
            $start,
            $stop
        )
    );
    return __PACKAGE__->_ndarray_cls($handle, $self->writable);
}

=head2  _at

    Returns a sub NDArray that shares memory with current one.

    Parameters
    ----------
    idx : int
        index of the sub array.
=cut


method _at(Index $idx)
{
    my $sub = AI::MXNet::RunTime->Features()->is_enabled('INT64_TENSOR_SIZE')
              ? \&AI::MXNetCAPI::NDArrayAt64
              : \&AI::MXNetCAPI::NDArrayAt;
    my $handle = check_call(
                $sub->(
                    $self->handle, $idx >=0 ? $idx : $self->shape->[0] + $idx
                )
    );
    return __PACKAGE__->_ndarray_cls($handle, $self->writable);
}

=head2 reshape

    Returns a **view** of this array with a new shape without altering any data.
    One shape dimension can be -1. In this case, the value is inferred
    from the length of the array and remaining dimensions.

    Parameters
    ----------
    $new_shape : Shape
        new shape of NDArray
    :$reverse : bool, default 0
        If true then the special values are inferred from right to left.
=cut

method reshape(ArrayRef[Int] $new_shape, Bool :$reverse=0)
{
    my $handle = check_call(
                    AI::MXNetCAPI::NDArrayReshape64(
                        $self->handle,
                        scalar(@$new_shape),
                        $new_shape,
                        $reverse
                    )
    );
    return __PACKAGE__->_ndarray_cls($handle, $self->writable);
}

=head2 ndim

    Returns the number of dimensions of this array.
=cut

method ndim()
{
    scalar(@{ $self->shape });
}

=head2 moveaxis

    Moves the 'source' axis into the 'destination' position
    while leaving the other axes in their original order

    Parameters
    ----------
    source : int
        Original position of the axes to move.
    destination : int
        Destination position for each of the original axes.

    Returns
    -------
    result :NDArray
    Array with moved axes.

    Examples
    --------
    > $X = mx->nd->array([[1, 2, 3],
                          [4, 5, 6]]);
    > print Dumper($X->moveaxis(0, 1)->shape)
    > [3, 2]
=cut

method moveaxis(Int $source, Int $dest)
{
    my @axes = 0..$self->ndim-1;
    $source += @axes if $source < 0;
    $dest += @axes if $dest < 0;
    assert($source < @axes);
    assert($dest < @axes);
    my ($to_move) = splice(@axes, $source, 1);
    splice(@axes, $dest, 0, $to_move);
    return __PACKAGE__->transpose($self, \@axes);
}

=head2 broadcast_to

    Broadcasting the current NDArray into the given shape.

    Parameters
    ---------
    Shape $shape : the shape to broadcast
=cut

method broadcast_to(Shape $shape)
{
    my $cur_shape = $self->shape;
    my $err_str = "operands could not be broadcast together with remapped shapes"
                  ."[original->remapped]: [@$cur_shape] and requested shape [@$shape]";
    if(@$shape < @$cur_shape)
    {
        confess($err_str);
    }
    @$cur_shape = ((1)x(@$shape - @$cur_shape), @$cur_shape);
    my $cur_shape_arr = pdl($cur_shape);
    my $broadcasting_axes = ($cur_shape_arr != pdl($shape))->which->unpdl;
    if (grep { $cur_shape->[$_] != 1 } @$broadcasting_axes)
    {
        confess($err_str);
    }
    if(join(',',@$cur_shape) ne join(',',@{ $self->shape }))
    {
        # return __PACKAGE__->SUPER::broadcast_to($self->reshape($cur_shape), { shape => $shape });
        return __PACKAGE__->_npi_broadcast_to($self->reshape($cur_shape), shape => $shape );
    }
    else
    {
        # return __PACKAGE__->SUPER::broadcast_to($self, { shape => $shape });
        return __PACKAGE__->_npi_broadcast_to($self, shape => $shape);
    }
}

=head2 wait_to_read

    Block until all pending write operations on the NDArray are finished.

    This function will return when all the pending writes to the current
    NDArray are finished. There can be pending reads going on when the
    function returns.
=cut

method wait_to_read()
{
    check_call(AI::MXNetCAPI::NDArrayWaitToRead($self->handle));
}

=head2 shape

    Get the shape of current NDArray.

    Returns
    -------
    an array ref representing the shape of current ndarray
=cut

method shape()
{
    if(AI::MXNet::RunTime->Features()->is_enabled('INT64_TENSOR_SIZE'))
    {
        return [map { $_ + 0 } @{ scalar(check_call(AI::MXNetCAPI::NDArrayGetShapeEx64($self->handle))) }];
    }
    else
    {
       return scalar(check_call(AI::MXNetCAPI::NDArrayGetShapeEx($self->handle)));
    }
}

=head2 size

    Number of elements in the array.
=cut

method size(Shape|Undef $shape=)
{
    my $size = 1;
    map { $size *= $_ } @{ $shape//$self->shape };
    return $size;
}


=head2 context

    The context of the NDArray.

    Returns
    -------
    $context : AI::MXNet::Context
=cut

method context()
{
    my ($dev_type_id, $dev_id) = check_call(
        AI::MXNetCAPI::NDArrayGetContext($self->handle)
    );
    return AI::MXNet::Context->new(
        device_type => AI::MXNet::Context::devtype2str->{ $dev_type_id },
        device_id => $dev_id
    );
}

=head2 dtype

    The data type of current NDArray.

    Returns
    -------
    a data type string ('float32', 'float64', 'float16', 'uint8', 'int32')
    representing the data type of the ndarray.
    'float32' is the default dtype for the ndarray class.
=cut

method dtype()
{
    my $dtype = check_call(
        AI::MXNetCAPI::NDArrayGetDType(
            $self->handle
        )
    );
    
    # print "MXNet dtype code = $dtype\n";
    
    return DTYPE_MX_TO_STR->{ $dtype };
}

=head2 copyto

    Copy the content of current array to another entity.

    When another entity is the NDArray, the content is copied over.
    When another entity is AI::MXNet::Context, a new NDArray in the context
    will be created.

    Parameters
    ----------
    other : NDArray or Context
        Target NDArray or context we want to copy data to.

    Returns
    -------
    dst : NDArray
=cut

method copyto(AI::MXNet::Context|AI::MXNet::NDArray $other)
{
    if(blessed($other) and $other->isa('AI::MXNet::Context'))
    {
        my $hret = __PACKAGE__->empty(
            $self->shape,
            ctx => $other,
            dtype => $self->dtype
        );
        return __PACKAGE__->_copyto($self, { out => $hret });
    }
    else
    {
        if ($other->handle eq $self->handle)
        {
            Carp::cluck('copy an array to itself, is it intended?');
        }
        return __PACKAGE__->_copyto($self, { out => $other });
    }
}

=head2 copy

    Makes a copy of the current ndarray in the same context

    Returns
    ------
    $copy : NDArray
=cut

method copy()
{
    return $self->copyto($self->context);
}

## alias for PDL::NiceSlice
*sever = \&copy;

=head2 T

    Get transpose of the NDArray.
    Works only on 2-D matrices.
=cut

method T()
{
    if (@{$self->shape} > 2)
    {
        confess('Only 2D matrix is allowed to be transposed');
    }
    return __PACKAGE__->transpose($self);
}

=head2 astype

    Returns copied ndarray of current array with the specified type.

    Parameters
    ----------
    $dtype : Dtype

    Returns
    -------
    $array : ndarray
        A copy of the array content.
=cut

method astype(Dtype $dtype)
{
    my $res = __PACKAGE__->empty($self->shape, ctx => $self->context, dtype => $dtype);
    $self->copyto($res);
    return $res;
}

=head2 as_in_context

    Returns an NDArray in the target context.
    If the array is already in that context, self is returned. Otherwise, a copy is
    made.

    Parameters
    ----------
    context : AI::MXNet::Context
        The target context we want the return value to live in.

    Returns
    -------
        A copy or self as an NDArray in the target context.
=cut

method as_in_context(AI::MXNet::Context $context)
{
    return $self if $self->context == $context;
    return $self->copyto($context);
}

=head2 onehot_encode

    One hot encoding indices into matrix out.

    Parameters
    ----------
    indices: NDArray
        An NDArray containing indices of the categorical features.

    out: NDArray
        The result of the encoding.

    Returns
    -------
        $out: NDArray
=cut

method onehot_encode(AI::MXNet::NDArray $indices, AI::MXNet::NDArray $out)
{
    return __PACKAGE__->_onehot_encode($indices, $out, { out => $out });
}

sub  _ufunc_helper
{
    my ($lhs, $rhs, $fn_array, $lfn_scalar, $rfn_scalar, $reverse) = @_;
    ($rhs, $lhs) = ($lhs, $rhs) if $reverse and $rfn_scalar;
    
    if(not ref $lhs)
    {
        if(not $rfn_scalar)
        {
            return __PACKAGE__->can($lfn_scalar)->(__PACKAGE__, $rhs, $lhs);
        }
        else
        {
            return __PACKAGE__->can($rfn_scalar)->(__PACKAGE__, $rhs, $lhs);
        }
    }
    elsif(not ref $rhs)
    {
        return __PACKAGE__->can($lfn_scalar)->(__PACKAGE__, $lhs, $rhs);
    }
    else
    {
        return __PACKAGE__->can($fn_array)->(__PACKAGE__, $lhs, $rhs);
    }
}

method stringify($other=, $reverse=)
{
    my $shape = $self->shape;
    my $context = $self->context;
    sprintf("<%s %s @%s>", ref($self), join('x', @{ $shape }), $context);
}

method atan2($other=, $reverse=)
{
    my $val = $reverse ? $other / $self : $self / $other;
    return __PACKAGE__->arctan($val);
}

method iadd(AI::MXNet::NDArray|AI::MXNet::NDArray::Slice|Num $other, $reverse=)
{
    confess('trying to add to a readonly NDArray') unless $self->writable;
    return ref $other
        ? __PACKAGE__->broadcast_add($self, $other, { out => $self })
        : __PACKAGE__->_plus_scalar($self, $other, { out => $self })
}

method add(AI::MXNet::NDArray|AI::MXNet::NDArray::Slice|Num $other, $reverse=)
{
    return _ufunc_helper(
        $self,
        $other,
        qw/broadcast_add _plus_scalar/
    );
}


method subtract(AI::MXNet::NDArray|AI::MXNet::NDArray::Slice|Num $other, $reverse=)
{
    return _ufunc_helper(
        $self,
        $other,
        qw/broadcast_sub _minus_scalar _rminus_scalar/,
        $reverse
    );
}

method isubtract(AI::MXNet::NDArray|AI::MXNet::NDArray::Slice|Num $other, $reverse=)
{
    confess('trying to add to a readonly NDArray') unless $self->writable;
    return ref $other
        ? __PACKAGE__->broadcast_sub($self, $other, { out => $self })
        : __PACKAGE__->_minus_scalar($self, $other, { out => $self })
}

method multiply(AI::MXNet::NDArray|AI::MXNet::NDArray::Slice|Num $other, $reverse=)
{
    return _ufunc_helper(
        $self,
        $other,
        qw/broadcast_mul _mul_scalar/
    );
}

method imultiply(AI::MXNet::NDArray|AI::MXNet::NDArray::Slice|Num $other, $reverse=)
{
    confess('trying to add to a readonly NDArray') unless $self->writable;
    return ref $other
        ? __PACKAGE__->broadcast_mul($self, $other, { out => $self })
        : __PACKAGE__->_mul_scalar($self, $other, { out => $self })
}

method divide(AI::MXNet::NDArray|AI::MXNet::NDArray::Slice|Num $other, $reverse=)
{
    return _ufunc_helper(
        $self,
        $other,
        qw/broadcast_div _div_scalar _rdiv_scalar/,
        $reverse
    );
}

method idivide(AI::MXNet::NDArray|AI::MXNet::NDArray::Slice|Num $other, $reverse=)
{
    confess('trying to add to a readonly NDArray') unless $self->writable;
    return ref $other
        ? __PACKAGE__->broadcast_div($self, $other, { out => $self })
        : __PACKAGE__->_div_scalar($self, $other, { out => $self })
}

method power(AI::MXNet::NDArray|AI::MXNet::NDArray::Slice|Num $other, $reverse=)
{
    return _ufunc_helper(
        $self,
        $other,
        qw/broadcast_power _power_scalar _rpower_scalar/,
        $reverse
    );
}

method maximum(AI::MXNet::NDArray|AI::MXNet::NDArray::Slice|Num $other)
{
    return _ufunc_helper(
        $self,
        $other,
        qw/broadcast_maximum _maximum_scalar/
    );
}

method minimum(AI::MXNet::NDArray|AI::MXNet::NDArray::Slice|Num $other)
{
    return _ufunc_helper(
        $self,
        $other,
        qw/broadcast_minimum _minimum_scalar/
    );
}

method equal(AI::MXNet::NDArray|AI::MXNet::NDArray::Slice|Num $other, $reverse=)
{
    return _ufunc_helper(
        $self,
        $other,
        qw/broadcast_equal _equal_scalar/
    );
}

method not_equal(AI::MXNet::NDArray|AI::MXNet::NDArray::Slice|Num $other, $reverse=)
{
    return _ufunc_helper(
        $self,
        $other,
        qw/broadcast_not_equal _not_equal_scalar/
    );
}

method greater(AI::MXNet::NDArray|AI::MXNet::NDArray::Slice|Num $other, $reverse=)
{
    return _ufunc_helper(
        $self,
        $other,
        qw/broadcast_greater _greater_scalar _lesser_scalar/,
        $reverse
    );
}

method greater_equal(AI::MXNet::NDArray|AI::MXNet::NDArray::Slice|Num $other, $reverse=)
{
    return _ufunc_helper(
        $self,
        $other,
        qw/broadcast_greater_equal _greater_equal_scalar _lesser_equal_scalar/,
        $reverse
    );
}

method lesser(AI::MXNet::NDArray|AI::MXNet::NDArray::Slice|Num $other, $reverse=)
{
    return _ufunc_helper(
        $self,
        $other,
        qw/broadcast_lesser _lesser_scalar _greater_scalar/,
        $reverse
    );
}

method lesser_equal(AI::MXNet::NDArray|AI::MXNet::NDArray::Slice|Num $other, $reverse=)
{
    return _ufunc_helper(
        $self,
        $other,
        qw/broadcast_lesser_equal _lesser_equal_scalar _greater_equal_scalar/,
        $reverse
    );
}

method true_divide(AI::MXNet::NDArray|AI::MXNet::NDArray::Slice|Num $other, $reverse=)
{
    return $self->divide($other, $reverse);
}

method modulo(AI::MXNet::NDArray|AI::MXNet::NDArray::Slice|Num $other, $reverse=)
{
    return _ufunc_helper(
        $self,
        $other,
        qw/broadcast_mod _mod_scalar _rmod_scalar/,
        $reverse
    );
}

method imodulo(AI::MXNet::NDArray|AI::MXNet::NDArray::Slice|Num $other, $reverse=)
{
    confess('trying to modulo to a readonly NDArray') unless $self->writable;
    return ref $other
        ? __PACKAGE__->broadcast_mod($self, $other, { out => $self })
        : __PACKAGE__->_mod_scalar($self, $other, { out => $self })
}

=head2 empty

    Creates an empty uninitialized NDArray, with the specified shape.

    Parameters
    ----------
    $shape : Shape
        shape of the NDArray.

    :$ctx : AI::MXNet::Context, optional
        The context of the NDArray, defaults to current default context.

    :$dtype : Dtype, optional
        The dtype of the NDArray, defaults to 'float32'.

    :$stype: Stype, optional
        The stype of the NDArray, defaults to 'default'

    Returns
    -------
    out: Array
        The created NDArray.
=cut

method empty(Shape $shape, AI::MXNet::Context :$ctx=AI::MXNet::Context->current_ctx, Dtype :$dtype='float32', Stype :$stype='default')
{
    if($stype ne 'default')
    {
        return AI::MXNet::NDArray::Sparse->empty($stype, $shape, ctx => $ctx, dtype => $dtype);
    }
    return __PACKAGE__->new(
                handle => _new_alloc_handle(
                    $shape,
                    $ctx,
                    0,
                    DTYPE_STR_TO_MX->{$dtype}
                )
    );
}

=head2 zeros

    Creates a new NDArray filled with 0, with specified shape.

    Parameters
    ----------
    $shape : Shape
        shape of the NDArray.

    :$ctx : AI::MXNet::Context, optional
        The context of the NDArray, defaults to current default context.

    :$dtype : Dtype, optional
        The dtype of the NDArray, defaults to 'float32'.

    :$stype: Stype, optional
        The stype of the NDArray, defaults to 'default'
    Returns
    -------
    out: Array
        The created NDArray.
=cut

method zeros(
    Shape $shape,
    AI::MXNet::Context :$ctx=AI::MXNet::Context->current_ctx,
    Dtype :$dtype='float32',
    Maybe[AI::MXNet::NDArray] :$out=,
    Maybe[Str] :$name=,
    Maybe[Str] :$__layout__=,
    Stype :$stype='default'
)
{
    if($stype ne 'default')
    {
        return AI::MXNet::NDArray::Sparse->zeros($stype, $shape, ctx => $ctx, dtype => $dtype, out => $out);
    }
    return __PACKAGE__->_zeros({ shape => $shape, ctx => "$ctx", dtype => $dtype, ($out ? (out => $out) : ())  });
}

=head2 ones

    Creates a new NDArray filled with 1, with specified shape.

    Parameters
    ----------
    $shape : Shape
        shape of the NDArray.

    :$ctx : AI::MXNet::Context, optional
        The context of the NDArray, defaults to current default context.

    :$dtype : Dtype, optional
        The dtype of the NDArray, defaults to 'float32'.

    Returns
    -------
    out: Array
        The created NDArray.
=cut

method ones(
    Shape $shape,
    AI::MXNet::Context :$ctx=AI::MXNet::Context->current_ctx,
    Dtype :$dtype='float32',
    Maybe[AI::MXNet::NDArray] :$out=,
    Maybe[Str] :$name=,
    Maybe[Str] :$__layout__=,
)
{
    return __PACKAGE__->_ones({ shape => $shape, ctx => "$ctx", dtype => $dtype, ($out ? (out => $out) : ()) });
}

=head2 full

    Creates a new NDArray filled with given value, with specified shape.

    Parameters
    ----------
    $shape : Shape
        shape of the NDArray.

    val : float or int
        The value to be filled with.

    :$ctx : AI::MXNet::Context, optional
        The context of the NDArray, defaults to current default context.

    :$dtype : Dtype, optional
        The dtype of the NDArray, defaults to 'float32'.

    Returns
    -------
    out: Array
        The created NDArray.
=cut

method full(
    Shape $shape, Num $val,
    AI::MXNet::Context :$ctx=AI::MXNet::Context->current_ctx,
    Dtype :$dtype='float32', Maybe[AI::MXNet::NDArray] :$out=,
    Maybe[Str] :$name=,
    Maybe[Str] :$__layout__=
)
{
    return __PACKAGE__->_set_value({ src => $val, out => $out ? $out : __PACKAGE__->empty($shape, ctx => $ctx, dtype => $dtype) });
}

=head2 array

    Creates a new NDArray that is a copy of the source_array.

    Parameters
    ----------
    $source_array : AI::MXNet::NDArray PDL, PDL::Matrix, Array ref in PDL::pdl format
        Source data to create NDArray from.

    :$ctx : AI::MXNet::Context, optional
        The context of the NDArray, defaults to current default context.

    :$dtype : Dtype, optional
        The dtype of the NDArray, defaults to 'float32'.

    Returns
    -------
    out: Array
        The created NDArray.
=cut

method array(PDL|PDL::Matrix|PDL::CCS::Nd|ArrayRef|AI::MXNet::NDArray $source_array, AI::MXNet::Context :$ctx=AI::MXNet::Context->current_ctx, Dtype :$dtype='float32')
{
    if(blessed $source_array and $source_array->isa('AI::MXNet::NDArray'))
    {
        return AI::MXNet::NDArray::Sparse->array($source_array, ctx => $ctx, dtype => $dtype) unless $source_array->stype eq 'default';
        my $arr = __PACKAGE__->empty($source_array->shape, ctx => $ctx, dtype => $dtype);
        $arr .= $source_array;
        return $arr;
    }
    elsif(blessed $source_array and $source_array->isa('PDL::CCS::Nd'))
    {
        return AI::MXNet::NDArray::Sparse->array($source_array, ctx => $ctx, dtype => $dtype);
    }
    my $pdl_type = PDL::Type->new(DTYPE_MX_TO_PDL->{ $dtype });
    if(not blessed($source_array))
    {
        $source_array = eval {
            pdl($pdl_type, $source_array);
        };
        confess($@) if $@;
    }
    $source_array = pdl($pdl_type, [@{ $source_array->unpdl } ? $source_array->unpdl->[0] : 0 ]) unless @{ $source_array->shape->unpdl };
    my $shape = $source_array->shape->unpdl;
    my $arr = __PACKAGE__->empty([ref($source_array) eq 'PDL' ? reverse @{ $shape } : @{ $shape }], ctx => $ctx, dtype => $dtype );
    $arr .= $source_array;
    return $arr;
}


=head2 concatenate

    Concatenates an array ref of NDArrays along the first dimension.

    Parameters
    ----------
    $arrays :  array ref of NDArrays
        Arrays to be concatenate. They must have identical shape except
        for the first dimension. They also must have the same data type.
    :$axis=0 : int
        The axis along which to concatenate.
    :$always_copy=1 : bool
        Default is 1. When not 1, if the arrays only contain one
        NDArray, that element will be returned directly, avoid copying.

    Returns
    -------
    An NDArray in the same context as $arrays->[0]->context.
=cut

method concatenate(ArrayRef[AI::MXNet::NDArray] $arrays, Index :$axis=0, :$always_copy=1)
{
    confess("no arrays provided") unless @$arrays > 0;
    if(not $always_copy and @$arrays == 1)
    {
        return $arrays->[0];
    }
    my $shape_axis = $arrays->[0]->shape->[$axis];
    my $shape_rest1 = [@{ $arrays->[0]->shape }[0..($axis-1)]];
    my $shape_rest2 = [@{ $arrays->[0]->shape }[($axis+1)..(@{ $arrays->[0]->shape }-1)]];
    my $dtype = $arrays->[0]->dtype;
    my $i = 1;
    for my $arr (@{ $arrays }[1..(@{ $arrays }-1)])
    {
        $shape_axis += $arr->shape->[$axis];
        my $arr_shape_rest1 = [@{ $arr->shape }[0..($axis-1)]];
        my $arr_shape_rest2 = [@{ $arr->shape }[($axis+1)..(@{ $arr->shape }-1)]];
        confess("first array $arrays->[0] and $i array $arr do not match")
            unless  join(',',@$arr_shape_rest1) eq join(',',@$shape_rest1);
        confess("first array $arrays->[0] and $i array $arr do not match")
            unless  join(',',@$arr_shape_rest2) eq join(',',@$shape_rest2);
        confess("first array $arrays->[0] and $i array $arr dtypes do not match")
            unless  join(',',@$arr_shape_rest2) eq join(',',@$shape_rest2);
        $i++;
    }
    my $ret_shape = [@$shape_rest1, $shape_axis, @$shape_rest2];
    my $ret = __PACKAGE__->empty($ret_shape, ctx => $arrays->[0]->context, dtype => $dtype);
    my $idx = 0;
    my $begin = [(0)x@$ret_shape];
    my $end = [@$ret_shape];
    for my $arr (@$arrays)
    {
        if ($axis == 0)
        {
            $ret->slice([$idx,($idx+$arr->shape->[0]-1)]) .= $arr;
        }
        else
        {
            $begin->[$axis] = $idx;
            $end->[$axis] = $idx+$arr->shape->[$axis];
            __PACKAGE__->_crop_assign(
                $ret, $arr,
                {
                    out => $ret,
                    begin => $begin,
                    end => $end
                }
            );
        }
        $idx += $arr->shape->[$axis];
    }
    return $ret
}

=head2 std

    Computes the standard deviation of the input NDArray.

    Similar function in the MXNet ndarray as numpy.std.
    See Also https://numpy.org/doc/stable/reference/generated/numpy.std.html.

    Parameters
    ----------
    $x : NDArray
        Input array.
        
    :$axis= : Int or ArrayRef[Int], optional
        Axis or axes along which the standard deviation is computed.
        For example:

            axis => 0
            axis => 1
            axis => [0, 1]

        By default, the standard deviation is computed over all elements
        of the array.
        
    :$keepdims=0 : Bool, optional
        If true, the reduced axes are left in the result as dimensions
        with size one, allowing the result to broadcast correctly against
        the input array.

    Returns
    -------
    $out : NDArray
        The standard deviation of the input array.

    Notes
    -----
    The standard deviation is computed as::

        sqrt(sum((x - mean(x)) ** 2) / N)

    where N is the number of elements along the reduction axis.
    This corresponds to numpy.std(..., ddof=0).
=cut

sub std{
  my ($self, $x) = splice(@_, 0, 2);
  my %args = $self->get_arguments(axis => undef,
                                  keepdims => 0,
                                  \@_);
  
  my $axis = defined $args{axis} ?
             $args{axis}: 
             'None';

  my $size = 1;
  if(ref($axis) eq 'ARRAY'){
    $size *= $x->shape->[$_] for @$axis;
  }elsif($axis eq 'None'){
    $size = $x->size;
  }else{
    $size = $x->shape->[$axis];
  }
             
  my $mean = $axis eq 'None' ?
             $x->mean() : 
             $x->mean(axis => $axis, keepdims => 1);
  
  my $std = (
    $self->sum(
        ($x - $mean)->power(2),
        axis     => $axis,
        keepdims => $args{keepdims}
    ) / $size
  )->sqrt();

  return $axis eq 'None' && !$args{keepdims}
    ? $std->reshape([])
    : $std;
}

=head2 cov

    Estimate a covariance matrix, given data and optional weights.

    Covariance indicates the level to which two variables vary together.
    If we examine N-dimensional samples, X = [x1, x2, ..., xN]^T,
    then the covariance matrix element C(i,j) is the covariance of
    xi and xj. The element C(i,i) is the variance of xi.

    Similar function in the MXNet ndarray as numpy.cov.
    See Also https://numpy.org/doc/stable/reference/generated/numpy.cov.html.

    Parameters
    ----------
    $x : NDArray
        A 1-D or 2-D NDArray containing variables and observations.
        Each row of $x represents a variable, and each column a single
        observation of all those variables. See also :$rowvar below.

    :$y= : NDArray, optional
        An additional set of variables and observations.
        $y must have the same form as that of $x.

    :$rowvar=1 : Bool, optional
        If true (default), each row represents a variable, with
        observations stored in the columns.

        If false, each column represents a variable and the rows
        contain observations.

    :$bias=0 : Bool, optional
        Default normalization is by (N - 1), where N is the number
        of observations (unbiased estimate).

        If true, normalization is by N.

        This value may be overridden by :$ddof.

    :$ddof= : Int, optional
        Overrides the default normalization implied by :$bias.

        For example:

            ddof => 0    # normalize by N
            ddof => 1    # normalize by N - 1

    :$fweights= : NDArray, optional
        A 1-D NDArray of integer frequency weights.

        Each element specifies how many times the corresponding
        observation vector should be repeated.

    :$aweights= : NDArray, optional
        A 1-D NDArray of observation weights.

        Larger values indicate observations that should contribute
        more strongly to the covariance estimate.

        When used with:

            ddof => 0

        the weights may be interpreted as probabilities.

    :$dtype= : Str, optional
        Data type used internally for the computation.

        Examples:

            dtype => 'float32'
            dtype => 'float64'

    Returns
    -------
    $out : NDArray
        Covariance matrix of the variables.

        If the input contains a single variable, a scalar NDArray
        containing the variance is returned.

    Notes
    -----
    The covariance matrix is computed as::

        C = (X - mean(X)) (X - mean(X))^T / fact

    where the normalization factor depends on the values of
    :$bias, :$ddof, :$fweights and :$aweights.

    This implementation follows the behavior of numpy.cov,
    including weighted covariance estimation using frequency
    and analytical weights.
=cut

sub cov{
  my ($self, $x) = splice(@_, 0, 2);
  my %args = $self->get_arguments(y        => undef,
                                  rowvar   => 1,
                                  bias     => 0,
                                  ddof     => undef,
                                  fweights => undef,
                                  aweights => undef,
                                  dtype    => 'float64',
                                  \@_);
  
  # Validation of input parameters
        
  die "Missing 1 required positional argument: 'x' as a 1-D or 2-D NDArray.\n"
    if ref ($x) !~ /^AI::MXNet::NDArray(?:::Slice)?$/;
    
  die "Required positional argument: 'x' has more than 2 dimensions.\n"
    if $x->ndim > 2;

  # Caso X.shape[0] == 0 
  return $self->empty([0,0], dtype=>$args{dtype})
    if $x->ndim == 2 && $x->shape->[0] == 0;
  
  # Caso escalar
  return $self->array(['NaN'])->reshape([])
    if $x->size == 1;

  if(defined $args{ddof}){
    die "ddof must be integer\n"
      unless int($args{ddof}) == $args{ddof};
  }
  
  if(defined $args{fweights}){
    
    die "fweights must be a 1-D NDArray.\n"
      if ref ($args{fweights}) !~ /^AI::MXNet::NDArray(?:::Slice)?$/;
    
    die sprintf("fweights must be 1-D. Found: %s-D\n", $args{fweights}->ndim)
      unless $args{fweights}->ndim == 1;
          
    die sprintf("fweights length mismatch: %s x %s", $args{fweights}->len, $x->size)
      unless $args{fweights}->len == ($x->ndim == 1 ? $x->shape->[0] : $x->shape->[1]);
          
    die sprintf("fweights cannot be negative")
       if ($args{fweights} < 0)->sum->asscalar > 0;

    die "fweights must contain integers only."
      if $self->abs($args{fweights} - $args{fweights}->trunc)->sum->asscalar > 1e-6;
  }

  if(defined $args{aweights}){
    
    die "aweights must be a 1-D NDArray.\n"
      if ref ($args{aweights}) !~ /^AI::MXNet::NDArray(?:::Slice)?$/;
      
    die sprintf("aweights must be 1-D. Found: %s-D\n", $args{aweights}->ndim)
      unless $args{aweights}->ndim == 1;

    die sprintf("aweights length mismatch: %s x %s", $args{aweights}->len, $x->size)
      unless $args{aweights}->len == ($x->ndim == 1 ? $x->shape->[0] : $x->shape->[1]);
        
    die sprintf("aweights cannot be negative.")
      if ($args{aweights} < 0)->sum->asscalar > 0;

    die "aweights sum to zero"
      unless $args{aweights}->sum->asscalar != 0;
  }

  if(defined $args{dtype}){
    $x = $x->astype($args{dtype});

    $args{y} = $args{y}->astype($args{dtype})
      if defined $args{y};

    $args{fweights} = $args{fweights}->astype($args{dtype})
      if defined $args{fweights};

    $args{aweights} = $args{aweights}->astype($args{dtype})
      if defined $args{aweights};
  }

  if (defined $args{y}){
    
    die "Optional argument 'y' must be a 1-D or 2-D NDArray.\n"
      if ref ($args{y}) !~ /^AI::MXNet::NDArray(?:::Slice)?$/;
    
    die "Optional argument 'y' has more than 2 dimensions.\n"
      if $args{y}->ndim > 2;
      
    die "Optional argument 'y' must have the same form as that of 'x'.\n"
      if $args{y}->shape->[-1] != $x->shape->[-1];
  }
  
  die "Optional argument 'rowvar' must be 0 or 1.\n"
    if $args{rowvar} !~ /^[01]$/;
  
  unless ($args{rowvar}){
    $x = $x->transpose;
    $args{y} = $args{y}->transpose if defined $args{y};
  }
  
  unless (defined $args{y}){
    $x = $x->expand_dims(axis => 0) if $x->ndim == 1;
  }else{
    if ($x->ndim == $args{y}->ndim){
      $x = $x->ndim == 1 ? $self->stack(($x, $args{y}), axis => 0) : $self->concat(($x, $args{y}), dim => 0);
    }elsif($x->ndim > $args{y}->ndim){
      $x = $self->concat(($x, $args{y}->expand_dims(axis => 0)), dim => 0);
    }elsif($x->ndim < $args{y}->ndim){
      $x = $self->concat(($x->expand_dims(axis => 0), $args{y}), dim => 0);
    }
  }
  
  # Calculate mean and center the matrix
  my $w = defined $args{fweights} ? $args{fweights} : undef;
  $w = defined $args{aweights} ? $args{aweights} : $w ;
  $w = defined ($args{fweights}) && defined ($args{aweights}) ? $args{fweights} * $args{aweights} : $w ;
      
  my $mean;
  if (ref($w)){
    $mean = ($x * $w)->sum(axis=>1, keepdims=>1) / $w->sum;
  }else{
    $mean = $x->mean(axis=>1, keepdims=>1);
  }
  
  my $xm = $x - $mean;
  my $n  = $x->shape->[1];

  my $ddof = defined $args{ddof}
           ? $args{ddof}
           : ($args{bias} ? 0 : 1);

  my $fact;
  if(!defined $args{fweights} && !defined $args{aweights}){
    $fact = $n - $ddof;
  }elsif(defined $args{fweights} && !defined $args{aweights}){
    my $wsum = $args{fweights}->sum->asscalar;
    $fact = $wsum - $ddof;
  }elsif(!defined $args{fweights} && defined $args{aweights}){
    my $v1 = $w->sum();
    my $v2 = $w->power(2)->sum();
    $fact = $v1 - $ddof * $v2 / $v1;
  }elsif(defined $args{fweights} && defined $args{aweights}){
    my $v1 = $self->sum($w);
    my $v2 = $self->sum($w * $args{aweights});
    $fact = $v1 - $ddof * $v2 / $v1;
  }
  
  warn "Degrees of freedom <= 0 for slice.\n"
    if (ref($fact) =~ /^AI::MXNet::NDArray(?:::Slice)?$/ ? $fact->asscalar : $fact) <= 0;

  # Compute covariance matrix
  my $cov = $self->dot(ref($w) ? $xm * $w : $xm, $xm->transpose) / $fact;

  return $cov->reshape([])
      if @{$cov->shape} == 2
      && $cov->shape->[0] == 1
      && $cov->shape->[1] == 1;
  
  return $cov->squeeze();
}

=head2 corrcoef

    Computes the Pearson product-moment correlation coefficient matrix.

    Similar function in the MXNet ndarray as numpy.corrcoef.
    See Also https://numpy.org/doc/stable/reference/generated/numpy.corrcoef.html
    https://mxnet.apache.org/versions/master/api/python/docs/api/np/generated/mxnet.np.corrcoef.html
    https://numpy.org/doc/stable/reference/generated/numpy.corrcoef.html
    https://en.wikipedia.org/wiki/Pearson_correlation_coefficient
    https://www.howtoexcel.org/correlation-coefficient/

    The relationship between the correlation coefficient matrix, C<R>,
    and the covariance matrix, C<C>, is

        R[i,j] = C[i,j] / sqrt(C[i,i] * C[j,j])

    The values of the correlation coefficients are between -1 and 1,
    inclusive.

    Parameters
    ----------
    $x : NDArray
        A 1-D or 2-D array containing variables and observations.
        By default, each row represents a variable and each column
        represents an observation.
    :$y= : NDArray, optional
        An additional set of variables and observations.
        C<$y> must have the same number of observations as C<$x>.
    :$rowvar=1 : Bool, optional
        If true (default), each row represents a variable and each
        column an observation. Otherwise, the relationship is
        transposed so that each column represents a variable.
    :$dtype= : Dtype, optional
        Data type of the result. If specified, the input arrays are
        converted to this type before computation.

    Returns
    -------
    $out : NDArray
        Correlation coefficient matrix.

        If only one variable is provided, a scalar correlation
        coefficient is returned.

    See Also
    --------
    cov : Covariance matrix.

    Notes
    -----
    The correlation matrix is computed from the covariance matrix
    returned by C<cov()>.

    Due to floating-point rounding errors, the resulting matrix may
    not be exactly symmetric, diagonal elements may differ slightly
    from 1, and correlation coefficients may slightly exceed the
    interval [-1, 1]. Values are clipped to the interval [-1, 1]
    when possible.

    Undefined correlations resulting from zero variance variables
    produce NaN values, consistent with NumPy behaviour.
=cut
sub corrcoef{
  my ($self, $x) = splice(@_, 0, 2);
  my %args = $self->get_arguments(y      => undef,
                                  rowvar => 1,
                                  dtype  => undef,
                                  \@_);
    
  # Compute covariance matrix
  my $cov = $self->cov($x, %args);

  if (!@{$cov->shape}){
    my $v = $cov->asscalar;
    return $v == 0 ?
           $self->array(['NaN'])->reshape([]) :
           return $self->array([$v / $v])->reshape([]);
  }
  
  # Compute standard deviations of each variable
  my $std  = $self->sqrt($self->diag($cov));
  
  # Compute correlation matrix
  my $std_outer = $self->dot($std->reshape([-1, 1]), $std->reshape([1, -1]));

  my $corr = $cov / $std_outer;
  
  $corr = $self->clip($corr, -1, 1);
}

=head2 random_choice

my \\$sample = \\$mx->random_choice(\\$a, %args);

Generates a random sample from a given 1-D array or scalar population.
    
    https://numpy.org/doc/stable/reference/generated/numpy.random.choice.html

    A random sample is drawn from the elements of a 1-D array-like object
    or generated as an interval sequence if an integer population size is provided.
    Sampling can be performed with or without replacement, and uniform or
    custom probability distributions can be applied.

    Similar function in the MXNet ndarray as numpy.random.choice.
    See Also https://numpy.org/doc/stable/reference/generated/numpy.random.choice.html.

    Parameters
    ----------
    $x : Int | ARRAY ref | NDArray
        The population from which to draw samples.
        If an integer, the random sample is generated as if it were a
        sequence from 0 to x - 1. If an array reference or NDArray,
        samples are drawn directly from its elements.

    :$size= : Int | ARRAY ref, optional
        Output shape of the generated tensor.
        If the given shape is, e.g., [m, n, k], then m * n * k samples
        are drawn. Default is undef, in which case a single scalar item
        (wrapped as a 0-D NDArray) is returned.

    :$replace=1 : Bool, optional
        Whether the sample is drawn with or without replacement.
        If true (default), values from the population can be selected
        multiple times.

    :$p= : ARRAY ref | NDArray, optional
        The probabilities associated with each entry in $x.
        If not given, a uniform distribution over all entries in $x
        is assumed. If provided, the vector is automatically normalized
        internally to sum to 1.0.

    :$device= : Context, optional
        The execution context device where the random sampling kernel
        will be allocated and executed. Default is AI::MXNet->cpu(0).

    :$out= : NDArray, optional
        An optional pre-allocated output tensor where the resulting
        samples will be written.

    Returns
    -------
    $out : NDArray
        The generated random samples encapsulated in an NDArray container
        shaped according to the :$size parameter.

    Raises
    ------
    ValueError
        If the required positional argument $x is missing or undefined.
        If $x is an integer less than or equal to zero.
        If $x or :$p are not 1-dimensional vectors.
        If $x and :$p have different lengths.
        If :$replace is false (0) and the requested total sample size
        is greater than the population size.

    Notes
    -----
    This implementation utilizes highly optimized internal MXNet bindings 
    mapping directly to the native C-API operator::

        _npi_choice

    If no custom weights are provided, an empty input array is passed 
    to the execution graph to trigger uniform distribution pipelines. 
    Otherwise, the normalized probability tensor is injected dynamically.

=cut

sub random_choice{
  my ($self, $x) = splice(@_, 0, 2);
  my %args = $self->get_arguments(size    => undef, # por defecto retorna un escalar si size es undef
                                  replace => 1,
                                  p       => undef,
                                  device  => AI::MXNet->cpu(0),
                                  out     => undef,
                                  \@_);

  # 1. Validación estricta del argumento obligatorio 'a'
  unless (defined $x) {
    die "ValueError: random_choice() missing 1 required positional argument: 'a'.\n";
  }

  # 2. Determinar la población (pop_size) y el tipo de entrada 'a'
  my $pop_size;
  my $is_scalar = (ref(\$x) eq 'SCALAR' || (ref($x) eq '' && $x =~ /^-?\d+$/));

  if ($is_scalar) {
    if ($x <= 0) {
      die "ValueError: a must be greater than 0 unless no samples are taken.\n";
    }
    $pop_size = $x;
  } else {
    $x = $self->array($x) if ref($x) eq 'ARRAY';
    if ($x->ndim != 1) {
      die "ValueError: Required positional argument 'a' must be 1-dimensional.\n";
    }
    $pop_size = $x->len;
  }

  # 3. Tratamiento del tamaño de salida (Size) conforme a NumPy
  my $return_scalar = (not defined $args{size}) ? 1 : 0;
  $args{size} = [1] unless defined $args{size};
  $args{size} = [$args{size}] if ref(\$args{size}) eq 'SCALAR';

  my $total_size = $self->prod($self->array($args{size}))->asscalar;
  return $return_scalar ? undef : $self->empty($args{size}, ctx => $args{device}) if $total_size == 0;

  # 4. Tratamiento del vector de probabilidades 'p'
  my $weighted = 0;
  my $p_ndarray;
  if (defined $args{p}) {
    $p_ndarray = $self->array($args{p}) if ref($args{p}) eq 'ARRAY';
    $p_ndarray = $args{p} if ref($args{p}) =~ /AI::MXNet::NDArray/;
    
    if ($p_ndarray->ndim != 1) {
        die "ValueError: p must be 1-dimensional\n";
    }
    if ($p_ndarray->len != $pop_size) {
        die "ValueError: a and p must have same size\n";
    }
    
    # Normalizar para evitar errores de punto flotante idéntico a NumPy
    $p_ndarray /= $p_ndarray->sum;
    $weighted = 1;
  }

  # 5. Validación de restricciones de Reemplazo
  if (!$args{replace} && $total_size > $pop_size) {
    die "ValueError: Cannot take a larger sample than population when replace is False\n";
  }

  # 6. Ejecución del Kernel de Alta Velocidad de MXNet (_npi_choice)
  # Si no es ponderado, pasamos un arreglo vacío de entradas a la C-API. 
  # Si es ponderado, inyectamos el tensor de probabilidades como la entrada esperada.
  my @inputs = $weighted ? ($p_ndarray) : ();

  my $indices = $self->_npi_choice(
      @inputs,
      a        => $pop_size,
      size     => $args{size},
      replace  => $args{replace},
      weighted => $weighted,
      ctx      => "$args{device}", 
      (defined $args{out} ? (out => $args{out}) : ())
  );

  # 7. Mapear los índices obtenidos al arreglo original 'a' (si 'a' no era un escalar)
  my $result = $is_scalar ? $indices : $self->take($x, $indices);

  # 8. Escalar  vs NDArray Estructurado
  return $return_scalar ? $result->reshape([0]) : $result;
}

#tril_indices(n, k=0, m=undef):
#    """
#    Return the indices for the lower-triangle of an (n, m) array.
#
#    Parameters
#    ----------
#    n : int
#        The row dimension of the arrays for which the returned
#        indices will be valid.
#    k : int, optional
#        Diagonal offset (see `tril` for details).
#    m : int, optional
#        The column dimension of the arrays for which the returned
#        arrays will be valid.
#        By default `m` is taken equal to `n`.
#
#
#    Returns
#    -------
#    inds : tuple of arrays
#        The row and column indices, respectively. The row indices are sorted
#        in non-decreasing order, and the corresponding column indices are
#        strictly increasing for each row.
        
sub tril_indices {
  my ($self, $n) = splice(@_, 0, 2);
  my %args = $self->get_arguments(k       => 0,
                                  m       => $n,
                                  p       => undef,
                                  device  => AI::MXNet->cpu(0),
                                  \@_);
  
  my $mask = AI::MXNet::NDArray->ones([$n, $args{m}], ctx => $args{device});

  $mask = AI::MXNet::NDArray->tril($mask, k => $args{k});

  return AI::MXNet::NDArray->nonzero($mask)->T;
}

#triu_indices(n, k=0, m=undef)
#    Return the indices for the upper-triangle of an (n, m) array.
#
#    Parameters
#    ----------
#    n : int
#        The size of the arrays for which the returned indices will
#        be valid.
#    k : int, optional
#        Diagonal offset (see `triu` for details).
#    m : int, optional
#        The column dimension of the arrays for which the returned
#        arrays will be valid.
#        By default `m` is taken equal to `n`.
#
#
#    Returns
#    -------
#    inds : tuple, shape(2) of ndarrays, shape(`n`)
#        The row and column indices, respectively. The row indices are sorted
#        in non-decreasing order, and the corresponding column indices are
#        strictly increasing for each row.
        
sub triu_indices {
  my ($self, $n) = splice(@_, 0, 2);
  my %args = $self->get_arguments(k       => 0,
                                  m       => $n,
                                  p       => undef,
                                  device  => AI::MXNet->cpu(0),
                                  \@_);

  my $mask = AI::MXNet::NDArray->ones([$n, $args{m}], ctx => $args{device});

  # equivalente a triu(mask, k)
  $mask = $mask - AI::MXNet::NDArray->tril($mask, k => $args{k} - 1);

  return AI::MXNet::NDArray->nonzero($mask)->T;
}

sub list_functions{
  my $self = shift;
  
  my $meta = AI::MXNet::NDArray::Base->function_meta_hash;
 
  foreach my $code (sort {
     $meta->{$a}{__name__} cmp $meta->{$b}{__name__}
  } keys %$meta)
  {
     print $meta->{$code}{__name__}, "\n";
  }
}

sub find_functions {
    my ($self, $pattern, $silent) = @_;

    my $meta = AI::MXNet::NDArray::Base->function_meta_hash;

    # 1. Escapar caracteres especiales del patrón del usuario
    my $regex_str = quotemeta($pattern);
    
    # 2. Traducir el comodín '*' a '.*' para permitir búsquedas con wildcards
    $regex_str =~ s/\\\*/.*/g;
    
    # 3. Permitir opcionalmente al inicio (?:_(?:(?:contrib|np[ix]?)_)?)?
    # Esto empareja de forma transparente:
    #   - Nombre limpio: eye
    #   - Prefijo simple: _eye
    #   - Prefijos de NumPy: _np_eye, _npi_eye, _npx_eye, _contrib_
    my $regex = qr/^(?:_(?:(?:contrib|np[ix]?)_)?)?$regex_str$/;

    # 4. Filtrar los metadatos usando la nueva expresión regular flexible
    my @filtered = grep { $_->{__name__} =~ $regex } values %$meta;
    
    # 5. Ordenar alfabéticamente por el campo '__name__'
    my @matches = sort { $a->{__name__} cmp $b->{__name__} } @filtered;

    # 6. Imprimir el listado indexado si no está en modo silencioso
    if (not $silent) {
        for my $i (0 .. $#matches) {
            printf "%d %s\n", $i, $matches[$i]{__name__};
        }
    }

    return wantarray ? @matches : $matches[0];
}

sub help {
  my ($self, $fname) = @_;

  # Call find_functions to search for matching operations and retrieve metadata hashes
  # We call it in list context to handle single names as well as wildcard expressions
  my @matches = $self->find_functions($fname, 1);

  if (not @matches or not defined $matches[0]) {
    print "No documentation found for pattern or function: '$fname'\n";
    return;
  }

  print "\n" . "=" x 80 . "\n";
  print "FOUND " . scalar(@matches) . " DOCUMENTATION ENTRY/ENTRIES FOR: '$fname'\n";
  print "=" x 80 . "\n\n";

  # Iterate through all matching function metadata references safely
  for my $function (@matches) {
    # Format the header and the raw dynamic C-API docstring string
    printf "Function: %s\n", $function->{__name__};
    print "-" x (10 + length($function->{__name__})) . "\n";
    
    if ($function->{__doc__}) {
      printf "%s\n", $function->{__doc__};
    } else {
      print "No detailed docstring description provided by the C-API.\n";
    }
    
    print "\n" . "=" x 80 . "\n\n";
  }
}

sub pi{
  return 3.141592653589793;
}

sub inf{
  return 1.7976931348623157e+308;  
}

=head2 load

    Loads ndarrays from a binary file.

    You can also use Storable to do the job if you only work with Perl.
    The advantage of load/save is the file is language agnostic.
    This means the file saved using save can be loaded by other language binding of mxnet.
    You also get the benefit being able to directly load/save from cloud storage(S3, HDFS)

    Parameters
    ----------
    fname : str
        The name of the file.Can be S3 or HDFS address (remember built with S3 support).
        Example of fname:

        - `s3://my-bucket/path/my-s3-ndarray`
        - `hdfs://my-bucket/path/my-hdfs-ndarray`
        - `/path-to/my-local-ndarray`

    Returns
    -------
    $out : array ref of NDArrays or hash ref with NDArrays
=cut

method load(Str $filename)
{
    my ($handles, $names) = check_call(AI::MXNetCAPI::NDArrayLoad($filename));
    if (not @$names)
    {
        return [map { __PACKAGE__->_ndarray_cls($_) } @$handles];
    }
    else
    {
        my $n = @$names;
        my $h = @$handles;
        confess("Handles [$h] and names [$n] count mismatch") unless $h == $n;
        my %ret;
        @ret{ @$names } = map { __PACKAGE__->_ndarray_cls($_) } @$handles;
        return \%ret;
    }
}

=head2 load_frombuffer

    Loads an array dictionary or list from a buffer

    See more details in 'save'.

    Parameters
    ----------
    buf : str
        Binary string containing contents of a file.

    Returns
    -------
    array ref of AI::MXNet::NDArray, AI::MXNet::NDArrayRowSparseNDArray or AI::MXNet::NDArray::CSR, or
    hash ref of AI::MXNet::NDArray, AI::MXNet::NDArrayRowSparseNDArray or AI::MXNet::NDArray::CSR
        Loaded data.
=cut

method load_frombuffer(Str $buf)
{
    my ($handles, $names) = check_call(AI::MXNetCAPI::NDArrayLoadFromBuffer($buf, length($buf)));
    if (not @$names)
    {
        return [map { __PACKAGE__->_ndarray_cls($_) } @$handles];
    }
    else
    {
        my $n = @$names;
        my $h = @$handles;
        confess("Handles [$h] and names [$n] count mismatch") unless $h == $n;
        my %ret;
        @ret{ @$names } = map { __PACKAGE__->_ndarray_cls($_) } @$handles;
        return \%ret;
    }
}

=head2 save

    Save array ref of NDArray or hash of str->NDArray to a binary file.

    You can also use Storable to do the job if you only work with Perl.
    The advantage of load/save is the file is language agnostic.
    This means the file saved using save can be loaded by other language binding of mxnet.
    You also get the benefit being able to directly load/save from cloud storage(S3, HDFS)

    Parameters
    ----------
    fname : str
        The name of the file.Can be S3 or HDFS address (remember built with S3 support).
        Example of fname:

        - `s3://my-bucket/path/my-s3-ndarray`
        - `hdfs://my-bucket/path/my-hdfs-ndarray`
        - `/path-to/my-local-ndarray`

    $data : array ref of NDArrays or hash ref of NDArrays
        The data to be saved.
=cut

method save(Str $filename, ArrayRef[AI::MXNet::NDArray]|HashRef[AI::MXNet::NDArray] $data)
{
    my $handles = [];
    my $names = [];
    if(ref $data eq 'HASH')
    {
        for my $name (keys %$data)
        {
            push @$names, $name;
            push @$handles, $data->{ $name }->handle;
        }
    }
    else
    {
        @$handles = map { $_->handle } @$data;
    }
    check_call(
        AI::MXNetCAPI::NDArraySave(
            $filename,
            scalar(@$handles),
            $handles,
            $names
        )
    );
}

=head2 imdecode

    Decode an image from string. Requires OpenCV to work.

    Parameters
    ----------
    $str_img : str
        binary image data
    :$clip_rect : iterable of 4 int
        clip decoded image to rectangle (x0, y0, x1, y1)
    :$out= : Maybe[NDArray]
        output buffer. can be 3 dimensional (c, h, w) or 4 dimensional (n, c, h, w)
    :$index : int
        output decoded image to i-th slice of 4 dimensional buffer
    :$channels=3 : int
        number of channels to output. Decode to grey scale when channels = 1.
    $mean= : Maybe[NDArray]
        subtract mean from decode image before outputting.
=cut

method imdecode($str_img, ArrayRef[Int] :$clip_rect=[0, 0, 0, 0],
                Maybe[AI::MXNet::NDArray] :$out=, Int :$index=0, Int :$channels=3, Maybe[AI::MXNet::NDArray] :$mean=)
{
    return __PACKAGE__->_imdecode(
        $mean//__PACKAGE__->_new_empty_handle(),
        $index,
        @$clip_rect,
        $channels,
        length($str_img),
        { str_img => $str_img, ($out ? (out => $out) : ()) }
    );
}

=head2 _new_empty_handle

    Returns a new empty handle.

    Empty handle can be used to hold result

    Returns
    -------
        a new empty ndarray handle
=cut

sub _new_empty_handle
{
    my $hdl = check_call(AI::MXNetCAPI::NDArrayCreateNone());
    return $hdl;
}

=head2 _new_alloc_handle

    Returns a new handle with specified shape and context.

    Empty handle is only used to hold results

    Returns
    -------
    a new empty ndarray handle
=cut

func _new_alloc_handle($shape, $ctx, $delay_alloc, $dtype)
{
    my $sub = AI::MXNet::RunTime->Features()->is_enabled('INT64_TENSOR_SIZE')
              ? \&AI::MXNetCAPI::NDArrayCreateEx64
              : \&AI::MXNetCAPI::NDArrayCreateEx;
    my $hdl = check_call(
        $sub->(
            $shape,
            scalar(@$shape),
            $ctx->device_type_id,
            $ctx->device_id,
            $delay_alloc,
            $dtype
        )
    );
    return $hdl;
}

method _new_from_shared_mem($shared_pid, $shared_id, $shape, $dtype)
{
    my $hdl = check_call(
        AI::MXNetCAPI::NDArrayCreateFromSharedMemEx(
            $shared_pid,
            $shared_id,
            $shape,
            scalar(@$shape),
            DTYPE_STR_TO_MX->{$dtype}
        )
    );
    return $hdl;
}

=head2 tostype

        Return a copy of the array with chosen storage type.

        Returns
        -------
        AI::MXNet::NDArray or AI::MXNet::NDArray::CSR or AI::MXNet::NDArray::RowSparse
            A copy of the array with the chosen storage stype
=cut

method tostype(Stype $stype)
{
    return $self->cast_storage(stype => $stype);
}


=head2 waitall

    Wait for all async operations to finish in MXNet.
    This function is used for benchmarks only.
=cut

method waitall()
{
    check_call(AI::MXNetCAPI::NDArrayWaitAll());
}

=head2 _fresh_grad

        Parameters:
        ----------
        Maybe[Bool] $state=

        Whether this array's corresponding gradient array
        (registered via `autograd->mark_variables`) has been
        updated by `autograd->backward` since last reset.

        `_fresh_grad` need to be manually set to False
        after consuming gradient (usually after updating this
        array).
=cut

method _fresh_grad(Maybe[Bool] $state=)
{
    if(defined $state)
    {
        check_call(AI::MXNetCAPI::NDArraySetGradState($self->handle, $state));
        return $state;
    }
    else
    {
        return scalar(check_call(AI::MXNetCAPI::NDArrayGetGradState($self->handle)));
    }
}

=head2 detach

    Returns a new NDArray, detached from the current graph.
=cut

method detach()
{
    my $handle = check_call(AI::MXNetCAPI::NDArrayDetach($self->handle));
    return __PACKAGE__->_ndarray_cls($handle);
}

=head2 attach_grad

        Attach a gradient buffer to this NDArray, so that `backward`
        can compute gradient with respect to it.

        Parameters
        ----------
        GradReq :$grad_req='write' : {'write', 'add', 'null'}
            How gradient will be accumulated.
            - 'write': gradient will be overwritten on every backward.
            - 'add': gradient will be added to existing value on every backward.
            - 'null': do not compute gradient for this NDArray.
        Maybe[Str] :$stype= : str, optional
            The storage type of the gradient array. Defaults to the same stype of this NDArray.
=cut

method attach_grad(GradReq :$grad_req='write', Maybe[Str] :$stype=)
{
    my $grad;
    if(defined $stype)
    {
        $grad = __PACKAGE__->zeros($self->shape, stype => $stype);
    }
    else
    {
        $grad = $self->zeros_like;
    }
    $grad_req = GRAD_REQ_MAP->{$grad_req};
    check_call(
        AI::MXNetCAPI::AutogradMarkVariables(
            1,
            [$self->handle],
            [$grad_req],
            [$grad->handle]
        )
    );
}

=head2 grad

    Returns gradient buffer attached to this NDArray.
=cut

method grad()
{
    my $handle = check_call(AI::MXNetCAPI::NDArrayGetGrad($self->handle));
    return undef unless defined $handle;
    return __PACKAGE__->_ndarray_cls($handle);
}

=head2 backward

    Compute the gradients of this NDArray w.r.t variables.

    Parameters
    ----------
    :$out_grad= : NDArray, optional
        Gradient with respect to head.
    :$retain_graph=0 : bool, optional
        Whether to retain the computaion graph for another backward
        pass on the same graph. By default the computaion history
        is cleared.
    :$train_mode=1 : bool, optional
        Whether to compute gradient for training or inference.
=cut

method backward(Maybe[AI::MXNet::NDArray] :$out_grad=, Bool :$retain_graph=0, Bool :$train_mode=1)
{
    check_call(
        AI::MXNetCAPI::AutogradBackwardEx(
            1,
            [$self->handle],
            [defined $out_grad ? $out_grad->handle : undef],
            0,
            [],
            $retain_graph,
            0,
            $train_mode
        )
    )
}

method CachedOp(@args) { AI::MXNet::CachedOp->new(@args) }

method histogram(@args) { __PACKAGE__->_histogram(@args%2 ? ('data', @args) : @args) }

my $lvalue_methods = join "\n", map {"use attributes 'AI::MXNet::NDArray', \\&AI::MXNet::NDArray::$_, 'lvalue';"}
qw/at slice aspdl asmpdl reshape copy sever T astype as_in_context copyto empty zero ones full
                       array/;
eval << "EOV" if ($^V and $^V >= 5.006007);
{
  no warnings qw(misc);
  $lvalue_methods
}
EOV

sub contrib { 'AI::MXNet::Contrib::NDArray' }
sub random  { 'AI::MXNet::Random' }
sub sparse  { 'AI::MXNet::NDArray::Sparse' }
sub linalg  { 'AI::MXNet::LinAlg::NDArray' }
sub image   { 'AI::MXNet::Image::NDArray' }

__PACKAGE__->meta->make_immutable;
