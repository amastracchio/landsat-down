#!/usr/bin/perl
#use strict;


# Documentacion https://m2m.cr.usgs.gov/api/docs/json/#section-overview


use Time::Format;
use Net::SSL ;
use Data::Dumper;
use warnings;
use 5.010;
use JSON;
use Scalar::Util qw(looks_like_number reftype dualvar );
use LWP::UserAgent;
use Getopt::Long qw(GetOptions);
 
my $today =  $time{'yyyy-mm-dd'};


# nuevo
my $loginurl = 'https://m2m.cr.usgs.gov/api/api/json/stable/login';
my $csrf;
my $ncforminfo;
my $key;
my $logfile = "land-down.log";

my @products;

my ($username, $password);
my $opt_request;
my ($latitude, $longitude);


open(FILE,">$logfile");
print FILE "Starting.";

# Busqueda, responde datasets que luego hacemos busqueda para ese dataset (entityID) las downloadoptions

#< search
# > datasets   
# > dataset 1,2,3
# <donwloadoptions segun dataset x 
#    >products  1,2,3

GetOptions(
    'username=s' => \$username,
    'password=s' => \$password,
    'latitude=s' => \$latitude,
    'longitude=s' => \$longitude,
    # Do request file
    "request"  => \$opt_request,
) or die "Error retrieving Username and Password\n";
 
unless($username) {die "Username is Required\n"};
unless($password) {die "Password is Required\n"};

unless($latitude) {die "latitude is Required\n"};
unless($longitude) {die "longitude is Required\n"};

$ENV{HTTPS_DEBUG} = 0;
$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;

say "\nRunning Script...\n\n";

my $serviceUrl = 'm2m.cr.usgs.gov/api/api/json/stable/';

my %inputParameters = ('username' => $username, 'password' => $password);

# apikey es la vieja en realidad
my $apiKey = sendRequest($loginurl, \%inputParameters, 1);
$key = $apiKey;

say "API Key: $apiKey\n";




    %inputParameters = (
        'maxResults' => 10,
#            'datasetName' => 'gls_all',
        'datasetName' => 'LANDSAT_8_C1',
#            'datasetName' => 'LANDSAT_TM_C1',

	'sceneFilter' => {

            'spatialFilter' => { 
                'filterType'  => 'mbr', 
                'lowerLeft' => { 
##                    'latitude'  => 15.4060, 
     #               'latitude'  => 12.53, 
           #         'latitude'  => 12.53, 
                    'latitude'  => $latitude,

#                    'longitude' => 79.0082 } , 
           #         'longitude' => -1.53 } , 
                    'longitude' => $longitude},
                'upperRight' => { 
                   # 'latitude'  => 17.9578, 
                  #  'latitude'  => 12.63, 
                    'latitude'  => $latitude,
                    #'longitude' => 80.6781 }
                    #'longitude' => -1.43 }
                    'longitude' => $longitude  }
             },
            'acquisitionFilter' => { 
                'start' => '2021-03-10 00:00:00-05', 
                'end' => $today." ". '00:00:00-05' },
        } #scenefilter
        );
 
    say "Searching datasets...\n";

    print "Sending ".Dumper \%inputParameters;

    my $datasets = sendRequest("https://${serviceUrl}scene-search", \%inputParameters,1);

    my $data = $datasets->{results};
    say "Found ", scalar @$data, " dataset(s)\n";

    my $contdata = 0;

    for my $dataset (@$data) {

        

	print "dataset $contdata= ". Dumper $dataset;


	$contdata++;


	my $entityid = $dataset->{entityId} ;





                my %inputParameters = (
                        'datasetName' => "LANDSAT_8_C1",
                        'entityIds' => $entityid,
                    );

	        print "Busca productos asociados a los data-sets encontrados !!!\n";
                my $downloadOptions = sendRequest("https://${serviceUrl}download-options", \%inputParameters,1);

		# die Dumper $downloadOptions;
		# siempre va a ser 1 registro porque buscamos la sceneid una por una...
		my $scenecount = 0;

                foreach my $sceneLevel (@$downloadOptions) {


		    print "Product  cont.=".$scenecount++." de dataset #".$contdata."\n";

		    # cosmetico
		    my $pro =  Dumper $sceneLevel;
		    $pro =~ s/    /\t\t\t/g;
		    print $pro;


                    my %inputParameters = (
				'downloads' => [{
				   'label' => 123456,
				   'productId' => $sceneLevel->{id},
				   'entityId' => $sceneLevel->{entityId}  
				  }
				],
				'downloadApplication' => "EE"
                    );

	           # die Dumper \%inputParameters;

 		   if ($opt_request) {

                       my $download_request_answer = sendRequest("https://${serviceUrl}download-request", \%inputParameters,1);

		       my $download = $download_request_answer->{availableDownloads};
		   }

		   print Dumper $download_request_answer;

		   my $download_first = $download->[0];
		   my $downloadurl =  $download_first->{url};


		} # foreach scene
	
 
   } # for dataset




   # Lista de ordenes pendientes /completas
   my %inputParameters = (
	   'label' => 123456
   );

   my $download_retrieve = sendRequest("https://${serviceUrl}download-retrieve", \%inputParameters,1);


   my $available = $download_retrieve->{available};
   print "Download pendientes = ".scalar @$available."\n";
   foreach my $avail (@$available){

# borrar pendientes
#                   	my %inputParameters = (
#				   'downloadId' => $avail->{downloadId}
#	   	   	);
#                        my $download_delete = sendRequest("https://${serviceUrl}download-remove", \%inputParameters,1);
			
   	# Bajar
   	$downloadurl = $avail->{url};
   	print "Requesting file = $downloadurl\n";
   	system ("lwp-download -s $downloadurl");
  }


    %inputParameters = (
            'apiKey' => $apiKey,
    );

    if (sendRequest("https://${serviceUrl}logout", \%inputParameters, 1)) {
        say "Logged Out\n\n";
    } else {
        say "Logout Failed\n\n";
    }
    


sub sendRequest
{
    my ($url, $datos, $isPost) = @_;
    $isPost ||= 0;

  my $request;
    print FILE  "Entra en sendRequest ($url), key (global) = $key\n";
    my $json = encode_json $datos ;

   print FILE  "json del request: ".$json."\n";
    
    my $ua = LWP::UserAgent->new(keep_alive => 1);

    $ua->env_proxy;


# ???
#    $ua->proxy('https', 'connect://127.0.0.1:3128/');
    $ua->proxy('https', 'http://127.0.0.1:3128/');
#    $ua->proxy(['https','http','json'], 'http://127.0.0.1:3128');




    if ($isPost) {
        $request =  HTTP::Request->new(POST => $url);
       $request->header( 'Content-Type' => 'application/json; charset=utf-8' );
       $request->header( 'Cache-Control' => 'max-age=259200' );
 
       $request->header( 'Accept' => '*/*' );
       $request->header( 'Accept-Encoding' => 'gzip, deflate, br' );
       $request->header( 'Accept-Language' => 'en-US,en; q=0.5' );
      
       if (defined $key ) {
            $request->header( 'X-Auth-Token' => $key );
       }
	
        $request->content( "$json\n" );
    } else {
        $url = "$url?$json";
	print "url = $url\n";

        $request =  HTTP::Request->new(GET => $url);
       if (defined $key ) {
            $request->header( 'X-Auth-Token' => $key );
       }

        $request->header( 'Content-Type' => 'application/x-www-form-urlencoded' );
    } 

    

    print FILE "request = ".Dumper $request;
    my $response = $ua->request($request);


    eval {

        if (! defined $response) {
            die "No output from service";
        }

        $res = $response->{_content};
	print FILE "Response headers= ".$response->headers()->as_string."\n";
        $res = decode_json $res;

        my $tmp = Dumper $res;
	print FILE "res = $tmp \n";

        if ($response == 0) {
            die "Could not parse JSON";
        }

        if ($res->{errorCode}) {
	  
	    print Dumper $res;
            die "$res->{errorCode} - $res->{error}";
        }

        if ($response->code == 404) {
            die "404 Not Found";
        } elsif ($response->code == 401) {
            die "401 Unauthorized";
        } elsif ($response->code == 400) {
            die "HTTP Status",$response->code;
        }
    };
    if ($@){
        die "Error: $@ $res\n";
    };

    
    return $res->{data};
}
