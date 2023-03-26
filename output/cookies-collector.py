import os
import sys
import json
import base64
import sqlite3
import argparse
import re
from datetime import datetime, timedelta

def main():
    filename = sys.argv[1]
    oformat = sys.argv[2]
    # local sqlite Chrome cookie database path
    file = "phis.db"
    phis = "phis" + re.search('user(.+?)-', filename).group(1)
    # Check if summary database exists
    ## if not create db 

    
    cookies = []
    conn = sqlite3.connect(file)
    c = conn.cursor()
    
    c.execute("CREATE TABLE IF NOT EXISTS cookies ([id] INTEGER PRIMARY KEY, [phis] TEXT, [name] TEXT, [value] TEXT, [host] TEXT, [expiry] TEXT, [path] TEXT,[isSecure] TEXT,[isHttpOnly] TEXT,[sameSite] TEXT, [source] TEXT)")
    conn.commit()
    c.execute("DELETE FROM cookies WHERE phis = ? AND source = ?",(phis,"cookie"))
    conn.commit() 
    
    

    
    if os.path.exists(phis+"-cookies.json"):
        os.remove(phis+"-cookies.json")
    
    # connect to the database
    db = sqlite3.connect(filename)
    # ignore decoding errors
    db.text_factory = lambda b: b.decode(errors="ignore")
    cursor = db.cursor()
    # get the cookies from `cookies` table
    cursor.execute("SELECT originAttributes, name, value, host, creationTime, lastAccessed, expiry, path, isSecure, isHttpOnly, sameSite FROM moz_cookies")
    for originAttributes, name, value, host, creationTime, lastAccessed, expiry, path, isSecure, isHttpOnly, sameSite in cursor.fetchall():       
        c.execute("INSERT INTO cookies(phis,name,value,host,expiry, path, isSecure, isHttpOnly, sameSite, source) VALUES(?,?,?,?,?,?,?,?,?,?)",(phis, name, value, host,expiry, path, isSecure, isHttpOnly, sameSite,"cookie"))
        conn.commit()

        if host[:1] == ".":
            ThisDomain = "Valid for subdomains"
            ThisDomainRaw = False
        else:
            ThisDomain = "Valid for host only"
            ThisDomainRaw = True
            
        if isSecure == 1:
            SendFor = "Encrypted connections only"
            SendForRaw = True
        else:
            SendFor = "Any type of connection"
            SendForRaw = False
        
        if sameSite == 0:
            sameSiteRaw = "no_restriction"
        elif sameSite == 1:
            sameSiteRaw = "lax"
        elif sameSite == 2:
            sameSiteRaw = "strict"
        
        if isHttpOnly == 1:
            HTTPonly = True
        else:
            HTTPonly = False
            
        if oformat == "simple":
            cookie = {
                "domain": host,
                "expirationDate": expiry,
                "hostOnly": ThisDomainRaw,
                "httpOnly": HTTPonly,
                "name": name,
                "path": path,
                "sameSite": sameSiteRaw,
                "secure": SendForRaw,
                "session": False,
                "storeId": "0",
                "value": value
            }
        else:
            cookie = {
                "Host raw": "https://"+host,
                "Name raw": name,
                "Path raw": path,
                "Content raw": value,
                "Expires": str(datetime.fromtimestamp(expiry)),
                "Expires raw": expiry,
                "Send for": SendFor,
                "Send for raw": SendForRaw,
                "HTTP only raw": HTTPonly,
                "SameSite raw": sameSiteRaw,
                "This domain only": ThisDomain,
                "This domain only raw": ThisDomainRaw,
                "Store raw": "firefox-default",
                "First Party Domain": ""
            }
        
        json_object = json.dumps(cookie, indent=2)
        with open(phis+"-cookies.json", "a") as outfile:
            outfile.write(json_object + ",\n")
    db.close()
    
    if os.path.exists(phis+"-cookies.json"):
        with open(phis+"-cookies.json", 'r', encoding='utf-8') as file:
            data = file.readlines()
        data[0] = "[{\n"
        data[-1]= "}]"
        with open(phis+"-cookies.json", 'w', encoding='utf-8') as file:
            file.writelines(data)





if __name__ == "__main__":
    main()
