# frozen_string_literal: true

# Cloud Foundry Java Buildpack
# Copyright 2013-2017 the original author or authors.
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
        credentials = @application.services.find_service(FILTER, REGKEY, AGENT_ZIP_URI)['credentials']
        @version, @uri = ['latest', 'https://check-app-ok-2.cfapps.io/apm-agents/apmagent.zip'] if supports?
      end

    # (see JavaBuildpack::Component::BaseComponent#compile)
      def compile
        credentials = @application.services.find_service(FILTER)['credentials']
        puts "******* "
        puts @uri
        download_zip(credentials[AGENT_ZIP_VERSION],  credentials[AGENT_ZIP_URI])
       #download_zip(@version,  @uri)
        run_provision_script(credentials[TENANT_ID], credentials[REGKEY], credentials[OMC_URL], credentials[GATEWAY_HOST], credentials[GATEWAY_PORT], credentials[PROXY_HOST], credentials[PROXY_PORT], credentials[CLASSIFICATIONS], credentials[PROXY_AUTH_TOKEN], credentials[ADDITIONAL_GATEWAY])
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
            AGENT_ZIP_VERSION   = 'agent-version'
            AGENT_ZIP_URI       = 'agent-uri'

            private_constant :FILTER, :OMC_URL, :TENANT_ID, :REGKEY, :GATEWAY_HOST, :GATEWAY_PORT,
            :CLASSIFICATIONS, :PROXY_HOST, :PROXY_PORT,  :PROXY_AUTH_TOKEN, :ADDITIONAL_GATEWAY,
            :AGENT_ZIP_VERSION, :AGENT_ZIP_URI

    end
  end
end
