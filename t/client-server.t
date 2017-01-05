#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 6;
use Cwd;
use Proc::Daemon;
use AnyEvent;

use GRNOC::RabbitMQ::Client;

my $daemon = Proc::Daemon->new(
    work_dir => getcwd() . "/t",
    exec_command => 'perl -Mlib=../blib/lib/ listener.pl'
    );
my $pid = $daemon->Init();

sleep(5);

my $client = GRNOC::RabbitMQ::Client->new(
    topic => "Test.Data",
    exchange => "Test",
    user => "guest",
    pass => "guest"
    );

my $cv = AnyEvent->condvar();
$client->get(async_callback => sub {
    my $res = shift;
    ok(($res->{'results'}->{'success'}), "client can talk to dispatcher asynchronously");
    $cv->send();
	     });
$cv->recv();

my $res = $client->get();
ok(($res->{'results'}->{'success'}), "client can talk to dispatcher synchronously");

$res = $client->help();
ok((scalar @{$res->{'results'}} == 3), "confirm three registered methods");
ok((grep {$_ eq "Test.Data.help"} @{$res->{'results'}}), "help is a method");
ok((grep {$_ eq "Test.Data.get"} @{$res->{'results'}}), "get is a method");
ok((grep {$_ eq "Test.Data.plus"} @{$res->{'results'}}), "plus is a method");

$daemon->Kill_Daemon($pid);
