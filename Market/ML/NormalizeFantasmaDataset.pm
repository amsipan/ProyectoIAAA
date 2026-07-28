package Market::ML::NormalizeFantasmaDataset;
use strict;
use warnings;
use JSON::PP ();

# Fit z-score (media/std) solo en train; aplica a train y test.
# Excluye meta_*, labels y*, categóricas sgr_kind_*, y ref_mid_pips (nivel absoluto).

our $VERSION = '0.1';

my @LABEL_COLS = qw( y3 y5 y10 y15 );

sub fit_transform {
    my ( $class, %opts ) = @_;
    my $train_path = $opts{train} // die "fit_transform: falta train\n";
    my $test_path  = $opts{test};
    my $method     = $opts{method} // 'zscore';    # zscore | minmax
    die "method desconocido: $method\n" unless $method eq 'zscore' || $method eq 'minmax';

    my ( $train_cols, $train_rows ) = $class->read_csv($train_path);
    my $feature_cols = $class->select_feature_columns( $train_cols, %opts );

    my $stats = $class->fit_stats( $train_rows, $feature_cols, $method );
    my $train_norm = $class->apply( $train_rows, $train_cols, $feature_cols, $stats );

    my $test_norm;
    my $test_cols;
    if ( defined $test_path && length $test_path ) {
        ( $test_cols, my $test_rows ) = $class->read_csv($test_path);
        $test_norm = $class->apply( $test_rows, $test_cols, $feature_cols, $stats );
    }

    return {
        feature_columns => $feature_cols,
        stats           => $stats,
        train_columns   => $train_cols,
        train_rows      => $train_norm,
        test_columns    => $test_cols,
        test_rows       => $test_norm,
        method          => $method,
        excluded        => $class->_exclusion_report( $train_cols, $feature_cols ),
    };
}

sub select_feature_columns {
    my ( $class, $cols, %opts ) = @_;
    my $include_ref_mid = $opts{include_ref_mid_pips} ? 1 : 0;
    my $onehot_sgr      = $opts{onehot_sgr}          ? 1 : 0;

    my @feats;
    for my $c (@$cols) {
        next if $c =~ /^meta_/;
        next if $c eq 'time';
        next if grep { $_ eq $c } @LABEL_COLS;
        next if $c =~ /^sgr_kind_/;    # categórica string; omitir en v1 (no one-hot)
        next if !$include_ref_mid && $c eq 'ref_mid_pips';
        push @feats, $c;
    }

    # one-hot sgr reservado; no activo en v1
    if ($onehot_sgr) {
        warn "onehot_sgr pedido pero no implementado en v1; sgr_kind_* siguen excluidos\n";
    }

    return \@feats;
}

sub _exclusion_report {
    my ( $class, $all_cols, $feats ) = @_;
    my %keep = map { $_ => 1 } @$feats;
    my @meta   = grep { /^meta_/ || $_ eq 'time' } @$all_cols;
    my @labels = grep { $_ eq 'y3' || $_ eq 'y5' || $_ eq 'y10' || $_ eq 'y15' } @$all_cols;
    my @sgr    = grep { /^sgr_kind_/ } @$all_cols;
    my @other  = grep { !$keep{$_} && !/^meta_/ && $_ ne 'time' && !/^y\d+$/ && !/^sgr_kind_/ } @$all_cols;
    return {
        meta_time   => \@meta,
        labels      => \@labels,
        sgr_kind    => \@sgr,
        other       => \@other,    # p.ej. ref_mid_pips
        note        => 'sgr_kind_* omitidos (categoricos string); ref_mid_pips excluido por defecto (nivel abs./PIP)',
    };
}

sub fit_stats {
    my ( $class, $rows, $feature_cols, $method ) = @_;
    $method //= 'zscore';
    my %stats = (
        method          => $method,
        columns         => {},
        n_rows          => scalar(@$rows),
        n_features      => scalar(@$feature_cols),
        missing_as_zero => 1,
        pip_note        => 'valores vacíos en features → 0 antes de normalizar',
    );

    for my $col (@$feature_cols) {
        my @vals;
        for my $r (@$rows) {
            my $v = $r->{$col};
            if ( !defined $v || $v eq '' ) {
                push @vals, 0;
            }
            else {
                push @vals, 0 + $v;
            }
        }
        my $n = scalar @vals;
        if ( $method eq 'zscore' ) {
            my ( $mean, $std ) = $class->_mean_std( \@vals );
            # std≈0 → columna constante; z queda 0
            $std = 1 if $std < 1e-12;
            $stats{columns}{$col} = { mean => $mean, std => $std, n => $n };
        }
        else {
            my ( $min, $max ) = $class->_min_max( \@vals );
            my $range = $max - $min;
            $range = 1 if abs($range) < 1e-12;
            $stats{columns}{$col} = { min => $min, max => $max, range => $range, n => $n };
        }
    }
    return \%stats;
}

sub apply {
    my ( $class, $rows, $all_cols, $feature_cols, $stats ) = @_;
    my $method = $stats->{method} // 'zscore';
    my %feat_set = map { $_ => 1 } @$feature_cols;

    my @out;
    for my $r (@$rows) {
        my %nr;
        for my $c (@$all_cols) {
            if ( !$feat_set{$c} ) {
                $nr{$c} = $r->{$c};
                next;
            }
            my $raw = $r->{$c};
            my $v = ( !defined $raw || $raw eq '' ) ? 0 : 0 + $raw;
            my $s = $stats->{columns}{$c};
            if ( $method eq 'zscore' ) {
                $nr{$c} = ( $v - $s->{mean} ) / $s->{std};
            }
            else {
                $nr{$c} = ( $v - $s->{min} ) / $s->{range};
            }
        }
        push @out, \%nr;
    }
    return \@out;
}

sub write_csv {
    my ( $class, $cols, $rows, $path ) = @_;
    open my $fh, '>:encoding(UTF-8)', $path
      or die "No se puede escribir $path: $!\n";
    print {$fh} join( ',', @$cols ), "\n";
    for my $r (@$rows) {
        print {$fh} join( ',', map { $class->_csv_escape( $r->{$_} ) } @$cols ), "\n";
    }
    close $fh;
    return;
}

sub write_stats_json {
    my ( $class, $result, $path ) = @_;
    my $payload = {
        method            => $result->{method},
        feature_columns   => $result->{feature_columns},
        excluded          => $result->{excluded},
        stats             => $result->{stats},
        train_rows        => scalar( @{ $result->{train_rows} || [] } ),
        test_rows         => $result->{test_rows} ? scalar( @{ $result->{test_rows} } ) : 0,
        include_ref_mid_pips => 0,
        sgr_kind_encoding    => 'excluded_v1',
    };
    my $json = JSON::PP->new->canonical(1)->pretty(1)->encode($payload);
    open my $fh, '>:encoding(UTF-8)', $path
      or die "No se puede escribir $path: $!\n";
    print {$fh} $json;
    close $fh;
    return;
}

sub read_csv {
    my ( $class, $path ) = @_;
    open my $fh, '<:encoding(UTF-8)', $path
      or die "No se puede leer $path: $!\n";
    my $header = <$fh>;
    die "CSV vacío: $path\n" unless defined $header;
    chomp $header;
    $header =~ s/\r$//;
    my @cols = split /,/, $header, -1;
    my @rows;
    while ( my $line = <$fh> ) {
        chomp $line;
        $line =~ s/\r$//;
        next if $line eq '';
        my @vals = $class->_parse_csv_line($line);
        my %row;
        for my $i ( 0 .. $#cols ) {
            $row{ $cols[$i] } = $vals[$i] // '';
        }
        push @rows, \%row;
    }
    close $fh;
    return ( \@cols, \@rows );
}

sub _parse_csv_line {
    my ( $class, $line ) = @_;
    my @vals;
    my $cur = '';
    my $in_q = 0;
    for my $i ( 0 .. length($line) - 1 ) {
        my $ch = substr( $line, $i, 1 );
        if ($in_q) {
            if ( $ch eq '"' ) {
                if ( substr( $line, $i + 1, 1 ) eq '"' ) {
                    $cur .= '"';
                    $i++;
                }
                else {
                    $in_q = 0;
                }
            }
            else {
                $cur .= $ch;
            }
        }
        else {
            if ( $ch eq '"' ) {
                $in_q = 1;
            }
            elsif ( $ch eq ',' ) {
                push @vals, $cur;
                $cur = '';
            }
            else {
                $cur .= $ch;
            }
        }
    }
    push @vals, $cur;
    return @vals;
}

sub _csv_escape {
    my ( $class, $v ) = @_;
    return '' unless defined $v;
    return $v if $v =~ /^-?\d+(?:\.\d+(?:[eE][+-]?\d+)?)?$/;
    $v =~ s/"/""/g;
    return qq{"$v"} if $v =~ /[,"\n]/;
    return $v;
}

sub _mean_std {
    my ( $class, $vals ) = @_;
    my $n = scalar @$vals;
    return ( 0, 1 ) if $n < 1;
    my $sum = 0;
    $sum += $_ for @$vals;
    my $mean = $sum / $n;
    my $ss = 0;
    $ss += ( $_ - $mean )**2 for @$vals;
    my $std = $n > 1 ? sqrt( $ss / ( $n - 1 ) ) : 0;    # sample std
    return ( $mean, $std );
}

sub _min_max {
    my ( $class, $vals ) = @_;
    return ( 0, 1 ) unless @$vals;
    my ( $min, $max ) = ( $vals->[0], $vals->[0] );
    for my $v (@$vals) {
        $min = $v if $v < $min;
        $max = $v if $v > $max;
    }
    return ( $min, $max );
}

1;
