package Market::ML::FantasmaLSTMData;
use strict;
use warnings;
use JSON::PP ();
use Market::ML::NormalizeFantasmaDataset;

# Carga CSV normalizado fantasma + arma matrices X/y en orden temporal.
# Targets: y3,y5,y10,y15. Features: lista de fantasma_norm_stats.json.

our $VERSION = '0.1';

my @DEFAULT_TARGETS = qw( y3 y5 y10 y15 );

sub load_stats {
    my ( $class, $path ) = @_;
    open my $fh, '<:encoding(UTF-8)', $path
      or die "No se puede leer stats $path: $!\n";
    local $/;
    my $raw = <$fh>;
    close $fh;
    my $json = JSON::PP->new->decode($raw);
    die "stats sin feature_columns: $path\n"
      unless ref( $json->{feature_columns} ) eq 'ARRAY'
      && @{ $json->{feature_columns} };
    return $json;
}

sub load_xy {
    my ( $class, %opts ) = @_;
    my $csv_path   = $opts{csv} // die "load_xy: falta csv\n";
    my $stats_path = $opts{stats};
    my $targets    = $opts{targets} // [@DEFAULT_TARGETS];

    my $feature_cols;
    if ( defined $stats_path && length $stats_path ) {
        my $stats = $class->load_stats($stats_path);
        $feature_cols = $stats->{feature_columns};
    }
    else {
        my ( $cols, undef ) = Market::ML::NormalizeFantasmaDataset->read_csv($csv_path);
        $feature_cols = Market::ML::NormalizeFantasmaDataset->select_feature_columns($cols);
    }

    my ( $cols, $rows ) = Market::ML::NormalizeFantasmaDataset->read_csv($csv_path);
    my %col_set = map { $_ => 1 } @$cols;
    for my $c ( @$feature_cols, @$targets ) {
        die "Columna ausente en $csv_path: $c\n" unless $col_set{$c};
    }

    my ( @X, @y, @meta );
    for my $r (@$rows) {
        push @X, [ map { $class->_num( $r->{$_} ) } @$feature_cols ];
        push @y, [ map { $class->_num( $r->{$_} ) } @$targets ];
        push @meta, {
            time       => $r->{meta_time} // '',
            event_bar  => $r->{meta_event_bar} // '',
            feature_bar => $r->{meta_feature_bar} // '',
        };
    }

    return {
        feature_columns => $feature_cols,
        targets         => [@$targets],
        X               => \@X,
        y               => \@y,
        meta            => \@meta,
        n_rows          => scalar(@X),
        n_features      => scalar(@$feature_cols),
        n_targets       => scalar(@$targets),
    };
}

# Ventanas [i .. i+seq_len-1]; label = fila final de la ventana (como lab).
sub make_sequences {
    my ( $class, $X, $y, $seq_len ) = @_;
    $seq_len = int($seq_len);
    die "seq_len debe ser >= 1\n" if $seq_len < 1;
    my $n = scalar @$X;
    die "pocas filas ($n) para seq_len=$seq_len\n" if $n < $seq_len;

    my ( @X_seq, @y_seq, @end_idx );
    for ( my $i = 0 ; $i <= $n - $seq_len ; $i++ ) {
        my @window;
        for my $t ( 0 .. $seq_len - 1 ) {
            push @window, [ @{ $X->[ $i + $t ] } ];
        }
        push @X_seq, \@window;
        push @y_seq, [ @{ $y->[ $i + $seq_len - 1 ] } ];
        push @end_idx, $i + $seq_len - 1;
    }
    return ( \@X_seq, \@y_seq, \@end_idx );
}

sub mae_rmse_per_target {
    my ( $class, $y_true, $y_pred, $target_names ) = @_;
    my $n = scalar @$y_true;
    die "mae_rmse: vacio\n" unless $n;
    my $nt = scalar @{ $y_true->[0] };
    my @names = $target_names ? @$target_names : map { "y$_" } ( 0 .. $nt - 1 );

    my @sum_abs = (0) x $nt;
    my @sum_sq  = (0) x $nt;
    for my $i ( 0 .. $n - 1 ) {
        for my $t ( 0 .. $nt - 1 ) {
            my $e = ( $y_pred->[$i][$t] // 0 ) - ( $y_true->[$i][$t] // 0 );
            $sum_abs[$t] += abs($e);
            $sum_sq[$t]  += $e * $e;
        }
    }

    my %out;
    for my $t ( 0 .. $nt - 1 ) {
        my $name = $names[$t] // "t$t";
        $out{$name} = {
            mae  => $sum_abs[$t] / $n,
            rmse => sqrt( $sum_sq[$t] / $n ),
            n    => $n,
        };
    }
    return \%out;
}

# Accuracy binaria opcional: pred>=umbral vs label>=umbral (conteo aparece/no).
sub binary_accuracy_per_target {
    my ( $class, $y_true, $y_pred, $target_names, $threshold ) = @_;
    $threshold //= 1;
    my $n  = scalar @$y_true;
    my $nt = scalar @{ $y_true->[0] };
    my @names = $target_names ? @$target_names : map { "y$_" } ( 0 .. $nt - 1 );

    my %out;
    for my $t ( 0 .. $nt - 1 ) {
        my ( $ok, $pos ) = ( 0, 0 );
        for my $i ( 0 .. $n - 1 ) {
            my $yt = ( $y_true->[$i][$t] // 0 ) >= $threshold ? 1 : 0;
            my $yp = ( $y_pred->[$i][$t] // 0 ) >= $threshold ? 1 : 0;
            $ok++  if $yt == $yp;
            $pos++ if $yt;
        }
        my $name = $names[$t] // "t$t";
        $out{$name} = {
            accuracy  => $n ? $ok / $n : 0,
            threshold => $threshold,
            n         => $n,
            n_pos     => $pos,
        };
    }
    return \%out;
}

sub write_metrics_json {
    my ( $class, $payload, $path ) = @_;
    my $json = JSON::PP->new->canonical(1)->pretty(1)->encode($payload);
    open my $fh, '>:encoding(UTF-8)', $path
      or die "No se puede escribir $path: $!\n";
    print {$fh} $json;
    close $fh;
    return;
}

sub write_preds_csv {
    my ( $class, $path, $meta, $end_idx, $y_true, $y_pred, $targets ) = @_;
    open my $fh, '>:encoding(UTF-8)', $path
      or die "No se puede escribir $path: $!\n";
    my @hdr = (qw( meta_time meta_event_bar meta_feature_bar row_idx ));
    push @hdr, map { "true_$_" } @$targets;
    push @hdr, map { "pred_$_" } @$targets;
    print {$fh} join( ',', @hdr ), "\n";
    for my $i ( 0 .. $#$y_true ) {
        my $ri = $end_idx->[$i];
        my $m  = $meta->[$ri] // {};
        my @row = (
            $m->{time} // '',
            $m->{event_bar} // '',
            $m->{feature_bar} // '',
            $ri,
            @{ $y_true->[$i] },
            @{ $y_pred->[$i] },
        );
        print {$fh} join( ',', @row ), "\n";
    }
    close $fh;
    return;
}

sub _num {
    my ( $class, $v ) = @_;
    return 0 if !defined $v || $v eq '';
    return 0 + $v;
}

1;
