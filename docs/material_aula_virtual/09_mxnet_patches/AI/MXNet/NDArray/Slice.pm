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

package AI::MXNet::NDArray::Slice;
use strict;
use warnings;
use Mouse;
use AI::MXNet::Base;
use AI::MXNet::Function::Parameters;

=head1 NAME

    AI::MXNet::NDArray::Slice - A convenience class for slicing of the AI::MXNet::NDArray objects.
=cut

has parent => (is => 'ro', isa => 'AI::MXNet::NDArray', required => 1);
has begin  => (is => 'ro', isa => 'Shape', required => 1);
has end    => (is => 'ro', isa => 'Shape', required => 1);
has step   => (is => 'ro', isa => 'Shape', default => sub { [] });
has squeeze_axes => (is => 'ro', isa  => 'ArrayRef[Int]', default => sub { [] });
use overload
    '.=' => \&set,
    '='  => sub { $_[0] },
    '""' => sub { my $self = $_[0]->sever; "$self" },
    '**' => sub { my $self = $_[0]->sever; $self ** $_[1] },
    '==' => sub { my $self = $_[0]->sever; $self == $_[1] },
    '!=' => sub { my $self = $_[0]->sever; $self != $_[1] },
    '+'  => sub { my $self = $_[0]->sever; $self +  $_[1] },
    '*'  => sub { my $self = $_[0]->sever; $self *  $_[1] },
    '-'  => sub { my $self = $_[0]->sever; $_[2] ? $_[1] - $self : $self - $_[1] },
    '/'  => sub { my $self = $_[0]->sever; $_[2] ? $_[1] / $self : $self / $_[1] },
    
    #'+=' => sub { my ($self, $other) = @_; my $in = $self->sever; $self .= ($in + $other) },
    #'-=' => sub { my ($self, $other) = @_; my $in = $self->sever; $self .= ($in - $other) },
    #'*=' => sub { my ($self, $other) = @_; my $in = $self->sever; $self .= ($in * $other) },
    #'/=' => sub { my ($self, $other) = @_; my $in = $self->sever; $self .= ($in / $other) },
    #'**='=> sub { my ($self, $other) = @_; my $in = $self->sever; $self .= ($in ** $other) },
    
    '+=' => sub { my ($self, $other) = @_; $self .= ($self->sever + $other)},
    '-=' => sub { my ($self, $other) = @_; $self .= ($self->sever - $other)},
    '*=' => sub { my ($self, $other) = @_; $self .= ($self->sever * $other)},
    '/=' => sub { my ($self, $other) = @_; $self .= ($self->sever / $other)},
    '**=' => sub {my ($self, $other) = @_; $self .= ($self->sever ** $other)},

    '>'  => sub { my $self = $_[0]->sever; return $_[2] ? $_[1] >  $self : $self >  $_[1] },
    '>=' => sub { my $self = $_[0]->sever; return $_[2] ? $_[1] >= $self : $self >= $_[1] },
    '<'  => sub { my $self = $_[0]->sever; return $_[2] ? $_[1] <  $self : $self <  $_[1] },
    '<=' => sub { my $self = $_[0]->sever; return $_[2] ? $_[1] <= $self : $self <= $_[1] };

# --- NUEVO MÉTODO: slice heredado y acumulativo ---
method slice(Slice|AdvancedSlice|InternalSlice|Undef @slices){
    confess("No slices supplied") unless @slices;

    # 1. Obtenemos el tensor materializado (virtualizado) temporalmente
    my $tmp_materialized = $self->sever;
    my $sub_slice = $tmp_materialized->slice(@slices);

    # Si devolvió algo que no es un objeto Slice (ej. gather_nd), retornamos directo
    return $sub_slice unless blessed($sub_slice) and $sub_slice->isa('AI::MXNet::NDArray::Slice');

    # Convertimos los ejes exprimidos en un hash para búsquedas O(1) rápidas
    my %is_squeezed = map { $_ => 1 } @{$self->squeeze_axes};

    my $parent_begin = [];
    my $parent_end   = [];
    my $parent_step  = [];

    # Este índice recorrerá los ejes disponibles del sub_slice (el tensor resultante actual)
    my $sub_axis_idx = 0;

    # 2. Iteramos sobre las dimensiones del tensor PADRE original
    for my $parent_axis_idx (0 .. $self->parent->ndim -1) { # $#{$self->begin}
        
        # Recuperamos los límites del primer slice. 
        # Si el primer slice no tocó este eje (porque se omitió), por defecto toma el rango completo [0, dimensión, 1]
        my $b1 = ( $parent_axis_idx <= $#{$self->begin} ) ? $self->begin->[$parent_axis_idx] : 0;
        my $e1 = ( $parent_axis_idx <= $#{$self->end} )   ? $self->end->[$parent_axis_idx]   : $self->parent->shape->[$parent_axis_idx];
        my $s1 = ( $parent_axis_idx <= $#{$self->step} )  ? ($self->step->[$parent_axis_idx] // 1) : 1;

        # CASO A: Este eje fue eliminado en el primer slice (Squeezed)
        # No existe en el sub_slice, por ende mantiene sus límites fijos del primer slice.
        if ($is_squeezed{$parent_axis_idx}) {
          push @$parent_begin, $b1;
          push @$parent_end,   $e1;
          push @$parent_step,  $s1;
          next; # Saltamos al siguiente eje del padre sin avanzar $sub_axis_idx
        }

        # CASO B: El eje está activo en el sub_slice
        # Pero debemos verificar si el segundo slice llegó a barrer este eje o no (remantentes con ':')
        if ($sub_axis_idx <= $#{$sub_slice->begin}) {
          my $b2 = $sub_slice->begin->[$sub_axis_idx] // 0;
          my $e2 = $sub_slice->end->[$sub_axis_idx];
          my $s2 = $sub_slice->step->[$sub_axis_idx]  // 1;
            
          # Verificamos si este sub-eje específico fue marcado para ser exprimido (Indexado escalar)
          my $is_sub_axis_squeezed = grep { $_ == $sub_axis_idx } @{$sub_slice->squeeze_axes};

          if ($is_sub_axis_squeezed) {
            # REGLA CORRECTA DE MXNET: 
            # Para un índice escalar, la ventana debe medir exactamente 1 unidad de tamaño.
            # Por lo tanto, end debe ser igual a (begin + step_padre)
            my $exact_begin = $b1 + ($b2 * $s1);
            push @$parent_begin, $exact_begin;
            push @$parent_end,   $exact_begin + $s1; # Mantiene la ventana de tamaño $s1
            push @$parent_step,  $s1;
          } else {
            # Si es un rango de rebanado normal (__SLICE__ con ':')
            push @$parent_begin, $b1 + ($b2 * $s1);
            push @$parent_end,   $b1 + ($e2 * $s1);
            push @$parent_step,  $s1 * $s2;
          }
        } 
        # CASO C: Ejes remanentes que no fueron explícitamente barridos en el segundo slice (actúan como ':')
        else {
          push @$parent_begin, $b1;
          push @$parent_end,   $e1;
          push @$parent_step,  $s1;
        }

        # Avanzamos al siguiente eje disponible del sub-slice
        $sub_axis_idx++;
    }

    # 3. Combinación inteligente de los ejes a exprimir (squeeze_axes)
    # Mapear de vuelta qué ejes virtuales del sub_slice corresponden a los del Padre Real
    my @mapped_sub_squeeze;
    my $curr_sub_axis = 0;
    
    for my $parent_axis_idx (0 .. $self->parent->ndim - 1) {
      # Si el eje ya estaba exprimido desde el primer slice, no existe en el sub_slice.
      # Nos saltamos el eje del padre SIN avanzar el contador del sub_slice.
      if ($is_squeezed{$parent_axis_idx}) {
        next;
      }
        
      # Si el sub_slice decidió exprimir este eje virtual disponible,
      # registramos que corresponde al eje real ($parent_axis_idx) en el espacio del Padre.
      if (grep { $_ == $curr_sub_axis } @{$sub_slice->squeeze_axes}) {
        push @mapped_sub_squeeze, $parent_axis_idx;
      }
        
      # CRUCIAL: Avanzamos al siguiente eje disponible del sub_slice
      $curr_sub_axis++;
    }

    # 4. Unimos los antiguos ejes exprimidos con los nuevos ejes reales mapeados
    my %combined_squeeze = map { $_ => 1 } (@{$self->squeeze_axes}, @mapped_sub_squeeze);
    my $parent_squeeze   = [ sort { $a <=> $b } keys %combined_squeeze ];

    # 5. Retornamos el Slice direccionado al Padre Real
    return new AI::MXNet::NDArray::Slice(
        parent       => $self->parent,
        begin        => $parent_begin,
        end          => $parent_end,
        step         => $parent_step,
        squeeze_axes => $parent_squeeze
    );
}

# method set(AcceptableInput $value, $reverse=){
sub set{
    my ($self, $value, $reverse) = @_;
    
    confess("set value must be defined") unless defined $value;
    confess("${\ $self->parent } is not writable") unless $self->parent->writable;
    my $shape = [ map {
        my($begin, $end) = @$_;
        ($end-$begin);
    } zip($self->begin, $self->end) ];
    
    if(ref $value){
        if(blessed($value) and $value->isa('AI::MXNet::NDArray')){
            $value = $value->as_in_context($self->parent->context);
        }elsif(blessed($value) and $value->isa('AI::MXNet::NDArray::Slice')){
            $value = $value->sever->as_in_context($self->parent->context);
        }else{
            $value = AI::MXNet::NDArray->array($value, ctx => $self->parent->context);
        }
        
        # Restore squeezed axes before shape validation
        # This is to work overload assignments like /= += -= *= **= print $value->aspdl;
        if(@{$self->squeeze_axes} and @{$value->shape} < @$shape){
            foreach my $axis (sort { $a <=> $b } @{$self->squeeze_axes}){
                $value = $value->expand_dims(axis => $axis);
            }
        }
        
        confess(sprintf("value of type %s does not match slice dim sizes [%s]", ref($value), join(',', @$shape)))
          if @{$value->shape} != @$shape;
          
        for(zip($shape, $value->shape)) {
                my ($dsize, $vdsize) = @$_;
                confess(sprintf("Slice [%s] != value shape [%s]", join(',', @$shape), join(',', @{ $value->shape })))
                  if $dsize != $vdsize;
        }
        
        AI::MXNet::NDArray->_crop_assign(
            $self->parent,
            $value,
            { out => $self->parent, begin => $self->begin, end => $self->end, step => $self->step }
        );
    }
    else
    {
        AI::MXNet::NDArray->_crop_assign_scalar(
            $self->parent,
            { "scalar" => $value, out => $self->parent, begin => $self->begin, end => $self->end, step => $self->step }
        );
    }
    return $self; #->parent;
}

#method sever()
#{
#    return AI::MXNet::NDArray->crop(
#            $self->parent,
#            { begin => $self->begin, end => $self->end }
#    );
#}
sub sever{
    my$self = shift; 
    my $result = AI::MXNet::NDArray->crop(
        $self->parent,
        { begin => $self->begin, end => $self->end, step => $self->step }
    );

    if(@{$self->squeeze_axes}){
        $result = $result->squeeze(axis => $self->squeeze_axes);
    }

    return $result;
}

{
    no warnings 'misc';
    use attributes 'AI::MXNet::NDArray::Slice', \&AI::MXNet::NDArray::Slice::sever, 'lvalue';
}

sub notsupported  { confess("NDArray only support continuous slicing on axis 0"); }
sub AUTOLOAD {
    my $sub = $AI::MXNet::NDArray::Slice::AUTOLOAD;
    $sub =~ s/.*:://;
    my $self = shift->sever;
    return $self->$sub(@_);
}

1;
