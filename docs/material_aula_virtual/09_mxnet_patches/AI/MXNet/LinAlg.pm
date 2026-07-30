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

package AI::MXNet::LinAlg;
use strict;
use warnings;
use AI::MXNet::NS;
use AI::MXNet::LinAlg::Symbol;
use AI::MXNet::LinAlg::NDArray;

=head1 NAME

    AI::MXNet::LinAlg - Linear Algebra routines for NDArray and Symbol.
=cut

=head1 DESCRIPTION

    The Linear Algebra API, provides imperative/symbolic linear algebra tensor operations on CPU/GPU.

    mx->linalg-><sym|nd>->gemm  Performs general matrix multiplication and accumulation.
    mx->linalg-><sym|nd>->gemm2 Performs general matrix multiplication.
    mx->linalg-><sym|nd>->potrf Performs Cholesky factorization of a symmetric positive-definite matrix.
    mx->linalg-><sym|nd>->potri Performs matrix inversion from a Cholesky factorization.
    mx->linalg-><sym|nd>->trmm  Performs multiplication with a lower triangular matrix.
    mx->linalg-><sym|nd>->trsm  Solves matrix equation involving a lower triangular matrix.
    mx->linalg-><sym|nd>->sumlogdiag    Computes the sum of the logarithms of the diagonal elements of a square matrix.
    mx->linalg-><sym|nd>->syrk  Multiplication of matrix with its transpose.
    mx->linalg-><sym|nd>->gelqf LQ factorization for general matrix.
    mx->linalg-><sym|nd>->syevd Eigendecomposition for symmetric matrix.
    L<NDArray Python Docs|https://mxnet.apache.org/api/python/ndarray/linalg.html>
    L<Symbol Python Docs|https://mxnet.apache.org/api/python/symbol/linalg.html>

    Examples:

    ## NDArray
    my $A = mx->nd->array([[1.0, 1.0], [1.0, 1.0]]);
    my $B = mx->nd->array([[1.0, 1.0], [1.0, 1.0], [1.0, 1.0]]);
    ok(almost_equal(
        mx->nd->linalg->gemm2($A, $B, transpose_b=>1, alpha=>2.0)->aspdl,
        pdl([[4.0, 4.0, 4.0], [4.0, 4.0, 4.0]])
    ));

    ## Symbol
    my $sym_gemm2 = mx->sym->linalg->gemm2(
        mx->sym->var('A'),
        mx->sym->var('B'),
        transpose_b => 1,
        alpha => 2.0
    );
    my $A = mx->nd->array([[1.0, 1.0], [1.0, 1.0]]);
    my $B = mx->nd->array([[1.0, 1.0], [1.0, 1.0], [1.0, 1.0]]);
    ok(almost_equal(
        $sym_gemm2->eval(args => { A => $A, B => $B })->[0]->aspdl,
        pdl([[4.0, 4.0, 4.0], [4.0, 4.0, 4.0]])
    ));

=cut

sub sym     { 'AI::MXNet::LinAlg::Symbol'  }
sub symbol  { 'AI::MXNet::LinAlg::Symbol'  }
sub nd      { 'AI::MXNet::LinAlg::NDArray' }
sub ndarray { 'AI::MXNet::LinAlg::NDArray' }

#-----------eig-----------
# Compute eigenvalues and right or left eigenvectors of a square matrix.
# First convert the input to a pdl array and
# then perform all the checks on
# that internal representation before calling LAPACK.
# https://docs.scipy.org/doc/scipy/reference/generated/scipy.linalg.eig.html
# https://numpy.org/doc/stable/reference/generated/numpy.linalg.eig.html
# The LEFT Eigenvectors are calculated the same way as the Right Eigenvectors, but with the Transposed matrix A.
# See Appendix B.2, p. 424 - Eigenvalues and Eigenvectors from the doctoral thesis of Pérez-Arriaga, "Selective modal analysis with applications to electric power systems" (1981).
# https://dspace.mit.edu/bitstream/handle/1721.1/15875/08206193-MIT.pdf?sequence=2
#----------\eig-----------
sub eig{
  my ($self, $A) = splice(@_, 0, 2);
  my %args = AI::MXNet::NDArray->get_arguments( b                   => undef,
                                                left                => 0,
                                                right               => 1,
                                                overwrite_a         => 0,
                                                overwrite_b         => 0,
                                                check_finite        => 1,
                                                homogeneous_eigvals => 0,
                                                \@_);

  die "TypeError: _eig_dispatcher() missing 1 required positional argument: 'A'.\n" if !defined $A;
  
  my $pdl =
        ref($A) eq 'PDL'                ? $A
      : ref($A) eq 'AI::MXNet::NDArray' ? $A->aspdl
      : ref($A) eq 'ARRAY'              ? pdl($A)
      : die "TypeError: First parameter 'A' must be an Array like, such as a AI::MXNet::NDArray, a PDL or a reference to a Perl ARRAY.\n";
  
  my $ndim = $pdl->ndims;
  
  die "ValueError: expected 2-dimensional matrix. $ndim-dimensional array given.\n" if $ndim != 2;
  
  my ($num_rows, $num_cols) = $pdl->dims;
  
  die "ValueError: expected square matrix" if ($ndim != 2 or $num_rows != $num_cols);

  #Validation of optional parameters
  
  die "Right eigen vector must be a boolean: 0 (False) or 1 (True).\n" if ($args{right} !~ /^[01]$/);

  die "Left eigen vector must be a boolean: 0 (False) or 1 (True).\n" if ($args{left} !~ /^[01]$/);
  
  die "Generalized eigenvalue problems not yet implemented" if defined $args{b};
  
  die "homogeneous_eigvals not yet implemented" if $args{homogeneous_eigvals};
  
  warn "overwrite_a ignored" if $args{overwrite_a};  
  
  return $self->array([]) if $pdl->isempty; # $num_rows == 0

  # Check finiteness like SciPy
  if ($args{check_finite}) {
    die "Array contains NaN\n" if (($pdl != $pdl)->sum > 0);
    die "Array contains Inf\n" if ((abs($pdl) == PDL::Core::inf())->sum > 0);
  }

  my $realvalues = PDL::Core::zeroes($num_rows);
  my $imagvalues = PDL::Core::zeroes($num_rows);
  my $rvector    = PDL::Core::zeroes($num_rows, $num_cols);
  my $lvector    = PDL::Core::zeroes($num_rows, $num_cols);
  my $info       = 0;

  our $HAVE_PDL_LINALG;
  BEGIN {
    eval {
      require PDL::LinearAlgebra;
      PDL::LinearAlgebra->import();
      $HAVE_PDL_LINALG = 1;
    };
  }
  die "PDL::LinearAlgebra unavailable" unless $HAVE_PDL_LINALG;

  PDL::LinearAlgebra::geev($pdl, $args{right}, $args{left}, $realvalues, $imagvalues, $rvector, $lvector, $info);
  die "LinAlgError: eig algorithm (geev) did not converge\n" if $info;
    
  $realvalues = AI::MXNet::NDArray->array($realvalues)->T;
  $imagvalues = AI::MXNet::NDArray->array($imagvalues)->T;
  $rvector    = AI::MXNet::NDArray->array($rvector)->T;
  $lvector    = AI::MXNet::NDArray->array($lvector)->T;
  
  my $w = {
      real => $realvalues,
      imag => $imagvalues
  };

  return $w if !$args{left} && !$args{right};

  return ($w, $lvector, $rvector) if $args{left} && $args{right};

  return ($w, $lvector) if $args{left};

  return ($w, $rvector);
}


=pod
# Calculates the stationary vector via Normalized Left Eigenvector

# dot(π, A) = π
# Left Eigenvectors verification dot(π, A) = π
# printf "dot(π : %s, A : %s) == π : %s\n", $pi->aspdl, $A->aspdl, mx->nd->dot($pi, $A)->aspdl;

# Example 1:
$A  = mx->nd->array([[0.6, 0.2, 0.2], [0.4, 0, 0.6], [0, 0.8, 0.2]]);
my $pi = mx->nd->stationary($A);
printf "π = %s\n", $pi->aspdl; # [1/3, 1/3, 1/3]
$pi = mx->nd->dot($pi, $A) for (1 .. 20);
printf "dot(π : %s, A : %s) == π : %s\n", $pi->aspdl, $A->aspdl, mx->nd->dot($pi, $A)->aspdl;

# Example 2:
$A  = mx->nd->array([[0.7, 0.3], [0.4, 0.6]]);
$pi = mx->nd->stationary($A);
printf "π = %s\n", $pi->aspdl; # [0.571429 0.428571] = [4/7, 3/7]
$pi = mx->nd->dot($pi, $A) for (1 .. 20);
printf "dot(π : %s, A : %s) == π : %s\n", $pi->aspdl, $A->aspdl, mx->nd->dot($pi, $A)->aspdl;

# Example 3:
$A  = mx->nd->array([[0.7, 0.2, 0.1], [0.3, 0.4, 0.3], [0.2, 0.3, 0.5]]);;
$pi = mx->nd->stationary($A);
printf "π = %s\n", $pi->aspdl; # [0.456522 0.282609 0.26087]
$pi = mx->nd->dot($pi, $A) for (1 .. 20);
printf "dot(π : %s, A : %s) == π : %s\n", $pi->aspdl, $A->aspdl, mx->nd->dot($pi, $A)->aspdl;
=cut
sub stationary{
  my ($self, $A) = @_;

  my ($w, $vl) = $self->eig($A, left=>1);
  
  # Find unitary eigenvalue index where λ≈1
  my $idx = AI::MXNet::NDArray->argmin(AI::MXNet::NDArray->abs($w->{real} - 1));
  my $pi  = $vl->slice(':', $idx->asscalar);
  
  # Normalized left unitary eigen vector
  return $pi /= $pi->sum();
}

{
  no warnings 'once';
  # Injects the functions 'eig' and 'stationary' so that they become accesible from the sub-package NDArray de LinAlg
  *AI::MXNet::LinAlg::NDArray::eig = \&AI::MXNet::LinAlg::eig;
  *AI::MXNet::LinAlg::NDArray::stationary = \&AI::MXNet::LinAlg::stationary;
}

1;
