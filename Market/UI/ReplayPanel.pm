package Market::UI::ReplayPanel;
use strict;
use warnings;
use utf8;

use Market::UI::Callbacks;
use Market::UI::ReplayGotoMenu;
use Market::UI::ReplaySpeedMenu;
use Market::UI::ReplayIntervalMenu;

# Market::UI::ReplayPanel — barra de controles Replay (task 0043/0045).
# Modo inline: empaquetada en la pestaña Replay de market.pl (sin place flotante).
# Etiquetas ASCII estilo control remoto (task 0048).

sub _panel_background {
    my ($widget) = @_;
    return '#f0f0f0' unless $widget && eval { $widget->exists };
    my $bg = eval { $widget->cget('-background') };
    return '#f0f0f0' unless defined $bg && length $bg;
    return '#f0f0f0' if ref($bg) || $bg =~ /^Tk::/ || $bg =~ /^\./;
    return $bg;
}

sub new {
    my ($class, %args) = @_;
    my $parent = $args{parent} or die "ReplayPanel: requiere parent";
    my $chart  = $args{chart}  or die "ReplayPanel: requiere chart";
    my $vars   = $args{ui_vars} || {};
    my $mw     = $args{mw};
    my $root   = $args{root} || $mw || $parent;
    my $inline = $args{inline} ? 1 : 0;
    my $menu_parent = $args{menu_parent} || $root;

    my $callbacks = callback_factories($chart, $mw, $vars);

    my $bg = $inline ? _panel_background($parent) : '#f0f0f0';
    my $frame = $parent->Frame(
        -background => $bg,
        -relief     => $inline ? 'flat' : 'groove',
        -bd         => $inline ? 0 : 2,
    );
    my $inner = $frame->Frame(-background => $bg)->pack(-side => 'left', -padx => 2, -pady => 1);

    my $btn_opts = sub {
        my ($text, $cb) = @_;
        return $inner->Button(
            -text             => $text,
            -command          => $cb,
            -relief           => 'flat',
            -padx             => 6,
            -pady             => 2,
            -background       => $bg,
            -activebackground => '#e0e0e0',
        );
    };

    # Select bar + Go-to |  |<  >  >|  1x  D  >>  X
    my $sel_box = $inner->Frame(-background => $bg)->pack(-side => 'left', -padx => 1);
    $btn_opts->('Select bar', $callbacks->{select_bar})->pack(-side => 'left', -in => $sel_box);

    my $goto_menu = Market::UI::ReplayGotoMenu->new(
        parent  => $menu_parent,
        root    => $root,
        chart   => $chart,
        mw      => $mw,
        ui_vars => $vars,
    );
    my $goto_btn;
    $goto_btn = $btn_opts->('v', sub { })->pack(-side => 'left', -in => $sel_box);
    $goto_menu->set_anchor($goto_btn);

    $btn_opts->('|<', $callbacks->{step_back})->pack(-side => 'left', -padx => 1);
    $btn_opts->('>', $callbacks->{play})->pack(-side => 'left', -padx => 1);
    $btn_opts->('>|', $callbacks->{step_fwd})->pack(-side => 'left', -padx => 1);

    my $speed_btn = $btn_opts->('1x', sub { });
    $speed_btn->pack(-side => 'left', -padx => 1);
    my $speed_menu = Market::UI::ReplaySpeedMenu->new(
        parent    => $menu_parent,
        root      => $root,
        chart     => $chart,
        panel_btn => $speed_btn,
        ui_vars   => $vars,
    );
    $speed_btn->configure(-command => sub { });

    my $interval_btn = $btn_opts->('D', sub { });
    $interval_btn->pack(-side => 'left', -padx => 1);
    my $interval_menu = Market::UI::ReplayIntervalMenu->new(
        parent    => $menu_parent,
        root      => $root,
        chart     => $chart,
        panel_btn => $interval_btn,
        ui_vars   => $vars,
    );
    $interval_btn->configure(-command => sub { });

    my $toggle_menu = sub {
        my ($menu, $btn) = @_;
        for my $other (
            grep { $_ && $_ != $menu }
            ($goto_menu, $speed_menu, $interval_menu)
        ) {
            $other->hide() if $other->can('hide');
        }
        $menu->toggle($btn);
    };
    $goto_btn->configure(-command => sub { $toggle_menu->($goto_menu, $goto_btn) });
    $speed_btn->configure(-command => sub { $toggle_menu->($speed_menu, $speed_btn) });
    $interval_btn->configure(-command => sub { $toggle_menu->($interval_menu, $interval_btn) });

    $btn_opts->('>>', $callbacks->{fast_fwd})->pack(-side => 'left', -padx => 1);
    $btn_opts->('X', $callbacks->{exit})->pack(-side => 'left', -padx => 4);

    my $self = bless {
        frame          => $frame,
        parent         => $parent,
        callbacks      => $callbacks,
        goto_menu      => $goto_menu,
        speed_menu     => $speed_menu,
        interval_menu  => $interval_menu,
        speed_label    => $speed_btn,
        interval_lbl   => $interval_btn,
        inline         => $inline,
        visible        => $inline ? 1 : 0,
    }, $class;

    if (ref($vars) eq 'HASH' && $vars->{replay_panel}) {
        ${ $vars->{replay_panel} } = $self;
    }

    if ($inline) {
        $frame->pack(-side => 'left', -fill => 'x');
    } else {
        $self->hide();
    }

    return $self;
}

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

sub is_inline {
    my ($self) = @_;
    return $self->{inline} ? 1 : 0;
}

sub replay_menus {
    my ($self) = @_;
    return grep { $_ } (
        $self->{goto_menu},
        $self->{speed_menu},
        $self->{interval_menu},
    );
}

sub hide_menus {
    my ($self) = @_;
    for my $menu ($self->replay_menus()) {
        $menu->hide() if $menu->can('hide');
    }
    return $self;
}

sub show {
    my ($self) = @_;
    return $self if $self->{inline};
    $self->{frame}->place(-relx => 0.5, -rely => 1.0, -anchor => 's', -y => -8);
    $self->{visible} = 1;
    return $self;
}

sub hide {
    my ($self) = @_;
    $self->hide_menus();
    return $self if $self->{inline};
    $self->{frame}->placeForget();
    $self->{visible} = 0;
    return $self;
}

sub is_visible {
    my ($self) = @_;
    return 1 if $self->{inline};
    return $self->{visible} ? 1 : 0;
}

sub frame     { shift->{frame} }
sub callbacks { shift->{callbacks} }

sub expected_button_labels {
    return (
        'Select bar', 'v', '|<', '>', '>|',
        '1x', 'D', '>>', 'X',
    );
}

1;