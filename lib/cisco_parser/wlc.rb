module CiscoParser
  class WLC
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

    def show_accesspoints(cmd = "show access-point-config")
      parse_accesspoints(command_output cmd)
    end

    def show_ap_inventory(cmd = "show ap inventory all")
      parse_ap_inventory(command_output cmd)
    end

    protected
    def get_hostname
      /.*\n\(([- \w]+)\) [>#]\n.*/.match(@io)[1]
    end

    def get_commands
      commands = []
      @io.each_line do |line|
        command = /^\(#{hostname}\) [>#]([\w |\-]+)$/m.match(line)
        commands.push command[1] if command
      end
      commands
    end

    def command_output(cmd)
      cmd_output = ''
      is_cmd_output = false

      @io.each_line do |line|
        is_cmd_output = false if (/^\(#{hostname}\) [>#][\w |]+$/m =~ line) == 0
        cmd_output += line if is_cmd_output
        is_cmd_output = true if (/^\(#{hostname}\) [>#]#{cmd}$/m =~ line) == 0
      end
      cmd_output
    end

    def parse_cdp(stream)
      neighbors = []
      neighbor = {}
      stream.each_line do |line|
        if /^-------------------------$/.match(line)
          neighbors.push neighbor unless neighbor.empty?
          neighbor = {}
        end
        match_hostname = /^Device ID: (.*)$/.match(line)
        neighbor[:hostname] = match_hostname[1].strip if match_hostname

        match_plat_cap = /^Platform: (?<platform>.*),  Capabilities: (?<capabilities>.*)$/m.match(line)
        if match_plat_cap
          neighbor[:platform] = match_plat_cap[:platform].strip
          neighbor[:capabilities] = match_plat_cap[:capabilities].strip
        end

        match_ifs = /^Interface: (?<interface>.*),  Port ID \(outgoing port\): (?<ne_interface>.*)$/m.match(line)
        if match_ifs
          neighbor[:interface] = match_ifs[:interface].strip
          neighbor[:ne_interface] = match_ifs[:ne_interface].strip
        end

        match_holdtime = /^Holdtime : (.*)$/m.match(line)
        neighbor[:holdtime] = match_holdtime[1].strip if match_holdtime

        #Version :
        #    Cisco IOS Software, Catalyst 4500 L3 Switch Software (cat4500e-IPBASEK9-M), Version 12.2(53)SG2, RELEASE SOFTWARE (fc1)
        #Technical Support: http://www.cisco.com/techsupport
        #Copyright (c) 1986-2010 by Cisco Systems, Inc.
        #    Compiled Tue 16-Mar-10 03:16 by prod_rel_team
        #
        match_cdp_version = /^advertisement version: (.*)$/.match(line)
        neighbor[:cdp_version] = match_cdp_version[1] if match_cdp_version

        match_vtp_domain = /^VTP Management Domain: (.*)$/.match(line)
        neighbor[:vtp_domain] = match_vtp_domain[1] if match_vtp_domain

        match_native_vlan = /^Native VLAN: (.*)$/.match(line)
        neighbor[:native_vlan] = match_native_vlan[1] if match_native_vlan

        match_duplex = /^Duplex: (.*)$/.match(line)
        neighbor[:duplex] = match_duplex[1] if match_duplex

        neighbor[:mgmt_address] = [] if neighbor[:mgmt_address].nil?
        match_ip_address = /^\s+IP address: (.*)$/.match(line)
        neighbor[:mgmt_address].push match_ip_address[1] if match_ip_address
        neighbor[:mgmt_address].uniq!

        #Power drawn: 15.400 Watts
        #Power request id: 36674, Power management id: 6
        #Power request levels are:15400 13000 0 0 0
      end
      neighbors.push neighbor
      neighbors
    end

    def parse_accesspoints(stream)
      aps = []
      ap = {}
      stream.each_line do |line|
        line.strip!
        match_name = /^Cisco AP Name\.+ (.*)$/.match(line)
        ap[:name] = match_name[1] if match_name

        match_mac_address = /^MAC Address\.+ (.*)$/.match(line)
        ap[:mac_address] = match_mac_address[1] if match_mac_address

        match_ip_address = /^IP Address\.+ (.*)$/.match(line)
        ap[:ip_address] = match_ip_address[1] if match_ip_address

        match_ip_mask = /^IP NetMask\.+ (.*)$/.match(line)
        ap[:ip_mask] = match_ip_mask[1] if match_ip_mask

        match_ip_gateway = /^Gateway IP Addr\.+ (.*)$/.match(line)
        ap[:ip_gateway] = match_ip_gateway[1] if match_ip_gateway

        match_location = /^Cisco AP Location\.+ (.*)$/.match(line)
        ap[:location] = match_location[1] if match_location

        match_wlc_primary = /^Primary Cisco Switch Name\.+ (.*)$/.match(line)
        ap[:wlc_primary] = match_wlc_primary[1].downcase if match_wlc_primary

        match_sw_version = /^S\/W  Version \.+ (.*)$/.match(line)
        ap[:sw_version] = match_sw_version[1] if match_sw_version

        match_model = /^AP Model\.+ (.*)$/.match(line)
        ap[:model] = match_model[1] if match_model

        match_serial_number = /^AP Serial Number\.+ (.*)$/.match(line)
        ap[:serial_number] = match_serial_number[1] if match_serial_number


        match_id = /^Cisco AP Identifier\.+ (.*)$/.match(line)
        if match_id
          aps.push ap unless ap.empty?
          ap = {}
        end
      end
      aps
    end

#Inventory for skfukrluap21

#NAME: "AP2800"    , DESCR: "Cisco Aironet 2800 Series (IEEE 802.11ac) Access Point"
#PID: AIR-AP2802E-E-K9,  VID: V03,  SN: FGL2131A3JS
		def parse_ap_inventory(stream)
      aps = []
      ap = {}
      stream.each_line do |line|
        line.strip!
        match_type_descr = /^NAME: \"(?<type>.*)\"\s+, DESCR: \"(?<description>.*)\"$/m.match(line)
        ap[:type] = match_type_descr[:type] if match_type_descr
        ap[:description] = match_type_descr[:description] if match_type_descr

        match_pid_vid_sn = /^PID: (?<product_id>.*),  VID: (?<version_id>.*),  SN: (?<serial_number>.*)$/m.match(line)
        ap[:product_id] = match_pid_vid_sn[:product_id] if match_pid_vid_sn
        ap[:version_id] = match_pid_vid_sn[:version_id] if match_pid_vid_sn
        ap[:serial_number] = match_pid_vid_sn[:serial_number] if match_pid_vid_sn

        match_hostname = /^Inventory for (.*)$/.match(line)
        if match_hostname
          aps.push ap unless ap.empty?
          ap = {}
          ap[:hostname] = match_hostname[1]

        end
      end
      aps
    end
  end
end
