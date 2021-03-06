require "net/http"
require "uri"
require "rexml/document"
require "rexml/xpath"

#
# Helper functions
#
def get_s3_dirlist url
  uri = URI.parse("#{url}?prefix=influxdb")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE
  request = Net::HTTP::Get.new(uri.request_uri)
  response = http.request(request)
  response.body
end

def get_package_files xmldata
  packages = []
  suffix = get_package_suffix()
  xml = REXML::Document.new(xmldata)
  xml.elements.each('ListBucketResult/Contents/Key') do |k|
    packages << k.text if k.text =~ /.*#{suffix}$/
  end
  packages
end

def get_package_suffix
  case lookupvar("osfamily").downcase
  when "redhat"
    if lookupvar("hardwaremodel") =~ /64/
      "x86_64.rpm"
    else
      "i686.rpm"
    end
  when "debian"
    if lookupvar("hardwaremodel") =~ /64/
      "amd64.deb"
    else
      "i686.deb"
    end
  end
end

def version_extract n
  n.gsub(/^influxdb(_|\-)(.*)(_|\-|\.)(x86|i686|i386|amd64).*/, '\2')
end

def compare a, b
  a_version = version_extract(a)
  b_version = version_extract(b)
  function_versioncmp([a_version, b_version])
end

def get_single_package packages, include_rc, include_nightly, version
  if version =~ /^[a-zA-Z]+$/
    packages_sorted = packages.select { |p|
      case p
      when /^influxdb[_\-](nightly|[0-9])/
        case p
        when /rc/
          include_rc
        when /nightly/
          include_nightly
        else
          true
        end
      else
        false
      end
    }.sort { |a, b| compare(a,b) }
  else
    packages_sorted = packages.select { |p|
      version_extract(p) == version
    }.sort { |a, b| compare(a,b) }
  end
  packages_sorted[-1]
end

#
# Actual Puppet custom function
#
module Puppet::Parser::Functions
  newfunction(:influxdb_download_url, :type => :rvalue, :doc => "
  Retrieves the latest or specific version from the Amazon S3 bucket that the InfluxDB
  team deploys packages to

  Relies on puppet built-in function versioncmp for version comparison

  Prototype:

    $url = influxdb_download_url(a, b, c)

    Where a is a boolean indicating that release candidates can be used
    Where b is a boolean indicating that nightly builds can be used
    Where c is version or ensure value like 'present' or 'latest'

  ") do |args|
    include_rc = args[0]
    include_nightly = args[1]
    version = args[2]
    raise Puppet::ParseError, "do not set boolean options to true if pinning specific version" if version !~ /^[a-zA-Z]+$/ and (include_rc or include_nightly)
    xml_data = get_s3_dirlist("https://s3.amazonaws.com/influxdb/")
    all_packages = get_package_files(xml_data)
    package = get_single_package(all_packages, include_rc, include_nightly, version)
    raise Puppet::ParseError, "could not find any package matching criteria" if package == nil
    "https://s3.amazonaws.com/influxdb/#{package}"
  end
end
