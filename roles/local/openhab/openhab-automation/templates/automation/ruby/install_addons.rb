# file: conf/automation/ruby/install_addons.rb
# synopsis: Install marketplace/other addons upon system start @L40 (defined in addons.cfg with custom syntax).

CFG_FILE = '{{ openhab_conf_dir }}/services/addons.cfg'
iniLines = nil


def readIni(key, iniFile=CFG_FILE)
  logger.debug "Reading addons.cfg and return \"#{key}\" items"
  # Extract the requested entry line from `conf/services/addons.cfg`
  iniLines = IO.readlines(iniFile) if iniLines.nil?
  if lineIndex = iniLines.index{ |line| line =~ /^#{key}/ } then
    return iniLines[lineIndex].split('=')[1].strip
  end
  return nil
end


def httpAction(httpRequest, httpUrl, httpBody=nil)
  logger.debug "Sending HTTP #{httpRequest} to #{httpUrl} with body \"#{httpBody}\""
  # Create the HTTP object
  uri = URI.parse(httpUrl)
  header = {'Content-Type': 'application/json', 'Accept': '*/*', 'X-OPENHAB-TOKEN': '{{ openhab_api_token }}'}
  http = Net::HTTP.new(uri.host, uri.port)
  request = httpRequest.downcase == "put" ? Net::HTTP::Put.new(uri.request_uri, header) : Net::HTTP::Post.new(uri.request_uri, header)
  request.body = httpBody unless httpBody.nil?
  response = http.request(request)
  logger.warn "Result #{response.code} (#{response.body}) - installing service/add-on @ #{httpUrl} failed" unless response.code == "200"
  return true ? response.code == "200" : false
end


rule "InstallAddons" do
  description "Install marketplace add-ons at system start"
  on_start at_level: 40
  run do
    # Extract the marketplace add-ons entry from the ini file
    addons = readIni("marketplace")
    logger.info "Install Marketplace add-ons (defined in addons.cfg) at system start"
    unless addons.nil?
      addons.split("|").each do |addon|
        addonName, addonType, addonId = addon.split(",")
        addonName = addonName.strip
        addonType = addonType.strip.downcase
        addonId = addonId.strip
        #TODO: Check for ill-formatted entries
        logger.info "Install addon \"#{addonName}\" from #{addonType == "marketplace" ? "Community Marketplace" : "Other Add-ons"}"
        result = httpAction("POST", "{{ openhab_api_url }}/addons/#{addonType}:#{addonId}/install?serviceId=#{addonType}")
        #TODO: Add check if addon is actually installed (async)
      end
    end
    logger.info "All 3rd party addons are installed" # This string is used to check the logfile
  end
end
