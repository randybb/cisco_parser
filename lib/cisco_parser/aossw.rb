module CiscoParser
  class AOSSW # ArubaOS-Switch
    def initialize(io)
      @io = io
      @hostname = get_hostname
      @commands = get_commands
    end

    def hostname
      @hostname
    end

    def commands
      @commands
    end

		def show_modules(cmd = "sh modules")
			parse_modules(command_output cmd)
		end

		def show_stacking(cmd = "sh stacking")
			parse_stacking(command_output cmd)
		end

		def show_transceivers(cmd = "sh interface transceiver")
			parse_transceivers(command_output cmd)
		end

    protected
    def get_hostname
      /.*\n([-\w]+)[>#] *\n.*/.match(@io)[1]
    end

    def get_commands
      commands = []
      @io.each_line do |line|
        command = /^#{hostname}[>#] *([\w |]+)$/m.match(line)
        commands.push command[1] if command
      end
      commands
    end

    def command_output(cmd)
      cmd_output = ''
      is_cmd_output = false

      @io.each_line do |line|
        is_cmd_output = false if (/^#{hostname}[>#][\w |]+$/m =~ line) == 0
        cmd_output += line if is_cmd_output
        is_cmd_output = true if (/^#{hostname}[>#] ?#{cmd}$/m =~ line) == 0
      end
      cmd_output
    end

		def parse_modules(stream)
			modules = []

			stream.each_line do |line|
#  ID     Slot     Module Description                  Serial Number    Status
#  ------ -------- ----------------------------------- ---------------- -------
#  1      Stack... HP J9733A 2-port Stacking Module    SG6AFM306B       Up
				match_module = /^  (?<id>.{6}) (?<slot>.{8}) (?<description>.{35}) (?<serial_number>.{16}) (?<status>.{7})$/m.match(line)
				if match_module
					mod = {}
					mod[:id] = match_module[:id].strip.to_i
					if mod[:id] != 0
						mod[:slot] = match_module[:slot].strip
						mod[:description] = match_module[:description].strip
						mod[:part_number] = mod[:description].match(/^HP (?<part_number>\w+) /)[:part_number]
						mod[:serial_number] = match_module[:serial_number].strip
						mod[:status] = match_module[:status].strip

						modules.push mod
					end
				end
			end
			modules
		end

		def parse_stacking(stream)
			members = []
			member = {}

			stream.each_line do |line|
# Mbr
# ID  Mac Address   Model                                  Pri Status
# --- ------------- -------------------------------------- --- ---------------
#  1  9cdc71-f60f00 HP J9728A 2920-48G Switch              128 Commander
				match_member = /^ (?<id>.{3}) (?<mac_address>.{13}) (?<model>.{38}) (?<priority>.{3}) (?<status>.{15})$/m.match(line)
				if match_member
					member = {}
					member[:id] = match_member[:id].strip.to_i
					if member[:id] != 0
						member[:mac_address] = match_member[:mac_address].strip.gsub("-", "")
						member[:model] = match_member[:model].strip
						member[:part_number] = member[:model].match(/^HP (?<part_number>\w+) /)[:part_number]
						member[:priority] = match_member[:priority].strip.to_i
						member[:status] = match_member[:status].strip

						members.push member
					end
				end
			end
			members
		end

		def parse_transceivers(stream)
			transceivers = []

			stream.each_line do |line|
#                     Product      Serial             Part
# Port    Type        Number       Number             Number
# ------- ----------- ------------ ------------------ ----------
# 1/47    1000SX      J4858C       CN73HGMCMH         1990-4415

				match_transceiver = /^ (?<port>.{7}) (?<type>.{11}) (?<product_number>.{12}) (?<serial_number>.{18}) (?<part_number>.{10})$/m.match(line)
				if match_transceiver
					transceiver = {}
					transceiver[:port] = match_transceiver[:port].strip
					transceiver[:type] = match_transceiver[:type].strip
					transceiver[:part_number] = match_transceiver[:product_number].strip
					transceiver[:serial_number] = match_transceiver[:serial_number].strip
					# transceiver[:part_number] = match_transceiver[:part_number].strip

					transceivers.push transceiver
					transceivers = [] if transceiver[:port] == "-------"
				end
			end
			transceivers
    end

		def parse_powersupply(stream)
			power = []

			stream.each_line do |line|
#  Member  PS#   Model     Serial      State           AC/DC  + V        Wattage   Max
#  ------- ----- --------- ----------- --------------- ----------------- --------- ------
#  1       1     JL085A    CN77GZ82MT  Powered         AC 120V/240V        74       250
#  1       2                           Not Present     -- ---------         0         0
#  2       1                           Not Present     -- ---------         0         0
#  2       2     JL085A    CN7AGZ80VW  Powered         AC 120V/240V        73       250

				match_psu = /^ (?<member>.{7}) (?<psu>.{5}) (?<mode>.{9}) (?<serial>.{11}) (?<state>.{15} (?<ac_dc_v>.{17}) (?<wattage>.{9}) (?<max>.{6}))$/m.match(line)
				if match_psu
					psu = {}
					psu[:member] = match_psu[:member].strip
					psu[:psu] = match_psu[:psu].strip
					psu[:part_number] = match_psu[:model].strip
					psu[:serial_number] = match_psu[:serial].strip
					psu[:state] = match_psu[:state].strip
					psu[:ac_dc] = match_psu[:ac_dc_v].strip.split[0]
					psu[:voltage] = match_psu[:ac_dc_v].strip.split[1]
					psu[:wattage] = match_psu[:wattage].strip
					psu[:wattage_max] = match_psu[:max].strip

					psus.push psu
					psus = [] if psu[:state] == "Not Present"
				end
			end
			psus
		end
  end
end
