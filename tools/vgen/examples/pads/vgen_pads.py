#!/usr/bin/env python

# vgen_pads.py - Generate verilog for pads
# Paul Whatmough Jan 2014
# Paul Whatmough Dec 2016
# Paul Whatmough April 2016


# TODO
# get rid of pd_pads.csv - didn't end up using it.


import time;
import re;
import shutil;
import os;
import sys;
import argparse;

from vgen import *;


# This is the minimum set of keys required for generating Verilog
pads_keys = [
    'name',       # logical name for pad
    'direction',  # direction: input or output
    'side'        # side of pad ring, 1-left, 2-top, 3-right, 4-bottom
  ]


# Templating
# TODO would be better to put all this into a better datastructure.

# IO cells names
in_cell =     'LIB_PAD'
out_cell =    in_cell
inout_cell =  in_cell

# Control signals for IO cells.
pad_control = [
  {'name': 'SC_PAD_ST', 'nbits': 1},
  {'name': 'SC_PAD_DS', 'nbits': 4},
  {'name': 'SC_PAD_SL', 'nbits': 1}
#  {'name': 'SC_PAD_RTE', 'nbits': 1}
]



###############################################################################
# Get signals
###############################################################################

# FIXME must check not only for new signals, but also for changes!
# FIXME also check csv for duplicate signals


def update_pads_csv_from_verilog(csv_file,verilog_file,pd_csv_file='',ignore_prefix=''):
  """
  Read in CSV and Verilog files,
  Any new signals found in Verilog that do not exist in CSV are added to CSV.
  Will warn about any signals found in CSV that do not exist in Verilog.
  Will wann about any signals found in verilog module port that are more than 1b wide.
  Ignores any signals with the specified prefix.
  Return True if any new signals were added to front-end csv.
  """
  # Read in list of io signals from CSV file
  print '** Reading csv_file: %s, and Verilog file: %s' % (csv_file,verilog_file)
  csv_vglist = read_csv(csv_file)  
  check_keys_exist(csv_vglist,pads_keys)

  # Remove pads from CSV that are not input, output or bidir (such as VDD / VSS etc).
  new_list = []
  for row in csv_vglist:
    if any(sig_dir in row['direction'] for sig_dir in ['input','output','bidir']):
      new_list.append(row)
  csv_vglist = new_list

  # Read in top-level verilog module file
  verilog_vglist = get_verilog_module_signals(verilog_file)
  
  # Remove signals that match ignore_prefix
  if ignore_prefix != '':
    new_list = []
    for row in verilog_vglist:
      if row['name'].startswith(ignore_prefix):
        print 'WARNING: Ignoring signal %s in Verilog module port, as it matches the ignore_prefix (%s).' % (row['name'],ignore_prefix)
      else:
        new_list.append(row)
    verilog_vglist = new_list

  # Should contain only single-bit signals
  check_field(verilog_vglist,'nbits',1)
  
  # collapse all signals for a bidir pad into a single entry and change direction type.
  # Remove all entries whose name contains "_PORTIN" or "_PORTOUT".
  # For entries whose name includes "_PORTEN", remove suffix and change direction to "bidir".
  new_list = []
  for row in verilog_vglist:
    if row['name'].endswith('_PORTIN'):
      print 'WARNING: Ignoring signal %s in Verilog module port, which is associated with a bidir pad.' % (row['name'])
    elif row['name'].endswith('_PORTOUT'):
      print 'WARNING: Ignoring signal %s in Verilog module port, which is associated with a bidir pad.' % (row['name'])
    elif row['name'].endswith('_PORTEN'):
      print 'Found bidir signal %s in Verilog module port.' % (row['name'])
      row['direction'] = 'bidir'
      row['name'] = row['name'][:-7]
      new_list.append(row)
    else:
      new_list.append(row)
  verilog_vglist = new_list
  
  # Remove nbits and start field
  verilog_vglist = remove_key(verilog_vglist,['nbits','start'])

  # Compare the two lists, keep signals that are in verilog and not in CSV
  new_in_verilog = find_new(csv_vglist,verilog_vglist,'name')
  
  #print 'csv_vglist: '+str([d['name'] for d in csv_vglist])
  #print 'verilog_vglist: '+str([d['name'] for d in verilog_vglist])

  # Compare the two lists, keep signals that are in CSV and not in Verilog
  missing_in_verilog = find_new(verilog_vglist,csv_vglist,'name')
  assert len(missing_in_verilog) == 0, \
    'WARNING: Found signals in CSV (%s) not in Verilog module port (%s): \n%s' % (csv_file,verilog_file,str(missing_in_verilog))

  # Write any new signals from Verilog back to the front-end CSV, and also PD CSV if specified
  if new_in_verilog != []: 
    print 'Found new signals in Verilog file (not listed in CSV):\n %s' % str([d['name'] for d in new_in_verilog])
    print 'Updating CSV file: %s' % csv_file
    append_csv(csv_file,new_in_verilog,pads_keys,unused_str='')
    if pd_csv_file != '':
      append_csv(pd_csv_file,new_in_verilog,pads_keys,unused_str='')
      print 'Updating CSV file: %s' % pd_csv_file
    else:
      print 'Nothing updated in CSV'

  # Return true if new signals were added to FE csv
  if new_in_verilog != []:
    return True
  else:
    return False


###############################################################################
# Generate Verilog PADS module - ASIC
###############################################################################

def gen_pads_module_asic(module_name,module_file,template_file,vglist):
  """ Generate an _PADS module from a template file and a signal vglist """
  assert check_keys_exist(vglist,pads_keys)
  
  # Find unused pad positions from vglist
  unused_pos=[68,68,68,68]
  for row in vglist:
    side = int(row['side'])
    unused_pos[(side-1)] -= 1

  # Open template
  fi_template = open(template_file,"r")
  
  # Open output file 
  if (os.path.isfile(module_file)):                   # if verilog already exists, backup first
    shutil.copy2(module_file,module_file+".bak")      # copy2 preserves mod/access info
  fo = open(module_file,"wb")
  print "** Writing module \""+module_name+"\" to file \""+fo.name+"\""
  fo.write(banner_start())

  # Print some header info into the generated file
  fo.write(read_to_tag(fi_template,"VGEN: HEADER"))

  # Module name
  fo.write(read_to_tag(fi_template,"VGEN: MODULE NAME"))
  fo.write(module_name+"\n")
 
  # Module declaration
  fo.write(read_to_tag(fi_template,"VGEN: MODULE DECLARATION"))
  for n, row in enumerate(vglist):
    if any(sig_dir in row['direction'] for sig_dir in ['input','output','bidir']):
      if n > 0:             # Nastyness to avoid trailing comma on last line.
        fo.write(',\n')
      if (row['direction'] == "input"):
        fo.write('input\twire\tPAD_'+row['name'])
      elif (row['direction'] == "output"):
        fo.write('output\twire\tPAD_'+row['name'])
      elif (row['direction'] == "bidir"):
        fo.write('inout\twire\tPAD_'+row['name'])

  # Add in un-used pad declaration
  for side in range(4):
    if unused_pos[side] > 0:
      if side != 3:
        unused_pad_num = unused_pos[side]
      else: 
        unused_pad_num = unused_pos[side] - 1
      for k in range(unused_pad_num):
        fo.write(',\n')
        fo.write('output\twire\tPAD_UNUSED_'+str(side+1)+'_'+str(k))

  # TOP signals
  fo.write(read_to_tag(fi_template,"VGEN: TOP LEVEL MODULE SIGNALS"))
  fo.write('\n// Control signals for IO cells.\n')
  for row in pad_control:
    if row['nbits'] == 1:
      fo.write('logic\t'+row['name']+';\n')
    elif row['nbits'] > 1:
      fo.write('logic\t'+'[' + str(int(row['nbits']) -1) +':0]\t' + row['name']+';\n')
  fo.write('\n// Signals from TOP to IO cells.\n')
  for row in vglist:
    if any(sig_dir in row['direction'] for sig_dir in ['input','output']):
      fo.write('logic\t'+row['name']+';\n')
    if row['direction'] == 'bidir':
      fo.write('logic\t'+row['name']+'_PORTEN;\n')
      fo.write('logic\t'+row['name']+'_PORTIN;\n')
      fo.write('logic\t'+row['name']+'_PORTOUT;\n')
      
  # TOP instantiation
  fo.write(read_to_tag(fi_template,"VGEN: TOP LEVEL MODULE INSTANTIATION"))
  fo.write('TOP uTOP (\n')
  fo.write('\n// Control signals for IO cells.\n')
  for row in pad_control:
    fo.write('.'+row['name'] + ',\n')
  fo.write('\n// Signals from TOP to IO cells.\n')
  for n, row in enumerate(vglist):
    if any(sig_dir in row['direction'] for sig_dir in ['input','output','bidir']):
      if n > 0:             # Nastyness to avoid trailing comma on last line.
        fo.write(',\n')
      if any(sig_dir in row['direction'] for sig_dir in ['input','output']):
        fo.write('.'+row['name'])
      elif row['direction'] == 'bidir':
        fo.write('.'+row['name']+'_PORTEN'+',\n')
        fo.write('.'+row['name']+'_PORTIN'+',\n')
        fo.write('.'+row['name']+'_PORTOUT')
  fo.write('\n);\n')

  # PAD instantiation
  fo.write('\n// NOTE: OEN pin in this cell is active LOW.  Hence inversion is included in instantiation.')
  fo.write(read_to_tag(fi_template,"VGEN: IO CELL INSTANTIATION"))
  fo.write('logic\tSC_PAD_RTE;\n')
  for n, row in enumerate(vglist):
    if (row['direction'] == 'input'):
      l = in_cell + '\t#(.DIRECTION("IN"),'
      if (row['side'] == '1') or (row['side'] == '3'):
        l += '.ORIENTATION("H")'
      elif (row['side'] == '2') or (row['side'] == '4'):
        l += '.ORIENTATION("V")'
      else:
        print 'WARNING: Side field not assigned for pad: %s' % row['name']
        l += '.ORIENTATION("H")'
      l += ')\tuPAD'+str(n)+'\t('
      l += '.PAD(PAD_'+row['name']+')'
      l += ',.OUT('+row['name']+')'
      l += ',.IN(1\'b0)'
      l += ',.OEN(1\'b1)'
      l += ',.DS(SC_PAD_DS),.SL(SC_PAD_SL),.ST(SC_PAD_ST),.RTE(SC_PAD_RTE));'
      l += '\t// ' + row['name'] + ': ' + row['description'] + '\n'
    elif (row['direction'] == 'output'):
      l = in_cell + '\t#(.DIRECTION("OUT"),'
      if (row['side'] == '1') or (row['side'] == '3'):
        l += '.ORIENTATION("H")'
      elif (row['side'] == '2') or (row['side'] == '4'):
        l += '.ORIENTATION("V")'
      else:
        print 'WARNING: Side field not assigned for pad: %s' % row['name']
        l += '.ORIENTATION("H")'
      l += ')\tuPAD'+str(n)+'\t('
      l += '.PAD(PAD_'+row['name']+')'
      l += ',.IN('+row['name']+')'
      l += ',.OUT()'
      l += ',.OEN(1\'b0)'
      l += ',.DS(SC_PAD_DS),.SL(SC_PAD_SL),.ST(SC_PAD_ST),.RTE(SC_PAD_RTE));'
      l += '\t// ' + row['name'] + ': ' + row['description'] + '\n'
    elif (row['direction'] == 'bidir'):
      l = in_cell + '\t#(.DIRECTION("BIDIR"),'
      if (row['side'] == '1') or (row['side'] == '3'):
        l += '.ORIENTATION("H")'
      elif (row['side'] == '2') or (row['side'] == '4'):
        l += '.ORIENTATION("V")'
      else:
        print 'WARNING: Side field not assigned for pad: %s' % row['name']
        l += '.ORIENTATION("H")'
      l += ')\tuPAD'+str(n)+'\t('
      l += '.PAD(PAD_'+row['name']+')'
      l += ',.IN(' + row['name'] + '_PORTOUT' + ')'
      l += ',.OUT(' + row['name'] + '_PORTIN' + ')'
      l += ',.OEN(~' + row['name'] + '_PORTEN' + ')'
      l += ',.DS(SC_PAD_DS),.SL(SC_PAD_SL),.ST(SC_PAD_ST),.RTE(SC_PAD_RTE));'
      l += '\t// ' + row['name'] + ': ' + row['description'] + '\n'
    else:
      pass    # Ignore VDD, VSS, etc
    fo.write(l)
  fo.write('\n')

  # Add io cell instantiations for un-used bumps
  fo.write('// Add Tied-off unused io-cells to fill out 272 bumps\n')
#  for side in range(4):
#    if len(unused_pos[side]) > 0:
#      for k in range(len(unused_pos[side])):
#        l = 'logic\tPAD_dummy'+str(side+1)+'_'+str(unused_pos[side][k])+';\n'
#        fo.write(l)
#    fo.write('\n')

  for side in range(4):
    if unused_pos[side] > 0:
      for k in range(unused_pos[side]):
        if side == 3 and k == (unused_pos[side]-1):
          fo.write('wire PAD_UNUSED_'+str(side+1)+'_'+str(k)+';\n')

        l = in_cell + '\t#(.DIRECTION("UNUSED"),'
        if ((side+1) == 1) or ((side+1) == 3):
          l += '.ORIENTATION("H")'
        elif ((side+1) == 2) or ((side+1) == 4):
          l += '.ORIENTATION("V")'
        l += ')\tuPAD_UNUSED_'+str(side+1)+'_'+str(k)+'\t('
        l += '.PAD(PAD_UNUSED_'+str(side+1)+'_'+str(k)+')'
        l += ',.IN(1\'b0)'
        l += ',.OUT()'
        l += ',.OEN(1\'b0)'
        l += ',.DS(SC_PAD_DS),.SL(SC_PAD_SL),.ST(SC_PAD_ST),.RTE(SC_PAD_RTE));'
        l += '\t// Unused tied-off IO Cell: Side'+str(side+1)+' Position'+str(k)+'\n'
        fo.write(l)
      fo.write('\n')
        
  
  # Retention Pad
  fo.write('// Retention Pad. NOTE: Retention mode is active high. Disabling retention by default\n')
  l = 'PAD_RET\tuPAD_rte\t('
  l += '.RTE(SC_PAD_RTE), '
  l += '.IRTE(1\'b0));'
  fo.write(l)
  fo.write('\n')

  # Rest of template
  fo.write(read_to_tag(fi_template,""))
  fo.write(banner_end())
  
  # Close files
  fo.close()
  fi_template.close()
  
###############################################################################
# Generate Verilog module instantiation (for testbench)
###############################################################################

# TODO clean this function up - hacked this in during tapeout
# TODO better to be two files, one with the signal instantiations and one with the module instantiation.


def gen_pads_instance_asic(module_name,instance_file,vglist):
  """ Generate an instantiation of _PADS module from a template file and a signal vglist """
  assert check_keys_exist(vglist,pads_keys)
  
#  # Find unused pad positions from vglist
#  used_pos=[]
#  for row in vglist:
#    side_pos = row['side'] + row['position']
#    used_pos.append(side_pos)
#
#  unused_pos = [[] for i in range(4)]
#  for side in range(4):
#    for k in range(68):
#      pos = str(side+1) + str(k+1)
#      if pos in used_pos:
#        pass
#      else:
#        unused_pos[side].append((k+1))
#
  # Open output file 
  if (os.path.isfile(instance_file)):               # if verilog already exists, backup first
    shutil.copy2(instance_file,instance_file+".bak")      # copy2 preserves mod/access info
  fo = open(instance_file,"wb")
  print "** Writing instantiation of \""+module_name+"\" to file \""+fo.name+"\""
  fo.write(banner_start())

  # Create a signal for each pin
  fo.write('// Signal declaration for each signal.\n')
  for n, row in enumerate(vglist):
    if any(sig_dir in row['direction'] for sig_dir in ['input','output','bidir']):
      if (row['direction'] == "bidir"):
        fo.write('wire\tPAD_'+row['name']+';\t\t// '+row['direction'].upper()+'\n')
      else:
        fo.write('logic\tPAD_'+row['name']+';\t\t// '+row['direction'].upper()+'\n')
  fo.write('\n')

  # Create a module instantiation
  fo.write('// Module instantiation.\n')
  fo.write(module_name+' u'+module_name+' (\n')
  for n, row in enumerate(vglist):
    if any(sig_dir in row['direction'] for sig_dir in ['input','output','bidir']):
      if n > 0:             # Nastyness to avoid trailing comma on last line.
        fo.write(',\n')
      fo.write('.PAD_'+row['name'])
  fo.write('\n);\n\n')
  
  # Create signal pullup for any bidir signals
  fo.write('// Pull-ups for bi-dir signals.\n')
  for n, row in enumerate(vglist):
    if (row['direction'] == 'bidir'):
      fo.write('pullup(PAD_'+row['name']+');\n')
  fo.write('\n')
  
  # Close files
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
  
  # Setup parser.
  parser = argparse.ArgumentParser(description='Generate everything required for pads.')
  parser.add_argument('-u','--update', nargs='?', const='../TOP.sv', type=str, help='Read in specified verilog file, find any new registers and add to CSV.', required=False)
  parser.add_argument('-g','--generate', nargs='?', const='TOP_PADS', type=str, help='Read in CSV and generate top-level module containing pads, with specified module name.', required=False)
  parser.add_argument('-c','--csv', default='pads.csv', type=str, help='Specifies the csv file.', required=False)
  parser.add_argument('-o','--output', default='output', help='Specifies an output directory.', required=False)
  #parser.add_argument('-c','--clock', default='?clk', help='Specify the name of the clock in the instantiation template.', required=False)
  #parser.add_argument('-r','--reset', default='?rstn', help='Specify the name of the reset in the instantiation template.', required=False)
  args = parser.parse_args()
  if not (args.generate or args.update):
    parser.error('No action specified.  Please specify an action: --update or --generate')
  print 'Command line arguments: %s' + str(args)

  # Run scripts.
  template_file = './pads_template.sv'
  verilog_file = args.update
  csv_file = args.csv
  pd_csv_file = 'pd_' + csv_file

  if (args.update):
    print args.update
    update_pads_csv_from_verilog(csv_file,verilog_file,pd_csv_file,ignore_prefix='SC_')

  if (args.generate):
    module_name = args.generate
    module_file = args.output + '/' + module_name + '.sv'
    instance_file = args.output + '/' + module_name + '_instance.sv'
    # Read in the pads list
    vglist = read_csv(csv_file,debug=False)
    # generate verilog
    gen_pads_module_asic(module_name,module_file,template_file,vglist)
    gen_pads_instance_asic(module_name,instance_file,vglist)


if __name__ == "__main__":
    main()


