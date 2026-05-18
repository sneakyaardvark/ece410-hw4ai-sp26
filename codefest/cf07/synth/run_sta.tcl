set LIB /home/andrew/.volare/volare/sky130/versions/0fe599b2afb6708d281543108caf8310912f54af/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
set NL  /home/andrew/repo/ece410-hw4ai-sp26/codefest/cf07/runs/synth_run2/final/nl/compute_core.nl.v
set SDC /home/andrew/repo/ece410-hw4ai-sp26/codefest/cf07/synth/compute_core.sdc

read_liberty $LIB
read_verilog $NL
link_design compute_core
read_sdc $SDC

report_checks -path_delay max -fields {slew cap input_pins nets} -format full_clock_expanded > /home/andrew/repo/ece410-hw4ai-sp26/codefest/cf07/synth/sta_setup.rpt
report_checks -path_delay min -fields {slew cap input_pins nets} -format full_clock_expanded > /home/andrew/repo/ece410-hw4ai-sp26/codefest/cf07/synth/sta_hold.rpt
report_wns  >> /home/andrew/repo/ece410-hw4ai-sp26/codefest/cf07/synth/sta_setup.rpt
report_tns  >> /home/andrew/repo/ece410-hw4ai-sp26/codefest/cf07/synth/sta_setup.rpt
report_worst_slack -max >> /home/andrew/repo/ece410-hw4ai-sp26/codefest/cf07/synth/sta_setup.rpt
report_worst_slack -min >> /home/andrew/repo/ece410-hw4ai-sp26/codefest/cf07/synth/sta_hold.rpt

puts "STA complete."
exit
