.PHONY: bitstream project clean

bitstream: proj/rv-pc.runs/impl_1/m_main.bit

proj/rv-pc.runs/impl_1/m_main.bit: proj/rv-pc.xpr
	vivado -mode batch -source scripts/generate_bitstream.tcl

project: proj/rv-pc.xpr

proj/rv-pc.xpr:
	vivado -mode batch -source scripts/create_project.tcl

clean:
	rm -rf proj
	rm -rf vivado*
	rm -rf .Xil
