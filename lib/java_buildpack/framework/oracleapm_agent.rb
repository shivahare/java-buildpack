# frozen_string_literal: true

# Cloud Foundry Java Buildpack
# Copyright 2013-2018 the original author or authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'java_buildpack/component/versioned_dependency_component'
require 'java_buildpack/framework'

module JavaBuildpack
  module Framework

    # Encapsulates the functionality for enabling zero-touch Oracle APM Agent support.
    class OracleapmAgent < JavaBuildpack::Component::VersionedDependencyComponent

      # Creates an instance
      #
      # @param [Hash] context a collection of utilities used the component
      def initialize(context)
        super(context)
        # @version, @uri = agent_download_url if supports?
      end

      # Download Agent URL
      def agent_download_url
        credentials = @application.services.find_service(FILTER)['credentials']
        agent_uri = credentials[AGENT_ZIP_URI]
        ['latest', agent_uri]
      end

      # (see JavaBuildpack::Component::BaseComponent#compile)
      def compile
        credentials = @application.services.find_service(FILTER)['credentials']

        # download APM agent zip file
        download_zip false
        # expect(@droplet.sandbox + "ProvisionApmJavaAsAgent.sh").to exist
        # expect(@droplet.sandbox + "apmagent/lib/system/ApmAgentInstrumentation.jar").to exist
        # Run apm provisioning script to install agent
        inputmap = create_map_with_variables(credentials)
        run_apm_provision_script(inputmap)
        cert = credentials[CERTIFICATE]
        validate_cert_not_blank(cert)

        no_certificate = credentials[TRUST_HOST]
        validate_no_certificate(no_certificate)

        add_startup_props = credentials[STARTUP_PROPERTIES]
        validate_startup_props(add_startup_props)

        # shell "rm -rf oracle"
      end

      # Create map with env variables
      def create_map_with_variables(credentials)
        { 'tenantid' => credentials[TENANT_ID], 'regkey' => credentials[REGKEY],
          'omcurl' => credentials[OMC_URL], 'gatewayh' => credentials[GATEWAY_HOST],
          'gatewayp' => credentials[GATEWAY_PORT], 'proxyhost' => credentials[PROXY_HOST],
          'proxyport' => credentials[PROXY_PORT], 'classifications' => credentials[CLASSIFICATIONS],
          'proxyauthtoken' => credentials[PROXY_AUTH_TOKEN],
          'additionalgateway' => credentials[ADDITIONAL_GATEWAY], 'v' => credentials[V],
          'debug' => credentials[DEBUG], 'insecure' => credentials[INSECURE],
          'h' => credentials[H] }
      end

      # Validate the certificate is not blank
      def validate_cert_not_blank(cert)
        # use user specified certificates
        return unless not_blank?(cert)
        target_directory = @droplet.sandbox
        agent_startup = "#{target_directory}/apmagent/config/AgentStartup.properties"
        apm_cert = "#{target_directory}/apmagent/config/apm.cer"
        shell "echo  -----BEGIN CERTIFICATE----- > #{apm_cert}"
        shell "echo  #{cert} >> #{apm_cert}"
        shell "echo  -----END CERTIFICATE----- >> #{apm_cert}"
        shell 'echo oracle.apmaas.common.pathToCertificate = ./apm.cer >> ' + agent_startup
      end

      # Validate the certificate is not null
      def validate_no_certificate(no_certificate)
        return unless not_null?(no_certificate)
        target_directory = @droplet.sandbox
        agent_startup = "#{target_directory}/apmagent/config/AgentStartup.properties"
        shell 'echo oracle.apmaas.common.trustRemoteSSLHost = true >> ' + agent_startup
        shell 'echo oracle.apmaas.common.disableHostnameVerification = true >> ' + agent_startup
      end

      # Validate the add startup properties
      def validate_startup_props(add_startup_props)
        return unless not_blank?(add_startup_props)
        target_directory = @droplet.sandbox
        agent_startup = "#{target_directory}/apmagent/config/AgentStartup.properties"
        add_startup_props.split(',').each do |property|
          shell "echo #{property} >> " + agent_startup
        end
      end

      # Run the provision script
      def run_apm_provision_script(name_parts = {},
                                   target_directory = @droplet.sandbox,
                                   name = @component_name)
        print_log(target_directory, name, name_parts)
        log_proxy_gateway_info(name_parts)
        log_misc_info(name_parts)
        log_additional_info(name_parts)
        provision_cmd = StringIO.new
        build_provision_cmd(provision_cmd, target_directory, name_parts)
        build_provision_cmd_second(provision_cmd, name_parts)
        build_provision_cmd_third(provision_cmd, name_parts)
        build_provision_cmd_fourth(provision_cmd, name_parts)
        build_provision_cmd_fifth(provision_cmd, target_directory, name_parts)

        puts "command : #{provision_cmd.string}"
        Dir.chdir target_directory do
          # shell "#{target_directory}/ProvisionApmJavaAsAgent.sh -regkey #{regkey} -no-wallet
          # -ph #{proxy_host} -d #{target_directory} -exact-hostname -no-prompt -omc-server-url
          #  #{omc_url} -tenant-id  #{tenant_id} -java-home #{@droplet.java_home.root} 2>&1"
          java_bin = "JAVA_BIN=#{@droplet.java_home.root}/bin/java"
          # puts " java : #{java_bin}"
          shell "echo #{java_bin} > ProvisionApmJavaAsAgent_CF.sh"
          # shell "sed -e 's/locate_java$/#locate_java/g' ProvisionApmJavaAsAgent.sh > ProvisionApmJavaAsAgent_tmp.sh"
          # shell "sed -e 's/^_java=/_java=$JAVA_BIN/g' ProvisionApmJavaAsAgent_tmp.sh >> ProvisionApmJavaAsAgent_CF.sh"
          # shell 'rm ProvisionApmJavaAsAgent_tmp.sh'
          # shell 'cat ProvisionApmJavaAsAgent.sh >> ProvisionApmJavaAsAgent_CF.sh'
          copy_content('ProvisionApmJavaAsAgent.sh', 'ProvisionApmJavaAsAgent_CF.sh')
          shell 'chmod +x ProvisionApmJavaAsAgent_CF.sh'
          shell provision_cmd.to_s
        end
      end

      # Print log
      def print_log(target_directory,
                    name,
                    nv = {})
        # shell "chmod +x #{target_directory}/ProvisionApmJavaAsAgent.sh"
        puts "check = #{target_directory}"
        puts "component name = #{name}"
        puts 'tenant_id : ' + nv.fetch('tenantid') if not_null?(nv.fetch('tenantid'))
        puts 'reg_key : ' + nv.fetch('regkey') if not_null?(nv.fetch('regkey'))
        puts 'omc_url : ' + nv.fetch('omcurl') if not_null?(nv.fetch('omcurl'))
      end

      # Insert log
      def log_proxy_gateway_info(nv = {})
        puts 'gateway_host : ' + nv.fetch('gatewayh') if not_null?(nv.fetch('gatewayh'))
        puts 'gateway_port : ' + nv.fetch('gatewayp') if not_null?(nv.fetch('gatewayp'))
        puts 'proxy_host : ' + nv.fetch('proxyhost') if not_null?(nv.fetch('proxyhost'))
        puts 'proxy_port : ' + nv.fetch('proxyport') if not_null?(nv.fetch('proxyport'))
      end

      # Insert log
      def log_misc_info(nv = {})
        puts 'classifications : ' + nv.fetch('classifications') if not_null?(nv.fetch('classifications'))
        puts 'proxy_auth_token : ' + nv.fetch('proxyauthtoken') if not_null?(nv.fetch('proxyauthtoken'))
        puts 'additional_gateways : ' + nv.fetch('additionalgateway') if not_null?(nv.fetch('additionalgateway'))
        puts "java_home : #{@droplet.java_home.root}"
      end

      # Insert log
      def log_additional_info(nv = {})
        puts 'v : ' + nv.fetch('v') if not_null?(nv.fetch('v'))
        puts 'h : ' + nv.fetch('h') if not_null?(nv.fetch('h'))
        puts 'debug : ' + nv.fetch('debug') if not_null?(nv.fetch('debug'))
        puts 'insecure : ' + nv.fetch('insecure') if not_null?(nv.fetch('insecure'))
      end

      # Insert log
      def build_provision_cmd(provision_cmd, target_directory,
                              nv = {})
        puts 'entered build provision cmd'
        provision_cmd << "#{target_directory}/ProvisionApmJavaAsAgent_CF.sh -regkey " + nv.fetch('regkey') +
" -no-wallet -d #{target_directory} -exact-hostname -no-prompt"
        provision_cmd << ' -tenant-id ' + nv.fetch('tenantid') if not_blank?(nv.fetch('tenantid'))
        provision_cmd << ' -omc-server-url ' + nv.fetch('omcurl') if not_blank?(nv.fetch('omcurl'))
        puts 'exit build provision cmd'
      end

      # Insert log
      def build_provision_cmd_second(provision_cmd, nv = {})
        puts 'entered build provision cmd second'
        provision_cmd << ' -gateway-host ' + nv.fetch('gatewayh') if not_blank?(nv.fetch('gatewayh'))
        provision_cmd << ' -gateway-port ' + nv.fetch('gatewayp') if not_blank?(nv.fetch('gatewayp'))
        provision_cmd << ' -ph ' + nv.fetch('proxyhost') if not_blank?(nv.fetch('proxyhost'))
        puts 'exit build provision cmd second'
      end

      # Insert log
      def build_provision_cmd_third(provision_cmd, nv = {})
        puts 'entered build provision cmd third'
        provision_cmd << ' -pp ' + nv.fetch('proxyport') if not_blank?(nv.fetch('proxyport'))
        provision_cmd << ' -classifications ' + nv.fetch('classifications') if not_blank?(nv.fetch('classifications'))
        provision_cmd << ' -pt ' + nv.fetch('proxyauthtoken') if not_blank?(nv.fetch('proxyauthtoken'))
        puts 'exit build provision cmd third'
      end

      # Insert log
      def build_provision_cmd_fourth(provision_cmd, nv = {})
        puts 'entered  build provision cmd fourth'
        gateway = nv.fetch('additionalgateway')
        provision_cmd << " -additional-gateways #{gateway}" if not_blank?(nv.fetch('additionalgateway'))
        provision_cmd << ' -h ' + nv.fetch('h') if not_blank?(nv.fetch('h'))
        puts 'exit build provision cmd fourth'
      end

      # Insert log
      def build_provision_cmd_fifth(provision_cmd, target_directory, nv = {})
        puts 'entered build provision cmd fifth'
        provision_cmd << ' -v ' if not_null?(nv.fetch('v'))
        provision_cmd << ' -debug ' if not_null?(nv.fetch('debug'))
        provision_cmd << ' -insecure ' if not_null?(nv.fetch('insecure'))
        provision_cmd << "  > #{target_directory}/provisionApmAgent.log "
        puts 'exit build provision cmd fifth'
      end

      # Insert log
      def not_blank?(value)
        !value.nil? && !value.empty?
      end

      # Insert log
      def not_null?(value)
        !value.nil?
      end

      # Copy Content
      def copy_content(inputfile, outputfile)
        File.open(inputfile.to_s, 'rb') do |input|
          File.open(outputfile.to_s, 'wb') do |output|
            buff = input.read(4096)
            while not_null?(buff)
              output.write(buff)
              buff = input.read(4096)
            end
          end
        end
      end

      # (see JavaBuildpack::Component::BaseComponent#release)
      def release
        @droplet.java_opts.add_javaagent(@droplet.sandbox + 'apmagent/lib/system/ApmAgentInstrumentation.jar')
      end

      protected

      # (see JavaBuildpack::Component::VersionedDependencyComponent#supports?)
      def supports?
        @application.services.one_service? FILTER, REGKEY, AGENT_ZIP_URI
      end

      FILTER = /oracleapm/

      OMC_URL             = 'omc-server-url'
      TENANT_ID           = 'tenant-id'
      REGKEY              = 'regkey'
      GATEWAY_HOST        = 'gateway-host'
      GATEWAY_PORT        = 'gateway-port'
      CLASSIFICATIONS     = 'classifications'
      PROXY_HOST          = 'ph'
      PROXY_PORT          = 'pp'
      PROXY_AUTH_TOKEN    = 'pt'
      ADDITIONAL_GATEWAY  = 'additional-gateways'
      AGENT_ZIP_URI       = 'agent-uri'
      V                   = 'v'
      DEBUG               = 'debug'
      INSECURE            = 'insecure'
      H                   = 'h'
      CERTIFICATE         = 'gateway-certificate'
      TRUST_HOST          = 'trust-host'
      STARTUP_PROPERTIES  = 'startup-properties'

      private_constant :FILTER, :OMC_URL, :TENANT_ID, :REGKEY, :GATEWAY_HOST, :GATEWAY_PORT,
                       :CLASSIFICATIONS, :PROXY_HOST, :PROXY_PORT, :PROXY_AUTH_TOKEN, :ADDITIONAL_GATEWAY,
                       :AGENT_ZIP_URI, :V, :DEBUG, :INSECURE, :H, :CERTIFICATE, :TRUST_HOST, :STARTUP_PROPERTIES

    end
  end
end
