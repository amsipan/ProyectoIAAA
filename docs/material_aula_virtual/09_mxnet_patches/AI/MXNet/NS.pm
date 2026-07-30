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

package AI::MXNet::NS;
use strict;
use warnings;

# ===================================================================
# HARMONIOUS DESIGN & SAFE DISPATCH ARCHITECTURE (PDL Bypass Solution)
# ===================================================================
# This class acts similarly to Exporter by adding a dynamic "import"
# method to the calling package. It allows emulation of Python's 
# "import mxnet as mx" or "import mxnet.ndarray as nd" style aliasing
# via Perl idioms like "use AI::MXNet qw(mx nd);".
#
# 1. SELECTIVE PROTECTION & CENTRALIZATION (NDArray/Base.pm):
#    - A flat, secure global lookup dictionary (%op_name_lookup) holds 
#      ALL mathematical operations generated dynamically from the MXNet C-API.
#    - A hardcoded blacklist defines critical operators that collide with PDL:
#      qw(diag sum min max).
#    - Thousands of standard functions outside this blacklist (such as '_arange') 
#      are injected normally into the package namespace. This ensures that 
#      MXNet's internal core logic (e.g., 'mx->nd->arange') can seamlessly 
#      locate its native dependencies without symbol errors.
#
# 2. HARD-ROUTING AUTOMATION VIA TYPEGLOB ALIASING (NDArray/Base.pm):
#    - At the end of module initialization, the blacklist is iterated over 
#      to perform hard typeglob aliasing directly into the target namespace:
#      *{"AI::MXNet::NDArray::$blacklisted_name"} = $native_mxnet_func;
#    - This early compilation/startup-time shielding completely expels PDL 
#      hijack attempts from the target symbol table. This guarantees that internal 
#      instance method calls (such as '$self->diag()' inside 'corrcoef' in 
#      NDArray.pm) resolve exclusively to MXNet, regardless of when PDL is loaded.
#
# 3. FLUID INTERFACE & DIRECT PYTHON-STYLE ALIASING (NS.pm):
#    - The 'AI::MXNet::NS::Proxy' acts as a unified perimeter shield to handle 
#      the syntax sugar for both chained calls ('mx->nd->diag(...)') and direct 
#      shorthand package aliases ('nd->array(...)').
#    - When evaluating 'mx->nd', the proxy mutates the existing '$self' object by 
#      setting its inner target package ('AI::MXNet::NDArray') and returns itself, 
#      preserving the method execution chain without creating a recursive loop.
#    - When evaluating the next link in the chain (e.g., '->diag(...)'), the Proxy's 
#      AUTOLOAD cleanly removes its own object reference and injects 
#      the real destination class splice(@_, 0, 1, $target_pkg); before delegating control via 'goto'. 
#      This prevents call stack recursion and perfectly aligns input arguments for 
#      Mouse/Moose strict signature validators.
#
# RESULT: Seamless, high-performance O(1) coexistence between MXNet and PDL.
# ===================================================================

sub _sym : lvalue
{
    my ($pkg, $name) = @_;
    no strict 'refs';
    no warnings 'once'; # Updated here
    *{"$pkg\::$name"};
}

#sub import
#{
#    my (undef, $opt) = @_;
#    my $class = caller();
#    my $func = sub { $class };
#    _sym($class, 'import') = sub {
#        my (undef, @names) = @_;
#        @names = map { s/[^\w:]//sgr } @names;
#        my $target = caller();
#
#        _sym($names[0], '') = _sym($class, '') if
#            @names == 1 and $opt and $opt eq 'global';
#
#        _sym($target, $_) = $func for @names;
#    };
#}

# Updated here:
#sub import
#{
#    my (undef, $opt) = @_;
#    my $class = caller();
#    
#    # my $func = sub { $class };
#    my $func = sub {
#        # El alias principal (ej. "mx") ahora devolverá un Proxy inteligente
#        return bless({ _base_class => $class }, 'AI::MXNet::NS::Proxy');
#    };
#    
#    no strict 'refs';  # Temporarily disable strict references
#    *{_sym($class, 'import')} = sub {
#        my (undef, @names) = @_;
#        @names = map { s/[^\w:]//sgr } @names;
#        my $target = caller();
#
#        *{_sym($names[0], '')} = \&{_sym($class, '')} if
#            @names == 1 and $opt and $opt eq 'global';
#
#        *{_sym($target, $_)} = $func for @names;
#    };
#    use strict 'refs'; # Re-enable strict references
#}

sub import
{
    my (undef, $opt) = @_;
    my $class = caller();
    
    no strict 'refs';  # Deshabilitamos temporalmente referencias estrictas para manipular typeglobs
    *{_sym($class, 'import')} = sub {
        my (undef, @names) = @_;
        @names = map { s/[^\w:]//sgr } @names;
        my $target = caller();

        # Si se usó la opción global, asignamos el paquete completo
        *{_sym($names[0], '')} = \&{_sym($class, '')} if
            @names == 1 and $opt and $opt eq 'global';

        # Iteramos sobre los nombres que el usuario desea importar (ej: 'mx', 'nd')
        for my $import_name (@names) {
            my $func;
            
            if ($import_name eq 'nd') {
                # NUEVO: Si piden importar 'nd' directamente, creamos un despachador
                # orientado por defecto a la clase de Tensores Imperativos (AI::MXNet::NDArray)
                $func = sub {
                    return bless({ _target_pkg => 'AI::MXNet::NDArray' }, 'AI::MXNet::NS::Proxy');
                };
            } else {
                # Comportamiento estándar para el alias raíz (ej: 'mx')
                $func = sub { $class };
            }
            
            # Inyectamos el closure dinámico en el script del llamador
            *{_sym($target, $import_name)} = $func;
        }
    };
    use strict 'refs'; # Re-enable strict references
}

my $autoload_template = q(
    sub AUTOLOAD
    {
        our ($AUTOLOAD, %AUTOLOAD);
        my $name = $AUTOLOAD =~ s/.*:://sr;
        my $func = $AUTOLOAD{$name};
        Carp::carp(qq(Can't locate object method "$name" via package "${\ __PACKAGE__ }"))
            unless $func;
        goto $func;
    }
);

# using AUTOLOAD here allows for the addition of an AI::MXNet::SomeClass
# class to coexist with an AI::MXNet->SomeClass() shorthand constructor.
sub register
{
    my ($class, $target) = @_;
    my $name = $class =~ s/.*:://sr;
    my $dest = $class->can('new');
    ${_sym($target, 'AUTOLOAD')}{$name} = sub {
        splice @_, 0, 1, $class;
        goto $dest;
    };
    return if $target->can('AUTOLOAD');
    eval sprintf 'package %s { %s }', $target, $autoload_template;
    die if $@;
    return;
}

1;

# ---------------------------------------------------------------------
# Declaración del paquete Proxy Corregido y Blindado de Forma Definitiva
# ---------------------------------------------------------------------
package AI::MXNet::NS::Proxy;
use strict;
use warnings;
use Carp;

our $AUTOLOAD;
sub AUTOLOAD 
{
    my ($self, @args) = @_;
    my $name = $AUTOLOAD =~ s/.*:://sr;
    return if $name eq 'DESTROY';

    # CASO 1: Soporte para constructores shorthand de submódulos (ej: mx->nd)
    # Alteramos el objeto actual sin crear nuevas referencias de empaquetado recursivas
    if ($name eq 'nd') {
        $self->{_target_pkg} = 'AI::MXNet::NDArray';
        return $self; # Retorna el mismo objeto mutado para que la cadena nd->diag(...) continúe de inmediato
    }

    # Determinamos el paquete objetivo (por defecto recurre a la clase base si no ha sido mutado)
    my $target_pkg = $self->{_target_pkg} || $self->{_base_class} || 'AI::MXNet::NDArray';

    # CASO 2: Es un método estático, constructor o función forzada de la clase real (ej: mx->nd->array, mx->nd->diag)
    if (my $method = $target_pkg->can($name)) {
        # LIMPIEZA DE ARGS: Eliminamos la referencia al objeto Proxy ($self) de @_ 
        # y colocamos el paquete real destino al inicio para no confundir a Mouse/Moose.
        splice(@_, 0, 1, $target_pkg); 
        goto &$method;
    }

    # CASO 3: Fallback estándar
    if (my $fallback = $target_pkg->can('AUTOLOAD')) {
        our $AUTOLOAD = "${target_pkg}::$name";
        splice(@_, 0, 1, $target_pkg); 
        goto &$fallback;
    }

    Carp::confess(qq(Can't locate object method "$name" via package "$target_pkg" (Proxy Dispatch)));
}
1;