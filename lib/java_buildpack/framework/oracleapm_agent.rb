# frozen_string_literal: true

# Cloud Foundry Java Buildpack
# Copyright 2013-2019 the original author or authors.
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

      # (see JavaBuildpack::Component::BaseComponent#compile)
      def compile
        credentials = @application.services.find_service(FILTER)['credentials']

        # download APM agent zip file
        download_zip false

        # provision oracle apm agent
        provision_apm_agent(credentials)
      end

      # provision apm agent
      def provision_apm_agent(credentials)
        # populate input map
        input_map = create_map_with_variables(credentials)
        # Run apm provisioning script to install agent
        run_apm_provision_script(input_map)
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

        # Switch to apm directory and make necessary changes to Provisioning script
        # we need to explicitly set the JAVA_BIN path
        Dir.chdir target_directory do
          java_bin = "JAVA_BIN=#{@droplet.java_home.root}/bin/java"
          # puts " java : #{java_bin}"
          shell "echo #{java_bin} > Provision.sh"
          shell "sed -e 's/locate_java$/#locate_java/g' ProvisionApmJavaAsAgent.sh > ProvisionApmJavaAsAgent_tmp.sh"
          shell "sed -e 's/^_java=/_java=$JAVA_BIN/g' ProvisionApmJavaAsAgent_tmp.sh >> Provision.sh"
          shell 'rm ProvisionApmJavaAsAgent_tmp.sh'
          shell 'chmod +x Provision.sh'
          # puts  "Provision Command : #{provision_cmd.string}"
          shell provision_cmd.string
        end
      end

      # below is command used to provision apm agent
      # shell "#{target_directory}/ProvisionApmJavaAsAgent.sh -regkey #{regkey}
      # -ph #{proxy_host} -d #{target_directory} -exact-hostname -no-prompt -omc-server-url
      # #{omc_url} -tenant-id  #{tenant_id} -java-home #{@droplet.java_home.root} 2>&1"

      # Print log
      def print_log(target_directory,
                    name,
                    nv = {})
        # shell "chmod +x #{target_directory}/ProvisionApmJavaAsAgent.sh"
        puts "target directory = #{target_directory}"
        puts "component name = #{name}"
        puts 'tenant_id : ' + nv.fetch('tenantid') if not_null?(nv.fetch('tenantid'))
        puts 'reg_key : ' + nv.fetch('regkey') if not_null?(nv.fetch('regkey'))
        puts 'omc_url : ' + nv.fetch('omcurl') if not_null?(nv.fetch('omcurl'))
      end

      # Print log proxy gateway info
      def log_proxy_gateway_info(nv = {})
        puts 'gateway_host : ' + nv.fetch('gatewayh') if not_null?(nv.fetch('gatewayh'))
        puts 'gateway_port : ' + nv.fetch('gatewayp') if not_null?(nv.fetch('gatewayp'))
        puts 'proxy_host : ' + nv.fetch('proxyhost') if not_null?(nv.fetch('proxyhost'))
        puts 'proxy_port : ' + nv.fetch('proxyport') if not_null?(nv.fetch('proxyport'))
      end

      # Print miscellenous info
      def log_misc_info(nv = {})
        puts 'classifications : ' + nv.fetch('classifications') if not_null?(nv.fetch('classifications'))
        puts 'proxy_auth_token : ' + nv.fetch('proxyauthtoken') if not_null?(nv.fetch('proxyauthtoken'))
        puts 'additional_gateways : ' + nv.fetch('additionalgateway') if not_null?(nv.fetch('additionalgateway'))
        puts "java_home : #{@droplet.java_home.root}"
      end

      # Print additional info
      def log_additional_info(nv = {})
        puts 'v : ' + nv.fetch('v') if not_null?(nv.fetch('v'))
        puts 'h : ' + nv.fetch('h') if not_null?(nv.fetch('h'))
        puts 'debug : ' + nv.fetch('debug') if not_null?(nv.fetch('debug'))
        puts 'insecure : ' + nv.fetch('insecure') if not_null?(nv.fetch('insecure'))
      end

      # Insert log
      def build_provision_cmd(provision_cmd, target_directory,
                              nv = {})
        provision_cmd << "#{target_directory}/Provision.sh -regkey " + nv.fetch('regkey') +
"  -d #{target_directory} -exact-hostname -no-prompt"
        provision_cmd << ' -tenant-id ' + nv.fetch('tenantid') if not_blank?(nv.fetch('tenantid'))
        provision_cmd << ' -omc-server-url ' + nv.fetch('omcurl') if not_blank?(nv.fetch('omcurl'))
      end

      # Insert log
      def build_provision_cmd_second(provision_cmd, nv = {})
        provision_cmd << ' -gateway-host ' + nv.fetch('gatewayh') if not_blank?(nv.fetch('gatewayh'))
        provision_cmd << ' -gateway-port ' + nv.fetch('gatewayp') if not_blank?(nv.fetch('gatewayp'))
        provision_cmd << ' -ph ' + nv.fetch('proxyhost') if not_blank?(nv.fetch('proxyhost'))
      end

      # Insert log
      def build_provision_cmd_third(provision_cmd, nv = {})
        provision_cmd << ' -pp ' + nv.fetch('proxyport') if not_blank?(nv.fetch('proxyport'))
        provision_cmd << ' -classifications ' + nv.fetch('classifications') if not_blank?(nv.fetch('classifications'))
        provision_cmd << ' -pt ' + nv.fetch('proxyauthtoken') if not_blank?(nv.fetch('proxyauthtoken'))
      end

      # Insert log
      def build_provision_cmd_fourth(provision_cmd, nv = {})
        gateway = nv.fetch('additionalgateway')
        provision_cmd << " -additional-gateways #{gateway}" if not_blank?(nv.fetch('additionalgateway'))
        provision_cmd << ' -h ' + nv.fetch('h') if not_blank?(nv.fetch('h'))
      end

      # Insert log
      def build_provision_cmd_fifth(provision_cmd, target_directory, nv = {})
        provision_cmd << ' -v ' if not_null?(nv.fetch('v'))
        provision_cmd << ' -debug ' if not_null?(nv.fetch('debug'))
        provision_cmd << ' -insecure ' if not_null?(nv.fetch('insecure'))
        provision_cmd << "  > #{target_directory}/provisionApmAgent.log "
      end

      # To check if not blank
      def not_blank?(value)
        !value.nil? && !value.empty?
      end

      # To check if not null
      def not_null?(value)
        !value.nil?
      end

      # (see JavaBuildpack::Component::BaseComponent#release)
      def release
        @droplet.java_opts.add_javaagent(@droplet.sandbox + 'apmagent/lib/system/ApmAgentInstrumentation.jar')
      end

      protected

      # (see JavaBuildpack::Component::VersionedDependencyComponent#supports?)
      def supports?
        @application.services.one_service? FILTER, REGKEY
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
      V                   = 'v'
      DEBUG               = 'debug'
      INSECURE            = 'insecure'
      H                   = 'h'
      CERTIFICATE         = 'gateway-certificate'
      TRUST_HOST          = 'trust-host'
      STARTUP_PROPERTIES  = 'startup-properties'

      private_constant :FILTER, :OMC_URL, :TENANT_ID, :REGKEY, :GATEWAY_HOST, :GATEWAY_PORT,
                       :CLASSIFICATIONS, :PROXY_HOST, :PROXY_PORT, :PROXY_AUTH_TOKEN, :ADDITIONAL_GATEWAY,
                       :V, :DEBUG, :INSECURE, :H, :CERTIFICATE, :TRUST_HOST, :STARTUP_PROPERTIES

    end
  end
end
