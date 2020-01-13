#!/usr/bin/env python

# vgen_regs.py - Various functions to generate verilog for memory-mapped CSRs
# Paul Whatmough Jan 2014
# Paul Whatmough Dec 2016 - Changed to CSV format.
# Paul Whatmough Mar 2016 - Added update functionality.

import time;
import re;
import shutil;
import os;
import sys;
import argparse;

from vgen import *;


# This is the minimum set of keys required for generation.
regs_keys = [
  'name',
  'idx',
  'nbits',
  'start',
  'access',
  'test',
  'rval'
  ]

# TODO
# Update command line arg parsing - setup the same as pads version.
# Might make sense to put the command line arg parsing into vgen.py?
# Add the update from Verilog functionality.
# Some other updates in pads version need back porting.
# Any commonality shoud go into vgen.py.


###############################################################################
# Get signals
###############################################################################

# FIXME must check not only for new signals, but also for changes in existing signals


def update_regs_csv_from_verilog(csv_file,verilog_file,match_prefix=''):
  """
  Read in CSV and Verilog files,
  Any new signals anywhere in Verilog that match the prefix and do not exist in CSV are added to CSV.
  Will warn about any signals found in CSV that do not exist in Verilog.
  Return True if any new signals were added to csv.
  """
  # Read in list of io signals from CSV file
  print '** Reading csv_file: %s, and Verilog file: %s' % (csv_file,verilog_file)
  csv_vglist = read_csv(csv_file)
  check_keys_exist(csv_vglist,regs_keys)

  # Read in verilog file to get all signals that match the prefix.
  verilog_vglist = get_verilog_signals(verilog_file,match_prefix)
  
  # TODO check for changes in the contents of other fields
  # Compare the two lists, keep signals that are in verilog and not in CSV
  new_in_verilog = find_new(csv_vglist,verilog_vglist,'name')
 
  # debug
  if (True):
    print 'csv_vglist: '+str([d['name'] for d in csv_vglist])
    print 'verilog_vglist: '+str([d['name'] for d in verilog_vglist])

  # Compare the two lists, keep signals that are in CSV and not in Verilog
  missing_in_verilog = find_new(verilog_vglist,csv_vglist,'name')
  if len(missing_in_verilog) > 0:
    print 'WARNING: Found signals in CSV (%s) not in Verilog (%s): \n%s' % (csv_file,verilog_file,str([d['name'] for d in missing_in_verilog]))

  # Write any new signals from Verilog back to the CSV.
  if new_in_verilog != []: 
    print 'Found new signals in Verilog file (not listed in CSV):\n %s' % str([d['name'] for d in new_in_verilog])
    print 'Updating CSV file: %s' % csv_file
    append_csv(csv_file,new_in_verilog,regs_keys,unused_str='')

  # Return true if new signals were added to FE csv
  if new_in_verilog != []:
    return True
  else:
    return False


###############################################################################
# Verilog module
###############################################################################


def gen_regs_module(module_name,module_file,template_file,regs):
  """ Generate a CSR module from a template file and a signal list """

  # Check the required keys are present (others will be ignored)
  csr_keys =[
    'idx',      # register order number
    'name',     # logical name for register
    'nbits',    # number of bits
    'access',   # read/write access
    'start',    # field start bit (typically 0)
    'test',     # enable test on this register
    'rval',     # reset value [hex string]
    'desc'      # simple informative description
    ]
  assert check_keys_exist(regs,csr_keys)

  # Open template
  fi_template = open(template_file,"r")
  
  # Open output file 
  if (os.path.isfile(module_file)):                   # if verilog already exists, backup first
    shutil.copy2(module_file,module_file+".bak")      # copy2 preserves mod/access info
  fo = open(module_file,"wb")
  print "**Writing module \""+module_name+"\" to file \""+fo.name+"\""
  fo.write(banner_start())

  # Print some header info into the generated file
  fo.write(read_to_tag(fi_template,"VGEN: HEADER"))
  
  l = "// Register file contents:\n"
  #l += "// " + str(csr_keys) + "\n\n"
  fo.write(l)
  for reg in regs:
    l = "//" + str(reg) + "\n"
    #l = "// %-10s %-2s %-2s %-2s %-2s %-2s %-2s %-50s\n" % tuple([reg[x] for x in csr_keys])
    fo.write(l)
  fo.write("\n\n")

  # Module name
  fo.write(read_to_tag(fi_template,"VGEN: MODULE NAME"))
  fo.write(module_name+"\n")
  
  # Port list inputs
  fo.write(read_to_tag(fi_template,"VGEN: INPUTS TO REGS"))
  for n, row in enumerate(regs):
    if (row['access'] == "r"):
      l = "input  logic "+reg_dims(row)+" "+row['name']+",\t"
      l += "/* idx #"+str(n)+": "+row['desc']+" */" + "\n"
      fo.write(l)
  
  # Port list outputs
  fo.write(read_to_tag(fi_template,"VGEN: OUTPUTS FROM REGS"))
  first = True
  for n, row in enumerate(regs):
    if (row['access'] == "rw"):
      l = ""
      if first:           # Nastyness to avoid final comma in list
        first = False
      else:
        l += ",\n"
      l += "output logic " + reg_dims(row) + " " + row['name'] + "\t"
      l += " /* idx #"+str(n)+": "+row['desc']+" */"
      fo.write(l)
 
  # Register write 
  fo.write(read_to_tag(fi_template,"VGEN: REG WRITE"))
  for n, row in enumerate(regs):
    if row['access'] == "rw":
      l = "// idx #"+str(n)+"\n"
      l += "logic " + reg_dims(row) + " "+row['name']+"_reg;\n"
      l += "always@(posedge clk or negedge rstn) begin\n"
      l += "  if(~rstn) begin\n    "
      l += row['name']+"_reg" + reg_dims(row)
      if int(row['rval'].rsplit('0x')[1]) == 0:
        l += " <= \'0;\n"
      else:   # TODO really should get the correct number of digits for the reset value
        l += " <= " + row['nbits'] + "\'h" + row['rval'].rsplit("0x")[1] + ";\n"
      l += "  end else begin\n"
      l += "    if(regbus.write_en & (regbus.addr[9:2]==8'h"+(hex(int(row['idx'])).lstrip("0x") or "0")+")) "
      l += row['name'] + "_reg" + reg_dims(row) + " <= regbus.wdata" + reg_dims(row)
      l += ";\n  end\nend\n"
      l += "assign "+row['name']+reg_dims(row)+" = "+row['name']+"_reg"+reg_dims(row)+";\n\n"
      fo.write(l)
  
  # Register read
  fo.write(read_to_tag(fi_template,"VGEN: REG READ"))
  for n, row in enumerate(regs):
    l = "    if(regbus.addr[9:2]==8'h"+(hex(int(row['idx'])).lstrip("0x") or "0")+") "
    l += l + "rdata_o"+reg_dims(row)+" = "+row['name']+reg_dims(row)+";\t"
    l = l +" // idx #"+str(n)+"\n"
    fo.write(l)
  
  # Rest of template
  fo.write(read_to_tag(fi_template,""))
  fo.write(banner_end())
  
  # Close files
  fo.close()
  fi_template.close()
  


###############################################################################
# Verilog instance
###############################################################################

def gen_regs_instance(module_name,instance_file,regs,clock='?clk',reset='?rstn'):
  """ Generate an instantiation template for the register module """

  fo = open(instance_file,"w")
  print "**Writing module instantiation template to file \""+fo.name+"\""
  fo.write(banner_start())

  # list of signals
  fo.write("// START\n")
  for n, row in enumerate(regs):
    l = "logic "+reg_dims(row)+" "+row['name']+";\n"
    fo.write(l)
  
  # module instantiation
  l = "\n" + module_name+" u_"+module_name+" (\n\n"
  l += "// clocks and resets\n"
  l += ".clk("+clock+"),\n.rstn("+reset+"),\n\n"
  l += "// Synchronous register interface\n"
  l += ".regbus           ("+module_name+".sink),\n"
  l += "\n// reg file signals\n"
  fo.write(l)
  
  first = True
  for n, row in enumerate(regs):
    l = ""
    if first:           # Nastyness to avoid final comma in list
      first = False
    else:
      l += ",\n"
    l += "."+row['name']+"("+row['name']+reg_dims(row)+")"
    l += "\t/* idx "+row['idx']+" */"
    fo.write(l)
  
  l = "\n\n);\n"
  l += "// END\n\n"
  fo.write(l)
  fo.write(banner_end())
  
  fo.close()


###############################################################################
# Markdown docs
###############################################################################

# TODO make this a generic function that lives in vgen.py
# TODO add the reset value and any other fields not included here

def gen_regs_docs(module_name,md_file,regs):
  """ Generate markdown documentation for the register module """

  fo = open(md_file,"w")
  print "**Writing module documentation to markdown file \""+fo.name+"\""
  fo.write(banner_start())
  
  # Title for the documentation
  l = ""
  l += "# Programmers Model\n\n"
  l += "## Module: "+module_name.upper()+"\n\n"
  fo.write(l)

  # Header for the markdown table
  l = ""
  l += "| Address Offset | Signal Name | Access | Bit width | Start bit | Description | \n"
  l += "| ---            | ---         | ---    | ---       | ---       | ---         | \n"
  l += "| \n"
  fo.write(l)
  
  # Generate table entries
  last_reg = 0
  for n, row in enumerate(regs):
    l = ""
    if (int(row['idx']) > (last_reg+1)): l += "|\n"    # insert a gap if address is not contiguous
    last_reg = int(row['idx'])
    l += "| "
    l += hex(int(row['idx']) *4)+" | "                 # Address
    l += "**"+(row['name']).upper()+"** | "            # Signal name
    if (row['access'] == "r"): l += "R | "             # Read / write access
    else:               l += "RW | "
    l += (row['nbits'])+" | "                          # bit width 
    l += (row['start'])+" | "                          # start bit position
    l += (row['desc'])+" | \n"
    fo.write(l)
  
  # Add a few blank lines at the bottom
  l = "\n\n"
  fo.write(l)

  fo.write(banner_end()) 
  fo.close()




###############################################################################
# C header
###############################################################################

def gen_regs_cheader(module_name,cheader_file,regs):
  """ Generate C header with definitions for the register module """

  fo = open(cheader_file,"w")
  print "**Writing register map to C header file \""+fo.name+"\""
  
  # comment line and header guards
  fo.write(banner_start()) 
  l = "#ifndef "+module_name.upper()+"_H \n"
  l += "#define "+module_name.upper()+"_H \n"
  l += "\n\n"
  fo.write(l)
   
  # start struct definition
  l = "typedef struct\n"
  l += "{\n"
  fo.write(l)
  
  # Generate each item in the struct
  current_reg = 0
  for n, row in enumerate(regs):
    l = ""
    
    while (int(row['idx']) != current_reg): 
      l += "\t\tuint32_t RESERVED"+str(current_reg)+";\n"   # Use RESERVED if address is not contiguous
      current_reg = current_reg + 1
    else :
      current_reg = current_reg + 1

    l += "\t"                            # insert the macro for volatile / static depending on R/W
    if (row['access'] == 'r'):  l += "__I "
    else:                       l += "__IO "

    l += "uint32_t "                               # data type
    l += row['name'].upper()+";\t\t"               # Signal name
    l += "/* "                                     # open a comment to hold some info
    l += "Offset: "+hex(int(row['idx']) *4)+" "    # Address
    if (row['access'] == "r"):  l += "(R/ ) "      # Read / write access
    else:                       l += "(R/W) "
    l += (row['desc'])                             # signal description
    l += " */\n"                                   # close comment
    fo.write(l)
  
  # close the struct
  l = "} "+module_name.upper()+"_TypeDef;\n\n"
  fo.write(l)
 
  # close the header guard
  l = "#endif\n\n"
  fo.write(l)

  
  fo.write(banner_end()) 
  fo.close()


###############################################################################
# Python class
###############################################################################

def gen_regs_python(module_name,output_file,regs):
  """ Generate Python module with dictionary containing definitions for the register module """

  fo = open(output_file,"w")
  print "**Writing register map dictionary to python module \""+fo.name+"\""
  
  # comment line and header guards
  fo.write("# "+banner_start())
   
  # start struct definition
  l = "class "+module_name.title()+"(object):\n"
  fo.write(l)
  
  # add a constructor to allow the base_offset to be set for the regs
  l = "\n\tdef __init__(self,base_offset):\n"
  l += "\t\tself.base_offset = base_offset\n\n\n"
  fo.write(l)

  # Generate each item in the struct
  current_reg = 0
  for n, row in enumerate(regs):
    l = ""
    
    while (int(row['idx']) != current_reg): 
      l += "\t\tself.RESERVED"+str(current_reg)+" = None\n"   # Use RESERVED if address is not contiguous
      current_reg = current_reg + 1
    else :
      current_reg = current_reg + 1

    l += "\t\tself."+row['name'].upper()+" = self.base_offset + "+hex(int(row['idx']) *4)  # Name and Address
    l += "\t\t# "+(row['desc'])                              # signal description in comment
    l += "\n"
    fo.write(l)
  
  # close the class
  l += "\n\n"
  fo.write(l)

  fo.write("# "+banner_end())
  fo.close()


###############################################################################
# C test
###############################################################################


def gen_regs_ctest(module_name,output_file,regs):
  """ Generate C header with definitions for the register module """
 
  # Write a header for the test
  fo = open(output_file[0],"w")
  print "**Writing C test header (.h) file \""+fo.name+"\""
  
  # comment line and header guards
  fo.write(banner_start()) 
  l = "#ifndef "+module_name.upper()+"_TEST_H \n"
  l += "#define "+module_name.upper()+"_TEST_H \n"
  l += "\n\n"
  fo.write(l)
  
  # include SM2 header
  l = "#include \"SM2_CM0.h\"\n\n"
  fo.write(l)
  
  # function prototype for initial value test
  l = "// This test is intended to check initial (reset) values of registers\n"
  l += "int "+module_name+"_initial_value_test(void);\n\n"
  fo.write(l)

  # function prototype for write read test
  l = "// This test is intended to check write and read to registers\n"
  l += "int "+module_name+"_write_read_test(void);\n\n"
  fo.write(l)
  
  # close the header guard
  l = "#endif\n\n"
  fo.write(l)

  fo.write(banner_end())
  fo.close()
 



  # Write out the c code for the test
  fo = open(output_file[1],"w")
  print "**Writing C test (.c) file \""+fo.name+"\""
  fo.write(banner_end())

  # include the header
  l = "#include \""+module_name+"_test.h\"\n\n"
  fo.write(l)
  
  # start of initial value test function
  l = "// This test is intended to check initial (reset) values of registers\n"
  l += "int "+module_name+"_initial_value_test(void) {\n"
  l += "\tint num_errors=0;\n\n"
  fo.write(l)
 
  # Generate test for each register
  l = ""
  for n, row in enumerate(regs):
    l += "\tif (SM2_"+module_name.upper()+"->"+row['name'].upper()+" != 0)\t\t{num_errors += 1; puts(\"ERROR: "+row['name'].upper()+"\");}\n"
  l += "\n\n"
  fo.write(l)

  # end of function
  l = "\treturn num_errors;\n\n"
  l += "}\n\n"
  fo.write(l)


  # start of write read test function
  l = "// This test is intended to check write read to registers\n"
  l += "int "+module_name+"_write_read_test(void) {\n"
  l += "\tint num_errors=0;\n\n"
  fo.write(l)
 
  # Generate test for each register
  l = ""
  for n, row in enumerate(regs):
    if (row['access'].lower()=="rw"):
      l += "\tSM2_"+module_name.upper()+"->"+row['name'].upper()+" = 0xFFFFFFFF;\t// write all-1s\n"
      l += "\tif (SM2_"+module_name.upper()+"->"+row['name'].upper()+" != (0xFFFFFFFF >> (32-"+row['nbits']+")))\t\t{num_errors += 1; puts(\"ERROR: "+row['name'].upper()+"\");}\t// check field is all-1s\n"
      l += "\tSM2_"+module_name.upper()+"->"+row['name'].upper()+" = 0x0;\t// clear field\n"
      l += "\tif (SM2_"+module_name.upper()+"->"+row['name'].upper()+" != 0x0)\t\t{num_errors += 1; puts(\"ERROR: "+row['name'].upper()+"\");}\t// check field is all-0s\n"
  l += "\n\n"
  fo.write(l)

  # end of function
  l = "\treturn num_errors;\n\n"
  l += "}\n\n"
  fo.write(l)
 
  fo.write(banner_end())
  fo.close()


###############################################################################
# 
###############################################################################


def test():
  """ 
  Simple test of some of the functions
  """

  # Read in the register list
  csrs = read_csv('csr_test.csv')
  #print csrs

  # generate verilog
  gen_regs_module('csr','my_csr.sv','template_csr.sv',csrs)
  gen_regs_instance('csr','my_csr.inst.sv',csrs)
  gen_regs_docs('csr','my_csr.md',csrs)
  gen_regs_python('csr','my_csr.py',csrs)
  gen_regs_cheader('csr','my_csr.h',csrs)
  gen_regs_ctest('csr',csrs)



def main():

  parser = argparse.ArgumentParser(description='Generate memory-mapped registers.')
  parser.add_argument('-u','--update', nargs='?', const='DEFAULT', type=str, help='Read in specified verilog file, find new registers and store back to CSV', required=False)
  parser.add_argument('-g','--generate', nargs='?', const='DEFAULT', help='Read in specified CSV and generate module and associated collateral.', required=False)
  parser.add_argument('-p','--prefix', default='DEFAULT', type=str, help='Specifies the prefix for signals.', required=False)
  parser.add_argument('-c','--csv', default='DEFAULT', type=str, help='Specifies the csv file.', required=False)
  parser.add_argument('-o','--output', default='output', help='Specifies an output directory', required=False)
  parser.add_argument('-clk','--clock', default='?clk', help='Specify the name of the clock in the instantiation template.', required=False)
  parser.add_argument('-rst','--reset', default='?rstn', help='Specify the name of the reset in the instantiation template.', required=False)
  args = parser.parse_args()
  if not (args.generate or args.update):
    parser.error('No action specified.  Please specify an action: --update or --generate')
  print 'Command line arguments: %s' + str(args)

  # Run scripts
  
  if (args.update):
    update_regs_csv_from_verilog(args.csv,args.update,match_prefix=args.prefix)
 
  if (args.generate):
    # Module name is derived from the CSV filename
    module = args.generate.split('.')[0]
    print module
    outdir = args.output

    # Read in the register list
    regs = read_csv(args.generate,debug=True)

    # generate verilog
    gen_regs_module(module,outdir+'/'+module+'.sv','regs_template.sv',regs)
    gen_regs_instance(module,outdir+'/'+module+'.inst.sv',regs,clock=args.clock,reset=args.reset)
    gen_regs_docs(module,outdir+'/'+module+'.md',regs)
    gen_regs_python(module,outdir+'/'+module+'.py',regs)
    gen_regs_cheader(module,outdir+'/'+module.upper()+'.h',regs)
    gen_regs_ctest(module,[outdir+'/'+module+'_test.h',outdir+'/'+module+'_test.c'],regs)


if __name__ == "__main__":
    main()


