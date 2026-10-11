#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 4;
use AnyEvent;

use GRNOC::RabbitMQ::Dispatcher;
use GRNOC::RabbitMQ::Method;
use GRNOC::RabbitMQ::Client;

# Regression test for a channel-only close (e.g. the broker sends
# channel.close because of a protocol exception, while the underlying
# connection survives). Before the fix, GRNOC::RabbitMQ::on_close_handler
# (the channel's on_close) never flipped 'connected' to false, so nothing
# -- Client::AUTOLOAD's auto_reconnect check included -- ever noticed the
# channel was dead, and the reply queue would accumulate messages forever.

my $dispatcher = GRNOC::RabbitMQ::Dispatcher->new(
    queue    => "Test11",
    exchange => "Test11",
    topic    => "Test11.Data",
    user     => "guest",
    pass     => "guest",
    port     => "5672"
);

my $method = GRNOC::RabbitMQ::Method->new(
    name        => "get",
    description => "get data from queue",
    callback    => sub { return { success => 1 }; },
);
$dispatcher->register_method($method);

my $client = GRNOC::RabbitMQ::Client->new(
    topic          => "Test11.Data",
    exchange       => "Test11",
    user           => "guest",
    pass           => "guest",
    auto_reconnect => 1,
);

ok($client->connected, "client is connected before the channel is closed");

# Force a channel-only close: redeclare the client's own exclusive reply
# queue with a mismatched 'durable' flag. The broker replies with 406
# PRECONDITION_FAILED and closes just that channel, leaving the underlying
# connection intact.
$client->channel->declare_queue(
    queue      => $client->queue,
    durable    => 1,
    exclusive  => 1,
    arguments  => $client->arguments,
    on_success => sub { },
    on_failure => sub { },
);

# Give the close frame time to propagate through the event loop.
my $closed_cv  = AnyEvent->condvar;
my $close_poll = AnyEvent->timer(
    after    => 0.1,
    interval => 0.1,
    cb       => sub { $closed_cv->send(1) if !$client->connected; },
);
my $close_timeout = AnyEvent->timer(
    after => 5,
    cb    => sub { $closed_cv->send(0); },
);
$closed_cv->recv();
undef $close_poll;
undef $close_timeout;

ok(!$client->connected, "client is marked disconnected after the channel closes");

# With auto_reconnect set, the next RPC call should transparently reconnect
# and succeed.
my $call_res;
$client->get(
    async_callback => sub {
        $call_res = shift;
        $dispatcher->stop_consuming();
    }
);

my $hang_guard = AnyEvent->timer(
    after => 10,
    cb    => sub { $dispatcher->stop_consuming() if $dispatcher->consuming; },
);
$dispatcher->start_consuming();
undef $hang_guard;

ok($client->connected, "client reconnected automatically after the channel closed");
ok(defined($call_res) && $call_res->{'results'}, "RPC succeeded after automatic reconnect");
