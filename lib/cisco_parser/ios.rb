module CiscoParser
  class IOS
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

    def show_cdp(cmd = "show cdp neighbors detail")
      parse_cdp(command_output cmd)
    end

    def show_etherchannels(cmd = "show etherchannel summary")
      parse_etherchannels(command_output cmd)
    end

    def show_interfaces(cmd = "show configuration")
      parse_interfaces(command_output cmd)
    end

    def show_if_transceiver(cmd = "show interface transceiver")
      parse_if_transceiver(command_output cmd)
    end

    protected
    def get_hostname
      /.*\n([\w-]+)[>#]\n.*/.match(@io)[1]
    end

    def get_commands
      commands = []
      @io.each_line do |line|
        command = /^#{hostname}[>#]([\w |]+)$/m.match(line)
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
        is_cmd_output = true if (/^#{hostname}[>#]#{cmd}$/m =~ line) == 0
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

        match_ifs = /^Interface: (?<src_interface>.*),  Port ID \(outgoing port\): (?<interface>.*)$/m.match(line)
        if match_ifs
          neighbor[:interface] = match_ifs[:interface].strip
          neighbor[:interface_abbr] = abbr_ifs match_ifs[:interface].strip
          neighbor[:src_interface] = match_ifs[:src_interface].strip
          neighbor[:src_interface_abbr] = abbr_ifs match_ifs[:src_interface].strip
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

    def abbr_ifs(string)
      replacement_strings = [
          %w(FastEthernet Fa),
          %w(GigabitEthernet Gi),
          %w(TenGigabitEthernet Te),
          %w(Port-channel Po),
          %w(Vlan Vl),
          %w(LAGInterface LAG)
      ]
      replacement_strings.each do |from, to|
        string.gsub!(from, to)
      end
      string
    end

    def parse_etherchannels(stream)
      pos = []
      ports = []
      stream.each_line do |line|
        # this will match only interfaces bundled to Po...
        next_ports_regex = /^[\s]+(?<ports>[\w\/]+\([\w]?\).*)[\s]+$/m.match(line)
        unless next_ports_regex.nil?
          next_ports_raw = next_ports_regex[:ports].split(' ')
          next_ports_raw.each do |port_raw|
            port_regex = /^(?<name>[\w\/]+)\((?<flag>[\w]*)\)$/m.match(port_raw)
            ports << {name: port_regex[:name], flag_id: port_regex[:flag], flag_name: po_flag_value(port_regex[:flag])}
          end
        end
        if /Po[\d]+/.match(line)
          # ... and there are added to pos with previous po
          unless ports.empty?
            pos << {id: @po[:id], name: @po[:name], flags: @flags, protocol: @po[:protocol], ports: ports}
            ports = []
          end

          @po = /^(?<id>[\d]+)[\s]+(?<name>Po[\d]+)\((?<flags>[\w]+)\)[\s]+(?<protocol>[\w-]+)[\s]+(?<ports>.*)[\s]+$/m.match(line)
          unless @po.nil?
            @flags = @po[:flags].scan(/./).map { |flag| {id: flag, name: po_flag_value(flag)} }
            ports_raw = @po[:ports].split(" ")
            ports_raw.each do |port_raw|
              port_regex = /^(?<name>[\w\/]+)\((?<flag>[\w]*)\)$/m.match(port_raw)
              ports << {name: port_regex[:name], flag_id: port_regex[:flag], flag_name: po_flag_value(port_regex[:flag])}
            end
          end
        end
      end
      begin
        pos << {id: @po[:id], name: @po[:name], flags: @flags, protocol: @po[:protocol], ports: ports}
      rescue
        nil
      end
      pos
    end

    def po_flag_value(string)
      mapping = {
          D: 'down',
          P: 'bundled in port-channel',
          I: 'stand-alone',
          s: 'suspended',
          H: 'Hot-standby (LACP only)',
          R: 'Layer3',
          S: 'Layer2',
          U: 'in use',
          f: 'failed to allocate aggregator',
          M: 'not in use, minimum links not met',
          u: 'unsuitable for bundling',
          w: 'waiting to be aggregated',
          d: 'default port'
      }
      mapping[:"#{string}"]
    end

    def parse_interfaces(stream)
      interfaces = []
      interface = {}
      stream.each_line do |line|
        match_ifname = /^interface (.*)$/.match(line)
        if match_ifname
          interface[:name] = match_ifname[1]
          interface[:name_abbr] = abbr_ifs match_ifname[1]
        end

        match_desc = /^ description (.*)$/m.match(line)
        interface[:desc] = match_desc[1].strip if match_desc

        match_sw_mode = /^ switchport mode (.*)$/m.match(line)
        interface[:mode] = match_sw_mode[1].strip if match_sw_mode

        match_sw_access = /^ switchport access vlan (.*)$/m.match(line)
        interface[:access_vlan] = match_sw_access[1].strip if match_sw_access

        match_sw_voice = /^ switchport voice vlan (.*)$/m.match(line)
        interface[:voice_vlan] = match_sw_voice[1].strip if match_sw_voice

        match_sw_trunk_native = /^ switchport trunk native vlan (.*)$/m.match(line)
        interface[:trunk_native_vlan] = match_sw_trunk_native[1].strip if match_sw_trunk_native

        match_sw_trunk_allowed = /^ switchport trunk allowed vlan (.*)$/m.match(line)
        interface[:trunk_allowed_vlan] = match_sw_trunk_allowed[1].strip if match_sw_trunk_allowed

        match_port_channel = /^ channel-group (?<number>[\d]+)( mode (?<mode>.*))$/m.match(line)
        interface[:port_channel] = 'Port-channel' + match_port_channel[:number].strip if match_port_channel

        match_ipv4_address = /^ ip address (?<ip>[\d]{,3}\.[\d]{,3}\.[\d]{,3}\.[\d]{,3}) (?<mask>[\d]{,3}\.[\d]{,3}\.[\d]{,3}\.[\d]{,3})(?<sec> secondary)?$/m.match(line)
        if match_ipv4_address
          interface[:ipv4] = [] if interface[:ipv4].nil?
          primary_addr = match_ipv4_address[:sec].nil? ? true : false
          ipv4_address = {address: match_ipv4_address[:ip].strip, mask: match_ipv4_address[:mask].strip, primary: primary_addr}
          interface[:ipv4].push ipv4_address
        end

        match_shut = /^ shutdown$/.match(line)
        interface[:shutdown] = true if match_shut

        match_poe = /^ power inline never$/.match(line)
        interface[:poe] = false if match_poe

        match_dhcp_snooping = /^ ip dhcp snooping (\w+)( (.+))?$/.match(line)
        unless match_dhcp_snooping.nil?
          interface[:dhcp_snooping] = {} if interface[:dhcp_snooping].nil?
          key = match_dhcp_snooping[1]
          value = match_dhcp_snooping[3].nil? ? true : match_dhcp_snooping[3]
          interface[:dhcp_snooping].merge! Hash[key, value]
        end

        if /^!$/.match(line)
          interfaces.push interface unless interface.empty?
          interface = {}
        end
      end
      interfaces
    end
#skfukrlusw02-01#show interface transceiver
#If device is externally calibrated, only calibrated values are printed.
#++ : high alarm, +  : high warning, -  : low warning, -- : low alarm.
#NA or N/A: not applicable, Tx: transmit, Rx: receive.
#mA: milliamperes, dBm: decibels (milliwatts).
#
#                                           Optical   Optical
#           Temperature  Voltage  Current   Tx Power  Rx Power
#Port       (Celsius)    (Volts)  (mA)      (dBm)     (dBm)
#---------  -----------  -------  --------  --------  --------
#Gi1/1/3      22.5       3.27       2.7      -6.3      -6.3
#Gi1/1/4      21.7       3.30       2.5      -6.4      -5.8
#Gi2/1/3      22.9       3.28       2.8      -5.8      -6.8
#Gi2/1/4      23.2       3.27       2.5      -6.1      -6.2
    def parse_if_transceiver(stream)
      transceivers = []
      stream.each_line do |line|
        transceiver = {}
        match_if_transceiver = /^(?<interface>[\w\/]+)[\s]+(?<temperature>[\d\.\-]+)[\s]+(?<voltage>[\d\.\-]+)[\s]+(?<current>[\d\.\-]+)[\s]+(?<tx_power>[\d\.\-]+)[\s]+(?<rx_power>[\d\.\-]+)\s+$/m.match(line)
        if match_if_transceiver
          transceiver[:interface] = match_if_transceiver[:interface].strip
          transceiver[:temperature] = match_if_transceiver[:temperature].to_f
          transceiver[:voltage] = match_if_transceiver[:voltage].to_f
          transceiver[:current] = match_if_transceiver[:current].to_f
          transceiver[:tx_power] = match_if_transceiver[:tx_power].to_f
          transceiver[:rx_power] = match_if_transceiver[:rx_power].to_f
        end
        transceivers.push transceiver unless transceiver.empty?
      end
      transceivers
    end
  end
end
