package Market::Indicators::ATR;
use strict;
use warnings;

sub new {
my ($class, $period) = @_;
my $self = {
period => $period,
values => [],
};
bless $self, $class;
return $self;
}
sub update_last {
my ($self, $market_data) = @_;
# TODO
}
sub get_values {
my ($self) = @_;
# TODO
}
sub reset {
my ($self) = @_;
# TODO
}
1;