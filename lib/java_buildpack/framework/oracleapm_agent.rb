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
        @version, @uri = agent_download_url if supports?
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
        # Run apm provisioning script to install agent
        inputmap = create_map_with_variables(credentials)
        run_apm_provision_script(inputmap)
        cert = credentials[CERTIFICATE]
        validate_cert_not_blank(cert)

        no_certificate = credentials[TRUST_HOST]
        validate_no_certificate(no_certificate)

        add_startup_props = credentials[STARTUP_PROPERTIES]
        validate_startup_props(add_startup_props)

        create_aspect_file

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

      # Create aspect file
      def create_aspect_file
        aspect_filters = 'oracle/apmaas/agent/instrumentation/Aspect.filters'
        target_directory = @droplet.sandbox
        shell "unzip -x #{target_directory}/apmagent/lib/system/ApmAgentInstrumentation.jar " + aspect_filters
        shell "sed '/EXCLUDE/a  org.cloudfoundry.tomcat.logging.'" + aspect_filters + ' > Aspect.filters_temp'
        shell 'cat Aspect.filters_temp > ' + aspect_filters
        shell "zip -u #{target_directory}/apmagent/lib/system/ApmAgentInstrumentation.jar " + aspect_filters
        shell 'rm Aspect.filters_temp'
      end

      # Run the provision script
      def run_apm_provision_script(name_parts = {},
                                   target_directory = @droplet.sandbox,
                                   name = @component_name)
        print_log(name_parts, target_directory, name)
        log_proxy_gateway_info(name_parts)
        env_provision_cmd(name_parts)
        log_misc_info(name_parts)
        build_provision_cmd(target_directory, name_parts)
        build_provision_cmd_second(target_directory, name_parts)
        build_provision_cmd_third(name_parts)
        build_provision_cmd_fourth(target_directory, name_parts)
        build_provision_cmd_fifth(target_directory)

        # puts "command : #{provision_cmd.string}"
        Dir.chdir target_directory do
          # shell "#{target_directory}/ProvisionApmJavaAsAgent.sh -regkey #{regkey} -no-wallet
          # -ph #{proxy_host} -d #{target_directory} -exact-hostname -no-prompt -omc-server-url
          #  #{omc_url} -tenant-id  #{tenant_id} -java-home #{@droplet.java_home.root} 2>&1"
          java_bin = "JAVA_BIN=#{@droplet.java_home.root}/bin/java"
          puts " java : #{java_bin}"
          shell "echo #{java_bin} > ProvisionApmJavaAsAgent_CF.sh"
          shell "sed -e 's/locate_java$/#locate_java/g' ProvisionApmJavaAsAgent.sh > ProvisionApmJavaAsAgent_tmp.sh"
          shell "sed -e 's/^_java=/_java=$JAVA_BIN/g' ProvisionApmJavaAsAgent_tmp.sh >> ProvisionApmJavaAsAgent_CF.sh"
          shell 'rm ProvisionApmJavaAsAgent_tmp.sh'
          shell 'chmod +x ProvisionApmJavaAsAgent_CF.sh'
          shell provision_cmd.to_s
        end
      end

      # Print log
      def print_log(name_values = {},
                    target_directory = @droplet.sandbox,
                    name = @component_name)
        shell "chmod +x #{target_directory}/ProvisionApmJavaAsAgent.sh"
        puts "component name = #{name}"
        puts 'tenant_id : ' + name_values.fetch('tenantid')
        puts 'reg_key : ' + name_values.fetch('regkey')
        puts 'omc_url : ' + name_values.fetch('omcurl')
        puts 'gateway_host : ' + name_values.fetch('gatewayh')
        puts 'gateway_port : ' + name_values.fetch('gatewayp')
      end

      # Insert log
      def log_proxy_gateway_info(name_values = {})
        puts 'proxy_host : ' + name_values.fetch('proxyhost')
        puts 'proxy_port : ' + name_values.fetch('proxyport')
        puts 'classifications : ' + name_values.fetch('classifications')
        puts 'proxy_auth_token : ' + name_values.fetch('proxyauthtoken')
        puts 'additional_gateways : ' + name_values.fetch('additionalgateway')
      end

      # Insert log
      def log_misc_info(name_values = {})
        puts "java_home : #{@droplet.java_home.root}"
        puts 'v : ' + name_values.fetch('v')
        puts 'h : ' + name_values.fetch('h')
        puts 'debug : ' + name_values.fetch('debug')
        puts 'insecure : ' + name_values.fetch('insecure')
      end

      # Insert log
      def build_provision_cmd(target_directory,
                              name_values = {})
        provision_cmd = StringIO.new
        provision_cmd << "#{target_directory}/ProvisionApmJavaAsAgent_CF.sh -regkey " + name_values.fetch('regkey') +
" -no-wallet -d #{target_directory} -exact-hostname -no-prompt"
        provision_cmd << ' -tenant-id ' + name_values.fetch('tenantid') if not_blank?(tenant_id)
        provision_cmd << ' -omc-server-url ' + name_values.fetch('omcurl') if not_blank?(omc_url)
      end

      # Insert log
      def build_provision_cmd_second(name_values = {})
        provision_cmd << ' -gateway-host ' + name_values.fetch('gatewayh') if not_blank?(gateway_host)
        provision_cmd << ' -gateway-port ' + name_values.fetch('gatewayp') if not_blank?(gateway_port)
        provision_cmd << ' -ph ' + name_values.fetch('proxyhost') if not_blank?(proxy_host)
      end

      # Insert log
      def build_provision_cmd_third(name_values = {})
        provision_cmd << ' -pp ' + name_values.fetch('proxyport') if not_blank?(proxy_port)
        provision_cmd << ' -classifications ' + name_values.fetch('classifications') if not_blank?(classifications)
        provision_cmd << ' -pt ' + name_values.fetch('proxyauthtoken') if not_blank?(proxy_auth_token)
      end

      # Insert log
      def build_provision_cmd_fourth(target_directory,
                                     name_values = {})
        gateway = name_values.fetch('additionalgateway')
        provision_cmd << " -additional-gateways #{gateway}" if not_blank?(additional_gateway)
        env_provision_cmd_fourth(target_directory, name_values)
        provision_cmd << ' -h ' + name_values.fetch('h') if not_blank?(hostname)
      end

      # Insert log
      def build_provision_cmd_fifth(target_directory)
        provision_cmd << ' -v ' if not_null?(v)
        provision_cmd << ' -debug ' if not_null?(debug)
        provision_cmd << ' -insecure ' if not_null?(insecure)
        provision_cmd << "  > #{target_directory}/provisionApmAgent.log "
      end

      # Insert log
      def not_blank?(value)
        !value.nil? && !value.empty?
      end

      # Insert log
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
