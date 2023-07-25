#!/bin/bash

while true; do

# Replace 'your_text_file.txt' with the path to your text file containing IP addresses
file_path="/tmp/disconnect.txt"

# Read the first line of the file
ip_address=$(head -n 1 "$file_path")

# Check if the line is a valid IP address using regex
if [[ $ip_address =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    # Execute tcpkill for 5 seconds with the IP address
    timeout 5s /usr/sbin/tcpkill -9 host "$ip_address"

    # Remove the IP address line from the file
    sed -i "/$ip_address/d" "$file_path"
else
    echo "Invalid IP address: $ip_address"
fi

# Sleep for 30 seconds before running the script again
sleep 15

done
