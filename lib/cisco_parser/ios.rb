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

        match_schut = /^ shutdown$/.match(line)
        interface[:shutdown] = true if match_schut

        match_poe = /^ power inline never$/.match(line)
        interface[:poe] = false if match_poe

        if /^!$/.match(line)
          interfaces.push interface unless interface.empty?
          interface = {}
        end
      end
      interfaces
    end
  end
end
