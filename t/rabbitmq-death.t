#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;
use Test::More tests => 2;
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
    pass => "guest",
    auto_reconnect => 1
    );

system("/sbin/service rabbitmq-server stop");

my $res = undef;
eval {
    $res = $client->get();
};
ok(defined $res, "Response was defined");
ok(defined $res->{'error'}, "Error message was defined");

# TODO Create a dying Client
# ok($@, "fatal error for dead Rabbit");

$daemon->Kill_Daemon($pid);
system("/sbin/service rabbitmq-server start");
