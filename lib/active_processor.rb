# -*- encoding : utf-8 -*-
# ActiveProcessor

require 'forwardable'
require 'ostruct'
require 'yaml'

require 'core_ext/class/inheritable_attributes'

require 'active_processor/configuration'
require 'active_processor/core_ext'
require 'active_processor/engine' if defined?(Rails)
require 'active_processor/routes'

require 'active_processor/form_helper'

require 'active_processor/gateway_engine'
require 'active_processor/payment_engine'

require 'active_processor/payment_engines/gateway'
require 'active_processor/payment_engines/integration'
require 'active_processor/payment_engines/google_checkout'
require 'active_processor/payment_engines/ideal'
require 'active_processor/payment_engines/osmp'

# custom activemerchant gateways
require 'active_merchant'
require 'active_merchant/billing/gateways/hsbc_secure_epayments'
require 'active_merchant/billing/integrations/moneybooker'

require 'active_processor/action_view_helper'
ActionView::Base.send(:include, ActiveProcessor::ActionViewHelper)
