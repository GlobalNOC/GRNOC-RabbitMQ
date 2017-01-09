#!/usr/bin/perl

use Test::More tests => 4;

BEGIN {
        use_ok( 'GRNOC::RabbitMQ' );
        use_ok( 'GRNOC::RabbitMQ::Client' );
        use_ok( 'GRNOC::RabbitMQ::Dispatcher' );
        use_ok( 'GRNOC::RabbitMQ::Method');
}
