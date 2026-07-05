package Market::UI::ReplayPanel;
use strict;
use warnings;
use utf8;

use Market::UI::Callbacks;

# Market::UI::ReplayPanel — panel flotante media-player de Replay (task 0043).
# Frame hijo del chart con place(); sin Tk::NoteBook ni Optionmenu.
# task 0048: etiquetas ASCII (Tk/Fedora35 no tiene glyphs de reproductor ni utf8 sin use utf8).

sub new {
    my ($class, %args) = @_;
    my $parent = $args{parent} or die "ReplayPanel: requiere parent";
    my $chart  = $args{chart}  or die "ReplayPanel: requiere chart";
    my $vars   = $args{ui_vars} || {};
    my $mw     = $args{mw};

    my $callbacks = callback_factories($chart, $mw, $vars);

    my $frame = $parent->Frame(
        -background => '#f0f0f0',
        -relief     => 'groove',
        -bd         => 2,
    );
    my $inner = $frame->Frame(-background => '#f0f0f0')->pack(-padx => 4, -pady => 3);

    my $btn_opts = sub {
        my ($text, $cb) = @_;
        return $inner->Button(
            -text    => $text,
            -command => $cb,
            -relief  => 'flat',
            -padx    => 6,
            -pady    => 2,
            -background => '#f0f0f0',
            -activebackground => '#e0e0e0',
        );
    };

    # [Select bar v]  Play  Fwd >|  |< Back  1x  D  >>  ...  X  (task 0048: ASCII)
    my $sel_box = $inner->Frame(-background => '#f0f0f0')->pack(-side => 'left', -padx => 1);
    $btn_opts->('Select bar', $callbacks->{select_bar})->pack(-side => 'left', -in => $sel_box);
    $btn_opts->('v', $callbacks->{goto_menu})->pack(-side => 'left', -in => $sel_box);

    $btn_opts->('Play', $callbacks->{play})->pack(-side => 'left', -padx => 1);
    $btn_opts->('Fwd >|', $callbacks->{step_fwd})->pack(-side => 'left', -padx => 1);
    # Step back extra del proyecto (TV no lo tiene): |< Back junto a Fwd.
    $btn_opts->('|< Back', $callbacks->{step_back})->pack(-side => 'left', -padx => 1);

    my $speed_lbl = $btn_opts->('1x', $callbacks->{speed_menu});
    $speed_lbl->pack(-side => 'left', -padx => 1);
    my $interval_lbl = $btn_opts->('D', $callbacks->{interval_menu});
    $interval_lbl->pack(-side => 'left', -padx => 1);

    $btn_opts->('>>', $callbacks->{fast_fwd})->pack(-side => 'left', -padx => 1);

    $inner->Label(-text => '...', -background => '#f0f0f0')->pack(-side => 'left', -padx => 8);

    $btn_opts->('X', $callbacks->{exit})->pack(-side => 'left', -padx => 1);

    my $self = bless {
        frame        => $frame,
        parent       => $parent,
        callbacks    => $callbacks,
        speed_label  => $speed_lbl,
        interval_lbl => $interval_lbl,
        visible      => 0,
    }, $class;

    if (ref($vars) eq 'HASH' && $vars->{replay_panel}) {
        ${ $vars->{replay_panel} } = $self;
    }

    $self->hide();
    return $self;
}

# callback_factories — factorías del panel (testeable headless sin construir Tk).
sub callback_factories {
    my ($chart, $mw, $vars) = @_;
    die "callback_factories: requiere \$chart" unless $chart;
    return {
        select_bar    => Market::UI::Callbacks->make_replay_select_bar($chart, $vars),
        goto_menu     => Market::UI::Callbacks->make_replay_goto_menu_stub($chart, $vars),
        play          => Market::UI::Callbacks->make_replay_play($chart, $mw, $vars),
        step_fwd      => Market::UI::Callbacks->make_replay_step_fwd($chart),
        step_back     => Market::UI::Callbacks->make_replay_step_back($chart),
        speed_menu    => Market::UI::Callbacks->make_replay_speed_menu_stub($chart, $vars),
        interval_menu => Market::UI::Callbacks->make_replay_interval_menu_stub($chart, $vars),
        fast_fwd      => Market::UI::Callbacks->make_replay_fast_fwd($chart, $mw, $vars),
        exit          => Market::UI::Callbacks->make_replay_exit($chart, $vars),
    };
}

sub show {
    my ($self) = @_;
    $self->{frame}->place(-relx => 0.5, -rely => 1.0, -anchor => 's', -y => -8);
    $self->{visible} = 1;
    return $self;
}

sub hide {
    my ($self) = @_;
    $self->{frame}->placeForget();
    $self->{visible} = 0;
    return $self;
}

sub is_visible {
    my ($self) = @_;
    return $self->{visible} ? 1 : 0;
}

sub frame       { shift->{frame} }
sub callbacks   { shift->{callbacks} }

# expected_button_labels — textos ASCII de los botones (task 0048, para tests headless).
sub expected_button_labels {
    return (
        'Select bar', 'v', 'Play', 'Fwd >|', '|< Back',
        '1x', 'D', '>>', 'X',
    );
}

1;