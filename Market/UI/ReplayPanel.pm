package Market::UI::ReplayPanel;
use strict;
use warnings;
use utf8;

use Market::UI::Callbacks;
use Market::UI::ReplayGotoMenu;
use Market::UI::ReplaySpeedMenu;
use Market::UI::ReplayIntervalMenu;

# Market::UI::ReplayPanel — barra Replay inline (tasks 0043/0045/0046-prep).
# Botones estilo reproductor multimedia: Canvas + hit-area Button (-command).

use constant {
    MEDIA_FACE        => '#ececec',
    MEDIA_FACE_ACTIVE => '#d4d4d4',
    MEDIA_ICON        => '#363a45',
    MEDIA_CANVAS_W    => 28,
    MEDIA_CANVAS_H    => 24,
};

sub _media_colors {
    return (MEDIA_FACE, MEDIA_FACE_ACTIVE, MEDIA_ICON);
}

# ReplayMediaWidget — envoltorio con configure(-text/-command) para dropdowns.
{
    package ReplayMediaWidget;
    sub new {
        my ($class, %args) = @_;
        return bless { %args }, $class;
    }
    sub configure {
        my ($self, %opts) = @_;
        if (exists $opts{-text} && $self->{label}) {
            $self->{label}->configure(-text => $opts{-text});
            $self->{_text} = $opts{-text};
        }
        if (exists $opts{-command} && $self->{hit}) {
            $self->{hit}->configure(-command => $opts{-command});
        }
        return $self;
    }
    sub pack {
        my $self = shift;
        return $self->{frame}->pack(@_);
    }
    sub exists {
        my ($self) = @_;
        return eval { $self->{frame}->exists } ? 1 : 0;
    }
}

sub _make_media_button {
    my ($parent, $cb, $draw, $text_label) = @_;
    my ($face, $face_active, $icon_color) = _media_colors();

    my $outer = $parent->Frame(
        -relief     => 'raised',
        -bd         => 2,
        -background => $face,
        -cursor     => 'hand2',
    );
    my $inner = $outer->Frame(-background => $face)->pack(-padx => 1, -pady => 1);

    my $lbl;
    if ($draw) {
        my $c = $inner->Canvas(
            -width             => MEDIA_CANVAS_W,
            -height            => MEDIA_CANVAS_H,
            -background         => $face,
            -highlightthickness => 0,
            -borderwidth        => 0,
        );
        $c->pack();
        $draw->($c, $icon_color);
    }
    elsif (defined $text_label) {
        $lbl = $inner->Label(
            -text       => $text_label,
            -background => $face,
            -foreground => MEDIA_ICON,
            -font       => 'Helvetica 9 bold',
            -width      => 3,
        );
        $lbl->pack(-padx => 4, -pady => 2);
    }

    my $hit = _media_hit_button($outer, $face, $face_active, $cb);
    return ReplayMediaWidget->new(
        frame => $outer,
        label => $lbl,
        hit   => $hit,
        _text => $text_label,
    );
}

sub _media_hit_button {
    my ($outer, $face, $face_active, $cb) = @_;
    my $cmd = ref($cb) eq 'CODE' ? $cb : sub { };
    my $hit = $outer->Button(
        -text               => '',
        -command            => $cmd,
        -background         => $face,
        -activebackground   => $face_active,
        -relief             => 'flat',
        -borderwidth        => 0,
        -highlightthickness => 0,
        -cursor             => 'hand2',
    );
    $hit->place(-relx => 0, -rely => 0, -relwidth => 1, -relheight => 1);
    $hit->bind('<ButtonPress-1>', sub { $outer->configure(-relief => 'sunken') });
    $hit->bind('<ButtonRelease-1>', sub { $outer->configure(-relief => 'raised') });
    return $hit;
}

sub _draw_play {
    my ($c, $color) = @_;
    $c->createPolygon(9, 6, 9, 18, 21, 12, -fill => $color, -outline => $color, -tags => 'icon');
}

sub _draw_step_back {
    my ($c, $color) = @_;
    $c->createRectangle(7, 7, 9, 17, -fill => $color, -outline => $color, -tags => 'icon');
    $c->createPolygon(18, 12, 11, 6, 11, 18, -fill => $color, -outline => $color, -tags => 'icon');
}

sub _draw_step_fwd {
    my ($c, $color) = @_;
    $c->createPolygon(10, 6, 10, 18, 17, 12, -fill => $color, -outline => $color, -tags => 'icon');
    $c->createRectangle(18, 7, 20, 17, -fill => $color, -outline => $color, -tags => 'icon');
}

sub _draw_goto_chevron {
    my ($c, $color) = @_;
    $c->createPolygon(8, 9, 14, 17, 20, 9, -fill => $color, -outline => $color, -tags => 'icon');
}

sub _draw_select_bar {
    my ($c, $color) = @_;
    $c->createRectangle(12, 5, 16, 19, -fill => $color, -outline => $color, -tags => 'icon');
    $c->createRectangle(8, 11, 20, 13, -fill => $color, -outline => $color, -tags => 'icon');
}

sub _draw_jump {
    my ($c, $color) = @_;
    $c->createPolygon(5, 6, 5, 18, 11, 12, -fill => $color, -outline => $color, -tags => 'icon');
    $c->createPolygon(13, 6, 13, 18, 19, 12, -fill => $color, -outline => $color, -tags => 'icon');
    $c->createRectangle(21, 7, 23, 17, -fill => $color, -outline => $color, -tags => 'icon');
}

sub _draw_exit {
    my ($c, $color) = @_;
    $c->createLine(8, 6, 20, 18, -fill => $color, -width => 2, -tags => 'icon');
    $c->createLine(20, 6, 8, 18, -fill => $color, -width => 2, -tags => 'icon');
}

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

    my $pack_btn = sub {
        my ($widget, %pack) = @_;
        $pack{-side}  //= 'left';
        $pack{-padx}  //= 2;
        $widget->{frame}->pack(%pack);
        return $widget;
    };

    my $sel_box = $inner->Frame(-background => $bg)->pack(-side => 'left', -padx => 1);
    $pack_btn->(
        _make_media_button($sel_box, $callbacks->{select_bar}, \&_draw_select_bar),
        -in => $sel_box,
    );

    my $goto_menu = Market::UI::ReplayGotoMenu->new(
        parent  => $menu_parent,
        root    => $root,
        chart   => $chart,
        mw      => $mw,
        ui_vars => $vars,
    );
    my $goto_btn = _make_media_button($sel_box, sub { }, \&_draw_goto_chevron);
    $pack_btn->($goto_btn, -in => $sel_box);
    $goto_menu->set_anchor($goto_btn->{frame});

    $pack_btn->(_make_media_button($inner, $callbacks->{step_back}, \&_draw_step_back));
    $pack_btn->(_make_media_button($inner, $callbacks->{play}, \&_draw_play));
    $pack_btn->(_make_media_button($inner, $callbacks->{step_fwd}, \&_draw_step_fwd));

    my $speed_btn = _make_media_text_button($inner, '1x', sub { });
    $pack_btn->($speed_btn);
    my $speed_menu = Market::UI::ReplaySpeedMenu->new(
        parent    => $menu_parent,
        root      => $root,
        chart     => $chart,
        panel_btn => $speed_btn,
        ui_vars   => $vars,
    );

    my $interval_btn = _make_media_text_button($inner, 'D', sub { });
    $pack_btn->($interval_btn);
    my $interval_menu = Market::UI::ReplayIntervalMenu->new(
        parent    => $menu_parent,
        root      => $root,
        chart     => $chart,
        panel_btn => $interval_btn,
        ui_vars   => $vars,
    );

    my $toggle_menu = sub {
        my ($menu, $btn) = @_;
        for my $other (
            grep { $_ && $_ != $menu }
            ($goto_menu, $speed_menu, $interval_menu)
        ) {
            $other->hide() if $other->can('hide');
        }
        $menu->toggle($btn->{frame});
    };
    $goto_btn->configure(-command => sub { $toggle_menu->($goto_menu, $goto_btn) });
    $speed_btn->configure(-command => sub { $toggle_menu->($speed_menu, $speed_btn) });
    $interval_btn->configure(-command => sub { $toggle_menu->($interval_menu, $interval_btn) });

    $pack_btn->(_make_media_button($inner, $callbacks->{fast_fwd}, \&_draw_jump));
    $pack_btn->(_make_media_button($inner, $callbacks->{exit}, \&_draw_exit), -padx => 4);

    my $self = bless {
        frame          => $frame,
        parent         => $parent,
        callbacks      => $callbacks,
        goto_menu      => $goto_menu,
        speed_menu     => $speed_menu,
        interval_menu  => $interval_menu,
        speed_label    => $speed_btn,
        interval_lbl   => $interval_btn,
        play_btn       => 1,
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

sub _make_media_text_button {
    my ($parent, $text, $cb) = @_;
    return _make_media_button($parent, $cb, undef, $text);
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

sub expected_text_button_labels {
    return ('1x', 'D');
}

sub expected_media_icon_count {
    return 7;
}

sub has_play_icon_button {
    return 1;
}

1;