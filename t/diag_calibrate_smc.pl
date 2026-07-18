#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use Market::MarketData;
use Market::Indicators::SMC_Pro;

my $tf = $ARGV[0] // '15m';
my $extra = $ARGV[1] // '';  # e.g. with_march
my $md = Market::MarketData->new();
my @files = ("$FindBin::Bin/../Data/2026_04_to_07.csv");
unshift @files, "$FindBin::Bin/../Data/2026_03.csv" if $extra eq 'with_march';
for my $path (@files) {
    open my $fh, '<', $path or die $path;
    <$fh>;
    while (<$fh>) {
        chomp;
        my @f = split /,/;
        next unless @f >= 5;
        $md->add_candle( [ @f[ 0 .. 5 ] ] );
    }
    close $fh;
}
$md->build_timeframes();
$md->set_timeframe($tf);
my $ind = Market::Indicators::SMC_Pro->new();
for my $i ( 0 .. $md->size() - 1 ) {
    $ind->update_last( $md, $i );
}

sub ts {
    my ($i) = @_;
    return '?' unless defined $i;
    my $c = $md->get_candle($i);
    return $c ? $c->[0] : '?';
}
sub short {
    my ($t) = @_;
    return '?' if !defined $t || $t eq '?';
    $t =~ s/T/ /;
    $t =~ s/:00-0[45]:00//;
    return $t;
}

print "TF=$tf bars=", $md->size(), " events=", scalar(@{ $ind->get_events() }),
  " pivots=", scalar(@{ $ind->get_pivots() }), " eq=", scalar(@{ $ind->get_eqhl() }), "\n";

print "PIVOTS\n";
for my $p ( @{ $ind->get_pivots() } ) {
    my $t = ts( $p->{index} );
    next unless $t =~ /2026-05-0[45]/ || $t =~ /2026-06-0[89]/ || $t =~ /2026-06-1[01]/;
    print short($t), " ", $p->{type}, " ", $p->{price} // '', "\n";
}
print "EVENTS\n";
for my $e ( @{ $ind->get_events() } ) {
    my $a = ts( $e->{start_index} );
    my $b = ts( $e->{index} );
    next unless $a =~ /2026-05-0[45]/ || $b =~ /2026-05-0[45]/
      || $a =~ /2026-06-0[89]/ || $b =~ /2026-06-0[89]/
      || $a =~ /2026-06-1[01]/ || $b =~ /2026-06-1[01]/;
    print join( ' ', $e->{scope} // '?', $e->{type} // '?', $e->{dir} // '?',
        short($a), '->', short($b), $e->{price} // 0 ), "\n";
}
print "OBS\n";
for my $ob ( @{ $ind->get_order_blocks() } ) {
    my $t = ts( $ob->{index} );
    my $c = ts( $ob->{created_at} );
    next unless $t =~ /2026-05/ || $c =~ /2026-05/ || $t =~ /2026-06/ || $c =~ /2026-06/;
    print join( ' ', short($t), 'created', short($c), $ob->{bias} // '?',
        'hi', $ob->{hi} // '?', 'lo', $ob->{lo} // '?' ), "\n";
}
print "EQ\n";
for my $q ( @{ $ind->get_eqhl() } ) {
    my $a = ts( $q->{prev_index} );
    my $b = ts( $q->{index} );
    next unless $a =~ /2026-05-0[45]/ || $b =~ /2026-05-0[45]/;
    print $q->{type}, ' ', short($a), ' -> ', short($b), "\n";
}
