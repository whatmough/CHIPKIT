#!/group/brooks/shao/python-System/install/bin/python

#
#

import os;
import sys;
import numpy as np
import math
import binascii;
import getopt; 
print("Python version info: "+sys.version.rstrip())

baud_f = "./uart_baud.csv"

baud_rates = [9600,19200,38400,57600,115200,230400,460800]
frequency = [10,20,30,40,50,60,70,80,90,100]

clock_divides = []
for b in baud_rates:
  clock_divide_freq = []
  for f in frequency:
    clock_divide_freq.append(math.ceil(f*1e+6/(4*b)))
    #clock_divide_freq.append(math.floor(f*1e+6/(4*b)))
  print clock_divide_freq
  clock_divides += list(set(clock_divide_freq)-set(clock_divides))


print "Finish"
print clock_divides
print len(clock_divides)
