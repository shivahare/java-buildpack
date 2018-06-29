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

    # (see JavaBuildpack::Component::BaseComponent#compile)
      def compile
        download_zip false
        run_provision_script(100, 'erer', 'http://my.oracle.com')
      end

    # (see JavaBuildpack::Component::BaseComponent#release)
      def release
        @droplet.java_opts.add_javaagent(@droplet.sandbox + 'apmagent/lib/system/ApmAgentInstrumentation.jar')
      end

       protected

           # (see JavaBuildpack::Component::VersionedDependencyComponent#supports?)
            def supports?
              @application.services.one_service? FILTER
            end


            FILTER = /oracleapm/

            OMC_URL         = 'omc_url'
            TENANT_ID       = 'tenant_id'
            REGKEY          = 'regkey'
            GATEWAY_HOST    = 'gateway_host'
            GATEWAY_PORT    = 'gateway_port'
            PROXY_HOST      = 'proxy_host'
            PROXY_PORT      ='proxy_port'
            NO_WALLET       = 'no_wallet'
            CLASSIFICATION_STR = 'classification_str'

            private_constant :FILTER, :OMC_URL, :TENANT_ID, :REGKEY, :GATEWAY_HOST, :GATEWAY_PORT, :PROXY_HOST, :PROXY_PORT, :NO_WALLET, :CLASSIFICATION_STR

    end
  end
end
