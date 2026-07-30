#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";

use Market::ML::ExtractFantasmaDataset;

$| = 1;    # progreso en log sin buffer
select( ( select(STDERR), $| = 1 )[0] );

# CLI headless — extractor de features/labels fantasma (Opción A).
# Ejemplos:
#   perl scripts/extract_fantasma_dataset.pl --smoke
#   perl scripts/extract_fantasma_dataset.pl --csv Data/2026_Abril-Junio.csv --out Data/ml_out/train.csv
#   perl scripts/extract_fantasma_dataset.pl --csv Data/2026_07_24.csv --out Data/ml_out/test.csv --pack full

my %opt = (
    csv           => undef,
    out           => undef,
    pack          => 'full',
    max_bars      => undef,
    max_samples   => undef,
    start_ts      => undef,
    end_ts        => undef,
    length        => 50,
    smoke         => 0,
);

while ( @ARGV ) {
    my $a = shift @ARGV;
    if ( $a eq '--smoke' ) {
        $opt{smoke} = 1;
    }
    elsif ( $a eq '--csv' ) {
        $opt{csv} = shift @ARGV;
    }
    elsif ( $a eq '--out' ) {
        $opt{out} = shift @ARGV;
    }
    elsif ( $a eq '--pack' ) {
        $opt{pack} = shift @ARGV;
    }
    elsif ( $a eq '--max-bars' ) {
        $opt{max_bars} = 0 + shift @ARGV;
    }
    elsif ( $a eq '--max-samples' ) {
        $opt{max_samples} = 0 + shift @ARGV;
    }
    elsif ( $a eq '--start' ) {
        $opt{start_ts} = shift @ARGV;
    }
    elsif ( $a eq '--end' ) {
        $opt{end_ts} = shift @ARGV;
    }
    elsif ( $a eq '--length' ) {
        $opt{length} = 0 + shift @ARGV;
    }
    elsif ( $a eq '--help' || $a eq '-h' ) {
        print_usage();
        exit 0;
    }
    else {
        die "Opción desconocida: $a (usa --help)\n";
    }
}

if ( $opt{smoke} ) {
    $opt{csv} //= 'Data/2026_Abril-Junio.csv';
    # ~1 semana de abril (7*1440 = 10080); tope de muestras para smoke rápido
    $opt{start_ts}    //= '2026-04-01T00:00:00-05:00';
    $opt{end_ts}      //= '2026-04-08T00:00:00-05:00';
    $opt{max_samples} //= 80;
    $opt{out}         //= 'Data/ml_out/fantasma_smoke_abril_w1.csv';
    $opt{pack}        //= 'full';
}

$opt{csv} //= 'Data/2026_Abril-Junio.csv';
$opt{out} //= 'Data/ml_out/fantasma_dataset.csv';

die "CSV no encontrado: $opt{csv}\n" unless -f $opt{csv};

print "[*] Extractor fantasma Opción A\n";
print "[*] csv=$opt{csv} pack=$opt{pack}\n";
print "[*] start=", ( $opt{start_ts} // '-' ), " end=", ( $opt{end_ts} // '-' ), "\n";
print "[*] max_bars=", ( $opt{max_bars} // '-' ),
  " max_samples=", ( $opt{max_samples} // '-' ), "\n";

my $t0 = time();
my $res = Market::ML::ExtractFantasmaDataset->extract(
    csv          => $opt{csv},
    feature_pack => $opt{pack},
    max_bars     => $opt{max_bars},
    max_samples  => $opt{max_samples},
    start_ts     => $opt{start_ts},
    end_ts       => $opt{end_ts},
    length       => $opt{length},
);
my $elapsed = time() - $t0;

my $dir = $opt{out};
$dir =~ s{[\\/][^\\/]+$}{};
if ( length $dir && !-d $dir ) {
    require File::Path;
    File::Path::make_path($dir);
}

Market::ML::ExtractFantasmaDataset->write_csv( $res, $opt{out} );

my $st = $res->{stats} || {};
print "[*] bars=$st->{bars} triggers=$st->{triggers} samples=$st->{samples}",
  " trails=$st->{trails_total}\n";
print "[*] columns=", scalar( @{ $res->{columns} || [] } ), " elapsed=${elapsed}s\n";
print "[*] out=$opt{out}\n";

if ( @{ $res->{rows} || [] } ) {
    my $r0 = $res->{rows}[0];
    print "[*] sample0: time=$r0->{meta_time} tip=$r0->{meta_tip_index}",
      " y3=$r0->{y3} y5=$r0->{y5} y10=$r0->{y10} y15=$r0->{y15}",
      " atr=$r0->{atr_1m} pip_ob_1m=", ( $r0->{pip_ob_1m} // 'NA' ), "\n";

    # Masa de labels en clases 0…3
    for my $h ( 3, 5, 10, 15 ) {
        my %hist;
        for my $r ( @{ $res->{rows} } ) {
            my $v = $r->{"y$h"} // 0;
            $hist{$v}++;
        }
        my $mass03 = 0;
        $mass03 += ( $hist{$_} // 0 ) for 0 .. 3;
        my $n = scalar @{ $res->{rows} };
        printf "[*] y%-2d masa_0..3=%.1f%% hist={%s}\n",
          $h,
          $n ? 100 * $mass03 / $n : 0,
          join( ' ', map { "$_:" . ( $hist{$_} // 0 ) } sort { $a <=> $b } keys %hist );
    }
}

print "[*] OK\n";
exit 0;

sub print_usage {
    print <<'USAGE';
extract_fantasma_dataset.pl — features+labels LSTM fantasma (Opción A)

  --smoke              1ª semana abril train + max 80 muestras
  --csv PATH           CSV OHLCV 1m (default Data/2026_Abril-Junio.csv)
  --out PATH           CSV de salida
  --pack core|full     core=ATR/vol/labels; full=niveles multi-TF (default)
  --max-bars N         cortar carga del CSV
  --max-samples N      parar tras N disparos de fantasma
  --start TS           filtro inclusivo (string ISO)
  --end TS             filtro inclusivo
  --length N           length PivotPointsHL (default 50)

Full train (horas posibles):
  perl scripts/extract_fantasma_dataset.pl \
    --csv Data/2026_Abril-Junio.csv \
    --out Data/ml_out/fantasma_train_abril_junio.csv --pack full

Full test:
  perl scripts/extract_fantasma_dataset.pl \
    --csv Data/2026_07_24.csv \
    --out Data/ml_out/fantasma_test_julio.csv --pack full
USAGE
}
