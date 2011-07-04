#!/usr/bin/perl
use strict;
use warnings;

package SkypeLog2HTML;
use Class::Accessor::Lite (
    new => 1,
    rw  => [qw/user_id1 user_id2 user_name1 user_name2 user_name_pair dbfile view_type text_back_color all_messages daily_log dbh/],
);
use DBIx::Simple;
use Pod::Usage qw/pod2usage/;
use Time::Piece;

sub init {
    my ($self, $args) = @_;
    my ($user_id1, $user_id2, $user_name1, $user_name2, $dbfile, $view_type) = @$args{qw/user_id1 user_id2 user_name1 user_name2 dbfile view_type/};
    $user_name1 ||= $user_id1;
    $user_name2 ||= $user_id2;
    $dbfile ||= "main.db";
    $view_type ||= "pc";
    (($user_id1 && $user_id2) and (-f $dbfile))
        or pod2usage;
    $self->user_id1($user_id1);
    $self->user_id2($user_id2);
    $self->user_name1($user_name1);
    $self->user_name2($user_name2);
    $self->user_name_pair(+{
        $user_id1 => $user_name1,
        $user_id2 => $user_name2,
    });
    $self->dbfile($dbfile);
    $self->view_type($view_type);
    $self->text_back_color(+{
        $self->user_id1 => "userColor1",
        $self->user_id2 => "userColor2",
    });
    $self->daily_log(+{});
    my $query = sprintf 'dbi:SQLite:dbname=%s', $self->dbfile;
    my $dbh = DBIx::Simple->connect($query) || die DBIx::Simple->error;
    $self->dbh($dbh);
    return $self;
}
sub run {
    my ($self, ) = @_;

    $self->get_all_messages;
    $self->divide_messages_daily;
    $self->generate_daily;
    $self->generate_index;
    $self->dbh->disconnect;
}
sub get_all_messages {
    my ($self, ) = @_;

    my $query = sprintf
        'SELECT timestamp, author, body_xml FROM Messages WHERE chatname LIKE "#%s/$%s;%%" OR chatname LIKE "#%s/$%s;%%" ORDER BY id ASC',
        $self->user_id1, $self->user_id2, $self->user_id2, $self->user_id1;
    my $result = $self->dbh->query($query);
    $self->all_messages($result);
}
sub divide_messages_daily {
    my ($self, ) = @_;

    my %daily_log;
    my ($before_author, $before_ymd) = ("", "");
    while (my $row = $self->all_messages->hash) {
        $row->{body_xml} or next;
        my $tp = Time::Piece->new($row->{timestamp});
        my $hms = $tp->hms;
        my $ymd_hms = join " ", $tp->ymd("/"), $tp->hms;
        my $ymd = $tp->ymd('_');
        $daily_log{$ymd}->{body} ||= [];
        $row->{body_xml} =~ s{\n}{<br />}g;
        my ($author, $body_xml) = ($row->{author}, $row->{body_xml});
        my $print_author = (($author eq $before_author) and ($ymd eq $before_ymd)) ? '&nbsp;' : $author;
        if (($print_author ne '&nbsp;') and ($self->view_type eq "sp")) {
            $print_author = $self->user_name_pair->{$print_author};
        }
        my $hr_or_blank = (($author eq $before_author) and ($before_ymd eq $ymd) ) ? "" : "<hr />";
        ($before_author, $before_ymd) = ($author, $ymd);
        my $color_class = $self->text_back_color->{$row->{author}};

        my $body_row;
        if ($self->view_type eq "pc") {
            $body_row = sprintf
                '<div class="%s"><div class="main_l1">%s</div><div class="main_l2">%s</div><div class="main_l3">%s</div></div>%s',
                $color_class, $ymd_hms, $print_author, $body_xml, "\n";
        }
        elsif ($self->view_type eq "sp") {
            $body_row = sprintf q{
        %s
        <div class="messageBox">
            <div class="messageHeader">
                <span class="skypeName">%s</span>
                <span class="messageDate">%s</span>
            </div>
            <br />
            <div class="messageBody %s">
                %s
            </div>
        </div>},
                $hr_or_blank, $print_author, $hms, $color_class, $body_xml;
        }
        push @{$daily_log{$ymd}->{body}}, $body_row;
    }
    $self->daily_log(\%daily_log);
}
sub index_template {
    my ($self, ) = @_;
    my $template = <<_TEMPLATE;
<html>
<head>
<title>skype log</title>
</head>
<body>
%s
</body>
</html>
_TEMPLATE
    return $template;
}
sub generate_index {
    my ($self, ) = @_;

    my @log_ymds = reverse sort keys %{$self->daily_log};
    my @log_index;
    my ($_y, $_m) = (0, 0);
    for my $ymd (@log_ymds) {
        $ymd =~ /^(\d{4})_(\d{2})/;
        $_y ||= $1;
        $_m ||= $2;
        unless (($_y == $1) and ($_m == $2)) {
            push @log_index, qq{<hr />\n};
        }
        ($_y, $_m) = ($1, $2);
        my $line_number = @{$self->daily_log->{$ymd}->{body}};
        push @log_index, qq{<a href="$ymd.html" target="_blank">$ymd</a> (line: $line_number)<br />\n};
    }

    my $html = sprintf $self->index_template, join "", @log_index;
    open my $fh, ">", "index.html";
    print $fh $html;
    close $fh;
}

sub daily_html1_pc {
    my ($self, $args) = @_;
    my ($ymd, $prev) = @$args{qw/ymd prev/};

    my $html = <<_HTML;
<html>
<head>
<title>$ymd</title>
<style type="text/css">
<!--
.main_l1 {
    float: left;
    width: 190px;
}
.main_l2 {
    float:  left;
    width:  75px;
}
.main_l3 {
    overflow: hidden;
}
.head1 {
    background-color: #99F;
    text-align: center;
}
.head2 {
    background-color: #9CC;
    text-align: center;
}
.head3 {
    background-color: tan;
    text-align: center;
}
.@{[$self->text_back_color->{$self->user_id1}]} {
    background-color: lightsteelblue;
}
.@{[$self->text_back_color->{$self->user_id2}]} {
    background-color: thistle;
}
-->
</style>
</head>
<body>
<div class="autopagerize_page_element">
<a href="$prev.html">$prev</a> $ymd
<p><p/>
<div class="main">
<div><div class="main_l1 head1">time</div><div class="main_l2 head2">From</div><div class="main_l3 head3">Body_xml</div></div>
_HTML
    return $html;
}
sub daily_html2_pc {
    my ($self, $args) = @_;
    my ($ymd, $next) = @$args{qw/ymd next/};

    my $html = <<_HTML;
</div>
<p><p/>
$ymd <a href="$next.html" rel="next">$next</a>
</div>
<div class="autopagerize_insert_before"></div>
</body>
</html>
_HTML
    return $html;
}
sub daily_html1_sp {
    my ($self, $args) = @_;
    my ($ymd, $prev, $next) = @$args{qw/ymd prev next/};

    my $html = <<_HTML;
<!DOCTYPE html>
<html lang="ja">
    <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, user-scalable=no, initial-scale=1.0, minimum-scale=1.0, maximum-scale=1.0">
        <meta name="format-detection" content="telephone=no,email=no" />
        <title>$ymd</title>
        <style type="text/css">
            <!--
            * {
                margin: 0;
                padding: 0;
            }
            header {
                margin: 10px;
            }
            footer {
                margin: 10px;
            }
            .messageHeader {
                margin: 5px 1px 6px 2px;
            }
            .skypeName {
                font-weight: bold;
                float: left;
            }
            .messageBox {
                margin: 0px 5px;
            }
            .messageDate {
                float: right;
                color: #9B9B9B;
            }
            .messageBody {
                margin: 5px 0px;
                clear: both;
            }
            .dateBox {
                text-align: center;
                font-size: 120%;
                font-weight: bold;
            }
            .prevDate {
                float: left;
            }
            .nextDate {
                float: right;
            }
            .indexLink {
                text-align: center;
            }
            .@{[$self->text_back_color->{$self->user_id1}]} {
                background-color: lightsteelblue;
             }
            .@{[$self->text_back_color->{$self->user_id2}]} {
                background-color: thistle;
             }
        </style>
    </head>
    <body>
        <header id="header">
            <div class="dateBox">
                <span class="prevDate"><a href="$prev.html">$prev</a></span>
                <span class="indexLink"><a href="index.html">index</a></span>
                <span class="nextDate"><a href="$next.html">$next</a></span>
            </div>
        </header>
_HTML
    return $html;
}
sub daily_html2_sp {
    my ($self, $args) = @_;
    my ($prev, $next) = @$args{qw/prev next/};

    my $html = <<_HTML;

        <hr />
        <footer id="footer">
            <div class="dateBox">
                <span class="prevDate"><a href="$prev.html">$prev</a></span>
                <span class="indexLink"><a href="index.html">index</a></span>
                <span class="nextDate"><a href="$next.html">$next</a></span>
            </div>
        </footer>
    </body>
</html>
_HTML
    return $html;
}

sub generate_daily {
    my ($self, ) = @_;

    my $i = 0;
    my @log_ymds = reverse sort keys %{$self->daily_log};

    for my $ymd (@log_ymds) {
        my $next = $log_ymds[$i - 1];
        my $prev = ($log_ymds[$i + 1] || $log_ymds[0]);

        my $html1 = $self->view_type eq "pc" ? $self->daily_html1_pc({ymd => $ymd, prev => $prev}) :
                    $self->view_type eq "sp" ? $self->daily_html1_sp({ymd => $ymd, prev => $prev, next => $next}) : die "no match view_type";
        unshift @{$self->daily_log->{$ymd}->{body}}, $html1;

        my $html2 = $self->view_type eq "pc" ? $self->daily_html2_pc({ymd => $ymd, next => $next}) :
                    $self->view_type eq "sp" ? $self->daily_html2_sp({ymd => $ymd, prev => $prev, next => $next}) : die "no match view_type";
        push @{$self->daily_log->{$ymd}->{body}}, $html2;

        open my $fh, ">", "$ymd.html";
        print $fh @{$self->daily_log->{$ymd}->{body}};
        close $fh;
        $i++;
    }
}

package main;
use Getopt::Long qw/GetOptions/;

my %args;
GetOptions(\%args, qw/user_id1=s user_id2=s user_name1=s user_name2=s dbfile=s view_type=s/);
SkypeLog2HTML->new->init(\%args)->run;

__END__

=head1 NAME

skypelog2html.pl - convert skype log to html from sqlite

=head1 SYNOPSIS

  # basic
  % skypelog2html.pl -user_id1 user_id1 -user_id2 user_id2

  # optional
  % skypelog2html.pl -user_id1 user_id1 -user_id2 user_id2 \
        -user_name1 show_user_name1 -user_name2 show_user_name2 -dbfile skype_logfile (-view_type [pc|sp])";

=head1 ARGUMENTS

=over 4

=item -user_id1, -user_id2

skype id

=back

=head1 OPTIONS

=over 4

=item -dbfile

  target skype log file. default is "main.db".

=item -view_type

  generate html type. can set "pc" or "sp". default is "pc".
  "sp" means "smart phone", not "special" :)

=item -user_name1, -user_name2

  this affect only when set view_type "sp".

=back

=cut
