#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";

use Market::ML::NormalizeFantasmaDataset;

# Normalización train-only (z-score) para dataset fantasmita.
# Fit en train → aplica a train y test; guarda stats JSON.

my %opt = (
    train  => 'Data/ml_out/fantasma_train_abril_junio.csv',
    test   => 'Data/ml_out/fantasma_test_julio.csv',
    out_train => 'Data/ml_out/fantasma_train_norm.csv',
    out_test  => 'Data/ml_out/fantasma_test_norm.csv',
    stats  => 'Data/ml_out/fantasma_norm_stats.json',
    method => 'zscore',
    include_ref_mid_pips => 0,
);

while (@ARGV) {
    my $a = shift @ARGV;
    if ( $a eq '--train' ) {
        $opt{train} = shift @ARGV;
    }
    elsif ( $a eq '--test' ) {
        $opt{test} = shift @ARGV;
    }
    elsif ( $a eq '--out-train' ) {
        $opt{out_train} = shift @ARGV;
    }
    elsif ( $a eq '--out-test' ) {
        $opt{out_test} = shift @ARGV;
    }
    elsif ( $a eq '--stats' ) {
        $opt{stats} = shift @ARGV;
    }
    elsif ( $a eq '--method' ) {
        $opt{method} = shift @ARGV;
    }
    elsif ( $a eq '--include-ref-mid-pips' ) {
        $opt{include_ref_mid_pips} = 1;
    }
    elsif ( $a eq '--help' || $a eq '-h' ) {
        print_usage();
        exit 0;
    }
    else {
        die "Opción desconocida: $a (usa --help)\n";
    }
}

die "Train no encontrado: $opt{train}\n" unless -f $opt{train};
die "Test no encontrado: $opt{test}\n"   unless -f $opt{test};

for my $p ( $opt{out_train}, $opt{out_test}, $opt{stats} ) {
    my $dir = $p;
    $dir =~ s{[\\/][^\\/]+$}{};
    if ( length $dir && !-d $dir ) {
        require File::Path;
        File::Path::make_path($dir);
    }
}

print "[*] Normalización fantasmita ($opt{method})\n";
print "[*] train=$opt{train}\n";
print "[*] test=$opt{test}\n";

my $t0 = time();
my $res = Market::ML::NormalizeFantasmaDataset->fit_transform(
    train                => $opt{train},
    test                 => $opt{test},
    method               => $opt{method},
    include_ref_mid_pips => $opt{include_ref_mid_pips},
);

Market::ML::NormalizeFantasmaDataset->write_csv(
    $res->{train_columns}, $res->{train_rows}, $opt{out_train}
);
Market::ML::NormalizeFantasmaDataset->write_csv(
    $res->{test_columns} // $res->{train_columns},
    $res->{test_rows},
    $opt{out_test}
);
Market::ML::NormalizeFantasmaDataset->write_stats_json( $res, $opt{stats} );

my $elapsed = time() - $t0;
my $nf = scalar @{ $res->{feature_columns} || [] };
my $nt = scalar @{ $res->{train_rows} || [] };
my $ns = $res->{test_rows} ? scalar @{ $res->{test_rows} } : 0;

print "[*] features_norm=$nf train_rows=$nt test_rows=$ns elapsed=${elapsed}s\n";
print "[*] excluidos: meta/time=", scalar( @{ $res->{excluded}{meta_time} || [] } ),
  " labels=", scalar( @{ $res->{excluded}{labels} || [] } ),
  " sgr_kind=", scalar( @{ $res->{excluded}{sgr_kind} || [] } ),
  " other=", join( ',', @{ $res->{excluded}{other} || [] } ) || '-', "\n";
print "[*] out_train=$opt{out_train}\n";
print "[*] out_test=$opt{out_test}\n";
print "[*] stats=$opt{stats}\n";
print "[*] OK\n";
exit 0;

sub print_usage {
    print <<'USAGE';
normalize_fantasma_dataset.pl — z-score/min-max fit en train, aplica a test

  --train PATH
  --test PATH
  --out-train PATH   (default Data/ml_out/fantasma_train_norm.csv)
  --out-test PATH    (default Data/ml_out/fantasma_test_norm.csv)
  --stats PATH       (default Data/ml_out/fantasma_norm_stats.json)
  --method zscore|minmax
  --include-ref-mid-pips   incluir ref_mid_pips (por defecto EXCLUIDO)

Excluye siempre: meta_*, time, y3/y5/y10/y15, sgr_kind_* (categóricos).
USAGE
}
