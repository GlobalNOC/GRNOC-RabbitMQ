#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 1;
use Cwd;
use Proc::Daemon;
use AnyEvent;

use GRNOC::RabbitMQ::Client;

my $daemon = Proc::Daemon->new(
    work_dir => getcwd(),
    exec_command => 'perl listener.pl'
    );
my $pid = $daemon->Init();

sleep(5);

my $client = GRNOC::RabbitMQ::Client->new(
    topic => "Test.Data",
    exchange => "Test",
    user => "guest",
    pass => "guest"
    );

system("/sbin/service rabbitmq-server stop");

eval {
    my $res = $client->get();
};
ok($@, "fatal error for dead Rabbit");

$daemon->Kill_Daemon($pid);
system("/sbin/service rabbitmq-server start");
