"""Use this profile to spin up a build machine in OCT."""

import geni.portal as portal
import geni.rspec.pg as pg
import geni.rspec.emulab as emulab

# Create a Request object to start building the RSpec.
pc = portal.Context()
request = pc.makeRequestRSpec()

RAM = [16, 32, 64]
CPU = [2, 4, 8]
toolVersion = ['2023.2', '2023.1'] 

pc.defineParameter("RAM",  "RAM (GB)",
                   portal.ParameterType.INTEGER, RAM[0], RAM,
                   longDescription="RAM")

pc.defineParameter("CPU",  "No: of VCPUs",
                   portal.ParameterType.INTEGER, CPU[0], CPU,
                   longDescription="No: of VCPUs")

pc.defineParameter("toolVersion", "Tool Version",
                   portal.ParameterType.STRING,
                   toolVersion[0], toolVersion,
                   longDescription="Select the tool version.")    

pc.defineParameter("remoteDesktop", "Remote Desktop Access",
                   portal.ParameterType.BOOLEAN, True,
                   advanced=False,
                   longDescription="Enable remote desktop access by installing GNOME desktop and VNC server.")

params = pc.bindParameters() 
 
# Create a XenVM

node = request.XenVM('fpga-tools',exclusive=False)
node.component_manager_id = "urn:publicid:IDN+cloudlab.umass.edu+authority+cm"
#node.disk_image = params.diskImage
node.disk_image = "urn:publicid:IDN+emulab.net+image+emulab-ops//UBUNTU20-64-STD" // alveo-2023.1-ubuntu-22.04
node.setFailureAction('nonfatal')
node.Desire("FPGA-Build-Pool", 1.0)

# Request a specific number of VCPUs.
node.cores = params.CPU

# Request a specific amount of memory (in MB).

node.ram = 1024 * params.RAM
#node.ram = 1024

node.addService(pg.Execute(shell="bash", command="sudo /local/repository/post-boot.sh " + str(params.remoteDesktop) + " " + params.toolVersion + " >> /local/logs/output_log.txt"))  

# Print the RSpec to the enclosing page.
portal.context.printRequestRSpec()
