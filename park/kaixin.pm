package kaixin;
use warnings;
use strict;

use Data::Dumper;
use WWW::Mechanize;
use File::Slurp;
use Encode::Escape;
Encode::Escape::demode 'unicode-escape', 'python';
$\ = ''; # fix the Encode::Escape::Unicode's set as '\n'

use base qw/Class::Accessor::Fast/;
__PACKAGE__->mk_accessors($_) for qw/
	email password
	mech
	acc verify
	userdata first_fee_parking neighbor
	frienddata
	cars_need_move
	parkings_can_park
/;


sub new {
	my $class = shift;
	my $self = bless {}, $class;
	$self->mech( WWW::Mechanize->new );
	$self->cars_need_move([]);
	$self->parkings_can_park([]);
	return $self;
}

sub login {
	my $self = shift;
	unless ( defined $self->email and defined $self->password ){
		$self->say('need email and password.');
		exit;
	}

	$self->say('logging as %s ...', $self->email);
	$self->mech->get('http://www.kaixin001.com/');
	$self->mech->submit_form(
		form_number => 1,
		fields => {
			email => $self->email,
			password => $self->password,
		}
	);

	if ( $self->mech->content =~ /\bcheckNewMsg\b/s ){
		$self->say('logged in');
	}else{
		$self->say('failed login');
		exit;
	}
}

sub ready_park {
	my $self = shift;

	$self->say('going to parking homepage...');
	$self->mech->get('http://www.kaixin001.com/app/app.php?aid=1040');
	my $c = $self->mech->content;

	$self->say('what we have:');
	$self->acc( $self->get_acc($c) );
	$self->say(' - acc = %s', $self->acc);
	
	my ( $verify ) = ( $c =~ /var g_verify = "(.*?)";/ );
	$self->verify( $verify );
	$self->say(' - verify = %s', $self->verify);

	my ( $userdata ) = ( $c =~ /var v_userdata = (.*?);/ );
	$self->userdata( $self->json2perl($userdata) );
	$self->first_fee_parking( $self->userdata->{'user'}{'first_fee_parking'} );
	$self->neighbor( $self->userdata->{'user'}{'neighbor'} );

	my ( $frienddata ) = ( $c =~ /var v_frienddata = (.*?);/ );
	$self->frienddata( $self->json2perl($frienddata) );
}

sub show_my_parking {
	my $self = shift;
	$self->say('my parking:');
	foreach my $p ( @{$self->userdata->{'parking'}} ){
		$self->say(
			' - RMB %4d: %8d (%s) - %s (%s, %s)',
			$p->{'car_profit'},
			$p->{'carid'},
			$self->u2utf8($p->{'car_name'}),
			$p->{'parkid'},
			$self->u2utf8($p->{'car_real_name'}),
			$p->{'car_uid'},
		);
	}
}

sub show_my_cars {
	my $self = shift;
	$self->say('my cars:');
	my @cars_need_move = ();
	my $now = time;
	foreach my $car ( @{$self->userdata->{'car'}} ){

		my $need_move = ( 
			$car->{'park_profit'} > 200 or
			$car->{'park_profit'} == 0 and $now - $car->{'ctime'} > 60*15
		) ? 1 : 0;

		if ( $need_move ){
			push @cars_need_move, $car;
		}
		$self->say(
			' %s RMB %4d: %8d (%s) - %s (%s, %s)',
			( $need_move ) ? '+' : '-',
			$car->{'park_profit'},
			$car->{'carid'},
			$self->u2utf8($car->{'car_name'}),
			$car->{'parkid'},
			$self->u2utf8($car->{'park_real_name'}),
			$car->{'park_uid'},
		);
	}
	$self->cars_need_move(\@cars_need_move);
}

sub get_friend_data {
	my $self = shift;
	my $uid = shift;
	$self->mech->get( sprintf
		'http://www.kaixin001.com/parking/user.php?verify=%s&puid=%s',
		$self->verify, $uid
	);
	my $user = $self->json2perl($self->mech->content);
	return $user;
}

sub config_filename {
	my $self = shift;
	my $filename = $self->email;
	$filename =~ s/\@/_at_/;
	$filename =~ s/\W/_/g;
	$filename .= '.money_minute';
	return './'.$filename;
}

sub list_money_minute {
	my $self = shift;

	$self->say('listing the good parkings...');
	my @lines;
	foreach my $f (@{$self->frienddata}){
		my $user = $self->get_friend_data( $f->{'uid'} );
		my $money_minute = $user->{'config'}{'money_minute'};
		my $line = sprintf "%s\t%s\t%s", $money_minute, $f->{'uid'}, $self->u2utf8($f->{'real_name'});
		$self->say($line);
		push @lines, $line."\n";
	}
	write_file($self->config_filename, \@lines);
}

sub update_money_minute {
	my $self = shift;
	my $uid = shift;
	my $money = shift;
	my $name = shift;
	
	my $filename = $self->config_filename;
	my @lines = read_file($filename);
	my $hash;
	foreach ( @lines ){
		my ($m, $u, $n) = split(/\s+/, $_, 3);
		$hash->{$u} = {
			money => $m,
			name => $n
		};
	}

	$hash->{$uid} = {
		money => $money,
		name => $name
	};

	my @newlines;
	foreach ( keys %$hash ){
		push @newlines, sprintf "%s\t%s\t%s\n", $hash->{$_}{'money'}, $_, $hash->{$_}{'name'};
	}

	write_file($filename, \@newlines);
}

sub get_money_minute {

}

sub where_can_park {
	my $self = shift;
	my @parkings_can_park = ();
	foreach my $f (@{$self->frienddata}){
		next unless $f->{'full'} == 0;
		$self->say('checking %s ...', $self->u2utf8($f->{'real_name'}));
		my $user = $self->get_friend_data( $f->{'uid'} );
		
		#$self->update_money_minute( $f->{'uid'}, $user->{'config'}{'money_minute'}, $self->u2utf8($f->{'real_name'}) );
		
		my @parkids = map { $_->{'parkid'} }
			grep { ! ( ( $_->{'parkid'} >> 16 ) & 0xff ) } # but not free one
			grep { $_->{'carid'} == 0 } # find the empty
			@{$user->{'parking'}};
		$self->say('found %s parkings: %s', scalar @parkids, join(', ', @parkids));
		
		map {
			push @parkings_can_park, {
				parkid => $_,
				uid => $f->{'uid'},
				real_name => $f->{'real_name'},
			}
		} @parkids;
	}
	$self->parkings_can_park(\@parkings_can_park);
}


sub park {
	my $self = shift;
	my @cars_need_move = @{$self->cars_need_move};
	my @parkings_can_park = @{$self->parkings_can_park};

	while ( my $car = shift @cars_need_move ){

		# split parkings by uid
		my @parkings_same_uid = grep { $car->{'park_uid'} == $_->{'uid'} } @parkings_can_park;
		my @parkings_rest = grep { $car->{'park_uid'} != $_->{'uid'} } @parkings_can_park;

		# if no parkings can use
		if ( scalar @parkings_rest == 0 ){
			$self->say('no more empty parking...');

			# at the end, nothing we can do
			my @cars_need_move_otheruid = grep { $_->{'park_uid'} != $car->{'park_uid'} } @cars_need_move;
			if ( scalar @cars_need_move_otheruid == 0 ){
				$self->say('the rest cars are all the same uid as the last parking, abort');
				last;

			# wait later to try again
			}else{
				push @cars_need_move, $car;
			}

		# try the first parking
		}else{
			my $parking = shift @parkings_rest;

			# if success, collect the old parking
			if ( $self->park_car_to_parking( $car, $parking ) ){
				if ( $car->{'park_uid'} != 0 ){ # been kicked
					unshift @parkings_rest, {
						parkid => $car->{'parkid'},
						uid => $car->{'park_uid'},
						real_name => $car->{'park_real_name'},
					};
				}
			# failed, abort the parking, remain the car
			}else{
				push @cars_need_move, $car;
			}
		}
		
		# rebuild the parkings queue
		@parkings_can_park = ( @parkings_rest, @parkings_same_uid );
	}
}

sub park_car_to_parking {
	my $self = shift;
	my ( $car, $parking ) = @_;

	$self->say(
		'     parking %s (%s): %s (%s) => %s (%s) ...',
		$self->u2utf8($car->{'car_name'}),
		$car->{'carid'},

		$self->u2utf8($car->{'park_real_name'}),
		$car->{'parkid'},

		$self->u2utf8($parking->{'real_name'}),
		$parking->{'parkid'},
	);

	my $parameters = {
		carid => $car->{'carid'},
		park_uid => $parking->{'uid'},
		parkid => $parking->{'parkid'},
		verify => $self->verify,
		acc => $self->acc,
		first_fee_parking => $self->first_fee_parking,
		neighbor => $self->neighbor,
	};
	my $res = $self->mech->post( 'http://www.kaixin001.com/parking/park.php', $parameters );

	if ( $res->is_success ){
		my $msg = $self->json2perl( $res->decoded_content );
		if ( $msg->{'errno'} != 0 or $msg->{'ctime'} eq 'false'){
			$self->say('nok: %s', $self->u2utf8($msg->{'error'}) );
		}else{
			$self->say(' ok: %s', $self->u2utf8($msg->{'error'}) );
			sleep 6;
			return 1;
		}
	}else {
		$self->say('http failed: %s', $res->status_line);
	}
	return undef;
}


sub say {
	my $self = shift;
	my $message = shift;
	$message = sprintf $message, @_ if scalar @_;
	print STDERR $message ."\n";
}
sub json2perl {
	my $self = shift;
	my $str = shift;
	$str =~ s/\":null/\"=>undef/g;
	$str =~ s/\":false/\"=>0/g;
	$str =~ s/\":/\"=>/g;
	my $data;
	eval "\$data = $str;";
	die "json2perl failed: $@" if $@;
	return $data;
}
sub u2utf8{
	my $self = shift;
	my $str = shift;
	if ( $str !~ /\\u/){
		$str =~ s/([\da-fA-F]{4})/\\u$1/g;
	}
	return encode 'utf8', decode 'unicode-escape', $str;
}
sub get_acc {
	my $self = shift;
	my $str = shift;
	my @lines = split(/\n/, $str);

	my $line_number_acc;
	foreach my $i ( 0 .. $#lines ){
		if ( $lines[$i] =~ /function\s+acc\(\)/ ){
			$line_number_acc = $i;
			last;
		}
	}
	my $start = $line_number_acc - 3;
	my $end = $line_number_acc + 8;
	my $block = join("\n", @lines[$start..$end]);
	$block =~ s/var\s+/my \$/g;

	my $stay;
	my $acc_line;
	foreach (split(/\n/, $block)){
		if ( /\$acc\s+=/ ){
			s/^\s+//;
			if ( ! /charCodeAt/ ){
				s/\s+\+\s+/ \. /g;
			}
			s/([a-z0-9]{3,5})\./\$$1\./g;
			s/(\$[a-z0-9]{3,5})\.length/length\($1\)/g;
			s/(\$[a-z0-9]{3,5})\.charCodeAt\((\d)\)/ord\(substr\($1,$2,1\)\)/g;
			s/(\$[a-z0-9]{3,5})\.substr\((\d),(\d)\)/substr\($1,$2,$3\)/g;
			s/my\s+//;
			$acc_line = $_."\n";
		}elsif (/^my\s+/){
			$stay .= $_."\n";
		}
	}
	$stay .= $acc_line;

	my $acc;
	eval "$stay" or die "eval to get acc failed: $@";
	return $acc;
}

1;
