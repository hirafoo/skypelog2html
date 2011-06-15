#!/usr/bin/perl
use strict;
use warnings;

package SkypeLog2HTML;
use Class::Accessor::Lite (
    new => 1,
    rw  => [qw/user1 user2 dbfile text_back_color all_messages daily_log dbh/],
);
use DBIx::Simple;
use Time::Piece;

sub init {
    my ($self, @args) = @_;
    my ($user1, $user2, $dbfile) = @args;
    $dbfile ||= "main.db";
    (($user1 && $user2) and (-f $dbfile)) or do {
        die "usage: perl $0 user_id1 user_id2 (skype_logfile)\n";
    };
    $self->user1($user1);
    $self->user2($user2);
    $self->dbfile($dbfile);
    $self->text_back_color(+{
        $self->user1 => "userColor1",
        $self->user2 => "userColor2",
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
    $self->generate_index;
    $self->generate_daily;
    $self->dbh->disconnect;
}
sub get_all_messages {
    my ($self, ) = @_;

    my $query = sprintf
        'SELECT timestamp, author, body_xml FROM Messages WHERE chatname LIKE "#%s/$%s;%%" OR chatname LIKE "#%s/$%s;%%" ORDER BY id ASC',
        $self->user1, $self->user2, $self->user2, $self->user1;
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
        my $ymd_hms = join " ", $tp->ymd("/"), $tp->hms;
        my $ymd = $tp->ymd('_');
        $daily_log{$ymd}->{body} ||= [];
        $row->{body_xml} =~ s{\n}{<br />}g;
        my ($author, $body_xml) = ($row->{author}, $row->{body_xml});
        my $print_author = (($author eq $before_author) and ($ymd eq $before_ymd)) ? '&nbsp;' : $author;
        ($before_author, $before_ymd) = ($author, $ymd);
        my $color_class = $self->text_back_color->{$row->{author}};

        my $body_row = sprintf
            '<div class="%s"><div class="main_l1">%s</div><div class="main_l2">%s</div><div class="main_l3">%s</div></div>%s',
            $color_class, $ymd_hms, $print_author, $body_xml, "\n";
        push @{$daily_log{$ymd}->{body}}, $body_row;
    }
    $self->daily_log(\%daily_log);
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

    my $html = sprintf <<_STR, join "", @log_index;
<html>
<head>
<title>skype log</title>
</head>
<body>
%s
</body>
</html>
_STR

    open my $fh, ">", "index.html";
    print $fh $html;
    close $fh;
}

sub generate_daily {
    my ($self, ) = @_;

    my $i = 0;
    my @log_ymds = reverse sort keys %{$self->daily_log};

    for my $ymd (@log_ymds) {
        my $next = $log_ymds[$i - 1];
        my $prev = ($log_ymds[$i + 1] || $log_ymds[0]);

        my $html1 = <<_STR;
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
.@{[$self->text_back_color->{$self->user1}]} {
    background-color: lightsteelblue;
}
.@{[$self->text_back_color->{$self->user2}]} {
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
_STR

        unshift @{$self->daily_log->{$ymd}->{body}}, $html1;

        my $html2 = <<_STR;
</div>
<p><p/>
$ymd <a href="$next.html" rel="next">$next</a>
</div>
<div class="autopagerize_insert_before"></div>
</body>
</html>
_STR

        push @{$self->daily_log->{$ymd}->{body}}, $html2;

        open my $fh, ">", "$ymd.html";
        print $fh @{$self->daily_log->{$ymd}->{body}};
        close $fh;
        $i++;
    }
}

package main;
SkypeLog2HTML->new->init(@ARGV)->run;
