open_project proj/rv-pc.xpr
update_compile_order -fileset sources_1
launch_runs impl_1 -to_step write_bitstream -jobs [exec nproc]
wait_on_runs impl_1
exit
