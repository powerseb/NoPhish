import os
import sys
import json
import base64
import sqlite3
import argparse
import re


usernumber = sys.argv[1]
url = sys.argv[2]

file = "phis.db"    
conn = sqlite3.connect(file)
c = conn.cursor()

print("For the url",(url.split("/conn"))[0],":")

c.execute("SELECT Count(*) AS count FROM cookies WHERE source='session' AND phis='phis"+usernumber+"'")

for row in c.fetchall():
   print("- ",row[0], " cookies have been collected.")
   
c.execute("SELECT Count(*) AS count FROM cookies WHERE source='session' AND phis='phis"+usernumber+"'")

for row in c.fetchall():
   print("- ",row[0], " session cookies have been collected.")
