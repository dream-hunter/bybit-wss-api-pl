#!/usr/bin/env perl

use strict;
use IO::Async::Loop;
use Net::Async::WebSocket::Client;
use IO::Async::Timer::Periodic;
use JSON;
use POSIX;
use Data::Dumper;
use Digest::SHA qw(hmac_sha512_hex sha512_hex hmac_sha256_hex sha256_hex);

use feature qw( switch );
no warnings qw( experimental::smartmatch );

my $host = "stream.bybit.com";
my $port = "443";
my $heartbeat_interval = 60;
my $heartbeat;
my $api_key    = $ARGV[0];
my $api_secret = $ARGV[1];
#################################
# Async Web Socket Client handler
#################################
while (1) {
    my $timer  = undef;
    my $pinger = undef;
    my $req_id = {
        'pub'  => 0,
        'prv'  => 0
    };
    my $client = {
        'pub'  => 0,
        'prv'  => 0
    };
    my $loop   = undef;
    $heartbeat = {
        'pub' => time+$heartbeat_interval,
        'prv' => time+$heartbeat_interval
    };
    $timer = IO::Async::Timer::Periodic->new(
        interval=> 10,
        on_tick => sub {
# Heartbeat
            $heartbeat->{'err'} = undef;
            if ($heartbeat->{'pub'} < time) {
                printf ("%s Public Heartbeat error %s < %s\n", strftime("%Y-%m-%d %H:%M:%S ", localtime), $heartbeat->{'pub'}, time) ;
                $heartbeat->{'err'} = 1;
            } else {
                printf ("%s Public Heartbeat is fine %s > %s\n", strftime("%Y-%m-%d %H:%M:%S ", localtime), $heartbeat->{'pub'}, time) ;
            }
            if (defined $api_key && defined $api_secret && $heartbeat->{'prv'} < time) {
                printf ("%s Private Heartbeat error %s < %s\n", strftime("%Y-%m-%d %H:%M:%S ", localtime), $heartbeat->{'prv'}, time) ;
                $heartbeat->{'err'} = 1;
            } else {
                printf ("%s Private Heartbeat is fine %s > %s\n", strftime("%Y-%m-%d %H:%M:%S ", localtime), $heartbeat->{'prv'}, time) ;
            }
            if (defined $heartbeat->{'err'} && $heartbeat->{'err'} == 1) {
                printf ("%s Close connection...\n", strftime("%Y-%m-%d %H:%M:%S ", localtime));
                $client->{'pub'}->close_now;
                $client->{'prv'}->close_now;
                $timer->stop;
                $pinger->stop;
                $loop->loop_stop;
            }
# Heartbeat is fine so you can handle streams data, send REST API requests, analyse and perform trading
        }
    );

    $pinger = IO::Async::Timer::Periodic->new(
        interval=> 20,
        on_tick => sub {
            foreach my $key ( keys %{ $client } ) {
                $req_id->{$key} ++;
                my $req_json = {
                    "req_id" => $req_id->{$key},
                    "op"     => "ping"
                };
                my $req = encode_json($req_json);
                printf ("%s Sending ping msg: %s\n", strftime("%Y-%m-%d %H:%M:%S ",localtime), $req) ;
                $client->{$key}->send_text_frame($req);
            }
        }
    );

    $client->{'pub'} = Net::Async::WebSocket::Client->new(
        on_text_frame => sub {
            my $data_pub = dataHandler(@_);
            if (defined $data_pub && defined $data_pub->{'op'} && $data_pub->{'op'} eq "ping" && $data_pub->{'success'}) {
                $heartbeat->{'pub'} = time+$heartbeat_interval;
            }
# Here you can put any stuff, include subs, analyse etc
        }
    );

    $client->{'prv'} = Net::Async::WebSocket::Client->new(
        on_text_frame => sub {
            my $data_prv = dataHandler(@_);
            if (defined $data_prv && defined $data_prv->{'op'} && $data_prv->{'op'} eq "pong") {
                $heartbeat->{'prv'} = time+$heartbeat_interval;
            }
# Here you can put any stuff, include subs, analyse etc
        }
    );

    $loop = IO::Async::Loop->new;

    $timer->start;
    $loop->add( $timer );

    $pinger->start;
    $loop->add( $pinger );

    $loop->add( $client->{'pub'} );
    $client->{'pub'}->connect(
       host => $host,
       service => $port,
       url => "wss://$host:$port/v5/public/spot",
    )->get;
    if (defined $api_key && defined $api_secret) {
        $loop->add( $client->{'prv'} );
        $client->{'prv'}->connect(
           host => $host,
           service => $port,
           url => "wss://$host:$port/v5/private",
        )->get;
    }
    printf ("%s Connected, go ahead...\n", strftime("%Y-%m-%d %H:%M:%S ", localtime));
#################################
# Public subscription
#################################
    $req_id->{'pub'} ++;
    my $datasend = {
        "req_id" => $req_id->{'pub'},
        "op" => "subscribe",
        "args" => [
#            "tickers.BTCUSDT",
#            "tickers.ADAUSDT"
            "publicTrade.ADAUSDT"
        ]
    };
    $client->{'pub'}->send_text_frame( encode_json($datasend) );
#################################
# Private subscription
#################################
    if (defined $api_key && defined $api_secret) {
        printf ("%s API Key/Secret defined. Attempting to send private request...\n", strftime("%Y-%m-%d %H:%M:%S ", localtime));
# auth
        $req_id->{'prv'} ++;
        my $expires = (time + 3) * 1000;
        my $signature = hmac_sha256_hex("GET/realtime$expires", $api_secret);
        my $datasend = {
            'req_id' => $req_id->{'prv'},
            'op' => 'auth',
            'args' => [
                "$api_key",
                $expires,
                "$signature"
            ]
        };
#        print encode_json($datasend) . "\n";
        $client->{'prv'}->send_text_frame(encode_json($datasend));
# Request
        $req_id->{'prv'} ++;
        my $datasend = {
            "req_id" => $req_id->{'prv'},
            "op" => "subscribe",
            "args" => [
                "wallet"
            ]
        };
        $client->{'prv'}->send_text_frame(encode_json($datasend));
    } else {
        printf ("%s API Key/Secret not defined.\n", strftime("%Y-%m-%d %H:%M:%S ", localtime));
    }
#################################
# Start main loop
#################################
    $loop->run;
#################################
# Wait and Restart
#################################
    sleep 10;
    printf ("%s Start again\n", strftime("%Y-%m-%d %H:%M:%S ", localtime));
}
#################################
# Subroutines
#################################
sub dataHandler {
    my ( $self, $frame ) = @_;
    my $decoded = decode_json($frame);
    if (defined $decoded->{'topic'}) {
        given($decoded->{'topic'}) {
            when(/^tickers/) {
                printf ("%s %s %s %s\n",
                    strftime("%Y-%m-%d %H:%M:%S", localtime),
                    $decoded->{'data'}->{'symbol'},
                    $decoded->{'data'}->{'lastPrice'},
                    $decoded->{'data'}->{'highPrice24h'},
                    $decoded->{'data'}->{'lowPrice24h'},
                );
            }
            when(/^publicTrade/) {
                printf ("%s\n", strftime("%Y-%m-%d %H:%M:%S", localtime));
                foreach my $data ( @{ $decoded->{'data'} } ) {
                    printf ("\t %s %s %s %s\n",
                        $data->{'s'},
                        $data->{'S'},
                        $data->{'p'},
                        $data->{'v'},
                    );
                }
            }
            default {
                print Dumper $decoded;
            }
        }
        return $decoded;
    }
    if (defined $decoded->{'op'}) {
        given($decoded->{'op'}) {
            when(/ping/) {
                printf ("%s %s", strftime("%Y-%m-%d %H:%M:%S ",localtime), "Pong frame for public channel received ");
                if ($decoded->{'success'}) {
                    print "with success.\n";
                } else {
                    print "with no success.\n";
                }
            }
            when(/pong/) {
                printf ("%s %s", strftime("%Y-%m-%d %H:%M:%S ",localtime), "Pong frame for private channel received ");
                if ($decoded->{'args'}[0]) {
                    print "with success.\n";
                } else {
                    print "with no success.\n";
                }
            }
            when(/auth/) {
                printf ("%s %s", strftime("%Y-%m-%d %H:%M:%S ",localtime), "Authenticated with ");
                if ($decoded->{'success'}) {
                    print "with success.\n";
                } else {
                    print "with no success.\n";
                }
            }
            when(/subscribe/) {
                printf ("%s %s", strftime("%Y-%m-%d %H:%M:%S ",localtime), "Subscribed with ");
                if ($decoded->{'success'}) {
                    print "with success.\n";
                } else {
                    print "with no success.\n";
                }
            }
            default {
                print Dumper $decoded;
            }
        }
        return $decoded;
    }
    return undef;
}