package Market::IndicatorManager;
use strict;
use warnings;

sub new {
my ($class) = @_;
my $self = {
indicators => {},
};
bless $self, $class;
return $self;
}
sub register {
my ($self, $name, $indicator) = @_;
# TODO
}
sub update_last {
my ($self, $market_data) = @_;
# TODO
}
sub get {
my ($self, $name) = @_;
# TODO
}
sub slice_array {
my ($self, $name, $start, $end) = @_;
# TODO
}
sub reset_all {
my ($self) = @_;
# TODO
}
1;