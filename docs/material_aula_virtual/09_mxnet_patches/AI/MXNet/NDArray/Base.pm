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

package AI::MXNet::NDArray::Base;
use strict;
use warnings;
use AI::MXNet::Base;
use AI::MXNet::NDArray::Doc;
use Mouse;
use AI::MXNet::Function::Parameters;

=head1 NAME

    AI::MXNet::NDArray::Base
=cut

=head1 DESCRIPTION

    This module provides a convenient interface to a C++ functions
    that work with NDArray.
    Essentially it loads them up during the lib startup into the Perl space.
=cut

my %function_meta;
method function_meta($code)
{
    return $function_meta{$code};
}

method function_meta_hash()
{
    return \%function_meta;
}

func _make_ndarray_function($handle, $func_name)
{
    my ($real_name, $desc, $arg_names,
        $arg_types, $arg_descs, $key_var_num_args,
        $ret_type) = @{ check_call(AI::MXNetCAPI::SymbolGetAtomicSymbolInfo($handle)) };
    $ret_type //= '';
    my $doc_str = build_doc($func_name,
                            $desc,
                            $arg_names,
                            $arg_types,
                            $arg_descs,
                            $key_var_num_args,
                            $ret_type
    );
    my %ndarguments;
    my @arguments;
    my %arguments = (out => 1, name => 1, ctx => 1, shape => 1);
    my $j = 0;
    for my $i (0..(@$arg_names-1))
    {
        if(not $arg_types->[$i] =~ /^(?:NDArray|Symbol|ndarray\-or\-symbol)/)
        {
            push @arguments, $arg_names->[$i];
            $arguments{ $arg_names->[$i] } = 1;
        }
        else
        {
            $ndarguments{ $arg_names->[$i] } = $j++;
        }
    }
    my $generic_ndarray_function = sub
    {
        my $class = shift;
        my (@args, %kwargs, %ndkwargs, @tmp);
        if(@_ and ref $_[-1] eq 'HASH')
        {
            %kwargs = %{ pop(@_) };
        }
        else
        {
            while(@_ >= 2 and not ref $_[-2])
            {
                if(exists $arguments{ $_[-2] })
                {
                    my $v = pop(@_);
                    my $k = pop(@_);
                    $kwargs{ $k } = $v;
                }
                elsif(exists $ndarguments{ $_[-2] })
                {
                    my $v = pop(@_);
                    my $k = pop(@_);
                    $ndkwargs{ $k } = $v;
                }
                else
                {
                    unshift(@tmp, pop(@_));
                    unshift(@tmp, pop(@_));
                }
            }
        }
        @args = (@_, @tmp);
        if(%ndkwargs)
        {
            for my $k (keys %ndkwargs)
            {
                $args[$ndarguments{$k}] = $ndkwargs{$k};
            }
        }
        my @ndargs;
        my @pos_args;
        for my $i (@args)
        {
            # Materializes AI::MXNet::NDArray::Slice into AI::MXNet::NDArray
            $i = $i->sever if blessed($i) and $i->isa('AI::MXNet::NDArray::Slice');
            if(blessed($i) and $i->isa(__PACKAGE__))
            {
                push @ndargs, $i->handle;
            }
            else
            {
                push @pos_args, $i;
            }
            if(@pos_args > @arguments)
            {
                confess("Too many positional arguments");
            }
        }
        @kwargs{ @arguments[0..$#pos_args] } = @pos_args;
        my $original_output;
        my $output_vars;
        delete $kwargs{name};
        if(grep { $_ eq 'out' } keys %kwargs)
        {
            $output_vars = delete $kwargs{out};
            $original_output = $output_vars;
            unless(ref($output_vars) and ref($output_vars) eq 'ARRAY')
            {
                $output_vars = [$output_vars];
            }
        }
        else
        {
            $output_vars = [];
        }
        if(blessed($class) and $class->isa(__PACKAGE__) and not @{ $output_vars })
        {
            @ndargs = ($class->handle) if not @ndargs;
            $class = ref $class;
        }
        for my $key (keys %kwargs)
        {
            $kwargs{ $key } = "(" .join(", ", map { defined($_) ? $_ : 'None' } @{ $kwargs{ $key } }) .")"
                if ref $kwargs{ $key } eq 'ARRAY';
        }
        my ($out, $stypes) = check_call(AI::MXNetCAPI::ImperativeInvokeEx(
                    $handle,
                    scalar(@ndargs),
                    \@ndargs,
                    [map { $_->handle } @$output_vars],
                    scalar(keys %kwargs),
                    \%kwargs)
        );
        return $original_output if $original_output;
        if(@$out == 1)
        {
            return __PACKAGE__->_ndarray_cls($out->[0], 1, $stypes->[0]);
        }
        else
        {
            my $i = 0;
            return [map { __PACKAGE__->_ndarray_cls($_, 1, $stypes->[$i++]) } @$out];
        }
    };
    $function_meta{ $generic_ndarray_function }{__name__} = $func_name;
    $function_meta{ $generic_ndarray_function }{__doc__} = $doc_str;
    return $generic_ndarray_function;
}

method _ndarray_cls($handle, $writable=1, $stype=STORAGE_TYPE_UNDEFINED)
{
    if($stype eq STORAGE_TYPE_UNDEFINED)
    {
        $stype = __PACKAGE__->_storage_type($handle);
    }
    if($stype eq STORAGE_TYPE_DEFAULT)
    {
        return AI::MXNet::NDArray->new(handle => $handle, writable => $writable);
    }
    elsif($stype eq STORAGE_TYPE_CSR)
    {
        return AI::MXNet::NDArray::CSR->new(handle => $handle, writable => $writable);
    }
    elsif($stype eq STORAGE_TYPE_ROW_SPARSE)
    {
        return AI::MXNet::NDArray::RowSparse->new(handle => $handle, writable => $writable);
    }
    else
    {
        confess("unknown storage type: $stype");
    }
}

method _storage_type($handle)
{
    scalar(check_call(AI::MXNetCAPI::NDArrayGetStorageType($handle)));
}

method stype()
{
    return STORAGE_TYPE_ID_TO_STR->{ __PACKAGE__->_storage_type($self->handle) };
}

# Hash global interno para buscar las funciones generadas por su nombre de texto sin contaminar la tabla de símbolos
my %op_name_lookup;

method function_by_name($name)
{
    return $op_name_lookup{$name};
}

#method _init_ndarray_module()
#{
#    # Definimos la lista negra de operadores que colisionan con PDL y NO deben inyectarse globalmente
#    my %pdl_collisions = map { $_ => 1 } qw( diag );
#
#    my $op_names = check_call(AI::MXNetCAPI::ListAllOpNames());
#    for my $name (@$op_names)
#    {
#        my $handle = check_call(AI::NNVMCAPI::GetOpHandle($name));
#        my $function = _make_ndarray_function($handle, $name);
#        
#        # Siempre guardamos en nuestro diccionario seguro de MXNet
#        $op_name_lookup{$name} = $function;
#
#        # Si el operador NO está en la lista negra de colisiones con PDL,
#        # lo inyectamos de forma normal para que las llamadas internas como _arange funcionen perfectamente.
#        if (not exists $pdl_collisions{$name})
#        {
#            no strict 'refs';
#            *{__PACKAGE__."::$name"} = $function;
#        }
#    }
#}

#method _init_ndarray_module()
#{
#    # 1. Definimos los operadores de la lista negra que suelen colisionar con PDL
#    my @pdl_collisions = qw(diag);
#    my %collisions_hash = map { $_ => 1 } @pdl_collisions;
#
#    my $op_names = check_call(AI::MXNetCAPI::ListAllOpNames());
#    for my $name (@$op_names)
#    {
#        my $handle = check_call(AI::NNVMCAPI::GetOpHandle($name));
#        my $function = _make_ndarray_function($handle, $name);
#        
#        # Guardamos la función en el diccionario global interno
#        $op_name_lookup{$name} = $function;
#
#        # Inyectamos en el namespace de Base.pm todas las funciones normales (ej: _arange)
#        {
#            no strict 'refs';
#            *{__PACKAGE__."::$name"} = $function; 
#        }
#    }
#
#    # 2. AUTOMATIZACIÓN: Forzamos el enrutamiento duro para la lista negra.
#    # Esto expulsa a PDL del namespace de AI::MXNet::NDArray de forma definitiva.
#    no strict 'refs';
#    no warnings 'redefine', 'once';
#    
#    for my $blacklisted_name (@pdl_collisions)
#    {
#        # Buscamos la función nativa que acabamos de generar en Base.pm
#        my $native_mxnet_func = *{__PACKAGE__."::$blacklisted_name"}{CODE};
#        
#        if ($native_mxnet_func) {
#            # Forzamos que el slot de NDArray apunte DIRECTAMENTE a la función nativa de MXNet
#            *{"AI::MXNet::NDArray::$blacklisted_name"} = $native_mxnet_func;
#        }
#    }
#}

# This one introduces missing functions like nonzero, diff, unique
method _init_ndarray_module()
{
    # 1. Operators that collide with PDL/Mouse/ETC to protect via hard-routing
    my @collisions = qw(diag sum min max around);
    my %collisions_hash = map { $_ => 1 } @collisions;

    # Deletes all collisions first
    for my $name (@collisions)
    {
        {
            no strict 'refs';
            delete ${__PACKAGE__ . '::'}{around};
        }
    }
    
    # 2. Hardcoded list of methods manually implemented in NDArray.pm or imported core helpers
    # This prevents early compilation injection from clobbering high-level Perl code.
    my %manual_ndarray_methods = map { $_ => 1 } qw(
        slice eig reshape moveaxis broadcast_to copyto copy onehot_encode
        maximum minimum true_divide zeros ones full concatenate 
        imdecode CachedOp histogram
        add subtract multiply power equal not_equal greater greater_equal lesser lesser_equal
        svd product
    ); # around 

    # 3. Track all primary operations found in MXNet to detect missing counterparts
    my %registered_ops;

    my $op_names = check_call(AI::MXNetCAPI::ListAllOpNames());
    for my $name (@$op_names)
    {
        my $handle = check_call(AI::NNVMCAPI::GetOpHandle($name));
        my $function = _make_ndarray_function($handle, $name);
        
        # Save the master function in our secure global lookup cache
        $op_name_lookup{$name} = $function;
        $registered_ops{$name} = $function;

        # Inject into Base.pm namespace for internal library calls (like _arange)
        # Skip if it clobbers foundational utilities like around, svd, product
        if (not exists $manual_ndarray_methods{$name})
        {
            no strict 'refs';
            *{__PACKAGE__."::$name"} = $function; 
        }
    }

    # 4. COMPLEMENTARY SHORTHAND SYNTHESIS:
    # Look for prefixed functions that are missing their natural non-prefixed twins
    for my $name (keys %registered_ops)
    {
        if ($name =~ /^_(?:(?:np[xi]?|contrib)_)?(.+)$/) {
            my $clean_name = $1;

            # Only synthesize if it doesn't exist natively and isn't a manual/core method
            if (not exists $registered_ops{$clean_name} 
                and not exists $manual_ndarray_methods{$clean_name}) 
            {
                $op_name_lookup{$clean_name} = $registered_ops{$name};

                {
                    no strict 'refs';
                    *{__PACKAGE__."::$clean_name"} = $registered_ops{$name};
                }
                
                $registered_ops{$clean_name} = $registered_ops{$name};
            }
        }
    }

    # 5. HARD-ROUTING AUTOMATION (Typeglob Aliasing):
    no strict 'refs';
    no warnings 'redefine', 'once';
    
    for my $final_name (keys %registered_ops)
    {
        # Skip injecting into AI::MXNet::NDArray if it's a high-level manual method
        # (Exception: We MUST process it if it's on the PDL collision list)
        next if exists $manual_ndarray_methods{$final_name} 
                and not exists $collisions_hash{$final_name};

        # Fetch the authoritative native function from Base.pm
        my $native_mxnet_func = *{__PACKAGE__."::$final_name"}{CODE};
        
        if ($native_mxnet_func) {
            # Force the NDArray symbol table slot to point straight to MXNet.
            *{"AI::MXNet::NDArray::$final_name"} = $native_mxnet_func;
        }
    }
}

__PACKAGE__->_init_ndarray_module;

1;
