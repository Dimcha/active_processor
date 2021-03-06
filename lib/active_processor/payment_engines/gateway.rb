# -*- encoding : utf-8 -*-
module ActiveProcessor
  module PaymentEngines
    class Gateway < PaymentEngine
      extend Forwardable
      require 'uri'

      def_delegators :instance, :display_name, :supported_cardtypes

      # Instance of gateway (ActiveMerchant gateway or integration)
      attr_accessor :name
      # Test mode
      attr_accessor :test
      # Credit card object
      attr_reader :credit_card

      def initialize(engine, name, options, fields = {})
        @name = name.to_s
        @instance = ActiveMerchant::Billing::Base.gateway(name.to_s.capitalize.to_sym)

        super(engine, name, options, fields)
      end

      def pay(user, ip, error_notice, params)
        if self.get(:config, "tax_in_amount").to_s == "excluded"
          gross = exchange(params[@engine][@name]['amount'], params[@engine][@name]['currency'], params[@engine][@name]['default_currency'])
          money = ActiveProcessor.configuration.substract_tax.call(user, money)
          orig = ActiveProcessor.configuration.substract_tax.call(user, params[@engine][@name]['amount'])
          orig_with_tax = params[@engine][@name]['amount'].to_f
        else
          money = exchange(params[@engine][@name]['amount'], params[@engine][@name]['currency'], params[@engine][@name]['default_currency'])
          gross = ActiveProcessor.configuration.calculate_tax.call(user, money)
          orig = params[@engine][@name]['amount'].to_f
          orig_with_tax = ActiveProcessor.configuration.calculate_tax.call(user, params[@engine][@name]['amount'])
        end
        tax = gross - money
        @payment = OpenStruct.new({
                                      :money => money,
                                      :orig_amount => orig.to_f,
                                      :orig_with_tax => round_to_cents(orig_with_tax).to_f,
                                      :orig_tax => 0,
                                      :tax => round_to_cents(tax).to_f,
                                      :auth_config => {},
                                      :authorize => {},
                                      :ip => ip,
                                      :currency => params[@engine][@name]['currency'],
                                      :response => {}
                                  })
        @payment.orig_tax = (@payment.orig_with_tax - @payment.orig_amount)
        @payment.amount = (@payment.money + @payment.tax).ceil

        # we choose only those fields for authentication which have attribute for=authentication in configuration
        @fields['config'].dup.delete_if { |item, conf| conf['for'] != "authentication" }.each { |field, configuration|
          @payment.auth_config[field.to_sym] = configuration['html_options']['value']
        }
        @payment.auth_config[:test] = true if @fields['config']['test']['html_options']['value'] == "1"
        gw = @instance.new(@payment.auth_config)
        @fields['form'].dup.delete_if { |field, conf| conf['for'] != "authorization" }.each_pair { |field, config|
          field.match(/^(.*)\[(.*)\]$/)
          @payment.authorize.deep_merge!({$1.to_sym => {$2.to_sym => params[@engine][@name][$1][$2]}})
        }

        ActiveProcessor.log("paying with gateway: #{@name} from #{@payment.ip}. Original amount: #{@payment.orig_amount} #{@payment.currency} (with tax: #{@payment.orig_with_tax}), converted amount in cents #{@payment.money} (tax: #{@payment.tax}) #{params[@engine][@name]['default_currency']}")

        error_notice.replace(valid_gateway(gw))
        if error_notice.blank?
          begin
            if @name == 'authorize_net'
              @payment.response = gw.purchase(@payment.amount, @credit_card, {:ip => @payment.ip}.merge!(@payment.authorize).merge!(params))
            else
              @payment.response = gw.authorize(@payment.amount, @credit_card, {:ip => @payment.ip}.merge!(@payment.authorize))
            end
            if @payment.response.success?
              ActiveProcessor.log("successfully payed amount: #{@payment.orig_amount} #{@payment.currency} (authorization: #{@payment.response.authorization})")
              gw.capture(@payment.amount, @payment.response.authorization)
              return true
            else
              ActiveProcessor.log("failed to pay amount: #{@payment.money} #{@payment.currency}")
              return false
            end
          rescue ActiveMerchant::ConnectionError, ActiveMerchant::Billing::Error
            return false
          rescue SocketError => e
            error_notice.replace(_("gateway_error_invalid_uri"))
            return false
          end
        end
      end

      def valid_gateway(gateway)
        error_notice = ''
        if @name == 'hsbc_secure_epayments'
          error_notice.replace(_("gateway_error_invalid_uri")) unless valid_uri(gateway.options[:xml_url])
          error_notice.replace(_("gateway_error_blank_uri")) if gateway.options[:xml_url].blank?
        end
        error_notice
      end

      def valid_uri(uri)
        valid = true
        if !uri.blank?
          begin
            new_uri = URI.parse(uri.to_s)
            unless new_uri.kind_of?(URI::HTTP) || new_uri.kind_of?(URI::HTTPS)
              valid = false
            end
          rescue URI::InvalidURIError
            valid = false
          end
        end
        valid
      end

      def valid_hsbc?
        uri = get(:config, 'xml_url').to_s

        @errors.store('xml_url', "gateway_error_invalid_uri") if !valid_uri(uri)
        @errors.store('xml_url', "gateway_error_blank_uri") if uri.blank?
      end

      def valid_settings?
        if !get(:config, 'max_amount').to_f.zero? and !get(:config, 'min_amount').to_f.zero? and get(:config, 'max_amount').to_f < get(:config, 'min_amount').to_f
          @errors.store("min_amount", "gateway_error_min_amount_more_than_max")
        end
      end


      def valid?(params)
        for param, value in params[@engine][@name]
          set(:form, {param => value}) # field validations
        end

        error_counter = 0

        # CC and misc validations
        @credit_card = ActiveMerchant::Billing::CreditCard.new(
            params[@engine][@name].except('amount', 'with_tax', 'without_tax', 'separator', 'currency', 'default_currency').delete_if { |key, value|
              !value.kind_of?(String)
            }
        )

        unless @credit_card.valid?
          error_counter += 1
        end

        if get(:config, 'min_amount').to_i > 0
          if exchange(params[@engine][@name]['amount'], params[@engine][@name]['currency'], params[@engine][@name]['default_currency']).to_i < get(:config, 'min_amount').to_i * 100.0
            @errors.store("gateway_amount", "gateway_error_min_amount")
            error_counter += 1
          end
        end

        if get(:config, 'max_amount').to_i > 0
          if exchange(params[@engine][@name]['amount'], params[@engine][@name]['currency'], params[@engine][@name]['default_currency']).to_i > get(:config, 'max_amount').to_i * 100.0
            @errors.store("gateway_amount", "gateway_error_max_amount")
            error_counter += 1
          end
        end

        # Billing address validation
        if params[@engine][@name]['billing_address']
          if params[@engine][@name]['billing_address']['name'].to_s.strip.blank?
            @errors.store("gateway_billing_address_name", "cannot_be_empty")
            error_counter += 1
          end

          if params[@engine][@name]['billing_address']['address1'].to_s.strip.blank?
            @errors.store("gateway_billing_address_address1", "cannot_be_empty")
            error_counter += 1
          end

          if params[@engine][@name]['billing_address']['city'].to_s.strip.blank?
            @errors.store("gateway_billing_address_city", "cannot_be_empty")
            error_counter += 1
          end

          if params[@engine][@name]['billing_address']['country'].to_s.strip.blank? or Direction.where(:name => params[@engine][@name]['billing_address']['country'].to_s.strip.downcase.capitalize).first.blank?
            @errors.store("gateway_billing_address_country", "country_not_found")
            error_counter += 1
          end

          if params[@engine][@name]['billing_address']['zip'].to_s.strip.blank?
            @errors.store("gateway_billing_address_zip", "cannot_be_empty")
            error_counter += 1
          end

          if params[@engine][@name]['billing_address']['phone'].to_s.strip.blank?
            @errors.store("gateway_billing_address_phone", "cannot_be_empty")
            error_counter += 1
          end
        end

        if params[@engine][@name]['amount'].to_s.strip.blank?
          @errors.store("gateway_amount", "cannot_be_empty")
          error_counter += 1
        end

        return (error_counter > 0) ? false : true
      end

      private

      def exchange(amount, curr1, curr2)
        amount = amount.to_f * ActiveProcessor.configuration.currency_exchange.call(curr1, curr2) if defined? ActiveProcessor.configuration.currency_exchange
        return round_to_cents(amount).to_f * 100.0
      end

      def round_to_cents(amount)
        return sprintf("%.2f", amount.to_f)
      end

    end
  end
end
